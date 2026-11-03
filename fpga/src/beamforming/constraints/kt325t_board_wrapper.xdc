## PZ-K7325T-FH board wrapper constraints.
## Apply only when kt325t_beamforming_board_top is the project top.
## IQ and steering ports intentionally remain unassigned until their external
## receiver/ADC interface and channel ordering are confirmed.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

set_property PACKAGE_PIN AG10 [get_ports sys_clk_p]
set_property PACKAGE_PIN AH10 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]
create_clock -name sys_clk_200m -period 5.000 [get_ports sys_clk_p]

set_property PACKAGE_PIN T26 [get_ports sys_rstn]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rstn]

## Official PZ-K7325T LED example mapping.
set_property PACKAGE_PIN L11 [get_ports {led[0]}]
set_property PACKAGE_PIN K11 [get_ports {led[1]}]
set_property PACKAGE_PIN L15 [get_ports {led[2]}]
set_property PACKAGE_PIN K15 [get_ports {led[3]}]
set_property PACKAGE_PIN F12 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

