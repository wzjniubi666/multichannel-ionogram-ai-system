# 可复用整合流程

1. 锁定两个源目录、器件/顶层、协议、模型及比特流身份，记录全部SHA256。
2. 顶层按docs/fpga/host/metrics/skill/report归类，内部按beamforming/recognition隔开同名模块。
3. 只适配运行入口与路径；RTL、约束、模型、量化参数和原证据保持字节身份。修改的脚本保留迁移前快照。
4. 统一总入口，使用独立解释器。阶段间通过完整结果图片及哈希清单交接，不默认自动访问板卡。
5. 先做完整性、模型/参数身份、历史特征一致性、包内定点重放及交接/入口测试，再交付。硬件验证需要另有实际执行证据。
6. 重新训练、修改RTL或想用同一镜像同时跑两种算法时，作为独立设计工作重新验证资源、时钟、CDC、接口、时序和效果，不能继承本次打包检查结果。

上面是项目整合工作流；两原项目的工作流说明分别位于 [beamforming/](beamforming/) 和 [recognition/](recognition/)。

## FPGA 开发技能

以下 10 个独立技能覆盖 RTL 开发、HLS、仿真、约束、综合、实现、时序分析和板级调试。每个技能目录包含 `SKILL.md` 及其配套参考、脚本或示例。

| 技能 | 用途 |
|---|---|
| [fpga-development](fpga-development/SKILL.md) | RTL、定点计算、握手、CDC 与验证流程 |
| [vitis-hls-synthesis](vitis-hls-synthesis/SKILL.md) | C/C++ 高层次综合、接口、pragma 与 HLS 示例 |
| [vivado-analysis](vivado-analysis/SKILL.md) | 时序、资源、CDC 及实现报告分析 |
| [vivado-constraints](vivado-constraints/SKILL.md) | XDC、时钟、I/O 时序和物理约束 |
| [vivado-debug](vivado-debug/SKILL.md) | ILA、VIO、JTAG 与板级调试 |
| [vivado-impl](vivado-impl/SKILL.md) | 布局布线、物理优化与实现策略 |
| [vivado-sim](vivado-sim/SKILL.md) | RTL、网表及时序仿真 |
| [vivado-synth](vivado-synth/SKILL.md) | 综合策略、资源推断与 RTL 模板 |
| [vivado-tcl](vivado-tcl/SKILL.md) | Vivado/Vitis Tcl 流程脚本 |
| [vivado-timing-closure](vivado-timing-closure/SKILL.md) | 时序收敛、关键路径分析及迭代优化 |

使用支持 `SKILL.md` 的编程助手时，复制所需技能的整个文件夹到其技能目录，保留内部相对路径。Vivado 技能可以互相引用，配套使用时应一并安装。

这些技能是开发辅助材料，不是运行本项目上位机或 FPGA 镜像的必需依赖。目录中的示例需要各自对应的开发工具；导入技能文件不会自动执行脚本、重新综合设计或操作板卡。
