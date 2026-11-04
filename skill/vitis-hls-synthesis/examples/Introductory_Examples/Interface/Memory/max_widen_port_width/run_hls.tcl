
# Create a project
open_component -reset component_max_widen_port_width -flow_target vivado

#Add design files
add_files example.cpp
# Add test bench & files
add_files -tb example_test.cpp 

# Set the top-level function
set_top example

# ########################################################
# Create a solution

# Define technology and clock rate
set_part {xcvu9p-flga2104-2-i}
create_clock -period "75MHz"

# Set any global configuration settings
config_interface -m_axi_max_widen_bitwidth 256
config_interface -m_axi_alignment_byte_size 64

csim_design
csynth_design
cosim_design

exit
