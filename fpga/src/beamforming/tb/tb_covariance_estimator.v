`timescale 1ns/1ps
module tb_covariance_estimator;
    reg clk = 0, rst = 1, sample_valid = 0, frame_start = 0, frame_end = 0;
    reg signed [31:0] x_i_bus = 0, x_q_bus = 0;
    wire matrix_valid;
    wire signed [4*48-1:0] r_re_bus, r_im_bus;

    always #5 clk = ~clk;
    initial begin #10000; $fatal(1, "covariance timeout"); end

    covariance_estimator #(.N_CH(2), .FRAME_SAMPLES(2)) dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .x_i_bus(x_i_bus), .x_q_bus(x_q_bus),
        .matrix_valid(matrix_valid), .r_re_bus(r_re_bus), .r_im_bus(r_im_bus)
    );

    initial begin
        #12 rst = 0;
        // x=[1+j, 2], then x=[1-j, 2]. Sum R=[[4,4],[4,8]].
        @(negedge clk);
        frame_start = 1; sample_valid = 1;
        x_i_bus = {16'sd2, 16'sd1};
        x_q_bus = {16'sd0, 16'sd1};
        @(negedge clk);
        frame_start = 0; frame_end = 1;
        x_q_bus = {16'sd0, -16'sd1};
        @(negedge clk);
        frame_end = 0; sample_valid = 0;
        wait(matrix_valid === 1'b1);
        #1;
        if (!matrix_valid ||
            $signed(r_re_bus[0*48 +: 48]) !== 48'sd4 ||
            $signed(r_re_bus[1*48 +: 48]) !== 48'sd4 ||
            $signed(r_re_bus[2*48 +: 48]) !== 48'sd4 ||
            $signed(r_re_bus[3*48 +: 48]) !== 48'sd8 ||
            r_im_bus !== 0)
            $fatal(1, "covariance mismatch valid=%b", matrix_valid);
        $display("PASS covariance_estimator");
        $finish;
    end
endmodule
