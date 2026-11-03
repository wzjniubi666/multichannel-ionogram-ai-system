`timescale 1ns/1ps
module tb_covariance_16ch_256;
    reg clk = 0, rst = 1, sample_valid = 0, frame_start = 0, frame_end = 0;
    reg signed [16*16-1:0] x_i_bus = 0, x_q_bus = 0;
    wire matrix_valid;
    wire signed [16*16*48-1:0] r_re_bus, r_im_bus;
    integer k, n;

    always #5 clk = ~clk;
    initial begin #1000000; $fatal(1, "256-record covariance timeout"); end

    covariance_estimator #(.N_CH(16), .FRAME_SAMPLES(256)) dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .x_i_bus(x_i_bus), .x_q_bus(x_q_bus),
        .matrix_valid(matrix_valid), .r_re_bus(r_re_bus), .r_im_bus(r_im_bus)
    );

    initial begin
        // Constant x[k]=(k+1)+j for all 256 snapshots.
        for (k = 0; k < 16; k = k + 1) begin
            x_i_bus[k*16 +: 16] = k + 1;
            x_q_bus[k*16 +: 16] = 1;
        end
        #12 rst = 0;
        for (n = 0; n < 256; n = n + 1) begin
            @(negedge clk);
            sample_valid = 1;
            frame_start = (n == 0);
            frame_end = (n == 255);
        end
        @(negedge clk);
        sample_valid = 0;
        frame_start = 0;
        frame_end = 0;
        wait(matrix_valid === 1'b1);
        #1;
        if (!matrix_valid) $fatal(1, "matrix_valid missing");
        for (k = 0; k < 16; k = k + 1) begin
            if ($signed(r_re_bus[(k*16+k)*48 +: 48]) !== 256*((k+1)*(k+1)+1))
                $fatal(1, "diagonal mismatch at %0d", k);
            if (r_im_bus[(k*16+k)*48 +: 48] !== 0)
                $fatal(1, "diagonal imaginary mismatch at %0d", k);
        end
        // R[1,0] = 256*(3-j), R[0,1] = 256*(3+j).
        if ($signed(r_re_bus[(1*16+0)*48 +: 48]) !== 48'sd768 ||
            $signed(r_im_bus[(1*16+0)*48 +: 48]) !== -48'sd256 ||
            $signed(r_re_bus[(0*16+1)*48 +: 48]) !== 48'sd768 ||
            $signed(r_im_bus[(0*16+1)*48 +: 48]) !== 48'sd256)
            $fatal(1, "off-diagonal mismatch");
        $display("PASS covariance_16ch_256");
        $finish;
    end
endmodule
