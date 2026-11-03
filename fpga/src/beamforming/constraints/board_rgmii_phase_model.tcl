# Explicit source/capture phases, avoiding accidental full-UI DDR setup/hold
# associations from negative same-clock input/output-delay recipes.
# At the FPGA RXC pin t=0, guaranteed data is stable [-1.2,+1.2]ns.
# Equivalent virtual PHY launch edges are -2,+2ns (periodically 6,10ns),
# with +/-0.8ns PHY uncertainty and +/-0.25ns board-skew assumption.
# set_*_delay without -add_delay replaces prior port constraints. The probe
# exports write_xdc so remaining clock/edge associations can be audited.
create_clock -name phy_rx_launch -period 8.000 -waveform {6.000 10.000}
set_input_delay -clock phy_rx_launch -max 1.050 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -min -1.050 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -clock_fall -add_delay -max 1.050 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock phy_rx_launch -clock_fall -add_delay -min -1.050 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
# RX capture uses an MMCM-compensated global clock; no input delay taps.
set rx_data_clocks [get_clocks -of_objects [get_pins u_tx/u_txc/C]]
set_clock_uncertainty -setup 0.400 $rx_data_clocks
set_clock_uncertainty -hold 0.400 $rx_data_clocks
# At the TXC boundary this generated reference models the PHY's INTERNAL
# capture edge, 2ns after the actual forwarded edge. It drives no FPGA logic.
# Relative external deadlines are unchanged: setup at TXC+0.75ns and hold to
# TXC+2.85ns. Positive phase prevents selecting the adjacent DDR unit interval.
create_generated_clock -name tx_forward -source [get_pins u_tx/u_txc/C] \
    -edges {1 2 3} -edge_shift {2.000 2.000 2.000} [get_ports rgmii_txc]
set_clock_uncertainty -setup 0.400 [get_clocks tx_forward]
set_clock_uncertainty -hold 0.400 [get_clocks tx_forward]
set_output_delay -clock tx_forward -max 1.250 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -min -0.850 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -clock_fall -add_delay -max 1.250 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
set_output_delay -clock tx_forward -clock_fall -add_delay -min -0.850 [get_ports {rgmii_tx_ctl rgmii_txd[*]}]
