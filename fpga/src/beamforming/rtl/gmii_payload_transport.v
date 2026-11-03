`timescale 1ns/1ps
// Three-domain integration boundary. Physical clocks/pins belong to board top.
module gmii_payload_transport #(
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
    output wire core_rst,
    output wire core_rx_valid,core_rx_last,
    input wire core_rx_ready,
    output wire [31:0]core_rx_data,
    input wire core_tx_valid,core_tx_last,
    output wire core_tx_ready,
    input wire [31:0]core_tx_data,
    output wire rx_desc_error,tx_desc_error,tx_overflow,
    output wire [31:0]rx_accepted,rx_rejected,rx_overflow
);
    wire rx_rst,tx_rst,unused_core_rst;
    wire store_free,store_we,store_commit,arp_request,arp_ready,arp_valid,arp_accept;
    wire [8:0]store_addr,store_words;
    wire [31:0]store_data,tx_payload_data;
    wire tx_payload_valid,tx_payload_ready,tx_payload_last;
    gmii_bfm_rx #(.BOARD_MAC(BOARD_MAC),.PEER_MAC(PEER_MAC),.BOARD_IP(BOARD_IP),.PEER_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT)) u_rx(
        .clk(rx_clk),.rst(rx_rst),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),.gmii_rxd(gmii_rxd),
        .store_available(store_free),.arp_ready(arp_ready),.store_we(store_we),.store_commit(store_commit),
        .store_addr(store_addr),.store_words(store_words),.store_data(store_data),.arp_request(arp_request),
        .accepted_packets(rx_accepted),.rejected_frames(rx_rejected),.overflow_frames(rx_overflow));
    packet_store_cdc u_rx_cdc(
        .async_reset(async_reset),.s_clk(rx_clk),.m_clk(core_clk),.s_rst(rx_rst),.m_rst(core_rst),
        .s_available(store_free),.s_we(store_we),.s_addr(store_addr),.s_data(store_data),
        .s_commit(store_commit),.s_words(store_words),.m_valid(core_rx_valid),.m_ready(core_rx_ready),
        .m_data(core_rx_data),.m_last(core_rx_last),.descriptor_error(rx_desc_error));
    packet_stream_cdc u_tx_cdc(
        .async_reset(async_reset),.s_clk(core_clk),.m_clk(tx_clk),.s_rst(unused_core_rst),.m_rst(tx_rst),
        .s_valid(core_tx_valid),.s_ready(core_tx_ready),.s_data(core_tx_data),.s_last(core_tx_last),
        .m_valid(tx_payload_valid),.m_ready(tx_payload_ready),.m_data(tx_payload_data),
        .m_last(tx_payload_last),.overflow(tx_overflow),.descriptor_error(tx_desc_error));
    network_event_cdc u_arp_cdc(.async_reset(async_reset),.s_clk(rx_clk),.m_clk(tx_clk),
        .s_event(arp_request),.s_ready(arp_ready),.m_valid(arp_valid),.m_accept(arp_accept));
    gmii_bfm_tx #(.BOARD_MAC(BOARD_MAC),.PEER_MAC(PEER_MAC),.BOARD_IP(BOARD_IP),.PEER_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT)) u_tx(
        .clk(tx_clk),.rst(tx_rst),.tx_allow(tx_allow),.payload_valid(tx_payload_valid),.payload_ready(tx_payload_ready),
        .payload_data(tx_payload_data),.payload_last(tx_payload_last),.arp_valid(arp_valid),.arp_accept(arp_accept),
        .gmii_tx_en(gmii_tx_en),.gmii_txd(gmii_txd),.sent_udp(),.sent_arp());
endmodule
