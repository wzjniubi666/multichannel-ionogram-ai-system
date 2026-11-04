open_component -reset directIo -flow_target vivado
set_top krnl_stream_vdatamover
add_files -tb tb.cpp  
add_files     dut.cpp    
# ########################################################
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
