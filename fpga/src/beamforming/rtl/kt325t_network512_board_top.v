`timescale 1ns/1ps
// Offline board candidate. No hardware release without checking assembly R152,
// actual PHY ID/delays, PCB skew and real PC endpoint. See board_network_contract.
module kt325t_network512_board_top #(
    parameter [47:0]BOARD_MAC=48'h020000000001,PEER_MAC=48'h020000000002,
    parameter [31:0]BOARD_IP=32'hc0000201,PEER_IP=32'hc0000202,
    parameter [15:0]BOARD_PORT=5000,PEER_PORT=5000,
    parameter integer PHY_RESET_CYCLES=10000,PHY_SETTLE_CYCLES=30000,
    parameter [15:0] ACTIVE_MASK=16'h7f7f
) (
    input wire sys_clk_p,sys_clk_n,sys_rstn,
    input wire rgmii_rxc,rgmii_rx_ctl,
    input wire [3:0]rgmii_rxd,
    output wire rgmii_txc,rgmii_tx_ctl,
    output wire [3:0]rgmii_txd,
    output wire phy_mdc,phy_reset_n,
    inout wire phy_mdio,
    output wire [4:0]led
);
    wire clock_in,core_clk,core_reset,mdc_clk,management_reset;
    reg [6:0]mdc_count;
    reg mdc_divide;
    wire external_reset=!sys_rstn;
    IBUFDS #(.DIFF_TERM("TRUE"),.IBUF_LOW_PWR("FALSE"),.IOSTANDARD("LVDS"))
        u_sys_ibuf(.I(sys_clk_p),.IB(sys_clk_n),.O(clock_in));
    BUFG u_core_bufg(.I(clock_in),.O(core_clk));
    network_cdc_reset reset_core(.clk(core_clk),.async_reset(external_reset),.rst(core_reset));
    always @(posedge core_clk or posedge core_reset)
        if(core_reset)begin mdc_count<=0;mdc_divide<=0;end
        else if(mdc_count==99)begin mdc_count<=0;mdc_divide<=~mdc_divide;end
        else mdc_count<=mdc_count+1'b1;
    BUFG u_mdc_bufg(.I(mdc_divide),.O(mdc_clk));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_mdc_forward(
        .C(mdc_clk),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0),.Q(phy_mdc));
    network_cdc_reset reset_management(.clk(mdc_clk),.async_reset(external_reset),.rst(management_reset));
    wire mdio_in,mdio_out,mdio_oe,configured,link_ready;
    wire [3:0]fault;
    (* MARK_DEBUG="TRUE" *) wire [15:0]phy_id1,phy_id2,phy_status,tx_delay_readback,rx_delay_readback;
    IOBUF u_mdio(.I(mdio_out),.T(!mdio_oe),.O(mdio_in),.IO(phy_mdio));
    rtl8211_phy_manager #(.RESET_CYCLES(PHY_RESET_CYCLES),.SETTLE_CYCLES(PHY_SETTLE_CYCLES))
        u_phy(.mdc_clk(mdc_clk),.rst(management_reset),.mdio_in(mdio_in),.mdio_out(mdio_out),
        .mdio_oe(mdio_oe),.phy_reset_n(phy_reset_n),.configured(configured),.link_ready(link_ready),
        .fault(fault),.phy_id1(phy_id1),.phy_id2(phy_id2),.phy_status(phy_status),
        .tx_delay_readback(tx_delay_readback),.rx_delay_readback(rx_delay_readback));
    wire rx_clk,rx_dv,rx_er,tx_en,idelay_ready,rx_clock_ok,busy;
    wire [7:0]rxd,txd;
    reg [4:0]idelay_reset_count;
    always @(posedge core_clk or posedge core_reset)
        if(core_reset)idelay_reset_count<=0;
        else if(!idelay_reset_count[4])idelay_reset_count<=idelay_reset_count+1'b1;
    (* IODELAY_GROUP="rgmii_delay" *) IDELAYCTRL u_idelayctrl(
        .REFCLK(core_clk),.RST(core_reset || !idelay_reset_count[4]),.RDY(idelay_ready));
    bfm_board_rgmii_rx u_rx(.rgmii_rxc(rgmii_rxc),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
        .rx_clk(rx_clk),.rx_dv(rx_dv),.rx_er(rx_er),.rxd(rxd));
    rgmii_clock_monitor u_clock_monitor(.rx_clk(rx_clk),.core_clk(core_clk),.async_reset(external_reset),
        .gigabit_clock_ok(rx_clock_ok));
    bfm_board_rgmii_tx u_tx(.tx_clk(rx_clk),.tx_en(tx_en),.txd(txd),.rgmii_txc(rgmii_txc),
        .rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
    // First collect status in one clock domain, then register the common reset
    // request. Combining independent-domain status directly at async PRE pins
    // produces multi-clock fan-in and potentially narrow reset pulses (CDC-12).
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [1:0]link_ready_sync,idelay_ready_sync;
    reg data_reset;
    always @(posedge core_clk or posedge core_reset)
        if(core_reset)begin link_ready_sync<=0;idelay_ready_sync<=0;end
        else begin
            link_ready_sync<={link_ready_sync[0],link_ready};
            idelay_ready_sync<={idelay_ready_sync[0],idelay_ready};
        end
    always @(posedge core_clk or posedge core_reset)
        if(core_reset)data_reset<=1;
        else data_reset<=!(link_ready_sync[1] && idelay_ready_sync[1] && rx_clock_ok);
    wire core_data_reset,rx_data_reset;
    network_cdc_reset reset_data_core(.clk(core_clk),.async_reset(data_reset),.rst(core_data_reset));
    network_cdc_reset reset_data_rx(.clk(rx_clk),.async_reset(data_reset),.rst(rx_data_reset));
    board_gmii512_beamforming_top #(.BOARD_MAC(BOARD_MAC),.PEER_MAC(PEER_MAC),.BOARD_IP(BOARD_IP),.PEER_IP(PEER_IP),
        .BOARD_PORT(BOARD_PORT),.PEER_PORT(PEER_PORT),.ACTIVE_MASK(ACTIVE_MASK)) u_network(
        .rx_rst(rx_data_reset),.core_rst(core_data_reset),.tx_rst(rx_data_reset),
        .rx_clk(rx_clk),.core_clk(core_clk),.tx_clk(rx_clk),
        .gmii_rx_dv(rx_dv),.gmii_rx_er(rx_er),.gmii_rxd(rxd),.tx_allow(1'b1),
        .gmii_tx_en(tx_en),.gmii_txd(txd),.busy(busy),.rx_accepted(),.rx_rejected(),.rx_overflow());
    // Core-board LED cathodes go through resistors to GND (sheet13): active high.
    assign led={(|fault),busy,link_ready,configured,phy_reset_n};
endmodule
