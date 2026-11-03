# 主机与 FPGA 接口

JTAG 负责下载 .bit 和 MDIO 初始化；图片与特征通过以太网 UDP。
默认主机 192.0.2.2/24，板卡 192.0.2.1，双方 UDP 端口 1234。
地址当前写在 host/app/udp_transport.py 和 RTL 中；settings.json 只配置 Vivado 路径，不能修改网口 IP。
连接前应手动确认有线网卡地址适配，避免相同地址冲突；程序不自动修改电脑网卡设置。

请求：网络字节序 `!5I`，magic=0x594f4c4f、seq、opcode、byte_address、count，写请求后接 count 个 32 位字。
opcode=1 写，opcode=2 读。应答 `!4I`：magic、seq、status、count，随后是读回字。
状态非零报错；每包最多 360 words，超时 0.75 秒，最多 4 次尝试。

| 字节地址 | 含义 |
|---|---|
| 0x000000 | 写 1 启动；读 1 表示完成 |
| 0x000004 | 本次 nonce，完成后读回核验 |
| 0x000008 | 总核心周期计数 |
| 0x00000c | 引擎 ID 0x594f4c47 |
| 0x001000 | 60 个原始 INT32 累加器抽样值 |
| 0x100000 | 输入：65536 个 32 位 RGB 字，R 位0..7、G 位8..15、B 位16..23 |
| 0x400000 | 输出：32768 个 32 位字，按低16位/高16位解包成65536个 INT16，存储顺序 HWC |

主机反序列化后转成 NCHW。完整寄存器实现以 fpga/src/rtl/c3_udp_engine.v、udp_axi_endpoint.v 和 host/app/udp_transport.py 为准。
PHY RTL8211F，MDIO 地址1；已实测 1000 Mbps 全双工和约125MHz RX 时钟。千兆是物理协商速率，并非实际图片传输吞吐。
