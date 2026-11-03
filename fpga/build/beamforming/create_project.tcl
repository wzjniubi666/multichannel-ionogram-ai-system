# New convenience project, not the original release build flow.
set delivery_root [file normalize [file join [file dirname [info script]] ../../..]]
set gui_out [file join $delivery_root fpga build beamforming work gui_active14]
if {[file exists $gui_out]} {error "Output exists; choose a new GUI directory: $gui_out"}
file mkdir [file dirname $gui_out]
create_project active14 $gui_out -part xc7k325tffg900-2
add_files [glob -directory [file join $delivery_root fpga src beamforming release_sources] *.v]
add_files -fileset constrs_1 [file join $delivery_root fpga src beamforming release_constraints kt325t_network_board.xdc]
foreach script {board_rgmii_duty_model.tcl board_network_cdc.tcl board_sync_preserve.tcl board_same_clock_paths.tcl} {
    set x [file join $delivery_root fpga src beamforming release_constraints $script]
    add_files -fileset constrs_1 $x
    set f [get_files $x]
    set_property FILE_TYPE XDC $f
    set_property USED_IN_SYNTHESIS false $f
    set_property PROCESSING_ORDER LATE $f
}
add_files -fileset sim_1 [concat \
    [glob -directory [file join $delivery_root fpga src beamforming tb] *.v] \
    [glob -directory [file join $delivery_root fpga src beamforming tb] *.sv]]
set_property top kt325t_network512_board_top [get_filesets sources_1]
set_property top tb_kt325t_network512_board [get_filesets sim_1]
update_compile_order -fileset sources_1
puts "Created GUI project. Testbench vectors need explicit paths; use README for release build."
