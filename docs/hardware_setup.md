# 硬件、接线和运行阶段

两项目均面向PZ-K7325T-FH、xc7k325tffg900-2，使用板载RTL8211系列PHY，PC网线直连板卡、JTAG连接下载器。使用与实际板卡版本一致的原配电源；电压、极性、跳帽和下载器接法按原厂手册核对，不以3.3V I/O标准代替外部供电值。

原理图、核心板手册和引脚表在docs/beamforming/hardware_reference/。两个镜像分别使用fpga/src/beamforming/release_constraints和fpga/src/recognition/constraints；引脚/时钟模型按各自完整XDC与报告，不叠加加载。

1. 模式A：使用原ACTIVE14 bit，200MHz核心、125MHz RGMII，16路接口14有效；启动合成上位机后明确确认镜像与直连。原专用网卡流程负责备份、设置和finally恢复。
2. 先完成/停止并等待恢复，再退出模式A。保存结果不会因为换镜像消失。
3. 模式B：在识别界面配置实际Vivado路径，明确初始化。该操作下载识别bit并做PHY/JTAG管理，会替换模式A；使用UDP1234。
4. 模式B不自动修改PC网卡，须按其说明保证有线IP192.0.2.2/24。不能假定模式A退出恢复后仍保留这个测试地址。
5. 同一板卡同一时刻只运行一个模式；返回模式A需重新下载A镜像。均为易失配置，不要求本次写Flash。

本次只整理文件和验证离线路径，没有连接下载器、下载板卡、修改网卡或启动真实UDP事务。原硬件证据在metrics/evidence各子系统目录。YOLO原tested_environment.json有旧100Mbps字段，而较新识别报告为1000Mbps；均保留原记录，当前新连接速率须由实际初始化读回，不把历史值当新测量。
