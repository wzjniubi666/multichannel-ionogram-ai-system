`timescale 1ns/1ps
module tb_beamforming_error_recovery;
    reg clk=0,rst=1,sv=0,fs=0,fe=0;
    reg signed [31:0] xi=0,xq=0;
    reg signed [47:0] sr={24'sd8388607,24'sd8388607},si=0;
    wire cv,wv,busy,err,ready,fr,rv,ov;
    wire signed [47:0] br,bi;
    integer count=0,error_count=0;
    reg check_output=0;
    always #5 clk=~clk;
    beamforming_top #(.N_CH(2),.FRAME_SAMPLES(2)) dut(
        .clk(clk),.rst(rst),.sample_valid(sv),.frame_start(fs),.frame_end(fe),
        .in_i_bus(xi),.in_q_bus(xq),.steering_re_bus(sr),.steering_im_bus(si),
        .covariance_valid(cv),.weights_valid(wv),.solver_busy(busy),.solver_error(err),
        .capture_ready(ready),.frame_ready(fr),.replay_valid(rv),.output_valid(ov),.beam_re(br),.beam_im(bi));
    always @(negedge clk) begin
        if(err) error_count=error_count+1;
        if(ov) begin
            if(!check_output) $fatal(1,"invalid/aborted frame produced beam output");
            if(br<48 || br>51 || bi!==0) $fatal(1,"recovery beam incorrect re=%0d im=%0d",br,bi);
            count=count+1;
        end
    end
    task send_frame;
        input zero_frame;
        begin
            wait(ready===1'b1);
            @(negedge clk); sv=1; fs=1; fe=0;
            xi=zero_frame ? 0 : {16'sd0,16'sd100};
            @(negedge clk); fs=0; fe=1;
            xi=zero_frame ? 0 : {16'sd100,16'sd0};
            @(negedge clk); sv=0; fe=0; xi=0;
        end
    endtask
    initial begin #1000000; $fatal(1,"error recovery timeout"); end
    initial begin
        repeat(3) @(negedge clk); rst=0;
        send_frame(1);
        wait(err===1'b1); repeat(3) @(negedge clk);
        if(!ready || busy || wv || error_count!=1) $fatal(1,"failed frame did not release exactly once");
        sr=0; // Nonzero covariance with zero steering gives a zero normalization denominator.
        send_frame(0);
        wait(err===1'b1); repeat(3) @(negedge clk);
        if(!ready || busy || wv || error_count!=2) $fatal(1,"zero denominator did not release frame");
        sr={24'sd8388607,24'sd8388607};
        send_frame(0);
        wait(busy===1'b1); repeat(100) @(negedge clk); rst=1;
        repeat(2) @(negedge clk); rst=0;
        repeat(150) @(negedge clk);
        if(!ready || busy || count!=0) $fatal(1,"reset did not discard pending frame");
        check_output=1; send_frame(0);
        wait(count==2); repeat(5) @(negedge clk);
        if(!ready || busy || count!=2 || error_count!=2) $fatal(1,"valid recovery frame failed");
        $display("PASS beamforming_error_recovery: zero pivot/denominator, frame discard, reset, next frame"); $finish;
    end
endmodule
