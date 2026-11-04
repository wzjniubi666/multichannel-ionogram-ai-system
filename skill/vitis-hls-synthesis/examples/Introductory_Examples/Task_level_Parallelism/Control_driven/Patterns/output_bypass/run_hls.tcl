
#Solution -1 shows the problem 
open_component -reset component_output_bypass_prob -flow_target vivado
set_top dut
add_files dut.cpp
add_files -tb test_dut.cpp
set_part {xqku115-rlf1924-1-i}
create_clock -period 10 -name default
csim_design
csynth_design
cosim_design

#solution-2 to the input bypassing task 
open_component -reset component_output_bypass_sol -flow_target vivado
set_top dut
add_files dut_sol.cpp
add_files -tb test_dut.cpp
set_part {xqku115-rlf1924-1-i}
create_clock -period 10 -name default
csim_design
csynth_design
cosim_design

