`timescale 1ns/1ps
// One outstanding event; duplicates while busy are intentionally coalesced/dropped.
module network_event_cdc(
    input wire async_reset,s_clk,m_clk,s_event,
    output wire s_ready,m_valid,
    input wire m_accept
);
    wire sr,mr;
    reg request_toggle,acknowledge_toggle;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] req_sync,ack_sync;
    network_cdc_reset reset_s(.clk(s_clk),.async_reset(async_reset),.rst(sr));
    network_cdc_reset reset_m(.clk(m_clk),.async_reset(async_reset),.rst(mr));
    assign s_ready=!sr && request_toggle==ack_sync[1];
    assign m_valid=!mr && req_sync[1]!=acknowledge_toggle;
    always @(posedge s_clk or posedge sr)
        if(sr)begin request_toggle<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge_toggle};
            if(s_event && s_ready)request_toggle<=~request_toggle;
        end
    always @(posedge m_clk or posedge mr)
        if(mr)begin acknowledge_toggle<=0;req_sync<=0;end
        else begin
            req_sync<={req_sync[0],request_toggle};
            if(m_valid && m_accept)acknowledge_toggle<=req_sync[1];
        end
endmodule
