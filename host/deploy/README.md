# 系统部署

根EXE/启动系统.vbs→start_system.ps1→host/app/system_launcher.py。默认总入口/波束Python在原工作区.venv-cos；system_settings.json可配置hub_python和recognition_python。波束合成继续按原封印工作区的.venv-cos运行。总入口只启动应用与图片预览，不发包或下载。

YOLO部分在另一台已配置好相应环境的电脑上运行，沿用Python3.10、原torch2.5/torchvision0.20等依赖；完整requirements和environment.yml在recognition/。跨电脑运行时通过电离图和交接清单连接两个阶段；同机部署可在系统窗口选择对应python.exe，或设置YOLO_PYTHON。波束3.12环境与识别环境分别保留。

YOLO的Vivado路径在recognition/settings.json或VIVADO_EXECUTABLE中配置，原验证工具为2018.3。合成构建使用原2025.2流程；本包没有安装任一工具或Python二进制环境。

波束生产门禁仍依赖原工作区XCK325Tboshuhecheng、HFceshi、.venv-cos及数据。迁移到另一台机器要带齐原工作区，并运行beamforming/configure_desktop.ps1指向该位置；不通过改旧哈希跳过预检。独立的包内9点检查不需要原COS。

旧子系统启动脚本/README保留其历史说明。当前有效路径是host/app/beamforming/com和host/app/recognition。总入口的--image交接默认不自动识别，硬件操作由用户在对应阶段明确启动。
