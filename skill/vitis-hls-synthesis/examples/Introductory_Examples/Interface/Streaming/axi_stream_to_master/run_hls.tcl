
# Create a project
open_component -reset component_axi_stream_to_master -flow_target vivado

# Add design files
add_files example.cpp
# Add test bench & files
add_files -tb example_test.cpp

# Set the top-level function
set_top example

# ########################################################
# Create a solution

# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 5

# Set variable to select which steps to execute
set hls_exec 2


csim_design
# Set any optimization directives
# End of directives

if {$hls_exec >= 1} {
	# Run Synthesis
   csynth_design
}
if {$hls_exec >= 2} {
	# Run Synthesis, RTL Simulation
   cosim_design
}
if {$hls_exec >= 3} { 
	# Run Synthesis, RTL Simulation, RTL implementation
   #export_design -format ip_catalog -version "1.00a" -library "hls" -vendor "xilinx.com" -description "A streaming IP created w/ Vivado HLS" -evaluate verilog
   export_design -format ip_catalog -evaluate verilog
}

exit
