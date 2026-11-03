# 部署与运行

## 桌面上位机入口

已补入现成的桌面上位机。直接双击 `../app/com/FPGAHost.exe` 或本目录 `启动上位机.vbs`；详细操作见 [上位机说明](../../docs/host_software.md) 和 [桌面程序说明](../app/com/README.md)。

在本工作区下自动发现原工程及Python。移动交付包后运行 `configure_desktop.ps1 -WorkspaceRoot '.'` 配置原工作区。上位机继续使用原生产发布门禁，虚拟环境及完整原始数据未装入压缩包。`build_desktop.ps1`可从C#源重新编译启动器。

桌面程序包括文件选择、9点/整幅、离线自测、收发进度、停止/继续、历史结果、图表缩放导出与网卡恢复。新目录适配文件以 `report/desktop_adaptation.json` 为准，原部署源码在 `original_gui/`。

## 命令行与原始入口

离线入口为 `run_offline.ps1`，使用项目相对路径，不操作网卡/板卡。Python 3.12，依赖见requirements.txt；实际本次环境版本见 `../../metrics/logs/package_verification_*.json`。

`original/`中的PowerShell以及 `../../fpga/build/original/`中的工具逐字节复制，保留原目录假设、绝对路径和发布封印。`../app/`顶层CLI文件也是原源码，某些程序由自身位置向上推导原工程根目录，移动后不保证全部命令独立运行。新增的`../app/com/`桌面入口已适配本包路径。不要在本包中直接运行归档的实板脚本，也不要改封印绕过生产门禁。

完整实板复现仍使用原工作区：

```powershell
# 原工作区只读预检；不发包、不修改网卡
& './.venv-cos/Scripts/python.exe' -E './XCK325Tboshuhecheng/python/m512_active14_scan.py' check --plan './XCK325Tboshuhecheng/validation/m_hf512_14ch_20261028/actual11_plan14_v2'
```

核对目标板、接线及bit后，原Vivado入口为：

```tcl
source {./XCK325Tboshuhecheng/tools/program_m512_active14.tcl}
```

实际扫描入口（由操作者在管理员PowerShell执行）：

```powershell
& './XCK325Tboshuhecheng/run_m512_active14_board_test.ps1' -Mode Run
```

默认9点计划先做验收。完整11:00扫描需明确传入 `-PlanDirectory './XCK325Tboshuhecheng/validation/m_hf512_14ch_20261028/scan41x118_110000_v1'`。使用新14路镜像和14路计划，不能与旧16路或32周期混用。

原入口会预检、备份网络设置、等待接线确认、扫描并恢复配置。中途超时保留结果，不自动重试。完整原始数据库和逐周期CSV留在原工作区，精确路径见 `../../report/external_artifacts.json`；本包保存两批摘要、数值产品与图像。
