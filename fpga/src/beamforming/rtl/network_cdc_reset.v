`timescale 1ns/1ps
// Common asynchronous assertion, local synchronous release. Do not reset one
// mailbox side independently: any domain reset request must join async_reset.
module network_cdc_reset(input wire clk, async_reset, output wire rst);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] release_sync;
    always @(posedge clk or posedge async_reset)
        if(async_reset) release_sync<=2'b11;
        else release_sync<={release_sync[0],1'b0};
    assign rst=release_sync[1];
endmodule
