# Read-only physical view of the verified UDP360 implementation.
set root [file normalize [file join [file dirname [info script]] .. .. ..]]
cd $root
open_checkpoint $root/fpga/build/recognition/board_case/udp_mdio_bridge.dcp
set logic [get_cells -hier -filter {REF_NAME =~ LUT* || REF_NAME =~ FD* || REF_NAME == CARRY4 || REF_NAME =~ RAM32* || REF_NAME =~ RAM64*}]
set brams [get_cells -hier -filter {REF_NAME == RAMB36E1 || REF_NAME == RAMB18E1}]
set macs [get_cells -hier -filter {REF_NAME == DSP48E1 && NAME !~ *scaled*}]
set scales [get_cells -hier -filter {REF_NAME == DSP48E1 && NAME =~ *scaled*}]
highlight_objects -color cyan $logic
highlight_objects -color orange $brams
highlight_objects -color green $macs
highlight_objects -color yellow $scales
puts "FLOORPLAN_LEGEND cyan=LUT/register/control/weight-ROM orange=BRAM green=64-convolution-MACs yellow=2-scaling-DSPs"
puts "FLOORPLAN_COUNTS macs=[llength $macs] scales=[llength $scales] bram_primitives=[llength $brams] pblocks=[llength [get_pblocks]]"
set out [open $root/fpga/build/recognition/board_case/resource_locations.csv w]
puts $out "category,cell,primitive,site"
foreach category {macs scales brams} {
 foreach cell [set $category] {
  puts $out "$category,$cell,[get_property REF_NAME $cell],[get_property LOC $cell]"
 }
}
close $out
# Leave the GUI running in its Device tab. No programming or implementation.
