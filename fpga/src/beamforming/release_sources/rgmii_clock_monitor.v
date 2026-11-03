`timescale 1ns/1ps
// Count core cycles between synchronized events occurring every 256 RX edges.
// Default 200/125 MHz => 409.6 cycles. No data-path reset feedback to this monitor.
module rgmii_clock_monitor #(
    parameter integer MIN_INTERVAL=350,MAX_INTERVAL=470,TIMEOUT_CYCLES=1000
) (
    input wire rx_clk,core_clk,async_reset,
    output reg gigabit_clock_ok
);
    reg [7:0]rx_count;
    reg rx_toggle;
    wire rr,cr;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *)reg [1:0]frequency_sync;
    reg previous,seen;
    reg [1:0]good_intervals;
    reg [10:0]interval;
    network_cdc_reset reset_r(.clk(rx_clk),.async_reset(async_reset),.rst(rr));
    network_cdc_reset reset_c(.clk(core_clk),.async_reset(async_reset),.rst(cr));
    always @(posedge rx_clk or posedge rr)
        if(rr)begin rx_count<=0;rx_toggle<=0;end
        else begin rx_count<=rx_count+1'b1;if(rx_count==255)rx_toggle<=~rx_toggle;end
    always @(posedge core_clk or posedge cr)
        if(cr)begin frequency_sync<=0;previous<=0;seen<=0;good_intervals<=0;interval<=0;gigabit_clock_ok<=0;end
        else begin
            frequency_sync<={frequency_sync[0],rx_toggle};previous<=frequency_sync[1];
            if(frequency_sync[1]!=previous)begin
                interval<=0;seen<=1;
                if(seen && interval>=MIN_INTERVAL && interval<=MAX_INTERVAL)begin
                    if(good_intervals!=3)good_intervals<=good_intervals+1'b1;
                    if(good_intervals>=1)gigabit_clock_ok<=1;
                end else begin good_intervals<=0;gigabit_clock_ok<=0;end
            end else if(interval>=TIMEOUT_CYCLES)begin
                interval<=0;seen<=0;good_intervals<=0;gigabit_clock_ok<=0;
            end else interval<=interval+1'b1;
        end
endmodule
