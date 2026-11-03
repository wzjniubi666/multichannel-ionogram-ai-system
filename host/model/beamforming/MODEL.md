# 模型与参考文件

这里的“模型”指MVDR数值模型与M序列参考码表。没有ONNX/PT神经网络权重，也不需要模型下载。

| 文件 | 用途 |
|---|---|
| ../app/mvdr_fixed_reference.py | 对齐RTL位宽/有符号/截断/ACTIVE_MASK的整数模型 |
| ../app/mvdr_reference.py | 浮点MVDR、阵列坐标与导向函数；旧COS入口含历史C数据参数 |
| ../app/m_reference_preprocess.py | 实际255码表、512周期、4相位相关压缩 |
| ../app/m512_active14_plan.py | 14路有效、113°/35°、512周期计划准备 |
| HFceshi/m255a.mat | 本版实际8阶255码片±1参考码 |
| HFceshi/readone.m、readall.m | 原始参考MATLAB脚本，示例参数与本批M数据不同 |
| HFceshi/其余mat | 原工程提供的其他长度码表，仅供历史追溯 |

采用实际码表而非猜测多项式。`load_reference`验证255位±1及循环自相关(255,-1,…)。原MATLAB示例含不同采集日期、码阶、周期和字节序；当前M数据用8阶/512周期/4相位/大端，不能直接按示例参数读取。

本包9点IQ和预期权值/结果位于 `../../metrics/evidence/active14_smoke_plan`，可不依赖原COS完成离线整数重放。原始完整COS及扫描计划位置见 `../../report/external_artifacts.json`。

导向沿用L形10m、113°/35°，随频率变化；它是指定处理模型。现有文件不能证明自动识别电路图、通用目标方向或物理SNR提升。仅做合成演示时必须标记其合成性质。
