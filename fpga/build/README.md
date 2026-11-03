# FPGA构建

波束合成入口：beamforming/build.tcl，使用同目录implement_m512_board.tcl创建候选DCP和报告。create_project.tcl可生成浏览工程。识别入口：recognition/build.tcl，board_case保留匹配的MEM参数。

先按docs/network_configuration.md配置本地通信参数。原bit、LTX、DCP、会话元数据和旧构建工具归档不公开；原工程保留在本地。公开源码需重新构建并验证，历史指标不适用于未经验证的新构建。本次未执行Vivado构建、编程或硬件测试。
