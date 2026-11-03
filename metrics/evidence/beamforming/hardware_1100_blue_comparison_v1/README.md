# 11:00单通道与14路实板回包：蓝底配色

`mvdr14_hardware_blue.png`仅改变原实板图配色，保留其背景归一化与0～40dB范围。

`single00_vs_mvdr14_common_background.png`为主对照：共同单通道00背景、相同色标。

`single00_vs_mvdr14_individual_background.png`为补充结构图：各自背景，不能直接比较绝对抑制度。

单通道00来自同批下发IQ/gain的离线相干积累；MVDR来自用户本次实板回包。全部4838条事务的输入、回包、模型与NPZ对应已核对。原实板图片、NPZ、数据库及摘要哈希保持不变。所有原值和超出显示范围的点保留在comparison_data.npz/CSV；没有掩去底部回波，也没有平滑或插值。

两者使用同512周期相干求和取功率；指向113°/35°，屏蔽07/15。每频点中位数/ln2仅是参考背景，不是校准噪声或物理SNR。输出功率降低不能单独证明目标保真或SNR改善；本图没有独立留出记录。

原结果：.\result\M_MVDR512_ACTIVE14_hardware_20261028_182518_eb4b30

图源、变换、显示截断数和文件哈希见figure_manifest.json。
