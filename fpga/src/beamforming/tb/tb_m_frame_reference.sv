`timescale 1ns/1ps
// Test-only: current 32-record board frame and future 512-record algorithm mode.
module m_frame_reference_case #(parameter integer K=32);
    localparam integer N=16;
    reg clk=0,rst=1,sv=0,fs=0,fe=0;
    reg [255:0] xi=0,xq=0;
    reg [383:0] sr=0,si=0;
    wire cv,wv,sbusy,err,cr,fr,rv,ov;
    wire signed [47:0] br,bi;
    reg [15:0] ii[0:N*K-1],qq[0:N*K-1];
    reg [47:0] rr[0:N*N-1],ri[0:N*N-1],yr[0:K-1],yi[0:K-1];
    reg [23:0] ar[0:N-1],ai[0:N-1],wr[0:N-1],wi[0:N-1];
    integer ch,s,k,cycle=0,nout=0,ncov=0,nweight=0,nreplay=0,accepted=0;
    integer capture_last=-1,cov_cycle=-1,weight_cycle=-1,first_output=-1;
    integer fbr,fbi,fwr,fwi;
    always #2.5 clk=~clk;
    beamforming_top #(.FRAME_SAMPLES(K)) dut(
        .clk(clk),.rst(rst),.sample_valid(sv),.frame_start(fs),.frame_end(fe),
        .in_i_bus(xi),.in_q_bus(xq),.steering_re_bus(sr),.steering_im_bus(si),
        .covariance_valid(cv),.weights_valid(wv),.solver_busy(sbusy),.solver_error(err),
        .capture_ready(cr),.frame_ready(fr),.replay_valid(rv),
        .output_valid(ov),.beam_re(br),.beam_im(bi));
    initial begin #5000000;$fatal(1,"M_FRAME timeout K=%0d",K);end
    // Count acceptance at the edge using pre-edge ready/valid values.
    always @(posedge clk) if(!rst && sv && cr) begin
        accepted=accepted+1;
        if(fe)capture_last=cycle;
    end
    // Check registered DUT values after NBA updates; avoid monitor races.
    always @(posedge clk) begin
        #1;cycle=cycle+1;
        if(!rst) begin
            if(err)$fatal(1,"M_FRAME solver error K=%0d",K);
            if(cv) begin
                ncov=ncov+1;cov_cycle=cycle;
                if(accepted!=K || ncov!=1)$fatal(1,"M_FRAME covariance timing/count");
                for(k=0;k<N*N;k=k+1) begin
                    if(dut.r_re_bus[k*48+:48]!==rr[k] || dut.r_im_bus[k*48+:48]!==ri[k])
                        $fatal(1,"M_FRAME covariance mismatch index=%0d",k);
                end
            end
            if(wv) begin
                nweight=nweight+1;weight_cycle=cycle;
                if(ncov!=1 || nweight!=1)$fatal(1,"M_FRAME weight timing/count");
                for(k=0;k<N;k=k+1) begin
                    if(dut.w_re_bus[k*24+:24]!==wr[k] || dut.w_im_bus[k*24+:24]!==wi[k])
                        $fatal(1,"M_FRAME weight mismatch channel=%0d rtl=(%0d,%0d) ref=(%0d,%0d)",
                            k,$signed(dut.w_re_bus[k*24+:24]),$signed(dut.w_im_bus[k*24+:24]),$signed(wr[k]),$signed(wi[k]));
                    $fdisplay(fwr,"%06x",dut.w_re_bus[k*24+:24]);
                    $fdisplay(fwi,"%06x",dut.w_im_bus[k*24+:24]);
                end
            end
            if(rv)nreplay=nreplay+1;
            if(ov) begin
                if(nweight!=1 || nout>=K)$fatal(1,"M_FRAME early or extra output");
                if(nout==0)first_output=cycle;
                if(br!==yr[nout] || bi!==yi[nout])
                    $fatal(1,"M_FRAME beam mismatch record=%0d rtl=(%0d,%0d) ref=(%0d,%0d)",
                        nout,br,bi,$signed(yr[nout]),$signed(yi[nout]));
                $fdisplay(fbr,"%012x",br);$fdisplay(fbi,"%012x",bi);
                nout=nout+1;
            end
        end
    end
    initial begin
        $readmemh("vectors/iq_i.hex",ii);$readmemh("vectors/iq_q.hex",qq);
        $readmemh("vectors/cov_re.hex",rr);$readmemh("vectors/cov_im.hex",ri);
        $readmemh("vectors/steering_re.hex",ar);$readmemh("vectors/steering_im.hex",ai);
        $readmemh("vectors/weight_re.hex",wr);$readmemh("vectors/weight_im.hex",wi);
        $readmemh("vectors/beam_re.hex",yr);$readmemh("vectors/beam_im.hex",yi);
        fbr=$fopen("rtl_beam_re.hex","w");fbi=$fopen("rtl_beam_im.hex","w");
        fwr=$fopen("rtl_weight_re.hex","w");fwi=$fopen("rtl_weight_im.hex","w");
        if(!fbr || !fbi || !fwr || !fwi)$fatal(1,"M_FRAME output files");
        for(ch=0;ch<N;ch=ch+1)begin sr[ch*24+:24]=ar[ch];si[ch*24+:24]=ai[ch];end
        repeat(5)@(negedge clk);rst=0;
        for(s=0;s<K;s=s+1)begin
            @(negedge clk);
            if(s%7==3)begin sv=0;fs=0;fe=0;@(negedge clk);end
            if(!cr)$fatal(1,"M_FRAME capture not ready before complete frame");
            for(ch=0;ch<N;ch=ch+1)begin xi[ch*16+:16]=ii[s*N+ch];xq[ch*16+:16]=qq[s*N+ch];end
            sv=1;fs=(s==0);fe=(s==K-1);
        end
        @(negedge clk);sv=0;fs=0;fe=0;
        wait(nout==K);repeat(20)@(negedge clk);
        if(accepted!=K || nreplay!=K || nout!=K || !cr || sbusy || ncov!=1 || nweight!=1)
            $fatal(1,"M_FRAME totals accepted=%0d replay=%0d output=%0d",accepted,nreplay,nout);
        $fclose(fbr);$fclose(fbi);$fclose(fwr);$fclose(fwi);
        $display("M_FRAME_CYCLES K=%0d capture_last=%0d covariance=%0d weights=%0d first_output=%0d",
            K,capture_last,cov_cycle,weight_cycle,first_output);
        $display("PASS M_FRAME: K=%0d covariance/weights/beam bit exact; capture gaps and output count checked",K);
        $finish;
    end
endmodule

module tb_m_frame32;m_frame_reference_case #(.K(32)) c();endmodule
module tb_m_frame512;m_frame_reference_case #(.K(512)) c();endmodule
