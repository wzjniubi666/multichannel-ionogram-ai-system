# RX and TX share one physical clock in the board Top. Replace only the two
# legacy ARP datapath-only exceptions with an ordinary one-period clocked bound.
set stages [get_cells -hierarchical -regexp {.*\/(req_sync[01]?|ack_sync[01]?)_reg\[0\]}]
if {[llength $stages]!=10} {error "Expected ten packet req/ack first stages"}
set changed 0
foreach stage $stages {
    set drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects [get_pins $stage/D]] -filter {DIRECTION == OUT}]
    if {[llength $drivers]!=1} {error "Ambiguous packet request source"}
    set source [get_cells -of_objects $drivers]
    set a [get_clocks -of_objects [get_pins $source/C]]
    set b [get_clocks -of_objects [get_pins $stage/C]]
    if {[llength $a]!=1 || [llength $b]!=1} {error "Missing packet clock"}
    if {$a eq $b} {
        set_max_delay -reset_path [get_property PERIOD $a] -from $source -to $stage
        incr changed
        puts "BOARD_SAME_CLOCK_BOUND $source -> $stage clock=$a"
    }
}
if {$changed!=2} {error "Expected two same-clock ARP paths, got $changed"}
