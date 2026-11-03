`timescale 1ns/1ps
// Complete-packet buffering in TX domain; vendor engines cannot pause mid-frame.
module gmii_bfm_tx #(
    parameter [47:0] BOARD_MAC=48'h020000000001, PEER_MAC=48'h020000000002,
    parameter [31:0] BOARD_IP=32'hc0000201, PEER_IP=32'hc0000202,
    parameter [15:0] BOARD_PORT=5000, PEER_PORT=5000
) (
    input wire clk,rst,tx_allow,
    input wire payload_valid,
    output wire payload_ready,
    input wire [31:0] payload_data,
    input wire payload_last,
    input wire arp_valid,
    output wire arp_accept,
    output wire gmii_tx_en,
    output wire [7:0] gmii_txd,
    output reg [31:0] sent_udp,sent_arp
);
    localparam FILL=0,CHECKSUM=1,READY=2,WAIT_DONE=3;
    localparam OWNER_IDLE=0,OWNER_UDP=1,OWNER_ARP=2,OWNER_IFG=3;
    reg [1:0] state,owner;
    reg [3:0] ifg_count;
    reg [8:0] fill_addr,read_addr;
    (* ram_style="block" *) reg [31:0] tx_memory[0:511];
    reg [31:0] vendor_data,payload_sum;
    reg [15:0] payload_bytes,udp_checksum;
    reg udp_start,arp_start;
    wire udp_req,udp_done,arp_done,udp_en,arp_en,udp_crc_en,arp_crc_en,udp_crc_clr,arp_crc_clr;
    wire [7:0] udp_data,arp_data;
    wire [31:0] udp_crc,udp_crc_next,arp_crc,arp_crc_next;
    assign payload_ready=!rst && state==FILL;
    assign arp_accept=!rst && tx_allow && owner==OWNER_IDLE && state!=READY && arp_valid;
    assign gmii_tx_en=!rst && ((owner==OWNER_UDP && udp_en) || (owner==OWNER_ARP && arp_en));
    assign gmii_txd=(owner==OWNER_ARP) ? arp_data : udp_data;
    function [15:0] checksum;
        input [31:0] sum;
        reg [16:0] t;reg [15:0] inverted;
        begin
            t={1'b0,sum[15:0]}+sum[31:16];t={1'b0,t[15:0]}+t[16];inverted=~t[15:0];
            checksum=(inverted==0) ? 16'hffff : inverted;
        end
    endfunction
    always @(posedge clk)begin
        if(payload_valid && payload_ready)tx_memory[fill_addr]<=payload_data;
        // The vendor tx_req arrives one cycle before the new word is consumed.
        if(udp_req)vendor_data<=tx_memory[read_addr];
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=FILL;owner<=OWNER_IDLE;ifg_count<=0;fill_addr<=0;read_addr<=0;
            payload_sum<=0;payload_bytes<=0;udp_checksum<=0;udp_start<=0;arp_start<=0;
            sent_udp<=0;sent_arp<=0;
        end else begin
            udp_start<=0;arp_start<=0;
            if(payload_valid && payload_ready)begin
                payload_sum<=payload_sum+payload_data[31:16]+payload_data[15:0];
                if(payload_last)begin payload_bytes<=(fill_addr+1'b1)<<2;state<=CHECKSUM;end
                else fill_addr<=fill_addr+1'b1;
            end
            if(state==CHECKSUM)begin
                udp_checksum<=checksum(payload_sum+BOARD_IP[31:16]+BOARD_IP[15:0]+PEER_IP[31:16]+
                    PEER_IP[15:0]+32'd17+BOARD_PORT+PEER_PORT+((32'd8+payload_bytes)<<1));
                state<=READY;
            end
            if(udp_req)read_addr<=read_addr+1'b1;
            case(owner)
                OWNER_IDLE:if(tx_allow)begin
                    if(state==READY)begin udp_start<=1;owner<=OWNER_UDP;state<=WAIT_DONE;read_addr<=0;end
                    else if(arp_valid)begin arp_start<=1;owner<=OWNER_ARP;end
                end
                OWNER_UDP:if(udp_done)begin
                    owner<=OWNER_IFG;ifg_count<=0;state<=FILL;fill_addr<=0;payload_sum<=0;
                    sent_udp<=sent_udp+1'b1;
                end
                OWNER_ARP:if(arp_done)begin owner<=OWNER_IFG;ifg_count<=0;sent_arp<=sent_arp+1'b1;end
                OWNER_IFG:if(ifg_count==11)owner<=OWNER_IDLE;else ifg_count<=ifg_count+1'b1;
            endcase
        end
    end
    bfm_vendor_udp_tx #(.BOARD_MAC(BOARD_MAC),.BOARD_IP(BOARD_IP),.DES_MAC(PEER_MAC),.DES_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT)) u_udp(
        .clk(clk),.rst_n(!rst),.tx_start_en(udp_start),.tx_data(vendor_data),.tx_byte_num(payload_bytes),
        .tx_udp_checksum(udp_checksum),.crc_data(udp_crc),.crc_next(udp_crc_next[31:24]),
        .tx_done(udp_done),.tx_req(udp_req),.gmii_tx_en(udp_en),.gmii_txd(udp_data),
        .crc_en(udp_crc_en),.crc_clr(udp_crc_clr));
    crc32_d8 crc_udp(.clk(clk),.rst_n(!rst),.data(udp_data),.crc_en(udp_crc_en),.crc_clr(udp_crc_clr),
        .crc_data(udp_crc),.crc_next(udp_crc_next));
    arp_tx #(.BOARD_MAC(BOARD_MAC),.BOARD_IP(BOARD_IP),.DES_MAC(PEER_MAC),.DES_IP(PEER_IP)) u_arp(
        .clk(clk),.rst_n(!rst),.arp_tx_en(arp_start),.arp_tx_type(1'b1),.des_mac(PEER_MAC),.des_ip(PEER_IP),
        .crc_data(arp_crc),.crc_next(arp_crc_next[31:24]),.tx_done(arp_done),.gmii_tx_en(arp_en),
        .gmii_txd(arp_data),.crc_en(arp_crc_en),.crc_clr(arp_crc_clr));
    crc32_d8 crc_arp(.clk(clk),.rst_n(!rst),.data(arp_data),.crc_en(arp_crc_en),.crc_clr(arp_crc_clr),
        .crc_data(arp_crc),.crc_next(arp_crc_next));
endmodule
