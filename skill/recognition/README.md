# 可复用操作工作流

这是项目操作清单，不是必须安装的 Codex Skill。

1. 离线：激活环境，运行 host/app/check_project.py --model 和 metrics/scripts/verify_reference.py。
2. 接线：按 docs/hardware_setup.md，确认板卡型号、供电、JTAG 和有线 IP。
3. 配置：在 host/deploy/settings.json 填写 Vivado 路径。
4. 识别：启动根目录 app_gui.py，初始化后添加图片，等待完成。
5. 核验：读取本次 report.json，确认 fpga_used、validation_mode、逐值/挑战校验，不能把 CPU 回退当 FPGA 成功。
6. 存档：保存检测图、report.json、worker.log 和特征；性能引用时写清计时范围。
7. 结束：任务完成或停止后再断电；下一次上电重新下载配置。
8. 更换模型：备份当前配套文件，重新校准、参数生成、实现并复核，禁止只替换 .pt。
