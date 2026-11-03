module iq_unpack_be #(
    parameter integer IQ_W = 16
) (
    input wire [IQ_W-1:0] i_hi_lo,
    input wire [IQ_W-1:0] q_hi_lo,
    output wire signed [IQ_W-1:0] i_data,
    output wire signed [IQ_W-1:0] q_data
);
    assign i_data = i_hi_lo;
    assign q_data = q_hi_lo;
endmodule
