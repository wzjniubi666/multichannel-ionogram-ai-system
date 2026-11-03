set root [file normalize [file join [file dirname [info script]] .. .. ..]]
cd $root/fpga/build/recognition/board_case
open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7k325t*] 0]
if {$dev eq ""} {error "XC7K325T not connected"}
set_property PROGRAM.FILE $root/fpga/build/recognition/board_case/udp_mdio_bridge.bit $dev
set_property PROBES.FILE $root/fpga/build/recognition/board_case/udp_mdio_bridge.ltx $dev
program_hw_devices $dev
refresh_hw_device $dev
set core [lindex [get_hw_axis] 0]
if {$core eq ""} {error "No AXI MDIO bridge"}
reset_hw_axi $core
proc rd {addr} {
 global core
 create_hw_axi_txn r $core -force -type READ -address [format %08x $addr] -len 1
 run_hw_axi -quiet r
 scan [get_property DATA [get_hw_axi_txns r]] %x val
 return [expr {$val & 0xffffffff}]
}
proc wr {addr data} {
 global core
 create_hw_axi_txn w $core -force -type WRITE -address [format %08x $addr] -len 1 -data [format %08x $data]
 run_hw_axi -quiet w
}
if {[rd 12]!=0x5544504d} {error "Wrong hardware magic"}
set ready_deadline [expr {[clock milliseconds]+3000}]
while {([rd 0]&2)==0} {if {[clock milliseconds]>$ready_deadline} {error "PHY reset not released"};after 10}
set trace [open mdio_trace.csv w]
puts $trace "elapsed_ms,operation,phy,register,value_hex,read_ack_error,command_id"
set began [clock milliseconds]
proc md {read phy reg {data 0}} {
 global trace began
 set prev [rd 8]
 set cmd [expr {($read<<31)|($phy<<21)|($reg<<16)|$data}]
 wr 0 $cmd
 set deadline [expr {[clock milliseconds]+2000}]
 while {[rd 8]==$prev} {
  if {[clock milliseconds]>$deadline} {error "MDIO transaction timed out"}
 }
 set seq [rd 8]
 set echoed [rd 16]
 set status [rd 0]
 if {$seq!=$prev+1 || $echoed!=$cmd || ($status&1)} {
  error "MDIO sequence mismatch: prev=$prev seq=$seq cmd=[format %08x $cmd] echo=[format %08x $echoed] status=$status"
 }
 set response [rd 4]
 set value [expr {$read?($response&65535):$data}]
 set ack [expr {$read?(($response>>16)&1):0}]
 puts $trace "[expr {[clock milliseconds]-$began}],$read,$phy,$reg,[format %04x $value],$ack,$seq"
 flush $trace
 if {$read && $ack} {return -1}
 return $value
}
set phy -1
for {set addr 1} {$addr<=7} {incr addr} {
 set id1 [md 1 $addr 2]
 if {$id1==0x001c} {
  set id2 [md 1 $addr 3]
  puts "FOUND_PHY address=$addr id=[format %04x $id1]:[format %04x $id2]"
  if {$phy<0} {set phy $addr}
 }
}
if {$phy<1} {error "No non-broadcast Realtek PHY responded"}
set summary [open diagnostic_summary.txt w]
puts $summary "PHY $phy"
foreach reg {0 1 1 2 3 4 5 6 9 10 15 24 26 31} {
 set value [md 1 $phy $reg]
 if {$value<0} {error "PHY stopped acknowledging"}
 puts $summary "BASELINE $reg [format %04x $value]"
}
# Select the documented standard page and verify every write immediately.
foreach pair {{31 0} {4 481} {9 512}} {
 lassign $pair reg value
 md 0 $phy $reg $value
 set actual [md 1 $phy $reg]
 puts $summary "WRITE_READBACK $reg [format %04x $value] [format %04x $actual]"
}
md 0 $phy 31 3336
set tx_delay [md 1 $phy 17]
md 0 $phy 17 [expr {$tx_delay | 256}]
set tx_readback [md 1 $phy 17]
puts $summary "TX_DELAY_REGISTER [format %04x $tx_readback]"
if {($tx_readback&256)==0} {error "TX internal delay not enabled"}
set rx_delay [md 1 $phy 21]
md 0 $phy 21 [expr {$rx_delay | 8}]
set rx_readback [md 1 $phy 21]
puts $summary "RX_DELAY_REGISTER [format %04x $rx_readback]"
if {($rx_readback&8)==0} {error "RX internal delay not enabled"}
md 0 $phy 31 0
set gbcr [md 1 $phy 9]
puts "GIGABIT_ADVERTISEMENT_READBACK=[format %04x $gbcr]"
if {$gbcr==512} {
 md 0 $phy 0 4608
 puts $summary "AUTONEG_RESTART requested"
} else {
 puts $summary "AUTONEG_RESTART skipped_10_100_configuration_not_verified"
}
set status_file [open negotiation.csv w]
puts $status_file "elapsed_ms,bmcr_hex,bmsr_hex,gbcr_hex,physr_hex"
for {set sample 0} {$sample<40} {incr sample} {
 set bmcr [md 1 $phy 0]
 md 1 $phy 1
 set bmsr [md 1 $phy 1]
 set gbcr [md 1 $phy 9]
 set physr [md 1 $phy 26]
 puts $status_file "[expr {[clock milliseconds]-$began}],[format %04x $bmcr],[format %04x $bmsr],[format %04x $gbcr],[format %04x $physr]"
 flush $status_file
 if {($bmsr&36)==36 && ($physr&12)==12 && (($physr>>4)&3)==2} {puts $summary "GIGABIT_FULL_DUPLEX_LINK confirmed";break}
 after 1000
}
close $status_file
set rxkhz [rd 24]
puts $summary "RX_CLOCK_KHZ $rxkhz"
if {($physr&12)!=12 || (($physr>>4)&3)!=2 || $rxkhz<124000 || $rxkhz>126000} {error "Gigabit full duplex / 125MHz PHY clock not confirmed"}
puts $summary "MAC_DEBUG [format %08x [rd 28]]"
close $summary
close $trace
puts "MDIO_DIAG_COMPLETE"
close_hw_target
disconnect_hw_server
exit
