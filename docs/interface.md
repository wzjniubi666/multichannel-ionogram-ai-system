# 系统接口

## 主机与FPGA

| 接口 | 波束合成A | YOLO识别B |
|---|---|---|
| 板卡/PC | 192.0.2.1 / 192.0.2.2 | 相同IP |
| UDP端口 | 5000 | 1234 |
| Magic | 0x42464D31（BFM1） | 0x594F4C4F（YOLO） |
| 请求头 | 32字节，version2 | !5I：magic/seq/op/address/count |
| 输入 | 512周期×16路I16/Q16；32个IQ包 | 65536个RGB32字；每包最多360字 |
| 输出 | 512个re48/im48，16个RESULT包 | 65536个INT16特征，HWC打包后转NCHW |
| 事务 | CONFIG→ACK→IQ逐包ACK→收齐RESULT | opcode1写、2读；seq与状态核对 |
| 失败策略 | 坏包/乱序/超时停止，不自动重试 | 原0.75s超时、最多4次尝试；数值失败停止 |

两协议不可互换。JTAG及PHY管理/时钟/管脚约束属于对应镜像，不能混用XDC或据端口不同推断同一镜像同时支持两协议。

模式A字段与状态码详见beamforming/interface.md；模式B寄存器见recognition/interface.md。模式B输入0x100000、输出0x400000、引擎ID地址0x00000C；模式A没有这些地址寄存器接口。

## 阶段间文件交接

输入是完整合成结果目录，必须包含scan_summary.json及blue_figures/mvdr_blue.png。默认要求source=hardware、status=COMPLETE_HARDWARE、verified_frames=planned_frames>0、14有效通道。系统只复制原图，不缩放、不去轴、不修改色标，并生成handoff.json，记录原目录、计划/摘要/图片哈希、来源和目标路径。

交接输出位于metrics/runs/handoff/时间编号/。识别界面的--image参数只显示图片，关闭添加后自动识别；由用户明确开始板卡动作。识别后另存检测图、框/类别/置信度及原校验报告。

这是可追溯的文件级接口，不证明模型在该图形风格、坐标或回波分布上的准确率。原两阶段证据各自有效，不合并成未经执行的端到端硬件验证。
