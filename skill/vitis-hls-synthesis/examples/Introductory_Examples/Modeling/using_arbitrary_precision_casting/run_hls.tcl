
# Create a project
open_component -reset component_using_arbitrary_precision_casting -flow_target vivado

# Add design files
add_files arbitrary_precision_casting.cpp
# Add test bench & files
add_files -tb arbitrary_precision_casting_test.cpp
add_files -tb result.golden.dat

# Set the top-level function
set_top arbitrary_precision_casting

# ########################################################
# Create a solution
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 4

# Set variable to select which steps to execute
set hls_exec 2


csim_design

if {$hls_exec == 1} {
	# Run Synthesis and Exit
	csynth_design
	
} elseif {$hls_exec == 2} {
	# Run Synthesis, RTL Simulation and Exit
	csynth_design
	
	cosim_design
} elseif {$hls_exec == 3} { 
	# Run Synthesis, RTL Simulation, RTL implementation and Exit
	csynth_design
	
	cosim_design
	export_design
} else {
	# Default is to exit after setup
	csynth_design
}

exit

