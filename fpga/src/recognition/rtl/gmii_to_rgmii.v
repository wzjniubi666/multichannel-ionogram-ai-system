`timescale 1ns/1ps
module gmii_to_rgmii #(parameter IDELAY_VALUE=8)(
 output physical_rx_clk,input idelay_clk,input rgmii_rxc,input rgmii_rx_ctl,input [3:0] rgmii_rxd,
 output rgmii_txc,output rgmii_tx_ctl,output [3:0] rgmii_txd,
 output gmii_rx_clk,output gmii_rx_en,output [7:0] gmii_rxd,
 output gmii_tx_clk,input gmii_tx_en,input [7:0] gmii_txd);
rgmii_rx #(.IDELAY_VALUE(IDELAY_VALUE)) receiver(.idelay_clk(idelay_clk),
 .rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .gmii_rx_clk(gmii_rx_clk),.gmii_rx_en(gmii_rx_en),.gmii_rxd(gmii_rxd));
assign physical_rx_clk=gmii_rx_clk;
assign gmii_tx_clk=gmii_rx_clk;
rgmii_tx transmitter(.gmii_tx_clk(gmii_tx_clk),.gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
endmodule
