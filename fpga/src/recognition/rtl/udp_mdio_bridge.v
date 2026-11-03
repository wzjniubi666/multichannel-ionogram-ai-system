`timescale 1ns/1ps
// Runtime input over JTAG AXI. 16 INT8 MAC lanes, fixed YOLOv5nu first Conv.
module udp_mdio_bridge(input sys_clk_p, input sys_clk_n, input sys_rstn, output [4:0] led, output eth_rst_n, output eth_mdc, inout eth_mdio,
 input net_rxc,input net_rx_ctl,input [3:0] net_rxd,
 output net_txc,output net_tx_ctl,output [3:0] net_txd);
wire clk_in,clk,fb,fbraw,raw,locked;
IBUFDS ci(.I(sys_clk_p),.IB(sys_clk_n),.O(clk_in));
MMCME2_BASE #(.CLKIN1_PERIOD(5.0),.CLKFBOUT_MULT_F(5.0),.CLKOUT0_DIVIDE_F(12.5)) mm
(.CLKIN1(clk_in),.CLKFBIN(fb),.CLKFBOUT(fbraw),.CLKOUT0(raw),.LOCKED(locked),.RST(~sys_rstn),.PWRDWN(1'b0));
BUFG bf(.I(fbraw),.O(fb)); BUFG bc(.I(raw),.O(clk));
reg [7:0] reset_pipe=0;
always @(posedge clk) reset_pipe <= {reset_pipe[6:0],locked & sys_rstn};
wire resetn=&reset_pipe;
wire [31:0] awaddr,wdata,araddr; wire [7:0] awlen,arlen;
wire awvalid,wvalid,wlast,bready,arvalid,rready;
wire awid,arid; wire [3:0] wstrb;
wire awready,wready,arready;
reg bvalid=0,rvalid=0,rlast=0; reg bid=0,rid=0; reg [31:0] rdata=0;
jtag_axi_0 ja(.aclk(clk),.aresetn(resetn),
.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awid(awid),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
.m_axi_bid(bid),.m_axi_bresp(2'b00),.m_axi_bvalid(bvalid),.m_axi_bready(bready),
.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arid(arid),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(2'b00),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));

// One host command remains stable across the request/response CDC handshake.
reg [23:0] boot=0;
always @(posedge clk) if(!resetn) boot<=0; else if(!(&boot)) boot<=boot+1;
assign eth_rst_n=resetn && boot>=24'd1600000;
wire phy_ready=&boot;

wire ref200,idelay_ready;
BUFG br(.I(clk_in),.O(ref200));
(* IODELAY_GROUP="rgmii_delay" *) IDELAYCTRL delay_control(.REFCLK(ref200),.RST(~resetn),.RDY(idelay_ready));
wire [4:0] net_debug;wire monitor_clk;
wire capture_clk,capture_valid;wire [7:0] capture_byte;
reg cap_arm=0;
(* ASYNC_REG="TRUE" *) reg cap_req_meta=0,cap_req_sync=0;
reg cap_served=0,cap_wait=0,cap_active=0,cap_done=0;
reg [15:0] cap_length=0;
// Optional packet trace RAM removed; inference and MDIO do not use it.
always @(posedge capture_clk or negedge resetn) begin
 if(!resetn) begin cap_req_meta<=0;cap_req_sync<=0;cap_served<=0;cap_wait<=0;cap_active<=0;cap_done<=0;cap_length<=0;end
 else begin
  cap_req_meta<=cap_arm;cap_req_sync<=cap_req_meta;
  if(cap_req_sync!=cap_served) begin cap_served<=cap_req_sync;cap_wait<=1;cap_active<=0;cap_done<=0;cap_length<=0;end
  else if(cap_wait && capture_valid && capture_byte==8'hd5) begin cap_wait<=0;cap_active<=1;cap_length<=0;end
  else if(cap_active) begin
   if(capture_valid) cap_length<=cap_length+1;
   else begin cap_active<=0;cap_done<=1;end
  end
 end
end

(* ASYNC_REG="TRUE" *) reg cap_meta=0,cap_sync=0;
always @(posedge clk) begin cap_meta<=cap_done;cap_sync<=cap_meta;end
reg [31:0] cap_q;


net_udp_loop net(.clk_200m(ref200),.clk_50m(clk),.sys_rst_n(resetn && phy_ready && idelay_ready),
 .external_phy_reset(eth_rst_n),.monitor_clk(monitor_clk),.capture_clk(capture_clk),.capture_valid(capture_valid),.capture_byte(capture_byte),.eth_mdc(),.eth_mdio(),.net_rst_n(),
 .net_rxc(net_rxc),.net_rx_ctl(net_rx_ctl),.net_rxd(net_rxd),
 .net_txc(net_txc),.net_tx_ctl(net_tx_ctl),.net_txd(net_txd),.debug_led(net_debug));
// RX clock rate diagnostic: Gray counter crosses into the 80 MHz host domain.
reg [23:0] rx_binary=0,rx_gray=0;
wire [23:0] rx_next=rx_binary+1;
always @(posedge monitor_clk or negedge resetn) begin
 if(!resetn) begin rx_binary<=0;rx_gray<=0;end
 else begin rx_binary<=rx_next;rx_gray<=rx_next^(rx_next>>1);end
end
(* ASYNC_REG="TRUE" *) reg [23:0] rx_meta=0,rx_sync=0;
(* ASYNC_REG="TRUE" *) reg [4:0] debug_meta=0,debug_sync=0;
reg [23:0] rx_decoded;
integer gray_i;
always @(*) begin
 rx_decoded[23]=rx_sync[23];
 for(gray_i=22;gray_i>=0;gray_i=gray_i-1) rx_decoded[gray_i]=rx_decoded[gray_i+1]^rx_sync[gray_i];
end
reg [16:0] measure_timer=0;
reg [23:0] rx_previous=0,rx_khz=0;
always @(posedge clk) begin
 rx_meta<=rx_gray;rx_sync<=rx_meta;debug_meta<=net_debug;debug_sync<=debug_meta;
 if(!resetn) begin measure_timer<=0;rx_previous<=0;rx_khz<=0;end
 else if(measure_timer==79999) begin measure_timer<=0;rx_previous<=rx_decoded;rx_khz<=rx_decoded-rx_previous;end
 else measure_timer<=measure_timer+1;
end
reg [31:0] command=0;
reg request=0,busy=0;
(* ASYNC_REG="TRUE" *) reg req_meta=0,req_sync=0;
reg served=0,md_busy=0,exec=0;
reg [31:0] md_command=0;
wire dri_clk,mdone,mack;wire [15:0] mdata;
reg response_toggle=0;
reg [16:0] md_response=0;
mdio_dri #(.CLK_DIV(6'd40)) md(.clk(clk),.rst_n(resetn),.op_exec(exec),
 .op_rh_wl(md_command[31]),.op_addr(md_command[20:16]),
 .op_wr_data(md_command[15:0]),.phy_addr(md_command[25:21]),
 .op_done(mdone),.op_rd_data(mdata),.op_rd_ack(mack),.dri_clk(dri_clk),
 .eth_mdc(eth_mdc),.eth_mdio(eth_mdio));
always @(posedge dri_clk or negedge resetn) begin
 if(!resetn) begin req_meta<=0;req_sync<=0;served<=0;md_busy<=0;exec<=0;response_toggle<=0;end
 else begin
  req_meta<=request;req_sync<=req_meta;exec<=0;
  if(!md_busy && req_sync!=served) begin
   served<=req_sync;md_command<=command;exec<=1;md_busy<=1;
  end
  if(md_busy && mdone) begin
   md_response<={md_command[31]?mack:1'b0,mdata};
   response_toggle<=~response_toggle;md_busy<=0;
  end
 end
end
(* ASYNC_REG="TRUE" *) reg resp_meta=0,resp_sync=0;
reg completed_toggle=0;
reg [16:0] response=0;
reg [31:0] completions=0;
reg writing=0,reading=0,read_delay=0;reg [31:0] wa=0,ra=0;reg [7:0] left=0;
always @(posedge clk) cap_q<=32'd0;
assign awready=resetn && !writing && !bvalid;
assign wready=writing;
assign arready=resetn && !reading && !rvalid;
always @(posedge clk) begin
 if(!resetn) begin
  writing<=0;reading<=0;bvalid<=0;rvalid<=0;request<=0;busy<=0;cap_arm<=0;read_delay<=0;
  resp_meta<=0;resp_sync<=0;completed_toggle<=0;completions<=0;
 end else begin
  resp_meta<=response_toggle;resp_sync<=resp_meta;
  if(resp_sync!=completed_toggle) begin
   completed_toggle<=resp_sync;response<=md_response;busy<=0;completions<=completions+1;
  end
  if(awvalid && awready) begin writing<=1;wa<=awaddr;bid<=awid;end
  if(wvalid && wready) begin
   if(wa==32 && wdata==1) cap_arm<=~cap_arm;
   if(wa==0 && !busy && phy_ready) begin command<=wdata;request<=~request;busy<=1;end
   wa<=wa+4;
   if(wlast) begin writing<=0;bvalid<=1;end
  end
  if(bvalid && bready) bvalid<=0;
  if(arvalid && arready) begin reading<=1;read_delay<=0;ra<=araddr;left<=arlen;rid<=arid;end
  if(reading && !rvalid && !read_delay) read_delay<=1;
  if(reading && !rvalid && read_delay) begin
   reading<=0;rvalid<=1;rlast<=(left==0);
   if(ra[23:20]==1) rdata<=cap_q;
   else case(ra[5:2])
    0:rdata<={30'd0,phy_ready,busy};
    1:rdata<={15'd0,response};
    2:rdata<=completions;
    3:rdata<=32'h5544504d;
    4:rdata<=command;
    5:rdata<={8'd0,boot};
    6:rdata<={8'd0,rx_khz};
    7:rdata<={26'd0,idelay_ready,debug_sync};
    8:rdata<={31'd0,cap_sync};
    9:rdata<={16'd0,cap_length};
    default:rdata<=0;
   endcase
  end
  if(rvalid && rready) begin rvalid<=0;if(left!=0) begin ra<=ra+4;left<=left-1;reading<=1;read_delay<=0;end end
 end
end
assign led={resetn,phy_ready,busy,eth_rst_n,1'b0};
endmodule
