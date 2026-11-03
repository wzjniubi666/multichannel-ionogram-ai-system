`timescale 1ns/1ps
// RGMII datapath integration, not a pin-constrained board top. Board management
// supplies reset after clocks/PHY configuration. PHY MDIO remains board-level work.
module rgmii_beamforming_link #(
    parameter integer IDELAY_VALUE=0,
    parameter [47:0] BOARD_MAC=48'h020000000001, PEER_MAC=48'h020000000002,
    parameter [31:0] BOARD_IP=32'hc0000201, PEER_IP=32'hc0000202,
    parameter [15:0] BOARD_PORT=5000, PEER_PORT=5000
) (
    input wire async_reset,ref_clk_200m,core_clk,
    input wire rgmii_rxc,rgmii_rx_ctl,
    input wire [3:0]rgmii_rxd,
    output wire rgmii_txc,rgmii_tx_ctl,
    output wire [3:0]rgmii_txd,
    output wire idelay_ready,busy
);
    wire rx_clk,rx_dv,rx_er,tx_en,ref_rst;
    wire [7:0]rxd,txd;
    reg [4:0]delay_reset_count;
    wire delay_reset=ref_rst || !delay_reset_count[4];
    network_cdc_reset reset_ref(.clk(ref_clk_200m),.async_reset(async_reset),.rst(ref_rst));
    always @(posedge ref_clk_200m or posedge ref_rst)
        if(ref_rst)delay_reset_count<=0;
        else if(!delay_reset_count[4])delay_reset_count<=delay_reset_count+1'b1;
    (* IODELAY_GROUP="rgmii_delay" *)
    IDELAYCTRL u_idelayctrl(.REFCLK(ref_clk_200m),.RST(delay_reset),.RDY(idelay_ready));
    bfm_rgmii_rx #(.IDELAY_VALUE(IDELAY_VALUE)) u_rgmii_rx(
        .idelay_clk(ref_clk_200m),.rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
        .gmii_rx_clk(rx_clk),.gmii_rx_en(rx_dv),.gmii_rx_er(rx_er),.gmii_rxd(rxd));
    // Official conversion uses the received gigabit clock for transmit as well.
    rgmii_tx u_rgmii_tx(.gmii_tx_clk(rx_clk),.gmii_tx_en(tx_en),.gmii_txd(txd),
        .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
    gmii_beamforming_top #(.BOARD_MAC(BOARD_MAC),.PEER_MAC(PEER_MAC),.BOARD_IP(BOARD_IP),.PEER_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT)) u_transport(
        .async_reset(async_reset || !idelay_ready),.rx_clk(rx_clk),.core_clk(core_clk),.tx_clk(rx_clk),
        .gmii_rx_dv(rx_dv),.gmii_rx_er(rx_er),.gmii_rxd(rxd),.tx_allow(1'b1),
        .gmii_tx_en(tx_en),.gmii_txd(txd),.busy(busy),.rx_accepted(),.rx_rejected(),.rx_overflow());
endmodule
