`timescale 1ns/1ps
module beamforming_top #(
    parameter integer N_CH = 16,
    parameter integer IQ_W = 16,
    parameter integer ACC_W = 48,
    parameter integer WEIGHT_W = 24,
    parameter integer WEIGHT_FRAC = 23,
    parameter integer FRAME_SAMPLES = 32,
    parameter [N_CH-1:0] ACTIVE_MASK = {N_CH{1'b1}}
) (
    input wire clk,
    input wire rst,
    input wire sample_valid,
    input wire frame_start,
    input wire frame_end,
    input wire signed [N_CH*IQ_W-1:0] in_i_bus,
    input wire signed [N_CH*IQ_W-1:0] in_q_bus,
    // Q1.23 steering values for the current RF frequency. The upstream
    // controller must update these for each frequency; a frame represents
    // 32 stored records at one gate in the present COS reference domain.
    input wire signed [N_CH*WEIGHT_W-1:0] steering_re_bus,
    input wire signed [N_CH*WEIGHT_W-1:0] steering_im_bus,
    output wire covariance_valid,
    output wire weights_valid,
    output wire solver_busy,
    output wire solver_error,
    output wire capture_ready,
    output wire frame_ready,
    output wire replay_valid,
    output wire output_valid,
    output wire signed [ACC_W-1:0] beam_re,
    output wire signed [ACC_W-1:0] beam_im
);
    wire signed [N_CH*N_CH*ACC_W-1:0] r_re_bus;
    wire signed [N_CH*N_CH*ACC_W-1:0] r_im_bus;
    wire signed [N_CH*WEIGHT_W-1:0] w_re_bus;
    wire signed [N_CH*WEIGHT_W-1:0] w_im_bus;
    wire replay_start;
    wire replay_start_out, replay_end;
    wire signed [N_CH*IQ_W-1:0] replay_i_bus, replay_q_bus;
    wire capture_accept;
    wire signed [N_CH*IQ_W-1:0] active_i_bus, active_q_bus;
    wire signed [N_CH*WEIGHT_W-1:0] active_steering_re, active_steering_im;
    // Mask before BOTH covariance accumulation and replay storage. Keep physical
    // channel numbering and the16-lane transport; never repack active antennas.
    genvar active_ch;
    generate for(active_ch=0;active_ch<N_CH;active_ch=active_ch+1) begin : active_inputs
        assign active_i_bus[active_ch*IQ_W +: IQ_W] = ACTIVE_MASK[active_ch] ? in_i_bus[active_ch*IQ_W +: IQ_W] : {IQ_W{1'b0}};
        assign active_q_bus[active_ch*IQ_W +: IQ_W] = ACTIVE_MASK[active_ch] ? in_q_bus[active_ch*IQ_W +: IQ_W] : {IQ_W{1'b0}};
        assign active_steering_re[active_ch*WEIGHT_W +: WEIGHT_W] = ACTIVE_MASK[active_ch] ? steering_re_bus[active_ch*WEIGHT_W +: WEIGHT_W] : {WEIGHT_W{1'b0}};
        assign active_steering_im[active_ch*WEIGHT_W +: WEIGHT_W] = ACTIVE_MASK[active_ch] ? steering_im_bus[active_ch*WEIGHT_W +: WEIGHT_W] : {WEIGHT_W{1'b0}};
    end endgenerate
    // A failed solve discards its pending frame and cancels any beam output.
    // The solver itself receives external reset only, so its error pulse is
    // observable for one full clock before capture is reopened.
    wire frame_logic_reset = rst || solver_error;

    // A frame is accepted only while the single-bank buffer is available.
    // The same accepted record feeds covariance and the frame store.
    assign capture_accept = sample_valid && capture_ready;
    assign replay_start = weights_valid;

    iq_frame_buffer #(.N_CH(N_CH), .IQ_W(IQ_W),
                      .FRAME_SAMPLES(FRAME_SAMPLES)) u_frame (
        .clk(clk), .rst(frame_logic_reset),
        .capture_valid(capture_accept), .capture_start(frame_start && capture_ready),
        .capture_end(frame_end && capture_ready),
        .capture_i_bus(active_i_bus), .capture_q_bus(active_q_bus),
        .capture_ready(capture_ready), .frame_ready(frame_ready),
        .replay_start(replay_start), .replay_valid(replay_valid),
        .replay_start_out(replay_start_out), .replay_end(replay_end),
        .replay_i_bus(replay_i_bus), .replay_q_bus(replay_q_bus)
    );

    covariance_estimator #(.N_CH(N_CH), .IQ_W(IQ_W), .ACC_W(ACC_W),
                            .FRAME_SAMPLES(FRAME_SAMPLES)) u_cov (
        .clk(clk), .rst(frame_logic_reset), .sample_valid(capture_accept),
        .frame_start(frame_start && capture_ready), .frame_end(frame_end && capture_ready),
        .x_i_bus(active_i_bus), .x_q_bus(active_q_bus),
        .matrix_valid(covariance_valid), .r_re_bus(r_re_bus), .r_im_bus(r_im_bus)
    );
    mvdr_solver_stub #(.N_CH(N_CH), .ACC_W(ACC_W), .WEIGHT_W(WEIGHT_W), .ACTIVE_MASK(ACTIVE_MASK)) u_solver (
        .clk(clk), .rst(rst), .matrix_valid(covariance_valid),
        .r_re_bus(r_re_bus), .r_im_bus(r_im_bus),
        .steering_re_bus(active_steering_re), .steering_im_bus(active_steering_im),
        .weights_valid(weights_valid), .busy(solver_busy), .solver_error(solver_error),
        .weight_re_bus(w_re_bus), .weight_im_bus(w_im_bus)
    );
    complex_beamformer #(.N_CH(N_CH), .IQ_W(IQ_W), .WEIGHT_W(WEIGHT_W),
                          .WEIGHT_FRAC(WEIGHT_FRAC), .ACC_W(ACC_W)) u_beam (
        .clk(clk), .rst(frame_logic_reset), .sample_valid(replay_valid),
        .x_i_bus(replay_i_bus), .x_q_bus(replay_q_bus),
        .w_re_bus(w_re_bus), .w_im_bus(w_im_bus),
        .output_valid(output_valid), .y_re(beam_re), .y_im(beam_im)
    );
endmodule
