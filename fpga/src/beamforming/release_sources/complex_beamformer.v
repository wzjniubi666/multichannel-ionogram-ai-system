`timescale 1ns/1ps
// One record per clock, including changing per-record weights. All accepted IQ
// and weight fields are captured together. The registered balanced reduction
// preserves modulo-ACC_W arithmetic and conjugate-weight semantics.
module complex_beamformer #(
    parameter integer N_CH=16, IQ_W=16, WEIGHT_W=24, ACC_W=48, WEIGHT_FRAC=23
)(
    input wire clk,rst,sample_valid,
    input wire signed [N_CH*IQ_W-1:0] x_i_bus,x_q_bus,
    input wire signed [N_CH*WEIGHT_W-1:0] w_re_bus,w_im_bus,
    output reg output_valid,
    output reg signed [ACC_W-1:0] y_re,y_im
);
    localparam integer LEVELS=(N_CH<=1) ? 0 : $clog2(N_CH);
    localparam integer PAD=1<<LEVELS;
    localparam integer PROD_W=IQ_W+WEIGHT_W;
    reg signed [N_CH*IQ_W-1:0] xi_latched,xq_latched;
    reg signed [N_CH*WEIGHT_W-1:0] wr_latched,wi_latched;
    reg [LEVELS+2:0] valid_pipe;
    wire signed [ACC_W-1:0] tree_re[0:(LEVELS+1)*PAD-1];
    wire signed [ACC_W-1:0] tree_im[0:(LEVELS+1)*PAD-1];
    always @(posedge clk) begin
        if(rst) begin valid_pipe<=0; output_valid<=0; y_re<=0; y_im<=0; end
        else begin
            valid_pipe<={valid_pipe[LEVELS+1:0],sample_valid};
            output_valid<=valid_pipe[LEVELS+2];
            if(sample_valid) begin
                xi_latched<=x_i_bus; xq_latched<=x_q_bus;
                wr_latched<=w_re_bus; wi_latched<=w_im_bus;
            end
            if(valid_pipe[LEVELS+2]) begin
                y_re<=tree_re[LEVELS*PAD]>>>WEIGHT_FRAC;
                y_im<=tree_im[LEVELS*PAD]>>>WEIGHT_FRAC;
            end
        end
    end
    genvar ch,level,node;
    generate for(ch=0;ch<PAD;ch=ch+1) begin : channels
        if(ch<N_CH) begin : active
            wire signed [IQ_W-1:0] xi=xi_latched[ch*IQ_W +: IQ_W];
            wire signed [IQ_W-1:0] xq=xq_latched[ch*IQ_W +: IQ_W];
            wire signed [WEIGHT_W-1:0] wr=wr_latched[ch*WEIGHT_W +: WEIGHT_W];
            wire signed [WEIGHT_W-1:0] wi=wi_latched[ch*WEIGHT_W +: WEIGHT_W];
            reg signed [PROD_W-1:0] m1,m2,m3,m4;
            reg signed [ACC_W-1:0] channel_re,channel_im;
            always @(posedge clk) begin
                if(!rst && valid_pipe[0]) begin
                    m1<=xi*wr; m2<=xq*wi; m3<=xq*wr; m4<=xi*wi;
                end
                if(!rst && valid_pipe[1]) begin
                    channel_re<=$signed(m1)+$signed(m2);
                    channel_im<=$signed(m3)-$signed(m4);
                end
            end
            assign tree_re[ch]=channel_re;
            assign tree_im[ch]=channel_im;
        end else begin : padding
            assign tree_re[ch]={ACC_W{1'b0}};
            assign tree_im[ch]={ACC_W{1'b0}};
        end
    end
    for(level=1;level<=LEVELS;level=level+1) begin : levels
        for(node=0;node<(PAD>>level);node=node+1) begin : nodes
            reg signed [ACC_W-1:0] sum_re,sum_im;
            always @(posedge clk) if(!rst && valid_pipe[level+1]) begin
                sum_re<=tree_re[(level-1)*PAD+2*node]+tree_re[(level-1)*PAD+2*node+1];
                sum_im<=tree_im[(level-1)*PAD+2*node]+tree_im[(level-1)*PAD+2*node+1];
            end
            assign tree_re[level*PAD+node]=sum_re;
            assign tree_im[level*PAD+node]=sum_im;
        end
    end endgenerate
endmodule
