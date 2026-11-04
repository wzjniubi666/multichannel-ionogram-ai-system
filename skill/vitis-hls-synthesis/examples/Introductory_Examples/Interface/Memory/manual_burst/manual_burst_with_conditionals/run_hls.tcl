
# Create a project
open_component -reset component_manual_burst_with_conditionals -flow_target vivado

#Add design files
add_files example.cpp
#Add test bench & files
add_files -tb example_test.cpp

#Set the top-level function
set_top example

#Create a solution
#Define technology and clock rate
set_part  {virtexu}
create_clock -period 3

csim_design
csynth_design	
cosim_design


