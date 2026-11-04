
# Create a project
open_component -reset component_using_defines -flow_target vivado

# Add design files
add_files dot_product.cpp
# Add test bench & files
add_files -tb tb_dot_product.cpp

# Set the top-level function
set_top dot_product

# ########################################################
# Create a solution
# Define technology and clock rate
set_part {xcvu9p-flga2104-2-i}
create_clock -period 5

# Set variable to select which steps to execute
set hls_exec 2

csim_design
# Set any optimization directives
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
	# Default is to exit after running csynth
	csynth_design
}

exit