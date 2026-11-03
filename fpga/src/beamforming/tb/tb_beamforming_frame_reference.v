`timescale 1ns/1ps
module tb_beamforming_frame_reference;
    localparam integer N=16, K=32, IW=16, AW=48, WW=24;
    reg clk=0, rst=1, sv=0, fs=0, fe=0;
    reg signed [N*IW-1:0] xi=0, xq=0;
    reg signed [N*WW-1:0] sr=0, si=0;
    wire cv,wv,sbusy,cr,fr,rv,ov;
    wire signed [AW-1:0] br,bi;
    reg [15:0] iq_i[0:N*K-1], iq_q[0:N*K-1];
    reg [47:0] ref_br[0:K-1], ref_bi[0:K-1];
    reg [23:0] steer_r[0:N-1], steer_i[0:N-1];
    integer s,ch,n,d,mismatches;
    always #5 clk=~clk;
    beamforming_top dut(
        .clk(clk),.rst(rst),.sample_valid(sv),.frame_start(fs),.frame_end(fe),
        .in_i_bus(xi),.in_q_bus(xq),.steering_re_bus(sr),.steering_im_bus(si),
        .covariance_valid(cv),.weights_valid(wv),.solver_busy(sbusy),
        .capture_ready(cr),.frame_ready(fr),.replay_valid(rv),
        .output_valid(ov),.beam_re(br),.beam_im(bi));
    initial begin #3000000; $fatal(1,"timeout waiting for frame beam output"); end
    initial begin
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_i.hex",iq_i);
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_q.hex",iq_q);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",steer_r);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",steer_i);
        $readmemh("sim_vectors/reference_10mhz_gate80/beam_re.hex",ref_br);
        $readmemh("sim_vectors/reference_10mhz_gate80/beam_im.hex",ref_bi);
        for(ch=0;ch<N;ch=ch+1) begin sr[ch*WW +: WW]=steer_r[ch]; si[ch*WW +: WW]=steer_i[ch]; end
        repeat(3) @(negedge clk); rst=0;
        for(s=0;s<K;s=s+1) begin
            @(negedge clk);
            for(ch=0;ch<N;ch=ch+1) begin
                xi[ch*IW +: IW]=iq_i[s*N+ch]; xq[ch*IW +: IW]=iq_q[s*N+ch];
            end
            sv=1; fs=(s==0); fe=(s==K-1);
        end
        @(negedge clk); sv=0; fs=0; fe=0;
        wait(ov===1'b1); mismatches=0; n=0;
        while(n<K) begin
            @(posedge clk);
            if(ov) begin
                d=$signed(br)-$signed(ref_br[n]); if(d<0)d=-d;
                if(d>2000000) begin $display("beam re[%0d] rtl=%0d ref=%0d",n,$signed(br),$signed(ref_br[n])); mismatches=mismatches+1; end
                d=$signed(bi)-$signed(ref_bi[n]); if(d<0)d=-d;
                if(d>2000000) begin $display("beam im[%0d] rtl=%0d ref=%0d",n,$signed(bi),$signed(ref_bi[n])); mismatches=mismatches+1; end
                n=n+1;
            end
        end
        if(mismatches) $fatal(1,"frame beam mismatch count %0d",mismatches);
        $display("PASS beamforming_frame_reference: capture -> MVDR -> replay -> 32 beam outputs"); $finish;
    end
endmodule
