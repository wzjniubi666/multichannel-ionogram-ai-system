# Keep the ten existing packet req/ack bounds; physical RX/TX now share rx_clk.
source [file join [file dirname [info script]] network_cdc_paths.tcl]
set frequency_first [get_cells u_clock_monitor/frequency_sync_reg\[0\]]
set frequency_source [get_cells u_clock_monitor/rx_toggle_reg]
if {[llength $frequency_first]!=1 || [llength $frequency_source]!=1} {error "Clock-monitor synchronizer missing"}
set_max_delay 8.000 -datapath_only -from $frequency_source -to $frequency_first
set reset_pres [get_pins -of_objects [get_cells -hierarchical -regexp {reset_data_(core|rx)/release_sync_reg\[[01]\]}] -filter {REF_PIN_NAME == PRE}]
if {[llength $reset_pres]!=4} {error "Expected one shared two-stage data reset per domain"}
# Only asynchronous request to synchronizer PRE; all downstream reset release
# and stage-1 -> stage-2 timing remain checked.
set_false_path -to $reset_pres
