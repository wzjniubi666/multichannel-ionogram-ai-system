
open_component -reset component_auto_burst_inference_failure -flow_target vivado
set_top krnl_transfer
add_files example.cpp
add_files example.h
add_files -tb example_tb.cpp -cflags "-Wno-unknown-pragmas" -csimflags "-Wno-unknown-pragmas"
set_part {xcvu11p-flga2577-1-e}
create_clock -period 10 -name default
config_interface -m_axi_alignment_byte_size 64 -m_axi_latency 64 -m_axi_max_widen_bitwidth 512
config_rtl -register_reset_num 3
source "directives.tcl"
csim_design
csynth_design
cosim_design -trace_level all

