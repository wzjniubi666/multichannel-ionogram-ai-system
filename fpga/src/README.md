# FPGA源码

beamforming/：原设计、tb、vendor、当前约束和与bit绑定的release_sources/release_constraints。生产顶层kt325t_network512_board_top。

recognition/：原RTL、sim与constraints，顶层udp_mdio_bridge，c3_udp_engine执行前15卷积。两套都有crc32、网络模块等同名定义，必须独立源列表和顶层，不能通配整个src加入同一工程。

合并未改RTL、XDC、MEM、bit、DCP或模型数值。构建入口只调整外部文件布局；工具版本和原实现证据按各阶段保持。没有生成同时包含两引擎的新镜像，没有XSA/HWH。
