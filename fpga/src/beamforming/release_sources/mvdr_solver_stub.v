`timescale 1ns/1ps
// A signed restoring divider. One quotient bit per iteration; sign correction
// has its own cycle. Requests while busy are ignored. Divide by zero is an
// explicit error with quotient zero; min/-1 wraps in WIDTH-bit two's complement.
module mvdr_signed_divider #(parameter integer WIDTH=129)(
    input wire clk, rst, start,
    input wire signed [WIDTH-1:0] numerator, denominator,
    output reg busy, done, divide_by_zero,
    output reg signed [WIDTH-1:0] quotient
);
    localparam integer CW=$clog2(WIDTH+1);
    reg [WIDTH-1:0] divisor, q_work;
    reg [WIDTH:0] remainder;
    reg [CW-1:0] bits_left;
    reg negative, finish_sign;
    wire [WIDTH:0] trial={remainder[WIDTH-1:0],q_work[WIDTH-1]};
    wire [WIDTH+1:0] difference={1'b0,trial}-{2'b00,divisor};
    wire subtract_ok=~difference[WIDTH+1];
    always @(posedge clk) begin
        if(rst) begin
            busy<=0; done<=0; divide_by_zero<=0; quotient<=0;
            finish_sign<=0; bits_left<=0; negative<=0;
            divisor<=0; q_work<=0; remainder<=0;
        end else begin
            done<=0; divide_by_zero<=0;
            if(start && !busy) begin
                if(denominator==0) begin
                    quotient<=0; done<=1; divide_by_zero<=1;
                end else begin
                    q_work<=numerator[WIDTH-1] ? -numerator : numerator;
                    divisor<=denominator[WIDTH-1] ? -denominator : denominator;
                    negative<=numerator[WIDTH-1]^denominator[WIDTH-1];
                    remainder<=0; bits_left<=WIDTH; finish_sign<=0; busy<=1;
                end
            end else if(busy) begin
                if(finish_sign) begin
                    quotient<=negative ? -$signed(q_work) : $signed(q_work);
                    busy<=0; done<=1; finish_sign<=0;
                end else begin
                    remainder<=subtract_ok ? difference[WIDTH:0] : trial;
                    q_work<={q_work[WIDTH-2:0],subtract_ok};
                    bits_left<=bits_left-1'b1;
                    if(bits_left==1) finish_sign<=1;
                end
            end
        end
    end
endmodule

// Exact signed 64x64 product. Sixteen 17x17 limb multipliers feed a registered
// reduction tree. The highest 16-bit limb is signed; the others are positive.
// Each reduction is modulo 2^128, preserving the exact two's-complement product.
module mvdr_mul64_pipeline(
    input wire clk, rst, in_valid,
    input wire signed [63:0] a,b,
    output wire out_valid,
    output reg signed [127:0] product
);
    reg [4:0] valid_pipe;
    reg signed [33:0] partial[0:15];
    wire signed [127:0] aligned[0:15];
    reg signed [127:0] sum8[0:7], sum4[0:3], sum2[0:1];
    genvar i,j,k;
    generate for(i=0;i<4;i=i+1) begin : a_limb
        for(j=0;j<4;j=j+1) begin : b_limb
            wire signed [16:0] aa={(i==3) ? a[63] : 1'b0,a[i*16 +: 16]};
            wire signed [16:0] bb={(j==3) ? b[63] : 1'b0,b[j*16 +: 16]};
            always @(posedge clk) if(in_valid) partial[i*4+j]<=aa*bb;
            assign aligned[i*4+j]=$signed({{94{partial[i*4+j][33]}},partial[i*4+j]}) <<< ((i+j)*16);
        end
    end
    for(k=0;k<8;k=k+1) begin : level8
        always @(posedge clk) if(valid_pipe[0]) sum8[k]<=aligned[2*k]+aligned[2*k+1];
    end
    for(k=0;k<4;k=k+1) begin : level4
        always @(posedge clk) if(valid_pipe[1]) sum4[k]<=sum8[2*k]+sum8[2*k+1];
    end
    for(k=0;k<2;k=k+1) begin : level2
        always @(posedge clk) if(valid_pipe[2]) sum2[k]<=sum4[2*k]+sum4[2*k+1];
    end endgenerate
    always @(posedge clk) begin
        if(rst) valid_pipe<=0;
        else valid_pipe<={valid_pipe[3:0],in_valid};
        if(valid_pipe[3]) product<=sum2[0]+sum2[1];
    end
    assign out_valid=valid_pipe[4];
endmodule

// Shared complex multiplier, normal or conjugate-B. Four scalar products are
// issued in consecutive clocks to the same pipeline. Sums retain 129 bits.
module mvdr_complex_multiplier(
    input wire clk,rst,start,conjugate_b,
    input wire signed [63:0] a_re,a_im,b_re,b_im,
    output reg busy,done,
    output reg signed [128:0] result_re,result_im
);
    reg signed [63:0] ar,ai,br,bi;
    reg conj;
    reg [2:0] issue_idx,receive_idx;
    reg signed [127:0] p0,p2;
    wire mul_valid=busy && issue_idx<4;
    wire signed [63:0] ma=(issue_idx==0 || issue_idx==3) ? ar : ai;
    wire signed [63:0] mb=(issue_idx==0 || issue_idx==2) ? br : bi;
    wire scalar_valid;
    wire signed [127:0] scalar_product;
    wire signed [128:0] scalar_ext={scalar_product[127],scalar_product};
    wire signed [128:0] p0_ext={p0[127],p0};
    wire signed [128:0] p2_ext={p2[127],p2};
    mvdr_mul64_pipeline u_scalar(
        .clk(clk),.rst(rst),.in_valid(mul_valid),.a(ma),.b(mb),
        .out_valid(scalar_valid),.product(scalar_product));
    always @(posedge clk) begin
        if(rst) begin
            busy<=0; done<=0; issue_idx<=0; receive_idx<=0;
            ar<=0; ai<=0; br<=0; bi<=0; conj<=0;
            p0<=0; p2<=0; result_re<=0; result_im<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                ar<=a_re; ai<=a_im; br<=b_re; bi<=b_im; conj<=conjugate_b;
                issue_idx<=0; receive_idx<=0; busy<=1;
            end else if(busy) begin
                if(issue_idx<4) issue_idx<=issue_idx+1'b1;
                if(scalar_valid) begin
                    case(receive_idx)
                        0: p0<=scalar_product;
                        1: result_re<=conj ? p0_ext+scalar_ext : p0_ext-scalar_ext;
                        2: p2<=scalar_product;
                        3: begin
                            result_im<=conj ? p2_ext-scalar_ext : p2_ext+scalar_ext;
                            done<=1; busy<=0;
                        end
                    endcase
                    receive_idx<=receive_idx+1'b1;
                end
            end
        end
    end
endmodule

// Resource-shared fixed-point MVDR solver. The parallel input transaction is
// snapshotted once; the complex Q16.16 working matrix uses synchronous TDP RAM.
// Arithmetic intentionally preserves the preceding solver's truncation widths.
// solver_error pulses on a zero divisor; no weights_valid accompanies failure.
module mvdr_solver_stub #(
    parameter integer N_CH=16, ACC_W=48, WEIGHT_W=24, WEIGHT_FRAC=23,
    parameter integer LOADING_NUM=5, LOADING_DEN=100,
    parameter [N_CH-1:0] ACTIVE_MASK={N_CH{1'b1}}
)(
    input wire clk,rst,matrix_valid,
    input wire signed [N_CH*N_CH*ACC_W-1:0] r_re_bus,r_im_bus,
    input wire signed [N_CH*WEIGHT_W-1:0] steering_re_bus,steering_im_bus,
    output reg weights_valid,busy,
    output wire signed [N_CH*WEIGHT_W-1:0] weight_re_bus,weight_im_bus,
    output reg solver_error
);
    function integer count_active;
        input [N_CH-1:0] mask;
        integer ch;
        begin
            count_active=0;
            for(ch=0;ch<N_CH;ch=ch+1) count_active=count_active+mask[ch];
        end
    endfunction
    localparam integer ACTIVE_COUNT=count_active(ACTIVE_MASK);
    localparam integer IW=(N_CH<=2) ? 1 : $clog2(N_CH);
    localparam integer MW=(N_CH*N_CH<=2) ? 1 : $clog2(N_CH*N_CH);
    localparam [5:0] IDLE=0,TRACE=1,MEAN_SETUP=2,MEAN_DONE=3,
        DELTA_SETUP=4,DELTA_DONE=5,LOAD_SETUP=6,LOAD_RE_DONE=7,
        LOAD_IM_SETUP=8,LOAD_IM_DONE=9,LOAD_WRITE=10,LOAD_VECTOR=11,
        PIVOT_READ=12,PIVOT_LATCH=13,PIVOT_RESULT=14,
        NORM_READ=15,NORM_LATCH=16,NORM_PRODUCT=17,NORM_RE_DONE=18,
        NORM_IM_DONE=19,NORM_WRITE=20,NORM_VECTOR_SETUP=21,
        ELIM_CHECK=22,FACTOR_READ=23,FACTOR_LATCH=24,ELIM_READ=25,
        ELIM_LATCH=26,ELIM_PRODUCT=27,ELIM_WRITE=28,
        ELIM_VECTOR_SETUP=29,ELIM_VECTOR_RESULT=30,
        DENOM_INIT=31,DENOM_SETUP=32,DENOM_RESULT=33,
        OUTPUT_SETUP=34,OUTPUT_RE_DONE=35,OUTPUT_IM_DONE=36,OUTPUT_WRITE=37,
        DIV_LAUNCH=38,DIV_WAIT=39,MUL_LAUNCH=40,MUL_WAIT=41,FAIL=42,LOAD_SELECT=43;
    reg [5:0] state,div_return,mul_return;
    reg signed [N_CH*N_CH*ACC_W-1:0] raw_re_latched,raw_im_latched;
    reg signed [N_CH*WEIGHT_W-1:0] steer_re_latched,steer_im_latched;
    reg signed [63:0] vr[0:N_CH-1],vi[0:N_CH-1];
    reg signed [63:0] trace_sum,mean_power,delta,denominator;
    reg signed [63:0] pivot_re,pivot_im,factor_re,factor_im;
    reg signed [63:0] target_re,target_im,norm_re,norm_im;
    reg signed [63:0] selected_load_re,selected_load_im;
    reg signed [128:0] pivot_norm,norm_im_numerator;
    reg signed [WEIGHT_W-1:0] output_re,output_im;
    reg [IW-1:0] trace_idx,load_i,load_j,pivot_idx,col_idx,denom_idx,output_idx;
    reg [IW:0] row_idx;
    reg normalizing_vector;

    // Read-first port A (read/write) and read-only port B. Neither RAM contents
    // nor read-data registers are reset. All locations are loaded before use.
    (* ram_style="block" *) reg [127:0] matrix_mem[0:N_CH*N_CH-1];
    reg [MW-1:0] ram_addr_a,ram_addr_b;
    reg ram_en_a,ram_en_b,ram_we_a;
    reg [127:0] ram_write_data;
    reg [127:0] ram_data_a,ram_data_b;
    wire signed [63:0] a_re=ram_data_a[63:0],a_im=ram_data_a[127:64];
    wire signed [63:0] b_re=ram_data_b[63:0],b_im=ram_data_b[127:64];
    always @* begin
        ram_addr_a=0; ram_addr_b=0; ram_en_a=0; ram_en_b=0;
        ram_we_a=0; ram_write_data={norm_im,norm_re};
        case(state)
            LOAD_WRITE: begin
                ram_en_a=1; ram_we_a=1; ram_addr_a=load_i*N_CH+load_j;
            end
            PIVOT_READ: begin ram_en_a=1; ram_addr_a=pivot_idx*N_CH+pivot_idx; end
            NORM_READ: begin ram_en_a=1; ram_addr_a=pivot_idx*N_CH+col_idx; end
            NORM_WRITE: if(!normalizing_vector) begin
                ram_en_a=1; ram_we_a=1; ram_addr_a=pivot_idx*N_CH+col_idx;
            end
            FACTOR_READ: begin ram_en_a=1; ram_addr_a=row_idx*N_CH+pivot_idx; end
            ELIM_READ: begin
                ram_en_a=1; ram_addr_a=row_idx*N_CH+col_idx;
                ram_en_b=1; ram_addr_b=pivot_idx*N_CH+col_idx;
            end
            ELIM_WRITE: begin
                ram_en_a=1; ram_we_a=1; ram_addr_a=row_idx*N_CH+col_idx;
                ram_write_data={target_im,target_re};
            end
        endcase
    end
    always @(posedge clk) if(!rst && ram_en_a) begin
        if(ram_we_a) matrix_mem[ram_addr_a]<=ram_write_data;
        ram_data_a<=matrix_mem[ram_addr_a];
    end
    always @(posedge clk) if(!rst && ram_en_b) ram_data_b<=matrix_mem[ram_addr_b];

    reg div_start,mul_start;
    reg signed [128:0] div_numerator,div_denominator;
    wire div_busy,div_done,div_zero;
    wire signed [128:0] div_quotient;
    reg signed [63:0] mul_ar,mul_ai,mul_br,mul_bi;
    reg mul_conjugate;
    wire mul_busy,mul_done;
    wire signed [128:0] mul_re,mul_im;
    mvdr_signed_divider #(.WIDTH(129)) u_divider(
        .clk(clk),.rst(rst),.start(div_start),.numerator(div_numerator),
        .denominator(div_denominator),.busy(div_busy),.done(div_done),
        .divide_by_zero(div_zero),.quotient(div_quotient));
    mvdr_complex_multiplier u_multiplier(
        .clk(clk),.rst(rst),.start(mul_start),.conjugate_b(mul_conjugate),
        .a_re(mul_ar),.a_im(mul_ai),.b_re(mul_br),.b_im(mul_bi),
        .busy(mul_busy),.done(mul_done),.result_re(mul_re),.result_im(mul_im));

    wire signed [63:0] raw_trace=ACTIVE_MASK[trace_idx] ? $signed(raw_re_latched[(trace_idx*N_CH+trace_idx)*ACC_W +: ACC_W]) : 64'sd0;
    wire load_active=ACTIVE_MASK[load_i] && ACTIVE_MASK[load_j];
    wire signed [63:0] raw_load_re=load_active ? $signed(raw_re_latched[(load_i*N_CH+load_j)*ACC_W +: ACC_W]) : 64'sd0;
    wire signed [63:0] raw_load_im=load_active ? $signed(raw_im_latched[(load_i*N_CH+load_j)*ACC_W +: ACC_W]) : 64'sd0;
    // Inactive rows form a disconnected identity block after normalization.
    // This cannot affect active weights and avoids a spurious zero pivot when
    // integer diagonal loading truncates to zero. Active arithmetic is unchanged.
    wire signed [63:0] diagonal_load=ACTIVE_MASK[load_i] ? delta : mean_power;
    wire signed [127:0] load_re_wide=$signed({{64{selected_load_re[63]}},selected_load_re})+
        ((load_i==load_j) ? $signed({{64{diagonal_load[63]}},diagonal_load}) : 128'sd0);
    wire signed [127:0] load_im_wide={{64{selected_load_im[63]}},selected_load_im};
    wire signed [127:0] load_re_shift=load_re_wide<<<16;
    wire signed [127:0] load_im_shift=load_im_wide<<<16;
    wire signed [63:0] loading_product=mean_power*LOADING_NUM;
    wire signed [63:0] steer_load_re=ACTIVE_MASK[load_i] ? $signed(steer_re_latched[load_i*WEIGHT_W +: WEIGHT_W]) : 64'sd0;
    wire signed [63:0] steer_load_im=ACTIVE_MASK[load_i] ? $signed(steer_im_latched[load_i*WEIGHT_W +: WEIGHT_W]) : 64'sd0;
    wire signed [63:0] steer_denom_re=ACTIVE_MASK[denom_idx] ? $signed(steer_re_latched[denom_idx*WEIGHT_W +: WEIGHT_W]) : 64'sd0;
    wire signed [63:0] steer_denom_im=ACTIVE_MASK[denom_idx] ? $signed(steer_im_latched[denom_idx*WEIGHT_W +: WEIGHT_W]) : 64'sd0;
    wire signed [127:0] mul_re_128=mul_re[127:0],mul_im_128=mul_im[127:0];
    wire signed [63:0] out_re_shift=vr[output_idx]<<<(WEIGHT_FRAC+16);
    wire signed [63:0] out_im_shift=vi[output_idx]<<<(WEIGHT_FRAC+16);

    // Static output slices with per-channel enables avoid wide variable writes.
    genvar wch;
    generate for(wch=0;wch<N_CH;wch=wch+1) begin : weights
        reg signed [WEIGHT_W-1:0] re_word,im_word;
        always @(posedge clk) begin
            if(rst || state==FAIL || !ACTIVE_MASK[wch]) begin re_word<=0; im_word<=0; end
            else if(state==OUTPUT_WRITE && output_idx==wch) begin
                re_word<=output_re; im_word<=output_im;
            end
        end
        assign weight_re_bus[wch*WEIGHT_W +: WEIGHT_W]=re_word;
        assign weight_im_bus[wch*WEIGHT_W +: WEIGHT_W]=im_word;
    end endgenerate

    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE; busy<=0; weights_valid<=0; solver_error<=0;
            div_start<=0; mul_start<=0; trace_idx<=0; trace_sum<=0;
            load_i<=0; load_j<=0; pivot_idx<=0; col_idx<=0;
            row_idx<=0; denom_idx<=0; output_idx<=0; normalizing_vector<=0;
        end else begin
            weights_valid<=0; solver_error<=0; div_start<=0; mul_start<=0;
            case(state)
                IDLE: begin
                    busy<=0;
                    if(matrix_valid) begin
                        raw_re_latched<=r_re_bus; raw_im_latched<=r_im_bus;
                        steer_re_latched<=steering_re_bus; steer_im_latched<=steering_im_bus;
                        trace_sum<=0; trace_idx<=0; busy<=1; state<=TRACE;
                    end
                end
                TRACE: begin
                    trace_sum<=trace_sum+raw_trace;
                    if(trace_idx==N_CH-1) state<=MEAN_SETUP;
                    else trace_idx<=trace_idx+1'b1;
                end
                MEAN_SETUP: begin
                    div_numerator<=trace_sum; div_denominator<=ACTIVE_COUNT;
                    div_return<=MEAN_DONE; state<=DIV_LAUNCH;
                end
                MEAN_DONE: begin
                    mean_power<=($signed(div_quotient[63:0])==0) ? 64'sd1 : $signed(div_quotient[63:0]);
                    state<=DELTA_SETUP;
                end
                DELTA_SETUP: begin
                    div_numerator<=loading_product; div_denominator<=LOADING_DEN;
                    div_return<=DELTA_DONE; state<=DIV_LAUNCH;
                end
                DELTA_DONE: begin delta<=div_quotient[63:0]; load_i<=0; load_j<=0; state<=LOAD_SELECT; end
                LOAD_SELECT: begin
                    selected_load_re<=raw_load_re; selected_load_im<=raw_load_im;
                    state<=LOAD_SETUP;
                end
                LOAD_SETUP: begin
                    div_numerator<={load_re_shift[127],load_re_shift}; div_denominator<=mean_power;
                    div_return<=LOAD_RE_DONE; state<=DIV_LAUNCH;
                end
                LOAD_RE_DONE: begin norm_re<=div_quotient[63:0]; state<=LOAD_IM_SETUP; end
                LOAD_IM_SETUP: begin
                    div_numerator<={load_im_shift[127],load_im_shift};
                    div_return<=LOAD_IM_DONE; state<=DIV_LAUNCH;
                end
                LOAD_IM_DONE: begin norm_im<=div_quotient[63:0]; state<=LOAD_WRITE; end
                LOAD_WRITE: begin
                    if(load_j==N_CH-1) begin
                        load_j<=0;
                        if(load_i==N_CH-1) begin load_i<=0; state<=LOAD_VECTOR; end
                        else begin load_i<=load_i+1'b1; state<=LOAD_SELECT; end
                    end else begin load_j<=load_j+1'b1; state<=LOAD_SELECT; end
                end
                LOAD_VECTOR: begin
                    vr[load_i]<=steer_load_re>>>(WEIGHT_FRAC-16);
                    vi[load_i]<=steer_load_im>>>(WEIGHT_FRAC-16);
                    if(load_i==N_CH-1) begin pivot_idx<=0; state<=PIVOT_READ; end
                    else load_i<=load_i+1'b1;
                end
                PIVOT_READ: state<=PIVOT_LATCH;
                PIVOT_LATCH: begin
                    pivot_re<=a_re; pivot_im<=a_im;
                    mul_ar<=a_re; mul_ai<=a_im; mul_br<=a_re; mul_bi<=a_im;
                    mul_conjugate<=1; mul_return<=PIVOT_RESULT; state<=MUL_LAUNCH;
                end
                PIVOT_RESULT: begin
                    pivot_norm<=mul_re; col_idx<=pivot_idx;
                    if(mul_re==0) state<=FAIL; else state<=NORM_READ;
                end
                NORM_READ: state<=NORM_LATCH;
                NORM_LATCH: begin
                    mul_ar<=a_re; mul_ai<=a_im; mul_br<=pivot_re; mul_bi<=pivot_im;
                    mul_conjugate<=1; normalizing_vector<=0;
                    mul_return<=NORM_PRODUCT; state<=MUL_LAUNCH;
                end
                NORM_VECTOR_SETUP: begin
                    mul_ar<=vr[pivot_idx]; mul_ai<=vi[pivot_idx];
                    mul_br<=pivot_re; mul_bi<=pivot_im;
                    mul_conjugate<=1; normalizing_vector<=1;
                    mul_return<=NORM_PRODUCT; state<=MUL_LAUNCH;
                end
                NORM_PRODUCT: begin
                    div_numerator<=mul_re<<<16; norm_im_numerator<=mul_im<<<16;
                    div_denominator<=pivot_norm; div_return<=NORM_RE_DONE; state<=DIV_LAUNCH;
                end
                NORM_RE_DONE: begin
                    norm_re<=div_quotient[63:0]; div_numerator<=norm_im_numerator;
                    div_return<=NORM_IM_DONE; state<=DIV_LAUNCH;
                end
                NORM_IM_DONE: begin norm_im<=div_quotient[63:0]; state<=NORM_WRITE; end
                NORM_WRITE: begin
                    if(normalizing_vector) begin
                        vr[pivot_idx]<=norm_re; vi[pivot_idx]<=norm_im;
                        row_idx<=0; state<=ELIM_CHECK;
                    end else if(col_idx==N_CH-1) state<=NORM_VECTOR_SETUP;
                    else begin col_idx<=col_idx+1'b1; state<=NORM_READ; end
                end
                ELIM_CHECK: begin
                    if(row_idx==N_CH) begin
                        if(pivot_idx==N_CH-1) state<=DENOM_INIT;
                        else begin pivot_idx<=pivot_idx+1'b1; state<=PIVOT_READ; end
                    end else if(row_idx==pivot_idx) row_idx<=row_idx+1'b1;
                    else state<=FACTOR_READ;
                end
                FACTOR_READ: state<=FACTOR_LATCH;
                FACTOR_LATCH: begin
                    factor_re<=a_re; factor_im<=a_im;
                    if(pivot_idx==N_CH-1) state<=ELIM_VECTOR_SETUP;
                    else begin col_idx<=pivot_idx+1'b1; state<=ELIM_READ; end
                end
                ELIM_READ: state<=ELIM_LATCH;
                ELIM_LATCH: begin
                    target_re<=a_re; target_im<=a_im;
                    mul_ar<=factor_re; mul_ai<=factor_im; mul_br<=b_re; mul_bi<=b_im;
                    mul_conjugate<=0; mul_return<=ELIM_PRODUCT; state<=MUL_LAUNCH;
                end
                ELIM_PRODUCT: begin
                    target_re<=target_re-(mul_re_128>>>16);
                    target_im<=target_im-(mul_im_128>>>16); state<=ELIM_WRITE;
                end
                ELIM_WRITE: begin
                    if(col_idx==N_CH-1) state<=ELIM_VECTOR_SETUP;
                    else begin col_idx<=col_idx+1'b1; state<=ELIM_READ; end
                end
                ELIM_VECTOR_SETUP: begin
                    target_re<=vr[row_idx]; target_im<=vi[row_idx];
                    mul_ar<=factor_re; mul_ai<=factor_im;
                    mul_br<=vr[pivot_idx]; mul_bi<=vi[pivot_idx];
                    mul_conjugate<=0; mul_return<=ELIM_VECTOR_RESULT; state<=MUL_LAUNCH;
                end
                ELIM_VECTOR_RESULT: begin
                    vr[row_idx]<=target_re-(mul_re_128>>>16);
                    vi[row_idx]<=target_im-(mul_im_128>>>16);
                    row_idx<=row_idx+1'b1; state<=ELIM_CHECK;
                end
                DENOM_INIT: begin denominator<=0; denom_idx<=0; state<=DENOM_SETUP; end
                DENOM_SETUP: begin
                    mul_ar<=steer_denom_re; mul_ai<=steer_denom_im;
                    mul_br<=vr[denom_idx]; mul_bi<=vi[denom_idx];
                    mul_conjugate<=1; mul_return<=DENOM_RESULT; state<=MUL_LAUNCH;
                end
                DENOM_RESULT: begin
                    denominator<=denominator+(mul_re_128>>>(WEIGHT_FRAC-16));
                    if(denom_idx==N_CH-1) begin output_idx<=0; state<=OUTPUT_SETUP; end
                    else begin denom_idx<=denom_idx+1'b1; state<=DENOM_SETUP; end
                end
                OUTPUT_SETUP: begin
                    div_numerator<=out_re_shift; div_denominator<=denominator;
                    div_return<=OUTPUT_RE_DONE; state<=DIV_LAUNCH;
                end
                OUTPUT_RE_DONE: begin
                    output_re<=div_quotient[WEIGHT_W-1:0]; div_numerator<=out_im_shift;
                    div_return<=OUTPUT_IM_DONE; state<=DIV_LAUNCH;
                end
                OUTPUT_IM_DONE: begin output_im<=div_quotient[WEIGHT_W-1:0]; state<=OUTPUT_WRITE; end
                OUTPUT_WRITE: begin
                    if(output_idx==N_CH-1) begin weights_valid<=1; busy<=0; state<=IDLE; end
                    else begin output_idx<=output_idx+1'b1; state<=OUTPUT_SETUP; end
                end
                DIV_LAUNCH: begin div_start<=1; state<=DIV_WAIT; end
                DIV_WAIT: if(div_done) begin
                    if(div_zero) state<=FAIL; else state<=div_return;
                end
                MUL_LAUNCH: begin mul_start<=1; state<=MUL_WAIT; end
                MUL_WAIT: if(mul_done) state<=mul_return;
                FAIL: begin solver_error<=1; weights_valid<=0; busy<=0; state<=IDLE; end
                default: state<=FAIL;
            endcase
        end
    end
endmodule
