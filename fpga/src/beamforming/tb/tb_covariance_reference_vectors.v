`timescale 1ns/1ps
module tb_covariance_reference_vectors;
    localparam integer N_CH = 16;
    localparam integer N_SAMPLES = 32;
    localparam integer IQ_W = 16;
    localparam integer ACC_W = 48;

    reg clk = 0;
    reg rst = 1;
    reg sample_valid = 0;
    reg frame_start = 0;
    reg frame_end = 0;
    reg signed [N_CH*IQ_W-1:0] x_i_bus = 0;
    reg signed [N_CH*IQ_W-1:0] x_q_bus = 0;
    wire matrix_valid;
    wire signed [N_CH*N_CH*ACC_W-1:0] r_re_bus, r_im_bus;

    reg [15:0] iq_i [0:N_CH*N_SAMPLES-1];
    reg [15:0] iq_q [0:N_CH*N_SAMPLES-1];
    reg [47:0] expected_re [0:N_CH*N_CH-1];
    reg [47:0] expected_im [0:N_CH*N_CH-1];
    integer s, ch, idx, mismatches;

    always #5 clk = ~clk;

    initial begin
        #100000;
        $fatal(1, "timeout waiting for covariance matrix");
    end

    covariance_estimator #(
        .N_CH(N_CH), .IQ_W(IQ_W), .ACC_W(ACC_W),
        .FRAME_SAMPLES(N_SAMPLES)
    ) dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .frame_start(frame_start), .frame_end(frame_end),
        .x_i_bus(x_i_bus), .x_q_bus(x_q_bus),
        .matrix_valid(matrix_valid), .r_re_bus(r_re_bus), .r_im_bus(r_im_bus)
    );

    initial begin
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_i.hex", iq_i);
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_q.hex", iq_q);
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_re.hex", expected_re);
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_im.hex", expected_im);

        repeat (3) @(negedge clk);
        rst = 0;
        for (s = 0; s < N_SAMPLES; s = s + 1) begin
            @(negedge clk);
            for (ch = 0; ch < N_CH; ch = ch + 1) begin
                x_i_bus[ch*IQ_W +: IQ_W] = iq_i[s*N_CH+ch];
                x_q_bus[ch*IQ_W +: IQ_W] = iq_q[s*N_CH+ch];
            end
            sample_valid = 1;
            frame_start = (s == 0);
            frame_end = (s == N_SAMPLES-1);
        end
        @(negedge clk);
        sample_valid = 0;
        frame_start = 0;
        frame_end = 0;

        wait (matrix_valid === 1'b1);
        #1;
        mismatches = 0;
        for (idx = 0; idx < N_CH*N_CH; idx = idx + 1) begin
            if ($signed(r_re_bus[idx*ACC_W +: ACC_W]) !== $signed(expected_re[idx])) begin
                if (mismatches < 8)
                    $display("RE mismatch [%0d,%0d] got=%0d expected=%0d",
                        idx/N_CH, idx%N_CH,
                        $signed(r_re_bus[idx*ACC_W +: ACC_W]), $signed(expected_re[idx]));
                mismatches = mismatches + 1;
            end
            if ($signed(r_im_bus[idx*ACC_W +: ACC_W]) !== $signed(expected_im[idx])) begin
                if (mismatches < 8)
                    $display("IM mismatch [%0d,%0d] got=%0d expected=%0d",
                        idx/N_CH, idx%N_CH,
                        $signed(r_im_bus[idx*ACC_W +: ACC_W]), $signed(expected_im[idx]));
                mismatches = mismatches + 1;
            end
        end
        if (mismatches != 0)
            $fatal(1, "covariance reference comparison failed: %0d mismatches", mismatches);
        $display("PASS covariance_reference_vectors: 16 channels x 32 records, 10 MHz gate 80, 512 matrix words matched");
        $finish;
    end
endmodule
