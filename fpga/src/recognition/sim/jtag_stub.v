module jtag_axi_0(input aclk,aresetn,
output [31:0] m_axi_awaddr, output [7:0] m_axi_awlen,output m_axi_awid,m_axi_awvalid,input m_axi_awready,
output [31:0] m_axi_wdata,output [3:0] m_axi_wstrb,output m_axi_wlast,m_axi_wvalid,input m_axi_wready,
input m_axi_bid,input [1:0] m_axi_bresp,input m_axi_bvalid,output m_axi_bready,
output [31:0] m_axi_araddr,output [7:0] m_axi_arlen,output m_axi_arid,m_axi_arvalid,input m_axi_arready,
input m_axi_rid,input [31:0] m_axi_rdata,input [1:0] m_axi_rresp,input m_axi_rlast,m_axi_rvalid,output m_axi_rready);
endmodule
