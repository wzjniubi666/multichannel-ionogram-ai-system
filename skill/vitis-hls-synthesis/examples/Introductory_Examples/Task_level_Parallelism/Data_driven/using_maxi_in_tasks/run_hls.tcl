open_component -reset proj -flow_target vivado
set_top stable_pointer
add_files dut.cpp 
add_files -tb dut_tb.cpp 
set_part zynq
create_clock -period 3.125 -name default
csim_design 

# Set variable to select which steps to execute
set hls_exec 2

csim_design
if {$hls_exec == 1} {
	# Run Synthesis and Exit
	csynth_design
	
} elseif {$hls_exec == 2} {
	# Run Synthesis, RTL Simulation and Exit
	csynth_design
	
	cosim_design -enable_tasks_with_m_axi 
} elseif {$hls_exec == 3} { 
	# Run Synthesis, RTL Simulation, RTL implementation and Exit
	csynth_design
	
	cosim_design -enable_tasks_with_m_axi -rtl verilog -trace_level all
	export_design
} else {
	# Default is to exit after setup
	csynth_design
}

exit
