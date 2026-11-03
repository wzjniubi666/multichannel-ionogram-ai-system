`timescale 1ns/1ps
// PZ-K7325T-FH board shell for the abstract beamforming core.
//
// The board provides a 200 MHz differential oscillator and an active-low
// reset. The IQ and steering buses remain abstract until the receiver/ADC
// electrical interface and channel mapping are confirmed.
module kt325t_beamforming_board_top #(
    parameter integer N_CH = 16,
    parameter integer IQ_W = 16,
    parameter integer ACC_W = 48,
    parameter integer WEIGHT_W = 24,
    parameter integer WEIGHT_FRAC = 23,
    parameter integer FRAME_SAMPLES = 32,
    parameter [N_CH-1:0] ACTIVE_MASK = (N_CH==16) ? 16'h7f7f : {N_CH{1'b1}}
) (
    input wire sys_clk_p,
    input wire sys_clk_n,
    input wire sys_rstn,
    input wire sample_valid,
    input wire frame_start,
    input wire frame_end,
    input wire signed [N_CH*IQ_W-1:0] iq_i_bus,
    input wire signed [N_CH*IQ_W-1:0] iq_q_bus,
    input wire signed [N_CH*WEIGHT_W-1:0] steering_re_bus,
    input wire signed [N_CH*WEIGHT_W-1:0] steering_im_bus,
    output wire [4:0] led,
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
    wire clk_ibuf;
    wire clk;
    reg [1:0] reset_pipe;
    wire rst;

    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("TRUE")
    ) u_sys_clk_ibufds (
        .I(sys_clk_p),
        .IB(sys_clk_n),
        .O(clk_ibuf)
    );

    BUFG u_sys_clk_bufg (
        .I(clk_ibuf),
        .O(clk)
    );

    // Asynchronously assert reset from the board supervisor and release it
    // synchronously after two 200 MHz clock edges.
    always @(posedge clk or negedge sys_rstn) begin
        if (!sys_rstn)
            reset_pipe <= 2'b00;
        else
            reset_pipe <= {reset_pipe[0], 1'b1};
    end
    assign rst = ~reset_pipe[1];

    beamforming_top #(
        .N_CH(N_CH),
        .IQ_W(IQ_W),
        .ACC_W(ACC_W),
        .WEIGHT_W(WEIGHT_W),
        .WEIGHT_FRAC(WEIGHT_FRAC),
        .FRAME_SAMPLES(FRAME_SAMPLES),
        .ACTIVE_MASK(ACTIVE_MASK)
    ) u_beamforming_top (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .in_i_bus(iq_i_bus),
        .in_q_bus(iq_q_bus),
        .steering_re_bus(steering_re_bus),
        .steering_im_bus(steering_im_bus),
        .covariance_valid(covariance_valid),
        .weights_valid(weights_valid),
        .solver_busy(solver_busy),
        .solver_error(solver_error),
        .capture_ready(capture_ready),
        .frame_ready(frame_ready),
        .replay_valid(replay_valid),
        .output_valid(output_valid),
        .beam_re(beam_re),
        .beam_im(beam_im)
    );

    // Active-high status indications for the official PZ-K7325T LED example.
    assign led[0] = frame_ready;
    assign led[1] = solver_busy;
    assign led[2] = weights_valid;
    assign led[3] = replay_valid;
    assign led[4] = output_valid;
endmodule

