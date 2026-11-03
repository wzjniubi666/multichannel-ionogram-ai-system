# 模型与参考

## 识别模型

recognition/best.pt为用户训练的YOLOv5nu两类回波权重：0 Backscatter echo、1 Vertical echo。SHA256：eb69a4d0f75e326b97e80f4c5cbbc6bc47b2b3c0b300a74649090d219484887e。

256×256 RGB、letterbox、NCHW、除255；前15卷积为INT8权重/INT16激活/INT32累加，后续网络和NMS在PC。14张校准图片在recognition/calibration_images，配套参数在fpga/build/recognition/board_case。权重张量与数值MEM保持；PT仅匿名化一项训练路径元数据。网络仿真MEM已替换地址并重算校验，原bit不公开，需本地重建。重训后不能只换PT继续使用旧bit。

YOLO第三方源码和许可在host/app/recognition/vendor，未改库代码。YOLO部分在另一台已配置好PyTorch环境的电脑上运行，沿用原模型、依赖和验证记录。可在该电脑的现有识别环境中执行check_project.py --model复查原三组特征/NMS。

## 波束合成参考

beamforming/HFceshi保存实际m255a.mat与原MATLAB脚本。数值参考位于host/app/beamforming/mvdr_fixed_reference.py、mvdr_reference.py及m_reference_preprocess.py。它们是信号处理参考，不是图像识别权重。原9点实际IQ、定点权值和输出在metrics/evidence/beamforming/active14_smoke_plan。

每种模型对应各自输入与指标；原SNR/结构图、识别置信度和真实分类准确率不可混同。
