`timescale 1ns/1ps
// Management logic runs on the FALLING edge of a free-running 1 MHz MDC.
// Read turnaround ACK is produced after rising slot 46; D15..D0 after 47..62.
// Slot 63 is idle. PHY samples writes on rising; reads sampled at end of high,
// >=500ns after rising (PHY data-valid maximum is 300ns in the supplied manual).
module mdio_clause22_master(
    input wire mdc_clk,rst,
    input wire command_valid,
    output wire command_ready,
    input wire command_read,
    input wire [4:0] phy_address,register_address,
    input wire [15:0] write_data,
    input wire mdio_in,
    output reg mdio_out,mdio_oe,
    output reg response_valid,ack_error,
    output reg [15:0] read_data
);
    reg busy,read_operation;
    reg [5:0] bit_index;
    reg [63:0] frame;
    reg [15:0] receive_shift;
    assign command_ready=!rst && !busy;
    always @(negedge mdc_clk or posedge rst)begin
        if(rst)begin
            busy<=0;read_operation<=0;bit_index<=0;frame<=0;receive_shift<=0;
            mdio_out<=1;mdio_oe<=0;response_valid<=0;ack_error<=0;read_data<=0;
        end else begin
            response_valid<=0;
            if(!busy)begin
                mdio_oe<=0;
                if(command_valid)begin
                    frame<={32'hffffffff,2'b01,command_read ? 2'b10 : 2'b01,
                        phy_address,register_address,command_read ? 2'b11 : 2'b10,write_data};
                    busy<=1;read_operation<=command_read;bit_index<=0;
                    receive_shift<=0;ack_error<=0;mdio_out<=1;mdio_oe<=1;
                end
            end else begin
                if(read_operation && bit_index==46 && mdio_in!=1'b0)ack_error<=1;
                if(read_operation && bit_index>=47 && bit_index<=62)receive_shift<={receive_shift[14:0],mdio_in};
                if(read_operation && bit_index==62)
                    read_data<={receive_shift[14:0],mdio_in};
                if(bit_index==63)begin
                    busy<=0;mdio_oe<=0;response_valid<=1;
                    if(!read_operation)read_data<=16'd0;
                end else begin
                    bit_index<=bit_index+1'b1;
                    mdio_out<=frame[62-bit_index];
                    mdio_oe<=!(read_operation && bit_index>=45);
                end
            end
        end
    end
endmodule
