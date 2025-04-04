classdef ULDC_Controller < handle
    % ULDC_Controller - 控制Optilab ULDC激光模块的核心类
    
    properties
        portName               % 串口号（如'COM4'）
        baudRate = 19200       % 波特率（默认19200）
        serialObj              % 串口对象
        defaultAddress = '00'  % 默认设备地址
        timeout = 2            % 响应超时时间（秒）
        isRemoteEnabled = false% 远程模式状态标记
        errorCallback          % 错误回调函数
        statusCallback         % 状态回调函数
    end
    
    events
        DataReceived           % 数据接收事件
        ErrorOccurred          % 错误发生事件
    end
    
    methods
        %% --------------------- 公有方法 ---------------------
        %% 构造函数
        function obj = ULDC_Controller(portName, varargin)
            p = inputParser;
            addParameter(p, 'BaudRate', 19200);
            addParameter(p, 'Timeout', 2);
            parse(p, varargin{:});
            
            obj.portName = portName;
            obj.baudRate = p.Results.BaudRate;
            obj.timeout = p.Results.Timeout;
            
            try
                obj.serialObj = serialport(obj.portName, obj.baudRate,...
            'DataBits', 8,...          % 数据位
            'StopBits', 1,...          % 停止位
            'Parity', 'none',...       % 校验位
            'FlowControl', 'none');    % 流控制
        
        configureTerminator(obj.serialObj, "CR/LF");
        configureCallback(obj.serialObj, "terminator", @obj.dataReceivedHandler);
            catch ME
                obj.handleError('CONNECTION_FAILURE', ME.message);
            end
        end
        
        %% 析构函数
        function delete(obj)
            try
                if isvalid(obj.serialObj)
                    flush(obj.serialObj);
                    delete(obj.serialObj);
                end
                fprintf('[INFO] Connection closed\n');
            catch ME
                obj.handleError('DISCONNECT_FAILURE', ME.message);
            end
        end
        
        %% 注册回调函数
        function registerCallback(obj, callbackType, funcHandle)
            % registerCallback 注册回调函数
            % 支持类型：'ERROR'、'STATUS'
            switch upper(callbackType)
                case 'ERROR'
                    obj.errorCallback = funcHandle;
                case 'STATUS'
                    obj.statusCallback = funcHandle;
                otherwise
                    obj.handleError('INVALID_CALLBACK', 'Supported types: ERROR, STATUS');
            end
        end
        
        %% --------------------- 设备控制方法 ---------------------
        %% 设置设备地址
        function setAddress(obj, address)
            validateattributes(address, {'char'}, {'numel', 2});
            cmd = sprintf('SA %s', address);
            resp = obj.sendCommand(cmd);
            obj.defaultAddress = address;
            obj.updateStatus('ADDRESS_SET', address);
        end
        
        %% 启用远程模式
        function enableRemote(obj, address)
            cmd = sprintf('RM%s 1', address);
            resp = obj.sendCommand(cmd, address);
            if contains(resp, 'ON')
                obj.isRemoteEnabled = true;
                obj.updateStatus('REMOTE_ENABLED', address);
            end
        end
        
        %% 设置激光电流
        function setLaserCurrent(obj, current, address)
            validateattributes(current, {'numeric'}, {'scalar', '>=', 0, '<=', 2000});
            cmd = sprintf('IS%s %03d', address, round(current));
            obj.sendCommand(cmd, address);
            obj.updateStatus('CURRENT_SET', sprintf('%d mA', current));
        end
        
        %% 查询设定激光电流
        function current = getLaserCurrent(obj, address)
    cmd = sprintf('IS%s?', address);
    resp = obj.sendCommand(cmd, address);
    
    % 更健壮的解析方式
    pattern = sprintf('IS%s:\\s*(\\d+)\\s*mA', address);
    matched = regexp(resp, pattern, 'tokens');
    if ~isempty(matched)
        current = str2double(matched{1}{1});
    else
        error('解析失败: %s', resp);
    end
        end 
        %% 查询当前激光电流
        function current = getCurrentCurrent(obj, address)
    cmd = sprintf('IM%s?', address);
    resp = obj.sendCommand(cmd, address);
    
    % 更健壮的解析方式
    pattern = sprintf('IM%s:\\s*(\\d+)\\s*mA', address);
    matched = regexp(resp, pattern, 'tokens');
    if ~isempty(matched)
        current = str2double(matched{1}{1});
    else
        error('解析失败: %s', resp);
    end
        end 
        %% 启用激光输出
        function enableLaser(obj, address)
            cmd = sprintf('LD%s 1', address);
            obj.sendCommand(cmd, address);
        end
        
        %% 禁用激光输出
        function disableLaser(obj, address)
            cmd = sprintf('LD%s 0', address);
            obj.sendCommand(cmd, address);
        end
        %% 设置TEC温度
        function setTemperature(obj, temp, address)
            % 参数验证
            validateattributes(temp, {'numeric'},...
                {'scalar', '>=', 10, '<=', 40},...
                'setTemperature', '温度值');
            
            % 构造命令（保留1位小数）
            cmd = sprintf('TS%s %.1f', address, temp);
            resp = obj.sendCommand(cmd, address);
            
            % 状态更新
            obj.updateStatus('TEMPERATURE_SET', sprintf('%.1f ℃', temp));
        end

        %% 查询设定温度
        function temp = getSetTemperature(obj, address)
            cmd = sprintf('TS%s?', address);
            resp = obj.sendCommand(cmd, address);
            
            pattern = sprintf('TS%s:\\s*(\\d+\\.?\\d*)\\s*C', address);
    matched = regexp(resp, pattern, 'tokens');
    
    if ~isempty(matched)
        temp = str2double(matched{1}{1});
    else
        error('解析温度失败. 原始响应: %s', resp);
    end
        end

        %% 查询当前温度
        function temp = getCurrentTemperature(obj, address)
    cmd = sprintf('TM%s?', address);
    resp = obj.sendCommand(cmd, address);
    
    % 使用sprintf构建正则表达式
    pattern = sprintf('TM%s:\\s*(\\d+\\.?\\d*)\\s*C', address);
    matched = regexp(resp, pattern, 'tokens');
    
    if ~isempty(matched)
        temp = str2double(matched{1}{1});
    else
        error('解析温度失败. 原始响应: %s', resp);
    end
