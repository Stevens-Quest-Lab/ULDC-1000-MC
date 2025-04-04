%% 创建控制器实例 (Initiallize, change'COM*' as needed)
controller = ULDC_Controller('COM4',...   % 串口号（根据实际修改）
    'BaudRate', 19200,...                % 波特率（必须与设备一致）
    'Timeout', 5);                       % 超时时间（秒）

% 注册回调函数（可选，用于实时监控）
controller.registerCallback('ERROR', @(t,m)fprintf('[ERROR] %s: %s\n', t, m));
controller.registerCallback('STATUS', @(t,d)fprintf('[STATUS] %s → %s\n', t, d));
%% 设置设备地址为 07（00-31）（Set address to 07)
controller.setAddress('07');  % 
%% 启用地址 07 的远程模式 (Enable remote mode)
controller.enableRemote('07'); 
%% 初始化 (Recomended step for initiallize the LASER diode)
% 初始化激光电流为 0 mA（必须！）
controller.setLaserCurrent(0, '07'); 

% 设置 TEC 目标温度（范围 10~40℃）
controller.setTemperature(25.0, '07'); 

% 等待温度稳定（建议至少 30 秒）
pause(30); 
%% 开启激光输出（此时电流为 0 mA）(Turn on LASER)
controller.enableLaser('07'); 
%% 设置激光电流（范围 0~2000 mA）(Set Current)(0-2000mA)
SetCurrent = 300
controller.setLaserCurrent(SetCurrent, '07'); 

%% 可选：调整温度（步进式渐变，避免热冲击）(Set temperature) (10.0 C~40.0 C)
target_temp = 30.0;  % 目标温度
for temp = 25.0:0.5:target_temp
    controller.setTemperature(temp, '07');
    pause(10);  % 每 10 秒升温 0.5℃
end
%% 查询设定激光电流 (Get current setting value)
current = controller.getLaserCurrent('07');
fprintf('设定电流: %d mA\n', current);

%% 查询当前激光电流 (Get current value right now)
ccurrent = controller.getCurrentCurrent('07');
fprintf('当前电流：%d mA\n', ccurrent);

%% 查询温度状态 (Get temperature)
set_temp = controller.getSetTemperature('07');
real_temp = controller.getCurrentTemperature('07');
fprintf('温度状态: 设定值 %.1f ℃ / 实际值 %.1f ℃\n', set_temp, real_temp);

%% 查询激光电压 (Get voltage)
resp = controller.sendCommand('LV07?', '07');
voltage = sscanf(resp, 'LV07: %f V');
fprintf('激光正向电压: %.2f V\n', voltage);
%% 逐步降低电流至 0 mA (Slowly change current to 0)
for current = SetCurrent:-10:0
    controller.setLaserCurrent(current, '07');
    pause(1);  % 每 1 秒降低 10 mA
end

%% 关闭激光输出 (Turn off LASER)
controller.disableLaser('07'); 

%% 关闭串口 (Clear controller)
clear controller; 



