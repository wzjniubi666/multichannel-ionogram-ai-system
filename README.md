# 多通道电离图智能识别系统 · Multichannel Ionogram AI System

FPGA MVDR beamforming and YOLO ionogram echo recognition on PZ-K7325T-FH / XC7K325T.

本项目把M序列斜返波束合成与YOLO回波识别整理为一个工程，提供两套上位机、统一总入口和完整电离图的文件交接。YOLO部分在另一台已有相应Python/PyTorch环境的电脑上运行。

## 工程结构

```text
README.md
docs/
  architecture.md
  interface.md
  hardware_setup.md
fpga/
  src/{beamforming,recognition}/
  build/{beamforming,recognition}/
  report/{beamforming,recognition}/
host/
  model/{beamforming,recognition}/
  app/                         两套上位机、总入口与通信代码
  deploy/                      部署脚本、独立环境和路径配置
metrics/
  metrics.csv
  logs/
  scripts/
  evidence/{beamforming,recognition}/
skill/README.md
report/
```

## 两个运行阶段

| 项目 | 波束合成 | 回波识别 |
|---|---|---|
| FPGA计算 | 16槽位、14有效、512周期MVDR；屏蔽07/15 | YOLO前15卷积，后续网络/NMS在PC |
| 传输 | BFM1 v2 / UDP5000 | YOLO寄存器协议 / UDP1234 |
| 处理参数 | ACTIVE_MASK=0x7F7F，113°/35°，5%加载 | RGB256×256，INT8权重/INT16激活 |
| 环境 | Python3.12，原Vivado2025.2流程 | 已有Python3.10/PyTorch环境，原Vivado2018.3流程 |

同一板卡按阶段切换各自bit；本仓库没有把两个bit拼成一个镜像。先完成并退出合成任务，再初始化识别模式。总入口和图片导入不会自动操作板卡。

## 使用

```powershell
git clone https://github.com/wzjniubi666/multichannel-ionogram-ai-system.git ionogram-ai-system
cd ionogram-ai-system
python metrics/scripts/verify_publication.py
# 安装NumPy的环境可重放包内数值夹具（不连接板卡）
python metrics/scripts/verify_publication.py --numerics
```

Windows总入口为根目录`电离图智能识别系统.exe`或`启动系统.vbs`；在`host/deploy/system_settings.json`配置总入口Python，在总界面选择YOLO电脑对应解释器。也可在各自电脑分别运行：

```powershell
# YOLO电脑，在现有识别环境中
python host/app/recognition/app_gui.py
```

波束合成的生产部署沿用已校验的工作区与发布门禁；通过`host/deploy/beamforming/configure_desktop.ps1`配置相应工作区。公开版没有个人现场的MAC/JTAG绑定、原始COS及私有验收封印。读者需针对自己的板卡、网卡和构建验证记录生成发布配置，不能绕过原门禁。公开模板中的原MAC由`BEAMFORMING_ORIGINAL_MAC`显式提供。

完整结果的`blue_figures/mvdr_blue.png`可通过总入口交接到识别界面；跨电脑时复制图片和`handoff.json`即可。未完成的结果保持灰色，不用参考值补图。图像交接本身不构成新识别准确率或物理SNR提升的证明。

## 模型、构建与证据

`host/model/recognition/best.pt`与识别MEM来自配套工程；bit需本地配置通信地址后重新构建，模型SHA256为`eb69a4d0f75e326b97e80f4c5cbbc6bc47b2b3c0b300a74649090d219484887e`。类别为Backscatter echo和Vertical echo；不要仅替换PT继续使用旧硬件参数。

公开版保留源码、匹配模型参数、软件数值夹具和选定图表。通信地址已改为文档示例；原bit/LTX不公开，需按[本地通信配置](docs/network_configuration.md)重建。厂商手册、DCP、原始个人日志、网络备份、私有发布封印及重复迁移历史不发布。路径和采集位置标识已匿名化；原始模型与数值参数字节保持。历史硬件指标不代表本次执行了新的板卡测试或取得端到端加速。

详见[架构](docs/architecture.md)、[接口](docs/interface.md)、[接线](docs/hardware_setup.md)、[模型](host/model/MODEL.md)和[发布说明](report/publication.md)。部分归档文档描述完整本地交付版的可选工件，公开内容以发布说明和文件清单为准。

## 许可

项目原创代码采用[GNU AGPL-3.0](LICENSE)。Ultralytics和其他第三方内容保留原许可/版权。板卡教程参考RTL不在本项目的AGPL重新许可范围内；其授权状态及来源见[第三方声明](THIRD_PARTY_NOTICES.md)。本仓库不为贡献者不拥有的第三方材料授予额外权利。
