

# Create a project
open_component -reset component_using_array_of_streams -flow_target vivado

# The source file and test bench
add_files example.cpp
add_files -tb example_test.cpp

# Specify the top-level function for synthesis
set_top	dut

###########################
# Solution settings

# Create solution1

# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period "400MHz"

csim_design
# Run Synthesis, RTL Simulation, RTL implementation and Exit
csynth_design
cosim_design
# Generate pcore
# export_design -format ip_catalog

exit


