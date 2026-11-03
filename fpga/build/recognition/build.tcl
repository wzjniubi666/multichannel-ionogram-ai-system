set root [file normalize [file join [file dirname [info script]] .. .. ..]]
cd $root/fpga/build/recognition/board_case
create_project -force c3 $root/fpga/build/recognition/generated -part xc7k325tffg900-2
set_property target_language Verilog [current_project]
create_ip -name jtag_axi -vendor xilinx.com -library ip -version 1.2 -module_name jtag_axi_0
set_property generate_synth_checkpoint false [get_files jtag_axi_0.xci]
generate_target all [get_ips jtag_axi_0]
set_msg_config -id {Synth 8-2898} -new_severity ERROR
read_verilog [glob $root/fpga/src/recognition/rtl/*.v]
read_xdc $root/fpga/src/recognition/constraints/board.xdc
synth_design -top udp_mdio_bridge -part xc7k325tffg900-2
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
set mdpin [get_pins -hier -filter {NAME =~ */dri_clk_reg/Q}]
if {[llength $mdpin]!=1} {error "MDIO divider pin not found"}
create_generated_clock -name mdio_controller -source [get_ports sys_clk_p] -divide_by 50 $mdpin
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sys_clk] -group [get_clocks -include_generated_clocks net_rx_clk]
write_checkpoint -force synth.dcp
opt_design

set checked_macs 0
foreach mac [get_cells -hier -filter {REF_NAME == DSP48E1}] {
 if {[string match *scaled* $mac]} {continue}
 set a24 [get_nets -of_objects [get_pins [format {%s/A[24]} $mac]]]
 set b17 [get_nets -of_objects [get_pins [format {%s/B[17]} $mac]]]
 foreach sign_net [list $a24 $b17] {
  set drivers [get_cells -of_objects [get_pins -of_objects $sign_net -filter {DIRECTION == OUT}]]
  if {[llength [filter $drivers {REF_NAME == GND || REF_NAME == VCC}]]} {error "Constant DSP sign input: $mac"}
 }
 incr checked_macs
}
puts "SIGNED_MAC_CHECK count=$checked_macs"
if {$checked_macs!=64} {error "Expected 64 signed MACs"}
set bram36 [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
set bram18 [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set used_bram [expr {$bram36+0.5*$bram18}]
puts "BRAM_BUDGET used=$used_bram limit=387"
report_utilization -file optimized_utilization.rpt
if {$used_bram>387} {error "BRAM budget exceeded"}
place_design
phys_opt_design -directive Explore
route_design
if {[get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]<0} {
 phys_opt_design -directive Explore
 route_design -directive Explore
}
write_checkpoint -force routed.dcp
report_utilization -file utilization.rpt
report_timing_summary -file timing.rpt
report_bus_skew -file bus_skew.rpt
set setup [get_property SLACK [lindex [get_timing_paths -setup -max_paths 1] 0]]
set hold [get_property SLACK [lindex [get_timing_paths -hold -max_paths 1] 0]]
puts "SLACK setup=$setup hold=$hold"
if {$setup<0 || $hold<0} {error "Timing failed"}
write_debug_probes -force udp_mdio_bridge.ltx
write_bitstream -force udp_mdio_bridge.bit
write_checkpoint -force udp_mdio_bridge.dcp
set ready [open build_ready.txt w]
puts $ready "DSP64 UDP360 timing and BRAM checks passed"
close $ready
exit
