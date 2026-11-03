`timescale 1ns/1ps
module tb_c3x2;
reg clock=0;always #5 clock=~clock;
reg reset=0,go=0;
c3_udp_engine d(.clk(clock),.resetn(reset),.mac_clk(clock),.rec_en(1'b0),.rec_pkt_done(1'b0),
 .rec_data(32'd0),.rec_byte_num(16'd0),.tx_req(1'b0),.tx_done(1'b0));
reg [15:0] expected[0:262143];reg [31:0] expected_debug[0:59];
integer i,errors=0;reg [31:0] input_fixture[0:65535];
reg arv=0,rr=0;reg [31:0] addr=0;reg [7:0] length=0;
function [15:0] bank_value;
 input integer bank,index;
 begin case(bank)
  0:bank_value=index%2?d.bank0odd[index/2]:d.bank0even[index/2];
  1:bank_value=index%2?d.bank1odd[index/2]:d.bank1even[index/2];
  2:bank_value=d.bank2[index];
  3:bank_value=d.bank3[index];
 endcase end
endfunction
initial begin
 force d.start=go;force d.awvalid=0;force d.wvalid=0;force d.bready=1;
 force d.arvalid=arv;force d.araddr=addr;force d.arlen=length;force d.arid=0;force d.rready=rr;
 $readmemh("input_words.txt",input_fixture);
 for(i=0;i<65536;i=i+1) begin d.pixels_r[i]=input_fixture[i][7:0];d.pixels_g[i]=input_fixture[i][15:8];d.pixels_b[i]=input_fixture[i][23:16];end
 $readmemh("debug_golden.mem",expected_debug);
 repeat(5) @(negedge clock);reset=1;
 @(negedge clock);go=1;@(negedge clock);go=0;
 wait(d.stage==1);@(negedge clock);
 $readmemh("stage0_golden.mem",expected,0,262143);
 for(i=0;i<262144;i=i+1) if(bank_value(0,i)!==expected[i]) begin
  if(errors<5) $display("STAGE0 mismatch index=%0d got=%h expected=%h",i,bank_value(0,i),expected[i]);errors=errors+1;
 end
 $display("STAGE0 checked 262144 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 0 failed");
 wait(d.stage==2);@(negedge clock);
 $readmemh("stage1_golden.mem",expected,0,131071);
 for(i=0;i<131072;i=i+1) if(bank_value(1,i)!==expected[i]) begin
  if(errors<5) $display("STAGE1 mismatch index=%0d got=%h expected=%h",i,bank_value(1,i),expected[i]);errors=errors+1;
 end
 $display("STAGE1 checked 131072 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 1 failed");
 wait(d.stage==3);@(negedge clock);
 $readmemh("stage2_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(0,i)!==expected[i]) begin
  if(errors<5) $display("STAGE2 mismatch index=%0d got=%h expected=%h",i,bank_value(0,i),expected[i]);errors=errors+1;
 end
 $display("STAGE2 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 2 failed");
 wait(d.stage==4);@(negedge clock);
 $readmemh("stage3_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(2,i)!==expected[i]) begin
  if(errors<5) $display("STAGE3 mismatch index=%0d got=%h expected=%h",i,bank_value(2,i),expected[i]);errors=errors+1;
 end
 $display("STAGE3 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 3 failed");
 wait(d.stage==5);@(negedge clock);
 $readmemh("stage4_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(3,i)!==expected[i]) begin
  if(errors<5) $display("STAGE4 mismatch index=%0d got=%h expected=%h",i,bank_value(3,i),expected[i]);errors=errors+1;
 end
 $display("STAGE4 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 4 failed");
 wait(d.stage==6);@(negedge clock);
 $readmemh("stage5_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(2,i)!==expected[i]) begin
  if(errors<5) $display("STAGE5 mismatch index=%0d got=%h expected=%h",i,bank_value(2,i),expected[i]);errors=errors+1;
 end
 $display("STAGE5 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 5 failed");
 wait(d.stage==7);@(negedge clock);
 $readmemh("stage6_golden.mem",expected,0,131071);
 for(i=0;i<131072;i=i+1) if(bank_value(1,i)!==expected[i]) begin
  if(errors<5) $display("STAGE6 mismatch index=%0d got=%h expected=%h",i,bank_value(1,i),expected[i]);errors=errors+1;
 end
 $display("STAGE6 checked 131072 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 6 failed");
 wait(d.stage==8);@(negedge clock);
 $readmemh("stage7_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(0,i)!==expected[i]) begin
  if(errors<5) $display("STAGE7 mismatch index=%0d got=%h expected=%h",i,bank_value(0,i),expected[i]);errors=errors+1;
 end
 $display("STAGE7 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 7 failed");
 wait(d.stage==9);@(negedge clock);
 $readmemh("stage8_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(1,i)!==expected[i]) begin
  if(errors<5) $display("STAGE8 mismatch index=%0d got=%h expected=%h",i,bank_value(1,i),expected[i]);errors=errors+1;
 end
 $display("STAGE8 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 8 failed");
 wait(d.stage==10);@(negedge clock);
 $readmemh("stage9_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(2,i)!==expected[i]) begin
  if(errors<5) $display("STAGE9 mismatch index=%0d got=%h expected=%h",i,bank_value(2,i),expected[i]);errors=errors+1;
 end
 $display("STAGE9 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 9 failed");
 wait(d.stage==11);@(negedge clock);
 $readmemh("stage10_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(3,i)!==expected[i]) begin
  if(errors<5) $display("STAGE10 mismatch index=%0d got=%h expected=%h",i,bank_value(3,i),expected[i]);errors=errors+1;
 end
 $display("STAGE10 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 10 failed");
 wait(d.stage==12);@(negedge clock);
 $readmemh("stage11_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(2,i)!==expected[i]) begin
  if(errors<5) $display("STAGE11 mismatch index=%0d got=%h expected=%h",i,bank_value(2,i),expected[i]);errors=errors+1;
 end
 $display("STAGE11 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 11 failed");
 wait(d.stage==13);@(negedge clock);
 $readmemh("stage12_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(1,i)!==expected[i]) begin
  if(errors<5) $display("STAGE12 mismatch index=%0d got=%h expected=%h",i,bank_value(1,i),expected[i]);errors=errors+1;
 end
 $display("STAGE12 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 12 failed");
 wait(d.stage==14);@(negedge clock);
 $readmemh("stage13_golden.mem",expected,0,32767);
 for(i=0;i<32768;i=i+1) if(bank_value(2,i)!==expected[i]) begin
  if(errors<5) $display("STAGE13 mismatch index=%0d got=%h expected=%h",i,bank_value(2,i),expected[i]);errors=errors+1;
 end
 $display("STAGE13 checked 32768 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 13 failed");
 wait(d.done);@(negedge clock);
 $readmemh("stage14_golden.mem",expected,0,65535);
 for(i=0;i<65536;i=i+1) if(bank_value(0,i)!==expected[i]) begin
  if(errors<5) $display("STAGE14 mismatch index=%0d got=%h expected=%h",i,bank_value(0,i),expected[i]);errors=errors+1;
 end
 $display("STAGE14 checked 65536 values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage 14 failed");
 for(i=0;i<60;i=i+1) if(d.debug_acc[i]!==expected_debug[i]) errors=errors+1;
 addr=32'h400000;length=3;arv=1;
 @(negedge clock);arv=0;rr=1;i=0;
 while(i<4) begin
  @(posedge clock);
  if(d.rvalid) begin
   if(d.rdata!=={expected[2*i+1],expected[2*i]}) errors=errors+1;
   if(d.rlast!==(i==3)) errors=errors+1;
   i=i+1;
  end
 end
 if(errors) $fatal(1,"Final accumulator/AXI errors=%0d",errors);
 $display("PASS all 15 convolutions, activations, three residuals, two concats, output groups, reused banks and host reads; cycles=%0d",d.cycles);
 $finish;
end
initial begin #250000000;$fatal(1,"Timeout stage=%0d state=%0d",d.stage,d.state);end
endmodule
