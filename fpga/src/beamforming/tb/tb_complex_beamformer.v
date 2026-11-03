`timescale 1ns/1ps
module tb_complex_beamformer;
    reg clk = 0, rst = 1, sample_valid = 0;
    reg signed [16*16-1:0] x_i_bus, x_q_bus;
    reg signed [16*24-1:0] w_re_bus, w_im_bus;
    wire output_valid;
    wire signed [47:0] y_re, y_im;

    always #5 clk = ~clk;
    initial begin #10000; $fatal(1,"beamformer timeout"); end

    integer k;

    complex_beamformer dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .x_i_bus(x_i_bus), .x_q_bus(x_q_bus),
        .w_re_bus(w_re_bus), .w_im_bus(w_im_bus),
        .output_valid(output_valid), .y_re(y_re), .y_im(y_im)
    );

    initial begin
        // Every channel has x=8+4j and w=1/16, so y=8+4j.
        x_i_bus = 0; x_q_bus = 0; w_re_bus = 0; w_im_bus = 0;
        for (k = 0; k < 16; k = k + 1) begin
            x_i_bus[k*16 +: 16] = 16'sd8;
            x_q_bus[k*16 +: 16] = 16'sd4;
            w_re_bus[k*24 +: 24] = 24'sd524288;
        end
        #12 rst = 0;
        @(negedge clk) sample_valid = 1;
        @(negedge clk) sample_valid = 0;
        wait(output_valid === 1'b1);
        #1;
        if (!output_valid || y_re !== 48'sd8 || y_im !== 48'sd4)
            $fatal(1, "beamformer mismatch valid=%b re=%0d im=%0d", output_valid, y_re, y_im);
        $display("PASS complex_beamformer re=%0d im=%0d", y_re, y_im);
        $finish;
    end
endmodule
