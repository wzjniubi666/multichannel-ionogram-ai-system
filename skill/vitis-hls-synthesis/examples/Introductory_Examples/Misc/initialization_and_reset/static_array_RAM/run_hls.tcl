
# ##################################################
# Utility procedures to be called in multiple places
# ##################################################
proc make_new_solution {{sol_name "solution1"}} {
    # Create the solution
    open_solution -reset $sol_name -flow_target vitis

    # Define technology and clock rate
    set_part  {xcvu9p-flga2104-2-i}
    create_clock -period 25
}

proc run_rest_of_the_flow {{hls_exec 2}} {

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
}

# ##################################################
# Main Entry: Create Project 
# ##################################################
open_component -reset component_static_array_RAM -flow_target vivado

# Add design files
add_files test.cpp
# Add test bench & files
add_files -tb test_tb.cpp

# Set the top-level function
set_top test

# ########################################################
# Solution_A
# ########################################################
make_new_solution "solution_A"

csim_design

# Set variable to select which steps to execute
set hls_exec 2

run_rest_of_the_flow $hls_exec

close_solution

# ########################################################
# Solution_B
# ########################################################
make_new_solution "solution_B"

csim_design

# Set any optimization directives
set_directive_reset test A
set_directive_reset test B
set_directive_reset test C
# End of directives

# Set variable to select which steps to execute
set hls_exec 2

run_rest_of_the_flow $hls_exec

close_solution

# ########################################################
# Solution_C
# ########################################################
make_new_solution "solution_C"

csim_design

# Set any optimization directives
config_rtl -reset state 
# End of directives

# Set variable to select which steps to execute
set hls_exec 2

run_rest_of_the_flow $hls_exec

exit

