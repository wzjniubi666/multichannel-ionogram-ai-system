`timescale 1ns/1ps
// Ready/valid producer wrapper for complete TX packets, two ownership slots.
module packet_stream_cdc #(
    parameter integer MAX_WORDS=264
) (
    input wire async_reset,s_clk,m_clk,
    output wire s_rst,m_rst,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_data,
    input wire s_last,
    output wire m_valid,
    input wire m_ready,
    output wire [31:0] m_data,
    output wire m_last,
    output reg overflow,
    output wire descriptor_error
);
    wire available;
    reg [8:0] addr,words;
    reg commit_pending,discard;
    wire transfer=s_valid && s_ready;
    assign s_ready=!s_rst && (discard || (available && !commit_pending));
    packet_store_cdc #(.MAX_WORDS(MAX_WORDS)) u_store(
        .async_reset(async_reset),.s_clk(s_clk),.m_clk(m_clk),.s_rst(s_rst),.m_rst(m_rst),
        .s_available(available),.s_we(transfer && !discard),.s_addr(addr),.s_data(s_data),
        .s_commit(commit_pending),.s_words(words),.m_valid(m_valid),.m_ready(m_ready),
        .m_data(m_data),.m_last(m_last),.descriptor_error(descriptor_error));
    always @(posedge s_clk or posedge s_rst) begin
        if(s_rst)begin addr<=0;words<=0;commit_pending<=0;discard<=0;overflow<=0;end
        else begin
            if(commit_pending)begin commit_pending<=0;addr<=0;end
            if(transfer)begin
                if(discard)begin if(s_last)begin discard<=0;addr<=0;end end
                else if(s_last)begin words<=addr+1'b1;commit_pending<=1;end
                else if(addr==MAX_WORDS-1)begin discard<=1;overflow<=1;addr<=0;end
                else addr<=addr+1'b1;
            end
        end
    end
endmodule
