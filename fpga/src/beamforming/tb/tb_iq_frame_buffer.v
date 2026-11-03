`timescale 1ns/1ps
module tb_iq_frame_buffer;
    reg clk=0,rst=1,cv=0,cs=0,ce=0,replay_start=0;
    reg signed [7:0] ci=0,cq=0;
    wire ready,frame_ready,rv,rs,re;
    wire signed [7:0] oi,oq;
    integer n,f;
    always #5 clk=~clk;
    iq_frame_buffer #(.N_CH(1),.IQ_W(8),.FRAME_SAMPLES(3)) dut(
        .clk(clk),.rst(rst),.capture_valid(cv),.capture_start(cs),.capture_end(ce),
        .capture_i_bus(ci),.capture_q_bus(cq),.capture_ready(ready),
        .frame_ready(frame_ready),.replay_start(replay_start),.replay_valid(rv),
        .replay_start_out(rs),.replay_end(re),.replay_i_bus(oi),.replay_q_bus(oq));
    initial begin
        #10000; $fatal(1,"frame buffer timeout");
    end
    initial begin
        repeat(2) @(negedge clk); rst=0;
        // Reset during a partial capture, then overwrite and replay two frames.
        @(negedge clk); cv=1; cs=1; ci=99; cq=-99;
        @(negedge clk); cv=0; cs=0; rst=1;
        @(negedge clk); rst=0;
        for(f=0;f<2;f=f+1) begin
            @(negedge clk); cv=1; cs=1; ci=11+f; cq=-11-f;
            @(negedge clk); cv=0; cs=0; // capture gap
            @(negedge clk); cv=1; ci=22+f; cq=-22-f;
            @(negedge clk); ci=33+f; cq=-33-f; ce=1;
            @(negedge clk); cv=0; ce=0;
            if(!frame_ready || ready) $fatal(1,"frame did not seal/hold");
            replay_start=1; @(negedge clk); replay_start=0;
            n=0;
            while(n<3) begin
                @(negedge clk);
                if(rv) begin
                    if(oi !== (n+1)*11+f || oq !== -(n+1)*11-f) $fatal(1,"replay data mismatch at %0d",n);
                    if(rs !== (n==0) || re !== (n==2)) $fatal(1,"replay markers mismatch at %0d",n);
                    n=n+1;
                end
            end
            @(negedge clk);
            if(frame_ready || !ready || rv) $fatal(1,"frame buffer did not release");
        end
        $display("PASS iq_frame_buffer: reset, capture gaps, two frames, ordered replay, release"); $finish;
    end
endmodule
