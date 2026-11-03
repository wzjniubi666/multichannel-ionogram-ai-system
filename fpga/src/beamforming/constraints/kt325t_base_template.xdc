## PZ-K7325T-FH XC7K325T-2FFG900I board reference template
##
## This file is intentionally not added to the current Vivado project yet.
## It targets a future board wrapper whose top-level ports are named below.
## Do not apply these constraints to the abstract beamforming_top directly.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

## 200 MHz board oscillator, Bank 33. The complementary pin is AH10.
set_property PACKAGE_PIN AG10 [get_ports sys_clk_p]
set_property PACKAGE_PIN AH10 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]
create_clock -name sys_clk_200m -period 5.000 [get_ports sys_clk_p]

## Active-low board reset.
set_property PACKAGE_PIN T26 [get_ports sys_rstn]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rstn]

## Official PZ-K7325T LED example mapping. Confirm intended LED bank before use.
set_property PACKAGE_PIN L11 [get_ports {led[0]}]
set_property PACKAGE_PIN K11 [get_ports {led[1]}]
set_property PACKAGE_PIN L15 [get_ports {led[2]}]
set_property PACKAGE_PIN K15 [get_ports {led[3]}]
set_property PACKAGE_PIN F12 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## RGMII is intentionally left out until the network interface is authorized.
## The verified board pins are documented in docs/kt325t_board_reference.md.

