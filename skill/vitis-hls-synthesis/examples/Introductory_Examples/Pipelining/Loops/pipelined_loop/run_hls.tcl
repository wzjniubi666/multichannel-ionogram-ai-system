
# Create a project
open_component -reset component1_pipelined_loop -flow_target vivado

# Add design files
add_files loop_pipeline.cpp
# Add test bench & files
add_files -tb loop_pipeline_test.cpp
add_files -tb result.golden.dat

# Set the top-level function
set_top loop_pipeline

# ########################################################
# Create a solution
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 25

# Set variable to select which steps to execute
set hls_exec 2


csim_design
# Set any optimization directives
set_directive_pipeline loop_pipeline/LOOP_J
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
# ########################################################
# Create a project
open_component -reset component2_pipelined_loop -flow_target vivado

# Add design files
add_files loop_pipeline.cpp
# Add test bench & files
add_files -tb loop_pipeline_test.cpp
add_files -tb result.golden.dat

# Set the top-level function
set_top loop_pipeline

# Create a solution
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 25

# Set variable to select which steps to execute
set hls_exec 2



# Set any optimization directives
set_directive_pipeline loop_pipeline/LOOP_I
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


# ########################################################
# Create a project
open_component -reset component3_pipelined_loop -flow_target vivado

# Add design files
add_files loop_pipeline.cpp
# Add test bench & files
add_files -tb loop_pipeline_test.cpp
add_files -tb result.golden.dat

# Set the top-level function
set_top loop_pipeline

# Create a solution
# Define technology and clock rate
set_part  {xcvu9p-flga2104-2-i}
create_clock -period 25

# Set variable to select which steps to execute
set hls_exec 2



# Set any optimization directives
set_directive_pipeline loop_pipeline
set_directive_array_partition -type complete -dim 0 loop_pipeline A
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
	ccsynth_design
}

exit

