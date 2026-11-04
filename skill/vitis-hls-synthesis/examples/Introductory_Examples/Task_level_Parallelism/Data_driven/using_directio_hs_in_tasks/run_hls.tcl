open_component -reset proj -flow_target vivado
set_top test
add_files test.cpp 
add_files -tb test_tb.cpp -cflags "-Wno-unknown-pragmas"
set_part {xc7v585t-ffg1761-2}
create_clock -period 5 -name default
config_export -vivado_clock 5

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

