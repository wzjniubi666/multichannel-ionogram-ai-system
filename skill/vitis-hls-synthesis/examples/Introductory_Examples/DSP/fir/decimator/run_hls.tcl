
# Create a project
open_component -reset comp_decimator -flow_target vivado

# Add design files
add_files fir_top.cpp
# Add testbench files
add_files -tb fir_tb.cpp

# Set the top-level function
set_top fir_top

# Define technology and clock rate
set_part  xcvc1902-vsva2197-2MP-e-S
create_clock -period 2.0

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
