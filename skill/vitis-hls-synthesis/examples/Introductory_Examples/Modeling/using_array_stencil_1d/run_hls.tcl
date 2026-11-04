
set top top
# Create a project

set src_file dut.cpp

open_component -reset component_using_array_stencil_1d -flow_target vivado
# Add design files

add_files $src_file -cflags "-I ."
# Add test bench & files

add_files -tb test.cpp -cflags "-I ."
# Set the top-level function

set_top $top
# ########################################################
# Create a solution
set_part zynq
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period "300MHz"
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
	# Default is to exit after setup
	csynth_design
}


exit
