`timescale 1ns/1ps
module tb_mvdr_solver_reference;
    localparam integer N=16, AW=48, WW=24;
    reg clk=0, rst=1, matrix_valid=0;
    reg signed [N*N*AW-1:0] rr=0, ri=0;
    reg signed [N*WW-1:0] ar=0, ai=0;
    wire weights_valid;
    wire solver_busy;
    wire signed [N*WW-1:0] wr, wi;
    reg [47:0] covr[0:N*N-1], covi[0:N*N-1];
    reg [23:0] steer_r[0:N-1], steer_i[0:N-1];
    reg [23:0] ref_r[0:N-1], ref_i[0:N-1];
    integer k, d, mismatches;
    reg signed [63:0] constraint_re, constraint_im;
    always #5 clk=~clk;
    mvdr_solver_stub #(.N_CH(N),.ACC_W(AW),.WEIGHT_W(WW)) dut(
        .clk(clk),.rst(rst),.matrix_valid(matrix_valid),
        .r_re_bus(rr),.r_im_bus(ri),.steering_re_bus(ar),.steering_im_bus(ai),
        .weights_valid(weights_valid),.busy(solver_busy),.weight_re_bus(wr),.weight_im_bus(wi));
    initial begin
        #2000000; $fatal(1,"timeout waiting for solver weights");
    end
    initial begin
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_re.hex",covr);
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_im.hex",covi);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",steer_r);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",steer_i);
        $readmemh("sim_vectors/reference_10mhz_gate80/weight_re.hex",ref_r);
        $readmemh("sim_vectors/reference_10mhz_gate80/weight_im.hex",ref_i);
        for(k=0;k<N*N;k=k+1) begin rr[k*AW +: AW]=covr[k]; ri[k*AW +: AW]=covi[k]; end
        for(k=0;k<N;k=k+1) begin ar[k*WW +: WW]=steer_r[k]; ai[k*WW +: WW]=steer_i[k]; end
        repeat(3) @(negedge clk); rst=0; @(negedge clk); matrix_valid=1;
        @(negedge clk); matrix_valid=0;
        wait(weights_valid===1'b1); #1; mismatches=0; constraint_re=0; constraint_im=0;
        for(k=0;k<N;k=k+1) begin
            constraint_re=constraint_re+$signed(steer_r[k])*$signed(wr[k*WW +: WW])+$signed(steer_i[k])*$signed(wi[k*WW +: WW]);
            constraint_im=constraint_im+$signed(steer_r[k])*$signed(wi[k*WW +: WW])-$signed(steer_i[k])*$signed(wr[k*WW +: WW]);
            d=$signed(wr[k*WW +: WW])-$signed(ref_r[k]); if(d<0)d=-d;
            if(d>150000) begin $display("weight real[%0d] rtl=%0d ref=%0d",k,$signed(wr[k*WW +: WW]),$signed(ref_r[k])); mismatches=mismatches+1; end
            d=$signed(wi[k*WW +: WW])-$signed(ref_i[k]); if(d<0)d=-d;
            if(d>150000) begin $display("weight imag[%0d] rtl=%0d ref=%0d",k,$signed(wi[k*WW +: WW]),$signed(ref_i[k])); mismatches=mismatches+1; end
        end
        if(mismatches) $fatal(1,"MVDR solver mismatch count %0d",mismatches);
        if ((constraint_re < 64'sd70200000000000) || (constraint_re > 64'sd70400000000000) ||
            (constraint_im < -64'sd100000000000) || (constraint_im > 64'sd100000000000))
            $fatal(1,"MVDR constraint failure a^H*w=(%0d,%0d)",constraint_re,constraint_im);
        $display("PASS mvdr_solver_reference: 16 Q1.23 weights within 0.018, target constraint verified"); $finish;
    end
endmodule
