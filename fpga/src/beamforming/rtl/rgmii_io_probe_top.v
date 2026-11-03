`timescale 1ns/1ps
// Physical clock/DDR fixture, no algorithm or packet-level validation claim.
module rgmii_io_probe_top(
    input wire sys_clk_p,sys_clk_n,sys_rstn,rgmii_rxc,rgmii_rx_ctl,
    input wire[3:0]rgmii_rxd,
    output wire rgmii_txc,rgmii_tx_ctl,
    output wire[3:0]rgmii_txd,
    output wire led
);
    wire clk,ref_in,ref_clk,ref_rst,ready,dv,er;wire[7:0]data;
    reg[4:0]reset_count;
    IBUFDS #(.DIFF_TERM("TRUE"),.IBUF_LOW_PWR("FALSE"),.IOSTANDARD("LVDS")) u_ref_ibuf(
        .I(sys_clk_p),.IB(sys_clk_n),.O(ref_in));
    BUFG u_ref_bufg(.I(ref_in),.O(ref_clk));
    network_cdc_reset reset_ref(.clk(ref_clk),.async_reset(!sys_rstn),.rst(ref_rst));
    always @(posedge ref_clk or posedge ref_rst)
        if(ref_rst)reset_count<=0;else if(!reset_count[4])reset_count<=reset_count+1'b1;
    (* IODELAY_GROUP="rgmii_delay" *) IDELAYCTRL u_idelayctrl(
        .REFCLK(ref_clk),.RST(ref_rst || !reset_count[4]),.RDY(ready));
    bfm_board_rgmii_rx u_rx(.rgmii_rxc(rgmii_rxc),
        .rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
        .rx_clk(clk),.rx_dv(dv),.rx_er(er),.rxd(data));
    bfm_board_rgmii_tx u_tx(.tx_clk(clk),.tx_en(dv && !er),.txd(data),
        .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
    assign led=ready;
endmodule
