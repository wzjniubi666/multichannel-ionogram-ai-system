`timescale 1ns/1ps
module divider_case #(parameter integer W=8, TRIALS=100)(output reg finished=0);
    reg clk=0,rst=1,start=0;
    reg signed [W-1:0] n=0,d=1;
    wire busy,done,zero;
    wire signed [W-1:0] q;
    reg signed [W-1:0] expected;
    integer k,b;
    reg [31:0] seed=32'h9381ab73;
    always #5 clk=~clk;
    mvdr_signed_divider #(.WIDTH(W)) dut(.clk(clk),.rst(rst),.start(start),
        .numerator(n),.denominator(d),.busy(busy),.done(done),
        .divide_by_zero(zero),.quotient(q));
    task run_division;
        input signed [W-1:0] nn,dd;
        begin
            @(negedge clk); n=nn; d=dd; start=1;
            @(negedge clk); start=0;
            // Inputs may change after acceptance. A busy request is ignored.
            n=0; d=0;
            if(busy) begin start=1; @(negedge clk); start=0; end
            wait(done===1'b1);
            #1;
            if(dd==0) begin
                if(zero!==1 || q!==0) $fatal(1,"divider zero policy W=%0d",W);
            end else begin
                expected=nn/dd;
                if(zero!==0 || q!==expected)
                    $fatal(1,"divider W=%0d n=%0d d=%0d got=%0d expected=%0d",W,nn,dd,q,expected);
            end
            repeat(2) @(negedge clk);
            if(done!==0 || busy!==0) $fatal(1,"divider did not release W=%0d",W);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst=0;
        run_division(0,1); run_division(-7,3); run_division(7,-3); run_division(-7,-3);
        run_division({1'b1,{(W-1){1'b0}}},-1);
        run_division({1'b1,{(W-1){1'b0}}},{1'b1,{(W-1){1'b0}}});
        run_division({1'b0,{(W-1){1'b1}}},1); run_division(123,0);
        for(k=0;k<TRIALS;k=k+1) begin
            for(b=0;b<W;b=b+1) begin
                seed=seed^(seed<<13); seed=seed^(seed>>17); seed=seed^(seed<<5); n[b]=seed[0];
                seed=seed^(seed<<13); seed=seed^(seed>>17); seed=seed^(seed<<5); d[b]=seed[0];
            end
            run_division(n,d);
        end
        // Abort a transaction and verify no stale completion follows reset.
        @(negedge clk); n=117; d=3; start=1;
        @(negedge clk); start=0;
        repeat(2) @(negedge clk); rst=1;
        @(negedge clk); rst=0;
        repeat(W+3) begin @(negedge clk); if(done || busy) $fatal(1,"stale divider result after reset"); end
        run_division(-111,7);
        $display("PASS divider_case W=%0d: boundaries, %0d deterministic random cases, busy, reset",W,TRIALS);
        finished=1;
    end
endmodule

module complex_multiplier_case(output reg finished=0);
    reg clk=0,rst=1,start=0,conj=0;
    reg signed [63:0] ar=0,ai=0,br=0,bi=0;
    wire busy,done;
    wire signed [128:0] re,im;
    reg signed [127:0] p0,p1,p2,p3;
    reg signed [128:0] er,ei;
    integer k;
    reg [31:0] seed=32'h51a783c9;
    always #5 clk=~clk;
    mvdr_complex_multiplier dut(.clk(clk),.rst(rst),.start(start),.conjugate_b(conj),
        .a_re(ar),.a_im(ai),.b_re(br),.b_im(bi),
        .busy(busy),.done(done),.result_re(re),.result_im(im));
    function [31:0] random_word;
        input [31:0] s;
        reg [31:0] v;
        begin v=s^(s<<13); v=v^(v>>17); random_word=v^(v<<5); end
    endfunction
    task run_product;
        input signed [63:0] aar,aai,bbr,bbi;
        input cc;
        begin
            p0=aar*bbr; p1=aai*bbi; p2=aai*bbr; p3=aar*bbi;
            er=cc ? $signed({p0[127],p0})+$signed({p1[127],p1}) :
                    $signed({p0[127],p0})-$signed({p1[127],p1});
            ei=cc ? $signed({p2[127],p2})-$signed({p3[127],p3}) :
                    $signed({p2[127],p2})+$signed({p3[127],p3});
            @(negedge clk); ar=aar; ai=aai; br=bbr; bi=bbi; conj=cc; start=1;
            @(negedge clk); start=0; ar=0; ai=0; br=0; bi=0; conj=~cc;
            @(negedge clk); start=1; @(negedge clk); start=0;
            wait(done===1'b1); @(negedge clk);
            if(re!==er || im!==ei) $fatal(1,"complex multiply mismatch case %0d conj=%b re=%h/%h im=%h/%h",k,cc,re,er,im,ei);
            @(negedge clk); if(done || busy) $fatal(1,"complex multiply did not release");
        end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst=0;
        run_product(0,0,1,-1,0);
        run_product(-1,-1,-1,-1,0);
        run_product(64'sh8000000000000000,64'sh8000000000000000,
                    64'sh8000000000000000,64'sh8000000000000000,1);
        run_product(64'sh7fffffffffffffff,64'sh8000000000000000,-1,1,0);
        for(k=0;k<180;k=k+1) begin
            seed=random_word(seed); ar[31:0]=seed; seed=random_word(seed); ar[63:32]=seed;
            seed=random_word(seed); ai[31:0]=seed; seed=random_word(seed); ai[63:32]=seed;
            seed=random_word(seed); br[31:0]=seed; seed=random_word(seed); br[63:32]=seed;
            seed=random_word(seed); bi[31:0]=seed; seed=random_word(seed); bi[63:32]=seed;
            run_product(ar,ai,br,bi,k%2);
        end
        @(negedge clk); ar=77; br=-63; start=1;
        @(negedge clk); start=0;
        repeat(2) @(negedge clk); rst=1;
        @(negedge clk); rst=0;
        repeat(16) begin @(negedge clk); if(done || busy) $fatal(1,"stale multiplier result after reset"); end
        run_product(-32768,32767,-65537,65535,1);
        $display("PASS complex_multiplier_case: full-width products, normal/conjugate, busy, reset");
        finished=1;
    end
endmodule

module tb_mvdr_arithmetic;
    wire a,b,c;
    divider_case #(.W(8),.TRIALS(150)) d8(a);
    divider_case #(.W(129),.TRIALS(100)) d129(b);
    complex_multiplier_case cm(c);
    initial begin #1000000; $fatal(1,"arithmetic test timeout"); end
    initial begin wait(a&&b&&c); $display("PASS mvdr_arithmetic:"); $finish; end
endmodule
