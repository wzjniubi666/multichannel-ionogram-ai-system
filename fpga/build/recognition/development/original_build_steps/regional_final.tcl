set root [file dirname [file normalize [info script]]]
cd $root/board_case
open_checkpoint routed.dcp
read_xdc $root/rx_ddr_constraints.xdc

# The old optional 256-byte trace RAM inferred 32 half-BRAMs; it is unused by inference.
set zero_trace [get_nets -of_objects [get_pins -of_objects [lindex [get_cells -hier -filter {REF_NAME == GND}] 0] -filter {DIRECTION == OUT}]]
set trace_rams [get_cells -hier -filter {REF_NAME =~ RAMB* && NAME =~ cap_memory_reg*}]
set trace_outputs [get_nets -of_objects [get_pins -of_objects $trace_rams -filter {DIRECTION == OUT}]]
puts "REMOVED_TRACE_BRAM_PRIMITIVES [llength $trace_rams]"
remove_cell $trace_rams
foreach n $trace_outputs {
 set sinks [get_pins -of_objects [get_nets $n] -filter {DIRECTION == IN}]
 if {[llength $sinks]} {disconnect_net -net $n -objects $sinks;connect_net -hier -net $zero_trace -objects $sinks}
}

set buffer [get_cells net/u_gmii_to_rgmii/receiver/BUFG_inst]
set ni [get_nets -of_objects [get_pins $buffer/I]]
set no [get_nets -of_objects [get_pins $buffer/O]]
set allp [get_pins -of_objects [get_nets $no] -filter {DIRECTION == IN}]
set receivers [get_cells -of_objects $allp]
set network [get_cells -hier -filter {(NAME =~ net/* && NAME !~ net/cnn/*) || NAME =~ net/cnn/endpoint/* || NAME =~ cap_* || NAME =~ rx_binary* || NAME =~ rx_gray*}]
set rxregion [get_clock_regions -of_objects [get_sites -of_objects [get_cells net_rxc_IBUF_inst]]]
set relocate {}
foreach ram [get_cells -hier -filter {REF_NAME == RAMB36E1 && NAME =~ net/cnn/* && NAME !~ net/cnn/endpoint/*}] {
 if {[get_clock_regions -of_objects [get_sites -of_objects $ram]] eq $rxregion} {set relocate $ram;break}
}
if {[llength $relocate]!=1} {error "Could not identify one adjacent feature BRAM to relocate"}
puts "REGIONAL_SLOT_RELEASE region=$rxregion feature_bram=$relocate"
set movable [lsort -unique [concat $receivers $network $relocate]]
set movable [get_cells $movable -filter {IS_PRIMITIVE == 1}]
set fixed [filter [get_cells -hier -filter {IS_PRIMITIVE == 1}] {NAME !~ net/* && NAME !~ cap_* && NAME !~ rx_binary* && NAME !~ rx_gray*}]
set corefixed [get_cells -hier -filter {IS_PRIMITIVE == 1 && NAME =~ net/cnn/* && NAME !~ net/cnn/endpoint/*}]
set_property IS_LOC_FIXED true [concat $fixed $corefixed]
set changed_nets [get_nets -of_objects [get_pins -of_objects $movable]]
route_design -unroute -nets $changed_nets
set_property IS_LOC_FIXED false $movable
unplace_cell $movable
remove_cell $buffer
create_cell -reference BUFR net/u_gmii_to_rgmii/receiver/BUFG_inst
set nb [get_cells net/u_gmii_to_rgmii/receiver/BUFG_inst]
set_property BUFR_DIVIDE BYPASS $nb
set_property SIM_DEVICE 7SERIES $nb
connect_net -hier -net $ni -objects [get_pins $nb/I]
connect_net -hier -net $no -objects [get_pins $nb/O]
set one [get_nets -of_objects [get_pins -of_objects [lindex [get_cells -hier -filter {REF_NAME == VCC}] 0] -filter {DIRECTION == OUT}]]
set zero [get_nets -of_objects [get_pins -of_objects [lindex [get_cells -hier -filter {REF_NAME == GND}] 0] -filter {DIRECTION == OUT}]]
connect_net -hier -net $one -objects [get_pins $nb/CE]
connect_net -hier -net $zero -objects [get_pins $nb/CLR]
set_property IDELAY_VALUE 0 [get_cells -hier -filter {REF_NAME == IDELAYE2}]
place_design -directive Explore
set besttap -1
set bestmargin -1000
foreach tap {0 4 8 12 16} {
 set_property IDELAY_VALUE $tap [get_cells -hier -filter {REF_NAME == IDELAYE2}]
 set sp [get_timing_paths -setup -from [get_ports {net_rx_ctl net_rxd[*]}] -max_paths 1]
 set hp [get_timing_paths -hold -from [get_ports {net_rx_ctl net_rxd[*]}] -max_paths 1]
 set ss [get_property SLACK [lindex $sp 0]]
 set hs [get_property SLACK [lindex $hp 0]]
 puts "RX_TAP_SCAN tap=$tap setup=$ss hold=$hs"
 set margin [expr {min($ss,$hs)}]
 if {$margin>$bestmargin} {set bestmargin $margin;set besttap $tap}
}
set_property IDELAY_VALUE $besttap [get_cells -hier -filter {REF_NAME == IDELAYE2}]
puts "RX_BEST_TAP $besttap margin=$bestmargin"
set f [open rx_selected_tap.txt w];puts $f $besttap;close $f
write_checkpoint -force regional_placed.dcp
phys_opt_design -directive Explore
route_design
write_checkpoint -force regional_routed.dcp
report_timing_summary -file regional_timing.rpt
report_timing -hold -from [get_ports {net_rx_ctl net_rxd[*]}] -max_paths 10 -file regional_rx_hold.rpt
report_timing -setup -from [get_ports {net_rx_ctl net_rxd[*]}] -max_paths 10 -file regional_rx_setup.rpt
set setup [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]
set hold [get_property SLACK [lindex [get_timing_paths -hold -max_paths 1] 0]]
puts "REGIONAL_SLACK setup=$setup hold=$hold"
if {$setup<0 || $hold<0} {error "Regional timing failed"}
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_bus_skew -file bus_skew.rpt
write_debug_probes -force udp_mdio_bridge.ltx
write_bitstream -force udp_mdio_bridge.bit
write_checkpoint -force udp_mdio_bridge.dcp
set f [open build_ready.txt w];puts $f "New model, regional gigabit DDR and 80MHz core timing passed";close $f
exit
