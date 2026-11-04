
# Create a project
open_component -reset component_handling_deadlock -flow_target vivado

# Add design files
add_files test.cpp
# Add test bench & files
add_files -tb test_tb.cpp

# Set the top-level function
set_top test

# ########################################################
# Create a solution
# Define technology and clock rate
set_part {xcvu9p-flga2104-2-i}
create_clock -period 5 -name default

if { [catch {csim_design} err] } {
  puts "PASS: catch error."
  close_project 
  exit 0
} else {
  puts "ERROR: did not catch error."
  close_project
  exit 1 
}

