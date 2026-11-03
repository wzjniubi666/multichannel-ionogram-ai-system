`timescale 1ns/1ps
module mii_byte_bridge(
 input raw_clk,input resetn,input rx_valid,input [3:0] rx_nibble,
 output gmii_clk,output reg gmii_rx_en=0,output reg [7:0] gmii_rxd=0,
 input gmii_tx_en,input [7:0] gmii_txd,output tx_en,output [3:0] tx_nibble);
reg divide=0;
always @(negedge raw_clk or negedge resetn) begin
 if(!resetn) divide<=0;else divide<=~divide;
end
BUFG byte_clock(.I(divide),.O(gmii_clk));
reg half=0,toggle=0;reg [3:0] lower=0;reg [7:0] assembled=0;
always @(posedge raw_clk or negedge resetn) begin
 if(!resetn) begin half<=0;toggle<=0;lower<=0;assembled<=0;end
 else if(!rx_valid) half<=0;
 else if(!half) begin lower<=rx_nibble;half<=1;end
 else begin assembled<={rx_nibble,lower};toggle<=~toggle;half<=0;end
end
reg consumed=0;
always @(posedge gmii_clk or negedge resetn) begin
 if(!resetn) begin consumed<=0;gmii_rx_en<=0;gmii_rxd<=0;end
 else begin
  gmii_rx_en<=(toggle!=consumed);
  if(toggle!=consumed) gmii_rxd<=assembled;
  consumed<=toggle;
 end
end
assign tx_en=gmii_tx_en;
assign tx_nibble=divide?gmii_txd[3:0]:gmii_txd[7:4];
endmodule
