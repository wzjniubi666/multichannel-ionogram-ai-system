
# Create a project
open_component -reset component_using_axi_lite_with_user_defined_offset -flow_target vivado

# Add design files
add_files example.cpp
# Add test bench & files
add_files -tb example_test.cpp
set_top example
set_part  {xcvu9p-flga2104-2-i}
create_clock -period "200MHz"
csim_design
csynth_design
cosim_design

