set root [file dirname [file normalize [info script]]]
cd $root/board_case
open_checkpoint regional_routed.dcp
report_io -file io_before_constraints.rpt
read_xdc $root/pins_only.xdc
route_design
report_io -file io_final.rpt
set setup [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]
set hold [get_property SLACK [lindex [get_timing_paths -hold -max_paths 1] 0]]
puts "FINAL_SLACK setup=$setup hold=$hold"
if {$setup<0 || $hold<0} {error "Timing failed"}
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_bus_skew -file bus_skew.rpt
write_debug_probes -force udp_mdio_bridge.ltx
write_bitstream -force udp_mdio_bridge.bit
write_checkpoint -force udp_mdio_bridge.dcp
set f [open build_ready.txt w];puts $f "New model, regional gigabit DDR, fixed board pins and 80MHz core timing passed";close $f
exit
