# FPGA源码来源

- `rtl/`：原工程rtl目录的非tb设计代码，未改写。
- `tb/`：同目录tb_开头的Verilog/SystemVerilog仿真文件，未改写。
- `constraints/`：原工程当前约束全部副本。
- `vendor/`：原供应商参考代码和来源说明，保留原README/provenance。
- `release_sources/`、`release_constraints/`：通过implementation_v4的冻结输入，与本包bit/DCP绑定。便携构建用这两处，不与vendor重复加入。

逐文件原路径及SHA256见 `../../report/source_manifest.json`。源码目录含旧32周期及抽象顶层以保留完整开发上下文，当前生产顶层明确为kt325t_network512_board_top。
