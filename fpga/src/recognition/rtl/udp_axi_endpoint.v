`timescale 1ns/1ps
// 360-word packets, split into <=256-beat bursts without crossing 4KB.
// Existing 512-word buffers freeze across request/reply CDC.
// Big-endian words: request YOLO,sequence,opcode,address,count,[write words].
// Reply: YOLO,sequence,status,count,[read words]. Opcodes 1=write,2=read.
module udp_axi_endpoint(
 input clk,resetn,mac_clk,rec_en,rec_pkt_done,input [31:0] rec_data,
 input [15:0] rec_byte_num,input tx_req,tx_done,
 output reg tx_start_en=0,output reg [15:0] tx_byte_num=0,
 output reg [31:0] tx_data=0,
 output reg [31:0] awaddr=0,wdata=0,araddr=0,
 output reg [7:0] awlen=0,arlen=0,
 output reg awvalid=0,wvalid=0,wlast=0,arvalid=0,
 output bready, rready,input awready,wready,bvalid,arready,rvalid,rlast,
 input [31:0] rdata);
localparam MAGIC=32'h594f4c4f;
(* ram_style="block" *) reg [31:0] request_ram[0:511];
(* ram_style="block" *) reg [31:0] reply_ram[0:511];
reg [8:0] rx_index=0,tx_index=0;
reg rx_busy=0,request_toggle=0;
reg [15:0] request_length=0;
reg reply_toggle=0;
reg [15:0] response_length=0;
(* ASYNC_REG="TRUE" *) reg reply_meta=0,reply_sync=0;
reg reply_seen=0;
always @(posedge mac_clk) begin
 if(!resetn) begin
  rx_index<=0;rx_busy<=0;request_toggle<=0;reply_meta<=0;reply_sync<=0;
  reply_seen<=0;tx_start_en<=0;tx_index<=0;
 end else begin
  reply_meta<=reply_toggle;reply_sync<=reply_meta;tx_start_en<=0;
  if(rec_en && !rx_busy) begin request_ram[rx_index]<=rec_data;rx_index<=rx_index+1'b1;end
  if(rec_pkt_done && !rx_busy) begin
   request_length<=rec_byte_num;request_toggle<=~request_toggle;rx_busy<=1;rx_index<=0;
  end
  if(reply_sync!=reply_seen) begin
   reply_seen<=reply_sync;tx_byte_num<=response_length;tx_start_en<=1;tx_index<=0;
  end
  if(tx_req) begin tx_data<=reply_ram[tx_index];tx_index<=tx_index+1'b1;end
  if(tx_done) rx_busy<=0;
 end
end
(* ASYNC_REG="TRUE" *) reg request_meta=0,request_sync=0;
reg request_seen=0;
reg [8:0] ram_index=0;
reg [31:0] ram_q=0;
always @(posedge clk) ram_q<=request_ram[ram_index];
reg [31:0] header[0:4];
reg [31:0] last_sequence=0;
reg have_cache=0;
reg [3:0] state=0;
reg [2:0] header_index=0,reply_index=0;
reg [8:0] count=0,index=0;
reg more_write=0;
reg [8:0] burst_end=0;
function [8:0] burst_words;
 input [31:0] address;
 input [8:0] remaining;
 reg [10:0] page_words;
 begin
  page_words=11'd1024-{1'b0,address[11:2]};
  burst_words=remaining>256?9'd256:remaining;
  if(page_words<burst_words) burst_words=page_words[8:0];
 end
endfunction
wire [8:0] first_words=burst_words(header[3],header[4][8:0]);
wire [31:0] next_address=header[3]+{21'd0,index,2'b00};
wire [8:0] next_words=burst_words(next_address,count-index);
wire [8:0] read_next_words=burst_words(next_address+32'd4,count-index-9'd1);
reg [31:0] status=0;
reg valid_addr;
reg [32:0] end_addr;
always @(*) begin
 end_addr={1'b0,header[3]}+{22'd0,header[4][8:0],2'b00};
 valid_addr=header[3][1:0]==0 &&
  ((header[3]<32'h3000 && end_addr<=33'h3000) ||
   (header[3]>=32'h100000 && end_addr<=33'h140000) ||
   (header[3]>=32'h400000 && end_addr<=33'h440000 && header[2]==2));
end
assign bready=(state==9);
assign rready=(state==11);
always @(posedge clk) begin
 if(!resetn) begin
  request_meta<=0;request_sync<=0;request_seen<=0;state<=0;have_cache<=0;
  awvalid<=0;wvalid<=0;arvalid<=0;reply_toggle<=0;
 end else begin
  request_meta<=request_toggle;request_sync<=request_meta;
  case(state)
   0: if(request_sync!=request_seen) begin
       request_seen<=request_sync;ram_index<=0;header_index<=0;state<=1;
      end
   1: state<=2;
   2: begin
       header[header_index]<=ram_q;
       if(header_index==4) state<=3;
       else begin header_index<=header_index+1'b1;ram_index<=ram_index+1'b1;state<=1;end
      end
   3: begin
       status<=0;count<=header[4][8:0];index<=0;more_write<=0;burst_end<=first_words-1'b1;
       if(header[0]!=MAGIC || (header[2]!=1 && header[2]!=2) ||
          header[4]<1 || header[4]>360 || !valid_addr ||
          (header[2]==1 && request_length!=20+header[4]*4) ||
          (header[2]==2 && request_length!=20)) begin
        status<=1;count<=0;reply_index<=0;state<=12;
       end else if(have_cache && header[1]==last_sequence) begin
        // An acknowledged command is never executed twice after a lost reply.
        reply_toggle<=~reply_toggle;state<=0;
       end else if(header[2]==1) begin
        awaddr<=header[3];awlen<=first_words-1'b1;awvalid<=1;state<=4;
       end else begin
        araddr<=header[3];arlen<=first_words-1'b1;arvalid<=1;state<=10;
       end
      end
   4: if(awvalid && awready) begin awvalid<=0;ram_index<=9'd5+index;state<=5;end
   5: state<=6;
   6: begin wdata<=ram_q;wlast<=(index==burst_end);wvalid<=1;state<=7;end
   7: if(wvalid && wready) begin
       wvalid<=0;
       if(index==count-1) begin more_write<=0;state<=9;end
       else if(index==burst_end) begin index<=index+1'b1;more_write<=1;state<=9;end
       else begin index<=index+1'b1;ram_index<=ram_index+1'b1;state<=5;end
      end
   9: if(bvalid) begin
       if(more_write) begin
        more_write<=0;awaddr<=next_address;awlen<=next_words-1'b1;
        burst_end<=index+next_words-1'b1;awvalid<=1;state<=4;
       end else begin count<=0;reply_index<=0;state<=12;end
      end
   10: if(arvalid && arready) begin arvalid<=0;state<=11;end
   11: if(rvalid) begin
        reply_ram[4+index]<=rdata;
        if(index==count-1) begin
         if(!rlast) status<=2;
         reply_index<=0;state<=12;
        end else if(index==burst_end) begin
         if(!rlast) status<=2;
         index<=index+1'b1;araddr<=next_address+32'd4;arlen<=read_next_words-1'b1;
         burst_end<=index+read_next_words;arvalid<=1;state<=10;
        end else index<=index+1'b1;
       end
   12: begin
        case(reply_index)
         0:reply_ram[0]<=MAGIC;
         1:reply_ram[1]<=header[1];
         2:reply_ram[2]<=status;
         3:reply_ram[3]<={23'd0,count};
        endcase
        if(reply_index==3) begin
         response_length<=16+count*4;
         // Only cache valid operations. Invalid requests must not replace a valid cache.
         if(status==0) begin have_cache<=1;last_sequence<=header[1];end
         else have_cache<=0;
         state<=13;
        end else reply_index<=reply_index+1'b1;
       end
   13: begin reply_toggle<=~reply_toggle;state<=0;end
   default:state<=0;
  endcase
 end
end
endmodule
