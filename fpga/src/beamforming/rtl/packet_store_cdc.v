`timescale 1ns/1ps
// Two complete-packet ownership mailboxes. See network_cdc_contract.md.
// One common reset request; local rst outputs may also reset connected logic.
// Payload RAM is dual clock. Only synchronized request/acknowledge cross as FFs.
module packet_store_cdc #(
    parameter integer MAX_WORDS=264
) (
    input wire async_reset, s_clk, m_clk,
    output wire s_rst, m_rst,
    output wire s_available,
    input wire s_we,
    input wire [8:0] s_addr,
    input wire [31:0] s_data,
    input wire s_commit,
    input wire [8:0] s_words,
    output wire m_valid,
    input wire m_ready,
    output wire [31:0] m_data,
    output wire m_last,
    output reg descriptor_error
);
    network_cdc_reset reset_s(.clk(s_clk),.async_reset(async_reset),.rst(s_rst));
    network_cdc_reset reset_m(.clk(m_clk),.async_reset(async_reset),.rst(m_rst));
    reg [1:0] request_toggle, acknowledge_toggle;
    reg write_bank,read_bank;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] req_sync0,req_sync1;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] ack_sync0,ack_sync1;
    wire [1:0] synced_request={req_sync1[1],req_sync0[1]};
    wire [1:0] synced_ack={ack_sync1[1],ack_sync0[1]};
    (* ram_style="block" *) reg [31:0] memory [0:1023];
    localparam IDLE=0,META_READ=1,META_USE=2,DATA_READ=3,DATA_USE=4,SEND=5;
    reg [2:0] state;
    reg [8:0] read_addr,word_count;
    reg [31:0] ram_read,output_data;
    wire ram_write_enable=s_available && (s_commit || (s_we && s_addr<MAX_WORDS));
    wire [9:0] ram_write_address={write_bank,s_commit ? 9'd511 : s_addr};
    wire [31:0] ram_write_data=s_commit ? {23'd0,s_words} : s_data;
    wire [9:0] ram_read_address={read_bank,(state==META_READ) ? 9'd511 : read_addr};
    assign s_available=!s_rst && (request_toggle[write_bank]==synced_ack[write_bank]);
    assign m_valid=!m_rst && state==SEND;
    assign m_data=output_data;
    assign m_last=(read_addr==word_count-1'b1);
    always @(posedge s_clk or posedge s_rst) begin
        if(s_rst) begin ack_sync0<=0;ack_sync1<=0;request_toggle<=0;write_bank<=0;end
        else begin
            ack_sync0<={ack_sync0[0],acknowledge_toggle[0]};
            ack_sync1<={ack_sync1[0],acknowledge_toggle[1]};
            if(s_commit && s_available) begin
                request_toggle[write_bank]<=~request_toggle[write_bank];
                write_bank<=~write_bank;
            end
        end
    end
    // No reset on RAM ports: reset invalidates ownership, not stored bits.
    always @(posedge s_clk)
        if(ram_write_enable) memory[ram_write_address]<=ram_write_data;
    always @(posedge m_clk)
        if(state==META_READ || state==DATA_READ) ram_read<=memory[ram_read_address];
    always @(posedge m_clk or posedge m_rst) begin
        if(m_rst) begin
            req_sync0<=0;req_sync1<=0;acknowledge_toggle<=0;read_bank<=0;
            state<=IDLE;read_addr<=0;word_count<=0;output_data<=0;descriptor_error<=0;
        end else begin
            req_sync0<={req_sync0[0],request_toggle[0]};
            req_sync1<={req_sync1[0],request_toggle[1]};
            case(state)
                IDLE: if(synced_request[read_bank]!=acknowledge_toggle[read_bank]) state<=META_READ;
                META_READ: state<=META_USE;
                META_USE: begin
                    if(ram_read==0 || ram_read>MAX_WORDS) begin
                        descriptor_error<=1;
                        acknowledge_toggle[read_bank]<=synced_request[read_bank];
                        read_bank<=~read_bank;state<=IDLE;
                    end else begin word_count<=ram_read[8:0];read_addr<=0;state<=DATA_READ;end
                end
                DATA_READ: state<=DATA_USE;
                DATA_USE: begin output_data<=ram_read;state<=SEND;end
                SEND: if(m_ready) begin
                    if(m_last) begin
                        acknowledge_toggle[read_bank]<=synced_request[read_bank];
                        read_bank<=~read_bank;state<=IDLE;
                    end else begin read_addr<=read_addr+1'b1;state<=DATA_READ;end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