end
        %% --------------------- 核心通信方法 ---------------------
        function response = sendCommand(obj, command, address)
            if nargin < 3, address = obj.defaultAddress; end
            
            % 允许SA和RM命令在未启用远程模式时执行
            allowedCommands = {'SA', 'RM'};
            if ~obj.isRemoteEnabled && ~any(startsWith(command, allowedCommands))
                obj.handleError('REMOTE_DISABLED', 'Remote mode must be enabled for non-config commands');
            end
            
            fullCommand = sprintf('%s\r\n', command); % 强制CR-LF
            maxRetries = 3;
            response = '';
            
            for retry = 1:maxRetries
                try
                    flush(obj.serialObj);
                    writeline(obj.serialObj, fullCommand);
                    
                    % 调试输出
                    fprintf('[DEBUG] Sent: %s (HEX: ', strtrim(fullCommand));
                    fprintf('%02X ', uint8(fullCommand));
                    fprintf(')\n');
                    
                    % 等待响应
                    startTime = tic;
                    while obj.serialObj.NumBytesAvailable == 0
                        if toc(startTime) > obj.timeout
                            error('Timeout after %.1fs', obj.timeout);
                        end
                        pause(0.01);
                    end
                    
                    response = readline(obj.serialObj);
                    notify(obj, 'DataReceived', ULDC_EventData(response, command, address));
                    
                    if contains(response, 'Error') || contains(response, 'Out of Range')
                        error('Device error: %s', response);
                    end
                    return;
                    
                catch ME
                    if retry == maxRetries
                        obj.handleError('COMMAND_FAILURE', ME.message);
                    else
                        fprintf('[RETRY] Command: %s (Attempt %d)\n', command, retry);
                        pause(0.5);
                    end
                end
            end
        end
        
    end
    
    methods (Access = private)
        %% --------------------- 私有方法 ---------------------
        %% 数据接收回调
        function dataReceivedHandler(obj, ~, ~)
            if obj.serialObj.NumBytesAvailable > 0
                data = readline(obj.serialObj);
                notify(obj, 'DataReceived', ULDC_EventData(data));
            end
        end
        
        %% 统一错误处理
        function handleError(obj, errorType, errorMsg)
            fullMsg = sprintf('[%s] %s', errorType, errorMsg);
            notify(obj, 'ErrorOccurred', ULDC_EventData(fullMsg));
            if ~isempty(obj.errorCallback)
                feval(obj.errorCallback, errorType, errorMsg);
            else
                error(fullMsg);
            end
        end
        
        %% 状态更新处理
        function updateStatus(obj, statusType, statusData)
            if ~isempty(obj.statusCallback)
                feval(obj.statusCallback, statusType, statusData);
            end
        end
    end
end