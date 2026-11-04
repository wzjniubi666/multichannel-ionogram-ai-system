
# Create a project
open_component -reset component_basic_arithmetic -flow_target vivado

# Add design files
add_files pointer_arith.c
# Add test bench & files
add_files -tb pointer_arith_test.c
add_files -tb result.golden.dat

# Set the top-level function
set_top pointer_arith

# ########################################################
# Create a solution
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 4

# Set variable to select which steps to execute
set hls_exec 2


csim_design
# Set any optimization directives
set_directive_interface -depth 5 -mode m_axi "pointer_arith" d
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


