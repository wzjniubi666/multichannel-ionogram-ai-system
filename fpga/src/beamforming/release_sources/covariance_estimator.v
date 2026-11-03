`timescale 1ns/1ps
// Frame-level covariance with a streamed internal RAM-read pipeline. A channel
// pair is held stable while all snapshots pass through RAM -> select -> multiply
// -> product sum -> accumulator. The next pair starts after the pipeline drains.
module covariance_estimator #(
    parameter integer N_CH=16, IQ_W=16, ACC_W=48, FRAME_SAMPLES=32
)(
    input wire clk,rst,sample_valid,frame_start,frame_end,
    input wire signed [N_CH*IQ_W-1:0] x_i_bus,x_q_bus,
    output reg matrix_valid,
    output wire signed [N_CH*N_CH*ACC_W-1:0] r_re_bus,r_im_bus
);
    localparam integer SNAP_W=(FRAME_SAMPLES<=2) ? 1 : $clog2(FRAME_SAMPLES);
    localparam integer CH_W=(N_CH<=2) ? 1 : $clog2(N_CH);
    localparam [2:0] IDLE=0,CAPTURE=1,STREAM=2,DRAIN=3,CONJUGATE=4,WRITE_PAIR=5,PUBLISH=6;
    reg [2:0] state;
    reg [SNAP_W:0] snapshot_count;
    reg [SNAP_W-1:0] snapshot_idx;
    reg [CH_W-1:0] pair_i,pair_j;
    (* ram_style="block" *) reg signed [N_CH*IQ_W-1:0] sample_i_mem[0:FRAME_SAMPLES-1];
    (* ram_style="block" *) reg signed [N_CH*IQ_W-1:0] sample_q_mem[0:FRAME_SAMPLES-1];
    reg signed [N_CH*IQ_W-1:0] sample_i_read,sample_q_read;
    wire capture_first=(state==IDLE) && sample_valid && frame_start;
    wire capture_next=(state==CAPTURE) && sample_valid && snapshot_count<FRAME_SAMPLES;
    wire [SNAP_W-1:0] write_addr=capture_first ? {SNAP_W{1'b0}} : snapshot_count[SNAP_W-1:0];
    always @(posedge clk) begin
        if(!rst && (capture_first || capture_next)) begin
            sample_i_mem[write_addr]<=x_i_bus;
            sample_q_mem[write_addr]<=x_q_bus;
        end
        if(!rst && state==STREAM) begin
            sample_i_read<=sample_i_mem[snapshot_idx];
            sample_q_read<=sample_q_mem[snapshot_idx];
        end
    end

    reg read_valid,select_valid,multiply_valid,product_valid;
    reg read_first,read_last,select_first,select_last,multiply_first,multiply_last,product_first,product_last;
    reg signed [IQ_W-1:0] xi_i,xj_i,xi_q,xj_q;
    reg signed [2*IQ_W-1:0] mul_ii,mul_qq,mul_qi,mul_iq;
    reg signed [2*IQ_W:0] product_re,product_im;
    reg signed [ACC_W-1:0] acc_re,acc_im,final_re,final_im,final_im_conjugate;
    always @(posedge clk) begin
        if(rst) begin
            read_valid<=0; select_valid<=0; multiply_valid<=0; product_valid<=0;
        end else begin
            read_valid<=(state==STREAM);
            select_valid<=read_valid;
            multiply_valid<=select_valid;
            product_valid<=multiply_valid;
            if(state==STREAM) begin
                read_first<=(snapshot_idx==0);
                read_last<=(snapshot_idx==FRAME_SAMPLES-1);
            end
            if(read_valid) begin
                xi_i<=$signed(sample_i_read[pair_i*IQ_W +: IQ_W]);
                xj_i<=$signed(sample_i_read[pair_j*IQ_W +: IQ_W]);
                xi_q<=$signed(sample_q_read[pair_i*IQ_W +: IQ_W]);
                xj_q<=$signed(sample_q_read[pair_j*IQ_W +: IQ_W]);
                select_first<=read_first; select_last<=read_last;
            end
            if(select_valid) begin
                mul_ii<=xi_i*xj_i; mul_qq<=xi_q*xj_q;
                mul_qi<=xi_q*xj_i; mul_iq<=xi_i*xj_q;
                multiply_first<=select_first; multiply_last<=select_last;
            end
            if(multiply_valid) begin
                product_re<={mul_ii[2*IQ_W-1],mul_ii} +
                            {mul_qq[2*IQ_W-1],mul_qq};
                product_im<={mul_qi[2*IQ_W-1],mul_qi} -
                            {mul_iq[2*IQ_W-1],mul_iq};
                product_first<=multiply_first; product_last<=multiply_last;
            end
        end
    end

    // The completed matrix remains a parallel register bank. Constant output
    // slices and shared conjugation preserve the previous area optimization.
    genvar bank_row,bank_col;
    generate for(bank_row=0;bank_row<N_CH;bank_row=bank_row+1) begin : rows
        for(bank_col=0;bank_col<=bank_row;bank_col=bank_col+1) begin : cols
            reg signed [ACC_W-1:0] real_word;
            wire word_enable=(state==WRITE_PAIR) && pair_i==bank_row && pair_j==bank_col;
            always @(posedge clk) begin
                if(rst) real_word<=0;
                else if(word_enable) real_word<=final_re;
            end
            assign r_re_bus[(bank_row*N_CH+bank_col)*ACC_W +: ACC_W]=real_word;
            if(bank_row!=bank_col) begin : off_diagonal
                reg signed [ACC_W-1:0] imag_word,conjugate_word;
                always @(posedge clk) begin
                    if(rst) begin imag_word<=0; conjugate_word<=0; end
                    else if(word_enable) begin imag_word<=final_im; conjugate_word<=final_im_conjugate; end
                end
                assign r_re_bus[(bank_col*N_CH+bank_row)*ACC_W +: ACC_W]=real_word;
                assign r_im_bus[(bank_row*N_CH+bank_col)*ACC_W +: ACC_W]=imag_word;
                assign r_im_bus[(bank_col*N_CH+bank_row)*ACC_W +: ACC_W]=conjugate_word;
            end else begin : diagonal
                assign r_im_bus[(bank_row*N_CH+bank_col)*ACC_W +: ACC_W]={ACC_W{1'b0}};
            end
        end
    end endgenerate

    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; snapshot_count<=0; snapshot_idx<=0; pair_i<=0; pair_j<=0;
            matrix_valid<=0; acc_re<=0; acc_im<=0;
            final_re<=0; final_im<=0; final_im_conjugate<=0;
        end else begin
            matrix_valid<=0;
            case(state)
                IDLE: if(capture_first) begin
                    snapshot_count<=1;
                    if(frame_end) begin snapshot_idx<=0; pair_i<=0; pair_j<=0; state<=STREAM; end
                    else state<=CAPTURE;
                end
                CAPTURE: if(capture_next) begin
                    if(frame_end) begin snapshot_idx<=0; pair_i<=0; pair_j<=0; state<=STREAM; end
                    else snapshot_count<=snapshot_count+1'b1;
                end
                STREAM: begin
                    if(snapshot_idx==FRAME_SAMPLES-1) state<=DRAIN;
                    else snapshot_idx<=snapshot_idx+1'b1;
                end
                DRAIN: begin end
                CONJUGATE: begin final_im_conjugate<=-final_im; state<=WRITE_PAIR; end
                WRITE_PAIR: begin
                    snapshot_idx<=0;
                    if(pair_j==pair_i) begin
                        pair_j<=0;
                        if(pair_i==N_CH-1) state<=PUBLISH;
                        else begin pair_i<=pair_i+1'b1; state<=STREAM; end
                    end else begin pair_j<=pair_j+1'b1; state<=STREAM; end
                end
                PUBLISH: begin matrix_valid<=1; snapshot_count<=0; state<=IDLE; end
                default: state<=IDLE;
            endcase
            if(product_valid) begin
                acc_re<=product_first ? product_re : acc_re+product_re;
                acc_im<=product_first ? product_im : acc_im+product_im;
                if(product_last) begin
                    final_re<=product_first ? product_re : acc_re+product_re;
                    final_im<=product_first ? product_im : acc_im+product_im;
                    state<=CONJUGATE;
                end
            end
        end
    end
endmodule
