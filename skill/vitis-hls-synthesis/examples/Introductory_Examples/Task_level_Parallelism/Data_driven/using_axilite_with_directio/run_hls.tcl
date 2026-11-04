open_component -reset proj -flow_target vivado
set_top test
add_files test.h
add_files test.cpp
add_files -tb test_tb.cpp 
set_part {xc7v585t-ffg1761-2}
create_clock -period 5 -name default

csim_design

csynth_design
	
cosim_design 


exit