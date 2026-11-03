`timescale 1ns/1ps
// Strict, fixed-endpoint IPv4/UDP receiver. Payload writes are speculative;
// only a fully validated Ethernet frame publishes the destination mailbox.
module gmii_bfm_rx #(
    parameter [47:0] BOARD_MAC=48'h020000000001, PEER_MAC=48'h020000000002,
    parameter [31:0] BOARD_IP=32'hc0000201, PEER_IP=32'hc0000202,
    parameter [15:0] BOARD_PORT=5000, PEER_PORT=5000
) (
    input wire clk,rst,gmii_rx_dv,gmii_rx_er,
    input wire [7:0] gmii_rxd,
    input wire store_available,arp_ready,
    output reg store_we,store_commit,
    output reg [8:0] store_addr,store_words,
    output reg [31:0] store_data,
    output reg arp_request,
    output reg [31:0] accepted_packets,rejected_frames,overflow_frames
);
    localparam IDLE=0,PREAMBLE=1,FRAME=2,DRAIN=3;
    reg [1:0] state;
    reg [3:0] preamble_count;
    reg [11:0] byte_count;
    reg frame_bad,can_store;
    reg [31:0] crc;
    reg [47:0] dst_mac,src_mac,arp_sender_mac;
    reg [15:0] eth_type,ip_total,ip_fragment,udp_length,src_port,dst_port,udp_checksum;
    reg [31:0] src_ip,dst_ip,arp_sender_ip,arp_target_ip;
    reg [31:0] ip_sum,udp_sum,pseudo_sum;
    reg [7:0] previous_byte;
    reg [23:0] payload_shift;
    reg [8:0] payload_words;
    reg ip_format_bad,arp_format_bad;
    wire [11:0] payload_offset=byte_count-12'd42;
    function [31:0] crc_byte;
        input [31:0] old_crc;input [7:0] data;
        reg [31:0] c;integer b;
        begin
            c=old_crc ^ {24'd0,data};
            for(b=0;b<8;b=b+1)c=c[0] ? (c>>1)^32'hedb88320 : (c>>1);
            crc_byte=c;
        end
    endfunction
    function [15:0] folded;
        input [31:0] sum;
        reg [16:0] t;
        begin t={1'b0,sum[15:0]}+sum[31:16];t={1'b0,t[15:0]}+t[16];folded=t[15:0];end
    endfunction
    wire common_good=!frame_bad && !gmii_rx_er && crc==32'hdebb20e3;
    wire udp_good=dst_mac==BOARD_MAC && src_mac==PEER_MAC && !ip_format_bad &&
        ip_total>=60 && ip_total<=1084 && byte_count==ip_total+18 &&
        (ip_fragment & 16'hbfff)==0 && folded(ip_sum)==16'hffff &&
        src_ip==PEER_IP && dst_ip==BOARD_IP && src_port==PEER_PORT && dst_port==BOARD_PORT &&
        udp_length==ip_total-20 && udp_length>=40 && udp_length<=1064 && udp_length[1:0]==0 &&
        udp_checksum!=0 && folded(udp_sum+pseudo_sum)==16'hffff && payload_words==((udp_length-8)>>2);
    wire arp_good=(dst_mac==BOARD_MAC || dst_mac==48'hffffffffffff) && src_mac==PEER_MAC &&
        !arp_format_bad && byte_count==64 && arp_sender_mac==PEER_MAC &&
        arp_sender_ip==PEER_IP && arp_target_ip==BOARD_IP;
    always @(posedge clk or posedge rst) begin
        if(rst)begin
            state<=IDLE;preamble_count<=0;byte_count<=0;frame_bad<=0;can_store<=0;crc<=32'hffffffff;
            dst_mac<=0;src_mac<=0;eth_type<=0;ip_total<=0;ip_fragment<=0;udp_length<=0;
            src_port<=0;dst_port<=0;udp_checksum<=0;src_ip<=0;dst_ip<=0;ip_sum<=0;udp_sum<=0;pseudo_sum<=0;
            previous_byte<=0;payload_shift<=0;payload_words<=0;ip_format_bad<=0;arp_format_bad<=0;
            arp_sender_mac<=0;arp_sender_ip<=0;arp_target_ip<=0;
            store_we<=0;store_commit<=0;store_addr<=0;store_data<=0;store_words<=0;arp_request<=0;
            accepted_packets<=0;rejected_frames<=0;overflow_frames<=0;
        end else begin
            store_we<=0;store_commit<=0;arp_request<=0;
            case(state)
                IDLE: if(gmii_rx_dv)begin
                    if(gmii_rxd==8'h55 && !gmii_rx_er)begin preamble_count<=1;state<=PREAMBLE;end
                    else state<=DRAIN;
                end
                PREAMBLE:begin
                    if(!gmii_rx_dv)begin rejected_frames<=rejected_frames+1'b1;state<=IDLE;end
                    else if(gmii_rx_er)state<=DRAIN;
                    else if(preamble_count<7 && gmii_rxd==8'h55)preamble_count<=preamble_count+1'b1;
                    else if(preamble_count==7 && gmii_rxd==8'hd5)begin
                        state<=FRAME;byte_count<=0;frame_bad<=0;can_store<=store_available;crc<=32'hffffffff;
                        dst_mac<=0;src_mac<=0;eth_type<=0;ip_total<=0;ip_fragment<=0;udp_length<=0;
                        src_port<=0;dst_port<=0;udp_checksum<=0;src_ip<=0;dst_ip<=0;ip_sum<=0;udp_sum<=0;pseudo_sum<=0;
                        payload_shift<=0;payload_words<=0;ip_format_bad<=0;arp_format_bad<=0;
                        arp_sender_mac<=0;arp_sender_ip<=0;arp_target_ip<=0;
                    end else state<=DRAIN;
                end
                FRAME:begin
                    if(gmii_rx_dv)begin
                        crc<=crc_byte(crc,gmii_rxd);
                        if(gmii_rx_er || byte_count>=1518)frame_bad<=1;
                        if(byte_count<4095)byte_count<=byte_count+1'b1;
                        previous_byte<=gmii_rxd;
                        if(byte_count<6)dst_mac<={dst_mac[39:0],gmii_rxd};
                        else if(byte_count<12)src_mac<={src_mac[39:0],gmii_rxd};
                        else if(byte_count<14)eth_type<={eth_type[7:0],gmii_rxd};
                        if(eth_type==16'h0800)begin
                            if(byte_count>=14 && byte_count<34 && byte_count[0])
                                ip_sum<=ip_sum+{previous_byte,gmii_rxd};
                            // Build pseudo-header incrementally, outside the final commit path.
                            if(byte_count==27 || byte_count==29 || byte_count==31 || byte_count==33)
                                pseudo_sum<=pseudo_sum+{previous_byte,gmii_rxd};
                            else if(byte_count==39)pseudo_sum<=pseudo_sum+{previous_byte,gmii_rxd}+32'd17;
                            if((byte_count>=34 && byte_count<42 && byte_count[0]) ||
                               (byte_count>=42 && byte_count<34+udp_length && byte_count[0]))
                                udp_sum<=udp_sum+{previous_byte,gmii_rxd};
                            case(byte_count)
                                14:if(gmii_rxd!=8'h45)ip_format_bad<=1;
                                16,17:ip_total<={ip_total[7:0],gmii_rxd};
                                20,21:ip_fragment<={ip_fragment[7:0],gmii_rxd};
                                22:if(gmii_rxd==0)ip_format_bad<=1;
                                23:if(gmii_rxd!=17)ip_format_bad<=1;
                                26,27,28,29:src_ip<={src_ip[23:0],gmii_rxd};
                                30,31,32,33:dst_ip<={dst_ip[23:0],gmii_rxd};
                                34,35:src_port<={src_port[7:0],gmii_rxd};
                                36,37:dst_port<={dst_port[7:0],gmii_rxd};
                                38,39:udp_length<={udp_length[7:0],gmii_rxd};
                                40,41:udp_checksum<={udp_checksum[7:0],gmii_rxd};
                            endcase
                            if(byte_count>=42 && byte_count<34+udp_length)begin
                                payload_shift<={payload_shift[15:0],gmii_rxd};
                                if(payload_offset[1:0]==3)begin
                                    if(payload_words<264 && can_store)begin
                                        store_we<=1;store_addr<=payload_words;store_data<={payload_shift,gmii_rxd};
                                    end
                                    if(payload_words<511)payload_words<=payload_words+1'b1;
                                end
                            end
                        end else if(eth_type==16'h0806)begin
                            case(byte_count)
                                14,20:if(gmii_rxd!=0)arp_format_bad<=1;
                                16:if(gmii_rxd!=8'h08)arp_format_bad<=1;
                                15,21:if(gmii_rxd!=1)arp_format_bad<=1;
                                17:if(gmii_rxd!=8'h00)arp_format_bad<=1;
                                18:if(gmii_rxd!=6)arp_format_bad<=1;
                                19:if(gmii_rxd!=4)arp_format_bad<=1;
                                22,23,24,25,26,27:arp_sender_mac<={arp_sender_mac[39:0],gmii_rxd};
                                28,29,30,31:arp_sender_ip<={arp_sender_ip[23:0],gmii_rxd};
                                38,39,40,41:arp_target_ip<={arp_target_ip[23:0],gmii_rxd};
                            endcase
                        end
                    end else begin
                        state<=IDLE;
                        if(common_good && eth_type==16'h0800 && udp_good)begin
                            if(can_store)begin
                                store_words<=payload_words;store_commit<=1;accepted_packets<=accepted_packets+1'b1;
                            end else overflow_frames<=overflow_frames+1'b1;
                        end else if(common_good && eth_type==16'h0806 && arp_good)begin
                            if(arp_ready)arp_request<=1;
                        end else rejected_frames<=rejected_frames+1'b1;
                    end
                end
                DRAIN:if(!gmii_rx_dv)begin rejected_frames<=rejected_frames+1'b1;state<=IDLE;end
            endcase
        end
    end
endmodule
