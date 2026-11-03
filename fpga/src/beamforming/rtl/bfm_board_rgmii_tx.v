`timescale 1ns/1ps
module bfm_board_rgmii_tx(
    input wire tx_clk,tx_en,
    input wire [7:0]txd,
    output wire rgmii_txc,rgmii_tx_ctl,
    output wire [3:0]rgmii_txd
);
    // Use matching ODDRs for forwarded clock and data; PHY adds TX clock delay.
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_txc(
        .C(tx_clk),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0),.Q(rgmii_txc));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_ctl(
        .C(tx_clk),.CE(1'b1),.D1(tx_en),.D2(tx_en),.R(1'b0),.S(1'b0),.Q(rgmii_tx_ctl));
    genvar i;
    generate for(i=0;i<4;i=i+1)begin:lanes
        ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_data(
            .C(tx_clk),.CE(1'b1),.D1(txd[i]),.D2(txd[i+4]),.R(1'b0),.S(1'b0),.Q(rgmii_txd[i]));
    end endgenerate
endmodule
