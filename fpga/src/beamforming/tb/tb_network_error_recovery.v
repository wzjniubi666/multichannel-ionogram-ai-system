`timescale 1ns/1ps
module tb_network_error_recovery;
    reg clk=0,rst=1,rx_valid=0,rx_last=0;
    reg [31:0]rx_data=0;
    wire rx_ready,tx_valid,tx_last,busy;
    wire [31:0]tx_data;
    reg [31:0]cfg[0:31],p0[0:263],p1[0:263],response[0:103];
    integer j,idx=0,packets=0,cancels=0;
    always #5 clk=~clk;
    network_beamforming_top dut(.clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),
        .rx_data(rx_data),.rx_last(rx_last),.rx_bad(1'b0),.tx_valid(tx_valid),.tx_ready(1'b1),
        .tx_data(tx_data),.tx_last(tx_last),.busy(busy));
    always @(posedge clk)if(!rst)begin
        if(dut.cancel)cancels=cancels+1;
        if(tx_valid)begin
            response[idx]=tx_data;
            if(tx_last)begin
                if(packets==0)begin
                    if(idx!=7 || response[1]!==32'h01810000)$fatal(1,"config ACK");
                end else if(packets==1)begin
                    if(idx!=7 || response[1]!==32'h01ff0007 || response[2]!==32'h12345678)
                        $fatal(1,"real solver failure did not return frame error");
                end else if(idx!=103 || response[1]!==32'h01820000 || response[2]!==32'h12345679)
                    $fatal(1,"failed to recover into successful next frame");
                if(response[3]!==32'h10203040 || response[4]!==32'h00a00050)$fatal(1,"metadata lost");
                packets=packets+1;idx=0;
            end else idx=idx+1;
        end
    end
    task send_packet;
        input integer source,count;
        input zero_iq;
        begin
            for(j=0;j<count;j=j+1)begin
                @(negedge clk);rx_valid=1;rx_last=(j==count-1);
                case(source)0:rx_data=cfg[j];1:rx_data=p0[j];2:rx_data=p1[j];endcase
                if(source!=0 && j>=8 && zero_iq)rx_data=0;
                @(posedge clk);while(!rx_ready)@(posedge clk);
                @(negedge clk);rx_valid=0;rx_last=0;
            end
        end
    endtask
    initial begin #4000000;$fatal(1,"network solver recovery timeout");end
    initial begin
        $readmemh("packets/config.hex",cfg);$readmemh("packets/iq0.hex",p0);$readmemh("packets/iq1.hex",p1);
        repeat(4)@(negedge clk);rst=0;
        send_packet(0,32,0);wait(packets==1);
        // A zero covariance has a real zero pivot, including zero diagonal loading.
        send_packet(1,264,1);send_packet(2,264,1);wait(packets==2);@(negedge clk);
        if(busy || cancels!=1)$fatal(1,"failed core was not cancelled/released");
        p0[2]=32'h12345679;p1[2]=32'h12345679;
        send_packet(1,264,0);send_packet(2,264,0);wait(packets==3);@(negedge clk);
        if(busy || cancels!=1)$fatal(1,"recovery ownership");
        $display("PASS network_error_recovery: real zero-pivot SOLVER response -> next COS frame succeeds");$finish;
    end
endmodule
