# Portable launcher around the unchanged, non-project release implementation script.
# Generates reports/DCP only. It neither writes bitstreams nor accesses hardware.
set delivery_root [file normalize [file join [file dirname [info script]] ../../..]]
set run_tag [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set run_dir [file join $delivery_root fpga build beamforming work implementation_$run_tag]
if {[file exists $run_dir]} {error "Build output exists: $run_dir"}
file mkdir $run_dir
file copy [file join $delivery_root fpga src beamforming release_sources] [file join $run_dir sources]
file copy [file join $delivery_root fpga src beamforming release_constraints] [file join $run_dir constraints]
set argv [list $run_dir - -]
set argc [llength $argv]
source [file join $delivery_root fpga build beamforming implement_m512_board.tcl]
puts "New implementation candidate at $run_dir. Audit all reports before any bitstream release."
