open_component -reset proj -flow_target vivado
set_top adder_top
add_files simple_adder.h
add_files adder_top.h
add_files adder_top.cpp
add_files -tb adder_tb.cpp 
set_part {xc7v585t-ffg1761-2}
create_clock -period 5 -name default

csim_design

csynth_design
	
cosim_design 


exit
