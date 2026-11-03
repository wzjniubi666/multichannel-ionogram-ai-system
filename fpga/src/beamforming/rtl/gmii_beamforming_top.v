`timescale 1ns/1ps
// Three-domain integration boundary. Physical clocks/pins belong to board top.
module gmii_beamforming_top #(
    parameter [47:0] BOARD_MAC=48'h020000000001, PEER_MAC=48'h020000000002,
    parameter [31:0] BOARD_IP=32'hc0000201, PEER_IP=32'hc0000202,
    parameter [15:0] BOARD_PORT=5000, PEER_PORT=5000
) (
    input wire async_reset,rx_clk,core_clk,tx_clk,
    input wire gmii_rx_dv,gmii_rx_er,
    input wire [7:0]gmii_rxd,
    input wire tx_allow,
    output wire gmii_tx_en,
    output wire [7:0]gmii_txd,
    output wire busy,
    output wire [31:0]rx_accepted,rx_rejected,rx_overflow
);
    wire core_rst,core_rx_valid,core_rx_ready,core_rx_last,core_tx_valid,core_tx_ready,core_tx_last;
    wire rx_desc_error,tx_desc_error,tx_overflow;
    wire [31:0]core_rx_data,core_tx_data;
    gmii_payload_transport #(.BOARD_MAC(BOARD_MAC),.PEER_MAC(PEER_MAC),.BOARD_IP(BOARD_IP),.PEER_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT)) u_transport(
        .async_reset(async_reset),.rx_clk(rx_clk),.core_clk(core_clk),.tx_clk(tx_clk),
        .gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),.gmii_rxd(gmii_rxd),.tx_allow(tx_allow),
        .gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),.core_rst(core_rst),
        .core_rx_valid(core_rx_valid),.core_rx_ready(core_rx_ready),.core_rx_last(core_rx_last),.core_rx_data(core_rx_data),
        .core_tx_valid(core_tx_valid),.core_tx_ready(core_tx_ready),.core_tx_last(core_tx_last),.core_tx_data(core_tx_data),
        .rx_accepted(rx_accepted),.rx_rejected(rx_rejected),.rx_overflow(rx_overflow),
        .rx_desc_error(rx_desc_error),.tx_desc_error(tx_desc_error),.tx_overflow(tx_overflow));
    network_beamforming_top u_application(
        .clk(core_clk),.rst(core_rst),.rx_valid(core_rx_valid),.rx_ready(core_rx_ready),.rx_data(core_rx_data),
        .rx_last(core_rx_last),.rx_bad(1'b0),.tx_valid(core_tx_valid),.tx_ready(core_tx_ready),
        .tx_data(core_tx_data),.tx_last(core_tx_last),.busy(busy));
endmodule
