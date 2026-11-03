`timescale 1ns/1ps
module tb_full;
reg sys=0;always #2.5 sys=~sys;
reg core=0;always #6.25 core=~core;
reg source_clock=0;always #4 source_clock=~source_clock;
wire rxc;assign #2 rxc=source_clock;
reg reset=0,rxctl=0;reg [3:0] rxd=0;
wire txc,txctl;wire [3:0] txd;wire [4:0] led;wire mdio,mdc,prst;
udp_mdio_bridge d(.sys_clk_p(sys),.sys_clk_n(~sys),.sys_rstn(reset),.led(led),
 .eth_rst_n(prst),.eth_mdc(mdc),.eth_mdio(mdio),
 .net_rxc(rxc),.net_rx_ctl(rxctl),.net_rxd(rxd),.net_txc(txc),.net_tx_ctl(txctl),.net_txd(txd));
initial begin
 force d.clk=core;force d.resetn=reset;force d.boot=24'hffffff;force d.idelay_ready=1;
 force d.net.u_gmii_to_rgmii.receiver.rgmii_rxd_delay=rxd;
 force d.net.u_gmii_to_rgmii.receiver.rgmii_rx_ctl_delay=rxctl;
end
reg [7:0] request[0:1599],reply[0:1599];
wire tx_sample;assign #1 tx_sample=txc;
reg half=0,was_tx=0;reg [3:0] lower=0;
integer txbytes=0,replies=0,i;integer request_length=64,reply_length=72;
always @(posedge tx_sample or negedge tx_sample) begin
 if(txctl) begin
  was_tx=1;
  if(!half) begin lower=txd;half=1;end
  else begin
   if(txbytes>=reply_length || {txd,lower}!==reply[txbytes]) $fatal(1,"ARP TX byte %0d got=%h expected=%h",txbytes,{txd,lower},reply[txbytes]);
   txbytes=txbytes+1;half=0;
  end
 end else if(was_tx) begin
  if(txbytes!=reply_length || half) $fatal(1,"ARP TX length %0d",txbytes);
  replies=replies+1;was_tx=0;txbytes=0;
 end
end
task send_byte;
 input [7:0] v;
 begin
  @(posedge source_clock);rxctl<=1;rxd<=v[3:0];
  @(negedge source_clock);rxctl<=1;rxd<=v[7:4];
 end
endtask
task send_arp;
 input integer preamble;
 integer k;
 begin
  for(k=0;k<preamble;k=k+1) send_byte(8'h55);
  send_byte(8'hd5);
  for(k=0;k<request_length;k=k+1) send_byte(request[k]);
  @(posedge source_clock);rxctl<=0;rxd<=0;
 end
endtask
initial begin
 for(i=0;i<360;i=i+1) begin
 d.net.cnn.bank0even[1023+i]=(32'haabbcc00+i)&65535;
 d.net.cnn.bank0odd[1023+i]=(32'haabbcc00+i)>>16;
 end
 $readmemh("arp_request.mem",request);$readmemh("arp_reply.mem",reply);
 #2000;reset=1;
 #2000;force d.cap_arm=1;
 #2000;
 send_arp(7);
 wait(replies==1);
 repeat(31) @(posedge source_clock);
 send_arp(5);
 wait(replies==2);
 repeat(31) @(posedge source_clock);
 request_length=66;reply_length=74;
 $readmemh("cmd1.mem",request,0,65);$readmemh("res1.mem",reply,0,73);
 send_arp(5);wait(replies==3);
 repeat(31) @(posedge source_clock);
 request_length=1506;reply_length=72;
 $readmemh("cmd2.mem",request,0,1505);$readmemh("res2.mem",reply,0,71);
 send_arp(5);wait(replies==4);
 repeat(31) @(posedge source_clock);
 request_length=66;reply_length=1510;
 $readmemh("cmd3.mem",request,0,65);$readmemh("res3.mem",reply,0,1509);
 send_arp(5);wait(replies==5);
 for(i=0;i<360;i=i+1) begin
 if(d.net.cnn.pixels_r[1023+i]!==((32'h7f123400+i)&255)) $fatal(1,"R input mismatch %0d",i);
 if(d.net.cnn.pixels_g[1023+i]!==(((32'h7f123400+i)>>8)&255)) $fatal(1,"G input mismatch %0d",i);
 if(d.net.cnn.pixels_b[1023+i]!==(((32'h7f123400+i)>>16)&255)) $fatal(1,"B input mismatch %0d",i);
 end
 $display("PASS full RGMII UDP: maximum frames, CRC, 360 input pixels and 360 output words across 4KB");
 $finish;
end
initial begin #1000000;$fatal(1,"ARP timeout replies=%0d flags=%b",replies,d.net_debug);end
endmodule
