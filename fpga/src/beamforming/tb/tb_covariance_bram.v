`timescale 1ns/1ps
// Exercises synchronous RAM latency, signed products, capture gaps, reset
// during compute, and reuse with a second independent frame.
module covariance_bram_case #(
    parameter integer N=3, K=3
) (output reg done=0);
    reg clk=0, rst=1, sv=0, fs=0, fe=0;
    reg signed [N*16-1:0] xi=0, xq=0;
    wire valid;
    wire signed [N*N*48-1:0] rr, ri;
    reg signed [63:0] er[0:N*N-1], ei[0:N*N-1];
    reg signed [63:0] ir, jr, iq, jq;
    integer f,s,c,i,j;
    always #5 clk=~clk;
    covariance_estimator #(.N_CH(N),.FRAME_SAMPLES(K)) dut(
        .clk(clk),.rst(rst),.sample_valid(sv),.frame_start(fs),.frame_end(fe),
        .x_i_bus(xi),.x_q_bus(xq),.matrix_valid(valid),.r_re_bus(rr),.r_im_bus(ri));

    function signed [15:0] iv;
        input integer frame_no, sample_no, channel_no;
        begin
            // Include the negative 16-bit extremum as well as both signs.
            if (sample_no==0 && channel_no==0) iv=-32768;
            else iv=(frame_no+1)*103 - sample_no*37 + channel_no*19;
        end
    endfunction
    function signed [15:0] qv;
        input integer frame_no, sample_no, channel_no;
        begin qv=-((frame_no+2)*97 + sample_no*11 - channel_no*43); end
    endfunction

    task send_frame;
        input integer frame_no;
        begin
            for(s=0;s<K;s=s+1) begin
                @(negedge clk);
                sv=1; fs=(s==0); fe=(s==K-1);
                for(c=0;c<N;c=c+1) begin
                    xi[c*16 +: 16]=iv(frame_no,s,c);
                    xq[c*16 +: 16]=qv(frame_no,s,c);
                end
                @(negedge clk); sv=0; fs=0; fe=0;
            end
        end
    endtask

    initial begin
        repeat(3) @(negedge clk); rst=0;
        // Abort a captured frame after it has entered the RAM read schedule.
        send_frame(7);
        @(negedge clk); rst=1;
        repeat(2) @(negedge clk); rst=0;
        for(f=0;f<2;f=f+1) begin
            for(i=0;i<N;i=i+1) for(j=0;j<N;j=j+1) begin
                er[i*N+j]=0; ei[i*N+j]=0;
                for(s=0;s<K;s=s+1) begin
                    ir=iv(f,s,i); jr=iv(f,s,j);
                    iq=qv(f,s,i); jq=qv(f,s,j);
                    er[i*N+j]=er[i*N+j]+ir*jr+iq*jq;
                    ei[i*N+j]=ei[i*N+j]+iq*jr-ir*jq;
                end
            end
            send_frame(f);
            wait(valid===1'b1);
            @(negedge clk);
            for(i=0;i<N*N;i=i+1) begin
                if($signed(rr[i*48 +: 48]) !== er[i] ||
                   $signed(ri[i*48 +: 48]) !== ei[i])
                    $fatal(1,"covariance N=%0d K=%0d frame=%0d element=%0d got=%0d,%0d expected=%0d,%0d",
                        N,K,f,i,$signed(rr[i*48 +: 48]),$signed(ri[i*48 +: 48]),er[i],ei[i]);
            end
            @(negedge clk);
            if(valid!==0) $fatal(1,"matrix_valid is not a pulse");
        end
        $display("PASS covariance_bram_case N=%0d K=%0d: reset, gaps, two frames, exact signed covariance",N,K);
        done=1;
    end
endmodule

module tb_covariance_bram;
    wire a,b,c;
    covariance_bram_case #(.N(3),.K(3)) non_power_of_two(a);
    covariance_bram_case #(.N(1),.K(1)) singleton(b);
    covariance_bram_case #(.N(16),.K(32)) current_size(c);
    initial begin #400000; $fatal(1,"covariance BRAM regression timeout"); end
    initial begin wait(a && b && c); $display("PASS covariance_bram:"); $finish; end
endmodule
