`timescale 1ns/1ps
module beamformer_pipeline_case #(parameter integer N=16,AW=48)(output reg finished=0);
    reg clk=0,rst=1,sv=0;
    reg signed [N*16-1:0] xi=0,xq=0;
    reg signed [N*24-1:0] wr=0,wi=0;
    wire bv,nv;
    wire signed [AW-1:0] br,bi,nr,ni;
    reg signed [AW-1:0] expect_re[0:511],expect_im[0:511];
    integer read_ptr=0,write_ptr=0,n,ch;
    reg [31:0] seed=32'h3591a2b7;
    always #5 clk=~clk;
    complex_beamformer_baseline #(.N_CH(N),.ACC_W(AW)) baseline(
        .clk(clk),.rst(rst),.sample_valid(sv),.x_i_bus(xi),.x_q_bus(xq),
        .w_re_bus(wr),.w_im_bus(wi),.output_valid(bv),.y_re(br),.y_im(bi));
    complex_beamformer #(.N_CH(N),.ACC_W(AW)) candidate(
        .clk(clk),.rst(rst),.sample_valid(sv),.x_i_bus(xi),.x_q_bus(xq),
        .w_re_bus(wr),.w_im_bus(wi),.output_valid(nv),.y_re(nr),.y_im(ni));
    always @(posedge clk) begin
        #1;
        if(rst) begin read_ptr=0; write_ptr=0; end
        else begin
            if(bv) begin expect_re[write_ptr]=br; expect_im[write_ptr]=bi; write_ptr=write_ptr+1; end
            if(nv) begin
                if(read_ptr>=write_ptr) $fatal(1,"unexpected/duplicate beam output N=%0d",N);
                if(nr!==expect_re[read_ptr] || ni!==expect_im[read_ptr])
                    $fatal(1,"beam bit mismatch N=%0d AW=%0d record=%0d got=(%0d,%0d) ref=(%0d,%0d)",N,AW,read_ptr,nr,ni,expect_re[read_ptr],expect_im[read_ptr]);
                read_ptr=read_ptr+1;
            end
        end
    end
    function [31:0] next_random;
        input [31:0] s;
        reg [31:0] v;
        begin v=s^(s<<13); v=v^(v>>17); next_random=v^(v<<5); end
    endfunction
    task drive_records;
        input integer length;
        begin
            for(n=0;n<length;n=n+1) begin
                @(negedge clk); sv=(n%5!=2);
                for(ch=0;ch<N;ch=ch+1) begin
                    if(n==0) begin
                        xi[ch*16 +: 16]=16'sh8000; xq[ch*16 +: 16]=16'sh7fff;
                        wr[ch*24 +: 24]=24'sh800000; wi[ch*24 +: 24]=24'sh7fffff;
                    end else begin
                        seed=next_random(seed); xi[ch*16 +: 16]=seed[15:0];
                        seed=next_random(seed); xq[ch*16 +: 16]=seed[15:0];
                        seed=next_random(seed); wr[ch*24 +: 24]=seed[23:0];
                        seed=next_random(seed); wi[ch*24 +: 24]=seed[23:0];
                    end
                end
            end
            @(negedge clk); sv=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        drive_records(160); repeat(20) @(negedge clk);
        if(read_ptr!=write_ptr || read_ptr!=128) $fatal(1,"beam outputs lost N=%0d",N);
        drive_records(3); @(negedge clk); rst=1;
        repeat(2) @(negedge clk); rst=0;
        repeat(20) @(negedge clk);
        if(read_ptr!=0 || write_ptr!=0) $fatal(1,"stale beam pipeline after reset");
        drive_records(100); repeat(20) @(negedge clk);
        if(read_ptr!=write_ptr || read_ptr!=80) $fatal(1,"post-reset beam outputs lost N=%0d",N);
        $display("PASS beamformer_pipeline_case N=%0d AW=%0d: exact stream, changing weights, gaps, reset",N,AW);
        finished=1;
    end
endmodule

module tb_complex_beamformer_pipeline;
    wire a,b,c,d;
    beamformer_pipeline_case #(.N(1)) singleton(a);
    beamformer_pipeline_case #(.N(3)) non_power_of_two(b);
    beamformer_pipeline_case #(.N(16)) current_size(c);
    beamformer_pipeline_case #(.N(3),.AW(32)) accumulator_wrap(d);
    initial begin #100000; $fatal(1,"beam pipeline test timeout"); end
    initial begin wait(a&&b&&c&&d); $display("PASS complex_beamformer_pipeline:"); $finish; end
endmodule
