# PHY data-valid is specified relative to the ACTUAL RXC edges. Model duty
# directly in both the source reference and forwarded clock, rather than
# additionally subtracting the same 0.4ns as uncorrelated I/O uncertainty.
# Default 50%; the final routed DCP must also pass 45% and 55% modes.
if {![info exists board_rx_fall]} {set board_rx_fall 4.000}
if {$board_rx_fall<3.600 || $board_rx_fall>4.400} {error "RX duty mode outside 45..55%"}
set wave [get_property WAVEFORM [get_clocks rx_clk]]
if {abs([lindex $wave 1]-$board_rx_fall)>0.00001} {
    create_clock -name rx_clk -period 8.000 -waveform [list 0.000 $board_rx_fall] [get_ports rgmii_rxc]
}
create_clock -name phy_rx_launch -period 8.000 -waveform [list 0.000 $board_rx_fall]
set rise_max [expr {$board_rx_fall-0.950}]
set fall_max [expr {8.000-$board_rx_fall-0.950}]
set_input_delay -clock phy_rx_launch -max $rise_max [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -min 0.950 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -clock_fall -add_delay -max $fall_max [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -clock_fall -add_delay -min 0.950 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set rx_data_clocks [get_clocks -of_objects [get_pins u_tx/u_txc/C]]
if {[llength $rx_data_clocks]!=1} {error "RX data clock ambiguous"}
# Retain the conservative internal margin. The explicit I/O clock-pair values
# below apply only to PHY-relative windows, already bounded by datasheet+PCB.
set_clock_uncertainty -setup 0.400 $rx_data_clocks
set_clock_uncertainty -hold 0.400 $rx_data_clocks
set_clock_uncertainty -setup 0.000 -from [get_clocks phy_rx_launch] -to $rx_data_clocks
set_clock_uncertainty -hold 0.000 -from [get_clocks phy_rx_launch] -to $rx_data_clocks
# Clock reference AT THE OUTPUT BOUNDARY represents PHY internal sampling 2ns
# after actual TXC; it drives no FPGA FF. External deadline remains TXC+0.75ns
# for setup and TXC+2.85ns for hold (includes +/-0.25ns board budget).
create_generated_clock -name tx_forward -source [get_pins u_tx/u_txc/C] \
    -edges {1 2 3} -edge_shift {2.000 2.000 2.000} [get_ports rgmii_txc]
set_output_delay -clock tx_forward -max 1.250 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -min -0.850 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -clock_fall -add_delay -max 1.250 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -clock_fall -add_delay -min -0.850 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_clock_uncertainty -setup 0.000 -from $rx_data_clocks -to [get_clocks tx_forward]
set_clock_uncertainty -hold 0.000 -from $rx_data_clocks -to [get_clocks tx_forward]
puts "BOARD_IO_DUTY fall_ns=$board_rx_fall RX_valid_before_after=0.950ns TX_setup_deadline=+0.750ns TX_hold_deadline=+2.850ns"
