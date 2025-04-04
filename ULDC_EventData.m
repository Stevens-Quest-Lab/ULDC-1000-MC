classdef ULDC_EventData < event.EventData
    properties
        Timestamp   % 时间戳
        RawData     % 原始数据
        Command     % 关联命令
        Address     % 设备地址
    end
    
    methods
        function this = ULDC_EventData(data, command, address)
            this.Timestamp = datetime('now');
            this.RawData = data;
            if nargin > 1
                this.Command = command;
                this.Address = address;
            end
        end
    end
end