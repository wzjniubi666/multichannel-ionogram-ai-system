# 模型与量化参数

- 来源：用户训练的 YOLOv5nu `runs/detect/train2/weights/best.pt`，不是 COCO 预训练权重。
- SHA256：`eb69a4d0f75e326b97e80f4c5cbbc6bc47b2b3c0b300a74649090d219484887e`。
- 类别：0 Backscatter echo；1 Vertical echo。
- 输入：RGB，NCHW，1×3×256×256，letterbox，除以 255。
- FPGA：前 5 个模块、15 个卷积；INT8 权重、INT16 激活、INT32 累加。
- 其余网络和类别相关 NMS（conf=0.25，IoU=0.45）在电脑运行。
- 14 张训练图片校准样本在 calibration_images/；固定参数在 fpga/build/board_case/*.mem 和 manifest.json。
- .pt、.mem 与 .bit 是配套的一组。更换 .pt 不能直接沿用当前硬件权重；需要重新校准、生成参数和配置并验证。
- 不需要 .onnx、.xmodel 或 .engine。本工程使用自定义 RTL，不使用 Vitis AI DPU。
- 模型、数据由用户提供；转发前请确认自身拥有相应分享权利。第三方 YOLO 授权文件保留在 host/app/vendor/。

公开版仅匿名化PT容器内一项训练路径字符串；所有非pickle归档成员（含权重张量）字节一致。公开bit需本地配置网络后重新构建。
