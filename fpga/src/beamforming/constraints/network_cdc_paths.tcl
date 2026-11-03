# Source this AFTER synthesis and clock creation. No blanket async clock groups:
# only identified req/ack stage-1 paths receive a bounded datapath exception.
# Dual-clock packet RAM stays immutable until synchronized acknowledgement.
set cdc_first_stages [get_cells -hierarchical -regexp {.*\/(req_sync[01]?|ack_sync[01]?)_reg\[0\]}]
if {[llength $cdc_first_stages] != 10} {
    error "Expected 10 req/ack first stages in gmii_payload_transport, got [llength $cdc_first_stages]"
}
foreach cdc_stage $cdc_first_stages {
    set cdc_d [get_pins $cdc_stage/D]
    set cdc_driver [get_pins -leaf -of_objects [get_nets -segments -of_objects $cdc_d] -filter {DIRECTION == OUT}]
    if {[llength $cdc_driver] != 1} {error "Ambiguous CDC source: $cdc_stage"}
    set cdc_source_cell [get_cells -of_objects $cdc_driver]
    set cdc_source_clock [get_clocks -of_objects [get_pins $cdc_source_cell/C]]
    if {[llength $cdc_source_clock] != 1} {error "Missing/ambiguous CDC source clock: $cdc_source_cell"}
    set cdc_period [get_property PERIOD $cdc_source_clock]
    # Use sequential CELL endpoints. A forced Q-pin startpoint can segment paths
    # and remove launch-clock identity, hiding crossings from report_cdc.
    set_max_delay $cdc_period -datapath_only -from $cdc_source_cell -to $cdc_stage
    puts "CDC_BOUNDED_PATH $cdc_driver -> $cdc_d budget_ns=$cdc_period"
}
