`timescale 1ns/1ps
// Fixed-address RTL8211F(I)/FD(I) manager. Source contract and evidence in docs.
// Parameters count 1 MHz management falling edges, never raw 200 MHz cycles.
module rtl8211_phy_manager #(
    parameter integer RESET_CYCLES=10000,SETTLE_CYCLES=30000,POLL_CYCLES=1000,RETRY_CYCLES=10000,
    parameter [4:0] PHY_ADDRESS=1,
    parameter TX_DELAY_ENABLE=1'b1,RX_DELAY_ENABLE=1'b1
) (
    input wire mdc_clk,rst,mdio_in,
    output wire mdio_out,mdio_oe,
    output reg phy_reset_n,configured,link_ready,
    output reg [3:0]fault,
    output reg [15:0]phy_id1,phy_id2,phy_status,tx_delay_readback,rx_delay_readback
);
    localparam RESET=0,SETTLE=1,ISSUE=2,RESPONSE=3,POLL=4,RETRY=5;
    reg [2:0]state;
    reg [4:0]step;
    reg [31:0]timer;
    reg [15:0]saved_page,old_tx,old_rx,old_bmcr;
    reg autoneg_done;
    reg command_valid,command_read;
    reg [4:0]register_address;
    reg [15:0]write_data;
    wire command_ready,response_valid,ack_error;
    wire [15:0]read_data;
    mdio_clause22_master u_mdio(.mdc_clk(mdc_clk),.rst(rst),.command_valid(command_valid),
        .command_ready(command_ready),.command_read(command_read),.phy_address(PHY_ADDRESS),
        .register_address(register_address),.write_data(write_data),.mdio_in(mdio_in),
        .mdio_out(mdio_out),.mdio_oe(mdio_oe),.response_valid(response_valid),
        .ack_error(ack_error),.read_data(read_data));
    always @* begin
        command_valid=(state==ISSUE);command_read=1;register_address=0;write_data=0;
        case(step)
            0:register_address=2;
            1:register_address=3;
            2:register_address=31;
            3:begin command_read=0;register_address=31;write_data=16'h0d08;end
            4,6:register_address=17;
            5:begin command_read=0;register_address=17;write_data=(old_tx & 16'hfeff) | (TX_DELAY_ENABLE ? 16'h0100 : 16'd0);end
            7,9:register_address=21;
            8:begin command_read=0;register_address=21;write_data=(old_rx & 16'hfff7) | (RX_DELAY_ENABLE ? 16'h0008 : 16'd0);end
            10,18:begin command_read=0;register_address=31;write_data=0;end
            11:register_address=0;
            12:begin command_read=0;register_address=0;write_data=(old_bmcr & 16'h33ff) | 16'h1200;end
            13,14:register_address=1;
            15:begin command_read=0;register_address=31;write_data=16'h0a43;end
            16:register_address=26;
            17:begin command_read=0;register_address=31;write_data=saved_page;end
        endcase
    end
    task fail;
        input [3:0]code;
        begin fault<=code;configured<=0;link_ready<=0;state<=RETRY;timer<=0;phy_reset_n<=0;end
    endtask
    always @(negedge mdc_clk or posedge rst)begin
        if(rst)begin
            state<=RESET;step<=0;timer<=0;phy_reset_n<=0;configured<=0;link_ready<=0;fault<=0;
            phy_id1<=0;phy_id2<=0;phy_status<=0;tx_delay_readback<=0;rx_delay_readback<=0;
            saved_page<=0;old_tx<=0;old_rx<=0;old_bmcr<=0;autoneg_done<=0;
        end else case(state)
            RESET:begin
                phy_reset_n<=0;configured<=0;link_ready<=0;
                if(timer==RESET_CYCLES-1)begin phy_reset_n<=1;timer<=0;state<=SETTLE;end
                else timer<=timer+1'b1;
            end
            SETTLE:if(timer==SETTLE_CYCLES-1)begin timer<=0;step<=0;state<=ISSUE;end
                else timer<=timer+1'b1;
            ISSUE:if(command_ready)state<=RESPONSE;
            RESPONSE:if(response_valid)begin
                state<=ISSUE;step<=step+1'b1;
                if(ack_error)fail(4'd1);
                else case(step)
                    0:begin phy_id1<=read_data;if(read_data!=16'h001c)fail(4'd2);end
                    1:begin phy_id2<=read_data;if((read_data & 16'hfff0)!=16'hc910)fail(4'd2);end
                    2:saved_page<=read_data;
                    4:old_tx<=read_data;
                    6:begin tx_delay_readback<=read_data;if(read_data[8]!=TX_DELAY_ENABLE)fail(4'd3);end
                    7:old_rx<=read_data;
                    9:begin rx_delay_readback<=read_data;if(read_data[3]!=RX_DELAY_ENABLE)fail(4'd3);end
                    11:old_bmcr<=read_data;
                    14:autoneg_done<=read_data[5];
                    16:phy_status<=read_data;
                    17:begin
                        configured<=1;fault<=0;
                        link_ready<=autoneg_done && phy_status[2] && phy_status[3] && phy_status[5:4]==2'b10;
                        state<=POLL;timer<=0;
                    end
                    18:step<=13;
                endcase
            end
            POLL:if(timer==POLL_CYCLES-1)begin timer<=0;step<=18;state<=ISSUE;end
                else timer<=timer+1'b1;
            RETRY:if(timer==RETRY_CYCLES-1)begin timer<=0;state<=RESET;end
                else timer<=timer+1'b1;
            default:begin state<=RESET;timer<=0;configured<=0;link_ready<=0;phy_reset_n<=0;end
        endcase
    end
endmodule
