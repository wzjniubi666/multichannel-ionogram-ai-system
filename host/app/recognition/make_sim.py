from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[3]
d=np.load(root/'fpga/build/recognition/board_case/case.npz')
sizes=[d[f'stage{i}'].size for i in range(15)]
banks=[0,1,0,2,3,2,1,0,1,2,3,2,1,2,0]
s='''`timescale 1ns/1ps
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
'''
for i,(size,bank) in enumerate(zip(sizes,banks)):
    s+=f''' wait({'d.stage=='+str(i+1) if i<14 else 'd.done'});@(negedge clock);
 $readmemh("stage{i}_golden.mem",expected,0,{size-1});
 for(i=0;i<{size};i=i+1) if(bank_value({bank},i)!==expected[i]) begin
  if(errors<5) $display("STAGE{i} mismatch index=%0d got=%h expected=%h",i,bank_value({bank},i),expected[i]);errors=errors+1;
 end
 $display("STAGE{i} checked {size} values, cumulative errors=%0d cycles=%0d",errors,d.cycles);
 if(errors) $fatal(1,"Stage {i} failed");
'''
s+=''' for(i=0;i<60;i=i+1) if(d.debug_acc[i]!==expected_debug[i]) errors=errors+1;
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
'''
(root/'fpga/src/recognition/sim/tb_c3x2.v').write_text(s,encoding='ascii')
