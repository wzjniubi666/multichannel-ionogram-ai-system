# 整合验证范围

新增检查日志与JSON在metrics/logs/integration。包括：统一目录、原复制文件及保护资产SHA256、运行代码语法/根目录/资源路径、识别MEM载入与三组既有FPGA特征对应、包内9帧ACTIVE14整数重放、总入口/独立解释器/完整结果交接及缺失/模拟来源拒绝测试。

recognition/check_project.py执行迁移后的完整性检查；--model与verify_reference.py可在另一台电脑已配置好的YOLO/PyTorch环境中运行。本次整合检查核对参数、路径和既有特征，完整模型及实板验证沿用YOLO电脑的原记录。旧YOLO的真实板卡三图证据、原GUI测试、合成实时UI13项与恢复模拟5项均按原样归档。

本次不会执行diagnose.tcl或真实上板入口，不编程FPGA、不修改网卡、不打开UDP socket。新旧源文件映射见merge_manifest.json/path_migration.json；统一内容清单见package_manifest.json。最终新增结果以integration/verification.json和相应日志为准。
