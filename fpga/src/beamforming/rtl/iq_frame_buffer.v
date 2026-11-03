`timescale 1ns/1ps
// Single-frame store-and-replay buffer. Capture and replay are mutually
// exclusive; the producer must hold a frame until capture_ready is high.
module iq_frame_buffer #(
    parameter integer N_CH=16, IQ_W=16, FRAME_SAMPLES=32,
    parameter integer ADDR_W=(FRAME_SAMPLES <= 2) ? 1 : $clog2(FRAME_SAMPLES)
) (
    input wire clk, rst,
    input wire capture_valid, capture_start, capture_end,
    input wire signed [N_CH*IQ_W-1:0] capture_i_bus, capture_q_bus,
    output wire capture_ready,
    output reg frame_ready, input wire replay_start,
    output reg replay_valid, output reg replay_start_out, output reg replay_end,
    output reg signed [N_CH*IQ_W-1:0] replay_i_bus, replay_q_bus
);
    localparam [1:0] EMPTY=0, CAPTURE=1, FULL=2, REPLAY=3;
    reg [1:0] state;
    // The frame store is read synchronously during replay and is idle while
    // capturing. Keep the two buses in block RAM rather than consuming LUTs.
    (* ram_style = "block" *)
    reg signed [N_CH*IQ_W-1:0] mem_i[0:FRAME_SAMPLES-1];
    (* ram_style = "block" *)
    reg signed [N_CH*IQ_W-1:0] mem_q[0:FRAME_SAMPLES-1];
    reg [ADDR_W:0] wr_count, rd_count;
    assign capture_ready=(state==EMPTY)||(state==CAPTURE);
    wire capture_first = (state==EMPTY) && capture_valid && capture_start;
    wire capture_next = (state==CAPTURE) && capture_valid && (wr_count<FRAME_SAMPLES);
    wire [ADDR_W-1:0] write_addr = capture_first ? {ADDR_W{1'b0}} : wr_count[ADDR_W-1:0];

    // One write port and one registered read port. Keep RAM accesses outside
    // the reset/state process: clearing the read data or describing multiple
    // write addresses in separate branches prevents the intended inference.
    // Read data is unspecified when replay_valid=0, including during reset.
    always @(posedge clk) begin
        if (!rst && (capture_first || capture_next)) begin
            mem_i[write_addr] <= capture_i_bus;
            mem_q[write_addr] <= capture_q_bus;
        end
        if (!rst && state==REPLAY) begin
            replay_i_bus <= mem_i[rd_count[ADDR_W-1:0]];
            replay_q_bus <= mem_q[rd_count[ADDR_W-1:0]];
        end
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=EMPTY; frame_ready<=0; replay_valid<=0;
            replay_start_out<=0; replay_end<=0;
            wr_count<=0; rd_count<=0;
        end else begin
            replay_valid<=0; replay_start_out<=0; replay_end<=0;
            case(state)
                EMPTY: if(capture_valid && capture_start) begin
                    wr_count<=1; state<=CAPTURE;
                    if(capture_end) begin state<=FULL; frame_ready<=1; end
                end
                CAPTURE: if(capture_valid) begin
                    if(wr_count<FRAME_SAMPLES) begin
                        wr_count<=wr_count+1'b1;
                        if(capture_end && wr_count==FRAME_SAMPLES-1) begin
                            state<=FULL; frame_ready<=1;
                        end
                    end
                end
                FULL: if(replay_start) begin rd_count<=0; state<=REPLAY; end
                REPLAY: begin
                    replay_valid<=1; replay_start_out<=(rd_count==0);
                    replay_end<=(rd_count==FRAME_SAMPLES-1);
                    if(rd_count==FRAME_SAMPLES-1) begin
                        state<=EMPTY; frame_ready<=0; wr_count<=0;
                    end else rd_count<=rd_count+1'b1;
                end
            endcase
        end
    end
endmodule
