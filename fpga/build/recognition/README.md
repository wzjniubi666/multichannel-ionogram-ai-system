# 构建与预置产物

board_case/ 保留配套定点参数、仿真输入、最终 udp_mdio_bridge.bit/.ltx/.dcp 及历史 DCP。
日常识别直接下载已有最终 .bit；无需重新综合。
build.tcl 为源码全流程入口；development/regional_final.tcl 和 export_final.tcl 为已有中间DCP区域时钟修正与最终导出脚本。
这些脚本已修改目录定位，但此次未重新执行完整综合/实现。
在 Vivado Tcl 控制台 source 对应脚本；日志和新报告会生成在当前 board_case 工作目录。
sim.cmd / sim_full.cmd 从已配置 Vivado 环境的命令行运行。原始历史步骤在 original_build_steps 中保留，包含旧路径，仅作参考。
