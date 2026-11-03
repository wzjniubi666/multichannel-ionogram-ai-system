`timescale 1ns/1ps
module network_beamforming512_top #(
    parameter integer IDLE_TIMEOUT_CYCLES=20000000,
    parameter integer CORE_TIMEOUT_CYCLES=20000000,
    parameter [15:0] ACTIVE_MASK=16'hffff
)(
    input wire clk,rst,rx_valid,
    output wire rx_ready,
    input wire [31:0]rx_data,
    input wire rx_last,rx_bad,
    output wire tx_valid,
    input wire tx_ready,
    output wire [31:0]tx_data,
    output wire tx_last,busy
);
    wire sv,start_frame,end_frame,cr,ov,err,cancel;
    wire [255:0]ii,qq;wire [383:0]sr,si;wire [47:0]br,bi;
    udp_beamforming512_adapter #(.IDLE_TIMEOUT_CYCLES(IDLE_TIMEOUT_CYCLES),.CORE_TIMEOUT_CYCLES(CORE_TIMEOUT_CYCLES))u_network(
        .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_data(rx_data),.rx_last(rx_last),.rx_bad(rx_bad),
        .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_data(tx_data),.tx_last(tx_last),
        .sample_valid(sv),.frame_start(start_frame),.frame_end(end_frame),.in_i_bus(ii),.in_q_bus(qq),
        .steering_re_bus(sr),.steering_im_bus(si),.capture_ready(cr),.output_valid(ov),.solver_error(err),
        .beam_re(br),.beam_im(bi),.core_cancel(cancel),.busy(busy));
    beamforming_top #(.FRAME_SAMPLES(512),.ACTIVE_MASK(ACTIVE_MASK))u_core(
        .clk(clk),.rst(rst||cancel),.sample_valid(sv),.frame_start(start_frame),.frame_end(end_frame),
        .in_i_bus(ii),.in_q_bus(qq),.steering_re_bus(sr),.steering_im_bus(si),.capture_ready(cr),.output_valid(ov),
        .solver_error(err),.beam_re(br),.beam_im(bi),.covariance_valid(),.weights_valid(),.solver_busy(),.frame_ready(),.replay_valid());
endmodule
