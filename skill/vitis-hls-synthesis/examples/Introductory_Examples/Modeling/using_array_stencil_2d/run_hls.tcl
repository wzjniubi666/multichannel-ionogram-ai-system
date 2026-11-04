open_component -reset component_using_array_stencil_2d -flow_target vivado
set_top Filter2DKernel
add_files -tb test.cpp  
add_files -tb cmdlineparser.cpp  
add_files -tb filter2d_sw.cpp    
add_files     filter2d_hw.cpp    
# ########################################################
# Create a solution
set_part {xcku11p-ffva1156-1-e}
create_clock -period 3.33333333 -name default
# Run Synthesis, RTL Simulation, RTL implementation and Exit
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
