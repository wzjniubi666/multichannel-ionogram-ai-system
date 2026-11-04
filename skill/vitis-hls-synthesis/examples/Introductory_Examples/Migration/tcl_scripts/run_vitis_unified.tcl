
# Create a component
open_component -reset component_pointer_basic -flow_target vivado

# Add design files
add_files pointer_basic.c
# Add test bench & files
add_files -tb pointer_basic_test.c
add_files -tb result.golden.dat

# Set the top-level function
set_top pointer_basic

# ########################################################
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 4

# Set variable to select which steps to execute
set hls_exec 2


csim_design
# Set any optimization directives
set_directive_interface -mode m_axi pointer_basic d -depth 1
# End of directives

# cosim_design option -trace_level all is used to create a VCD waveform file
if {$hls_exec == 1} {
	# Run Synthesis and Exit
	csynth_design
	
} elseif {$hls_exec == 2} {
	# Run Synthesis, RTL Simulation and Exit
	csynth_design
	
	cosim_design -trace_level all
} elseif {$hls_exec == 3} { 
	# Run Synthesis, RTL Simulation, RTL implementation and Exit
	csynth_design
	
	cosim_design -trace_level all
	export_design
} else {
	# Default is to exit after setup
	csynth_design
}

exit
