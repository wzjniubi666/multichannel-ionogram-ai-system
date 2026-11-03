# PZ 官方教程参考源码

从工作区已有 `1_FPGA.zip` 的 `1_FPGA/3_18_PZ_UDP_RGMII/` 提取。
`provenance.json` 保留确切 ZIP 条目和逐文件 SHA-256；这些 `.v` 文件保持原始字节，
原有版权和使用声明仍适用。本目录不是当前项目的全部设计源，不能整目录加入工程（含重复 Top）。

当前实际引用：

- `arp_tx.v`：ARP 响应发送引擎。
- `crc32.v`：官方发送引擎所需 CRC32。
- `rgmii_tx.v`：RGMII ODDR 输出（链路封装使用，真实管脚/双沿时序下一阶段确认）。

当前派生文件位于 `rtl/`：

- `bfm_vendor_udp_tx.v`：来自 `udp_tx.v`，仅改模块名、添加端口参数和调用方提供的 UDP 校验和。
- `bfm_rgmii_rx.v`：来自 `rgmii_rx.v`，模块名改变；RX_DV 取上升沿值，RX_ER 取上下沿 XOR；
  CNTVALUEIN 改为显式 5 位零。IDELAYCTRL 由 `rgmii_beamforming_link.v` 提供。

## 审查发现

原 UDP RX 数据为大端装配。最后数据字的 `rec_en`、`rec_pkt_done` 与字节数同时输出，
不足四字节时未覆盖位可能残留旧值；done 发生在 FCS 前。没有 IP/UDP 校验和、UDP 端口、
分片、完整帧长度或 FCS 校验，也没有 PHY RX_ER 输入。不能作为可信提交。

`net_ctrl.v` 会因 ARP 事件立即切换协议，可能打断 UDP。回环还将接收侧事件/数据直接连入
发送控制，且 `gmii_to_rgmii.v` 明确将发送时钟等同于接收时钟。新项目使用整帧仲裁与
两个方向的报文 CDC，不依赖这个隐含同域假设。

原例默认 BOARD_MAC 首字节 `0x99` 是组地址；新仿真默认值改为 `02:00:00:00:00:01`。
所有地址仍是示例参数，板上运行前绑定实际 PC MAC/IP/端口。

## PHY / MDIO 尚需板级确认

原文件混有 KSZ9031 注释，但 IP 实际为 RTL8211 配置。`mdio_ctrl.v` 从地址 0 开始扫描，
首次写 BMCR 也针对地址 0，然后探测 ACK/ID 高字 `0x001c`；使用页 `0x0d08` 中的
0x11/0x15 寄存器写 TX/RX delay，并循环监测/重写。当前板卡资料标注 PHY 地址 1。
因此本轮仅保留、审查该管理代码，未把这套扫描和延时写值直接接入数据链路。

`mdio_dri.v` 的 dri_clk 分频由 `floor(CLK_DIV/4)` 决定，再二分得到 MDC。
按原例 200 MHz 与 CLK_DIV=60 换算，MDC 约 3.33 MHz；这是源码计算，需按实际 PHY
数据手册核对允许频率。MDIO 的派生逻辑时钟还需要明确生成时钟约束。

形成真实板级 Top 时应先确认 PHY 准确型号/ID、地址、strap、TX/RX 内部延时和板级偏斜，
采用固定目标地址、读回核验、完整复位/失锁恢复与合适 MDC，再与 RGMII XDC 一并验收。
本轮 `rgmii_beamforming_link` 的 reset 必须由板级管理在时钟和 PHY 就绪后统一释放。
