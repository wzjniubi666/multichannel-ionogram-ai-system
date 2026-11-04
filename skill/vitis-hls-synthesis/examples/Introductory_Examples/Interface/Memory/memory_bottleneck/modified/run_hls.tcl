
# Create a project
open_component -reset component_modified -flow_target vivado

# Add design files
add_files mem_bottleneck_resolved.cpp
# Add test bench & files
add_files -tb mem_bottleneck_resolved_test.cpp
add_files -tb result.golden.dat

# Set the top-level function
set_top mem_bottleneck_resolved

# ########################################################
# Create a solution

# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 4

# Set variable to select which steps to execute
set hls_exec 2


csim_design

# Set any optimization directives
set_directive_pipeline mem_bottleneck_resolved/SUM_LOOP
# End of directives

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

