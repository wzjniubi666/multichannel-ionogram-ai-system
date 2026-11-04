
set parent_dir_name [file tail [file dirname [file normalize [info script]]]]
set my_top "transposed_fir"

# Create a project
open_component -reset component_$my_top -flow_target vivado

# Add design files
add_files $my_top.cpp
# Add test bench & files
add_files -tb ${my_top}_test.cpp

# Set the top-level function
set_top $my_top

# ########################################################
# Create a solution
# Define technology and clock rate
#set_part  {versalprime}
set_part {xcvp1702-vsva3340-3HP-e-S}
create_clock -period 800MHz

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
	export_design -flow impl
} else {
	# Default is to exit after running csynth
	csynth_design
}

exit

