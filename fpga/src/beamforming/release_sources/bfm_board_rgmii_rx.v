`timescale 1ns/1ps
// PHY internal RX delay provides the sampling phase. BUFIO captures at the IOB;
// BUFG carries the same root clock to packet logic. STA checks this transfer.
module bfm_board_rgmii_rx(
    input wire rgmii_rxc,rgmii_rx_ctl,
    input wire [3:0]rgmii_rxd,
    output wire rx_clk,rx_dv,rx_er,
    output wire [7:0]rxd
);
    wire clock_in,io_clk;
    wire [4:0]delayed,rise_data,fall_data;
    wire [4:0]pins={rgmii_rx_ctl,rgmii_rxd};
    IBUF u_rxc_ibuf(.I(rgmii_rxc),.O(clock_in));
    BUFIO u_rxc_bufio(.I(clock_in),.O(io_clk));
    BUFG u_rxc_bufg(.I(clock_in),.O(rx_clk));
    genvar i;
    generate for(i=0;i<5;i=i+1)begin:lanes
        (* IODELAY_GROUP="rgmii_delay" *)
        IDELAYE2 #(.DELAY_SRC("IDATAIN"),.IDELAY_TYPE("FIXED"),.IDELAY_VALUE(11),
            .REFCLK_FREQUENCY(200.0)) u_delay(
            .IDATAIN(pins[i]),.DATAIN(1'b0),.DATAOUT(delayed[i]),.C(1'b0),.CE(1'b0),
            .INC(1'b0),.LD(1'b0),.LDPIPEEN(1'b0),.REGRST(1'b0),.CINVCTRL(1'b0),
            .CNTVALUEIN(5'd0),.CNTVALUEOUT());
        IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),.SRTYPE("SYNC")) u_iddr(
            .C(io_clk),.CE(1'b1),.D(delayed[i]),.R(1'b0),.S(1'b0),
            .Q1(rise_data[i]),.Q2(fall_data[i]));
    end endgenerate
    assign rxd={fall_data[3:0],rise_data[3:0]};
    assign rx_dv=rise_data[4];
    assign rx_er=rise_data[4]^fall_data[4];
endmodule
