set out [file normalize [lindex $argv 0]]
set_param general.maxThreads 2
if {[llength $argv]>2 && [lindex $argv 2] ne "-"} {
    open_checkpoint [file normalize [lindex $argv 2]]
    puts "REUSED_EXACT512_SYNTHESIS: RTL and constraints matched by launcher"
} else {
    foreach src [glob -directory [file join $out sources] *.v] {read_verilog $src}
    read_xdc [file join $out constraints kt325t_network_board.xdc]
    synth_design -top kt325t_network512_board_top -part xc7k325tffg900-2 -flatten_hierarchy rebuilt
}
write_checkpoint -force [file join $out board_synth_raw.dcp]
source [file join $out constraints board_rgmii_duty_model.tcl]
source [file join $out constraints board_network_cdc.tcl]
source [file join $out constraints board_sync_preserve.tcl]
source [file join $out constraints board_same_clock_paths.tcl]
write_checkpoint -force [file join $out board_synth.dcp]
report_utilization -file [file join $out synth_utilization.rpt]
report_cdc -details -file [file join $out synth_cdc.rpt]
opt_design
report_config_implementation -file [file join $out implementation_config_before_incremental.rpt]
if {[llength $argv]>1 && [lindex $argv 1] ne "" && [lindex $argv 1] ne "-"} {
    read_checkpoint -incremental [file normalize [lindex $argv 1]]
    report_incremental_reuse -file [file join $out incremental_reuse.rpt]
}
report_config_implementation -file [file join $out implementation_config.rpt]
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
board_check_sync_links 0
report_cdc -details -file [file join $out placed_cdc.rpt]
write_checkpoint -force [file join $out board_placed.dcp]
route_design -directive NoTimingRelaxation
write_checkpoint -force [file join $out board_routed.dcp]
board_check_sync_links 0
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $out setup_paths.rpt]
report_timing -delay_type min -max_paths 20 -file [file join $out hold_paths.rpt]
foreach {name edge group} {rx_setup max from rx_hold min from tx_setup max to tx_hold min to} {
    if {$group eq "from"} {set ports [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]} else {set ports [get_ports {rgmii_tx_ctl rgmii_txd[*]}]}
    report_timing -$group $ports -delay_type $edge -max_paths 20 -nworst 4 -file [file join $out $name.rpt]
}
check_timing -verbose -file [file join $out check_timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out utilization_hier.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_drc -file [file join $out drc.rpt]
report_methodology -file [file join $out methodology.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_clocks -file [file join $out clocks.rpt]
file mkdir [file join $out mdio_diagnostics]
foreach {name edge group} {mdio_write_setup max to mdio_write_hold min to mdio_read_setup max from mdio_read_hold min from} {
    report_timing -$group [get_ports phy_mdio] -delay_type $edge -file [file join $out mdio_diagnostics $name.rpt]
}
report_exceptions -coverage -file [file join $out exceptions.rpt]
report_route_status -file [file join $out route_status.rpt]
report_io -file [file join $out io.rpt]
write_xdc -force [file join $out effective.xdc]
foreach board_rx_fall {3.600 4.400} {
    source [file join $out constraints board_rgmii_duty_model.tcl]
    set mode duty_[expr {int(round($board_rx_fall*10))}]
    file mkdir [file join $out $mode]
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out $mode timing_summary.rpt]
    foreach {name edge group} {rx_setup max from rx_hold min from tx_setup max to tx_hold min to} {
        if {$group eq "from"} {set ports [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]} else {set ports [get_ports {rgmii_tx_ctl rgmii_txd[*]}]}
        report_timing -$group $ports -delay_type $edge -max_paths 20 -nworst 4 -file [file join $out $mode $name.rpt]
    }
    check_timing -verbose -file [file join $out $mode check_timing.rpt]
    write_xdc -force [file join $out $mode effective.xdc]
}
puts "COMPLETE BOARD_IMPLEMENTATION_REPORTS"
# Deliberately no write_bitstream / hardware commands: this is an offline candidate.
