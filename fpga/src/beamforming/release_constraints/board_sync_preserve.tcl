# No timing waiver: retain every real two-FF ASYNC_REG link as direct routing.
# Aggressive hold fixing otherwise inserts LUT1s between the registers.
proc board_check_sync_links {apply_properties} {
    set syncs [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]
    if {[llength $syncs]!=38} {error "Expected 38 synchronizer registers, got [llength $syncs]"}
    if {$apply_properties} {set_property DONT_TOUCH TRUE $syncs}
    set links {}
    foreach c $syncs {
        set dp [get_pins $c/D]
        set nets [get_nets -segments -of_objects $dp]
        set drivers [get_pins -leaf -of_objects $nets -filter {DIRECTION == OUT}]
        if {[llength $drivers]!=1} {error "Ambiguous synchronizer D source: $c"}
        set source [get_cells -of_objects $drivers]
        if {[lsearch -exact $syncs $source]<0} {continue}
        if {[get_property REF_PIN_NAME $drivers] ne "Q"} {error "Unexpected synchronizer source pin"}
        set a [get_clocks -of_objects [get_pins $source/C]]
        set b [get_clocks -of_objects [get_pins $c/C]]
        if {[llength $a]!=1 || $a ne $b} {error "Synchronizer stages have different clocks"}
        if {$apply_properties} {set_property DONT_TOUCH TRUE $nets}
        lappend links $dp
        puts "SYNC_DIRECT_LINK $drivers -> $dp"
    }
    if {[llength $links]!=19} {error "Expected 19 direct synchronizer links, got [llength $links]"}
    puts "PASS SYNC_DIRECT_LINKS: registers=38 direct_links=19 protected=$apply_properties"
    return [get_nets -of_objects $links]
}
set board_sync_nets [board_check_sync_links 1]
