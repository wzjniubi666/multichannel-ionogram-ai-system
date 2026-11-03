
# Center-aligned DDR input. Separate virtual launch clock scopes edge exceptions to the PHY inputs only.
create_clock -name rgmii_launch -period 8.000
set_input_delay -clock rgmii_launch -max -1.15 [get_ports {net_rx_ctl net_rxd[*]}]
set_input_delay -clock rgmii_launch -min -2.85 [get_ports {net_rx_ctl net_rxd[*]}]
set_input_delay -clock rgmii_launch -clock_fall -add_delay -max -1.15 [get_ports {net_rx_ctl net_rxd[*]}]
set_input_delay -clock rgmii_launch -clock_fall -add_delay -min -2.85 [get_ports {net_rx_ctl net_rxd[*]}]
# Data launched before the corresponding sampling edge; check setup on that edge, not one cycle later.
set_multicycle_path 0 -setup -rise_from [get_clocks rgmii_launch] -rise_to [get_clocks net_rx_clk]
set_multicycle_path 0 -setup -fall_from [get_clocks rgmii_launch] -fall_to [get_clocks net_rx_clk]
# Each bit's setup uses its matching edge, hold uses the next opposite-edge transition (4ns later).
set_false_path -setup -rise_from [get_clocks rgmii_launch] -fall_to [get_clocks net_rx_clk]
set_false_path -setup -fall_from [get_clocks rgmii_launch] -rise_to [get_clocks net_rx_clk]
set_false_path -hold -rise_from [get_clocks rgmii_launch] -rise_to [get_clocks net_rx_clk]
set_false_path -hold -fall_from [get_clocks rgmii_launch] -fall_to [get_clocks net_rx_clk]
set_property DRIVE 8 [get_ports {net_tx_ctl net_txd[*]}]
