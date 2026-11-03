`timescale 1ns/1ps
// Reusable 32-lane engine: INT8 weights, INT16 activations, front two Conv and complete first C3.
module c3_udp_engine(input clk,resetn,mac_clk,rec_en,rec_pkt_done,
 input [31:0] rec_data,input [15:0] rec_byte_num,input tx_req,tx_done,
 output tx_start_en,output [15:0] tx_byte_num,output [31:0] tx_data);
wire [4:0] led;
wire [31:0] awaddr,wdata,araddr; wire [7:0] awlen,arlen;
wire awvalid,wvalid,wlast,bready,arvalid,rready;
wire awid,arid; wire [3:0] wstrb;
wire awready,wready,arready;
reg bvalid=0,rvalid=0,rlast=0; reg bid=0,rid=0; reg [31:0] rdata=0;
assign awid=0;assign arid=0;assign wstrb=15;
udp_axi_endpoint endpoint(.clk(clk),.resetn(resetn),.mac_clk(mac_clk),
 .rec_en(rec_en),.rec_pkt_done(rec_pkt_done),.rec_data(rec_data),.rec_byte_num(rec_byte_num),
 .tx_req(tx_req),.tx_done(tx_done),.tx_start_en(tx_start_en),.tx_byte_num(tx_byte_num),.tx_data(tx_data),
 .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
 .wdata(wdata),.wvalid(wvalid),.wlast(wlast),.wready(wready),.bvalid(bvalid),.bready(bready),
 .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
 .rdata(rdata),.rvalid(rvalid),.rlast(rlast),.rready(rready));
// Host uses aligned full-word INCR transfers, single outstanding read/write.
reg writing=0,reading=0,read_delay=0; reg [31:0] wa=0,ra=0; reg [7:0] left=0;
assign awready=resetn && !writing && !bvalid;
assign wready=resetn && writing;
assign arready=resetn && !reading && !rvalid;



reg [15:0] b1even_q,b1odd_q,b0even_q,b0odd_q;
wire [31:0] result_q={b0odd_q,b0even_q};
reg signed [31:0] debug_acc[0:59];
reg [31:0] stage_ends[0:14];
reg [31:0] nonce=0,cycles=0;
reg start=0,done=0,busy=0;
// Separate synchronous memory read permits true BRAM inference.

always @(posedge clk) begin
    start<=0;
    if(!resetn) begin writing<=0; reading<=0; bvalid<=0; rvalid<=0; nonce<=0; end
    else begin
        if(awvalid && awready) begin writing<=1;wa<=awaddr;bid<=awid;end
        if(wvalid && wready) begin

            if(wa==4) nonce<=wdata;
            if(wa==0 && wdata==1 && !busy) start<=1;
            wa<=wa+4;
            if(wlast) begin writing<=0;bvalid<=1;end
        end
        if(bvalid && bready) bvalid<=0;
        if(arvalid && arready) begin reading<=1;read_delay<=0;ra<=araddr;left<=arlen;rid<=arid;end
        if(reading && !rvalid && !read_delay) read_delay<=1;
        if(reading && !rvalid && read_delay) begin
            // Extra cycle ensures result_q corresponds to the new read address.
            reading<=0;rvalid<=1;rlast<=(left==0);
            if(ra[23:20]==4) rdata<=result_q;
            else if(ra[15:12]==1) rdata<=debug_acc[ra[7:2]];
            else if(ra[15:12]==2) rdata<=stage_ends[ra[5:2]];
            else case(ra[7:2])
                0:rdata<={30'd0,busy,done};
                1:rdata<=nonce;
                2:rdata<=cycles;
                3:rdata<=32'h594f4c47;
                default:rdata<=0;
            endcase
        end
        if(rvalid && rready) begin
            rvalid<=0;
            if(left!=0) begin ra<=ra+4;left<=left-1;reading<=1;read_delay<=0;end
        end
    end
end
`include "constants.vh"
reg [3:0] state=0,stage=0;
reg [6:0] ox=0,oy=0;
reg [8:0] tap=0;
reg [5:0] ic=0,wc=0,ic_q=0,ic_bq=0;
reg group=0;
reg [2:0] kx=0,ky=0;
wire [2:0] kernel=stage==0?6:((stage==1||stage==4||stage==7||stage==10||stage==12)?3:1);
wire [2:0] pad=stage==0?2:((stage==1||stage==4||stage==7||stage==10||stage==12)?1:0);
wire [8:0] in_size=stage==0?256:(stage==1?128:(stage<=7?64:32));
wire [6:0] last_xy=stage==0?127:(stage<=6?63:31);
wire [5:0] last_c=(stage==7||stage==14)?63:((stage==1||stage==6||stage>=8)?31:15);
wire [5:0] group_last=group?last_c:(last_c>31?6'd31:last_c);
wire [8:0] last_tap=stage==0?107:((stage==1||stage==4)?143:
 ((stage==7||stage==10||stage==12)?287:(stage==3?15:((stage==8||stage==13||stage==14)?63:31))));
wire stride2=(stage<2||stage==7);
wire [2:0] bx=kx==kernel-1?3'd0:kx+1'b1;
wire [2:0] by=kx==kernel-1?(ky==kernel-1?3'd0:ky+1'b1):ky;
wire [5:0] bi=ic+((kx==kernel-1)&&(ky==kernel-1));
wire [2:0] nx=bx==kernel-1?3'd0:bx+1'b1;
wire [2:0] ny=bx==kernel-1?(by==kernel-1?3'd0:by+1'b1):by;
wire [5:0] ni=bi+((bx==kernel-1)&&(by==kernel-1));
wire [9:0] py=(stride2?{2'b0,oy,1'b0}:{3'b0,oy})+ky;
wire [9:0] px=(stride2?{2'b0,ox,1'b0}:{3'b0,ox})+kx;
wire [9:0] pyb=(stride2?{2'b0,oy,1'b0}:{3'b0,oy})+by;
wire [9:0] pxb=(stride2?{2'b0,ox,1'b0}:{3'b0,ox})+bx;
wire inside=py>=pad&&py<in_size+pad&&px>=pad&&px<in_size+pad;
wire inside_b=pyb>=pad&&pyb<in_size+pad&&pxb>=pad&&pxb<in_size+pad;
wire [7:0] iy=py-pad,ix=px-pad,iyb=pyb-pad,ixb=pxb-pad;
function [17:0] input_address;
 input [7:0] y,x;input [5:0] channel;
 begin
  if(stage==1) input_address={y[6:0],x[6:0],channel[3:0]};
  else if(stage==2||stage==5||stage==7) input_address={1'b0,y[5:0],x[5:0],channel[4:0]};
  else if(stage<=6) input_address={2'b0,y[5:0],x[5:0],channel[3:0]};
  else if(stage==8||stage==13) input_address={2'b0,y[4:0],x[4:0],channel};
  else input_address={3'b0,y[4:0],x[4:0],channel[4:0]};
 end
endfunction
wire [17:0] in_address=input_address(iy,ix,ic);
wire [17:0] in_address_b=input_address(iyb,ixb,bi);
wire [17:0] issue_address=stage==0?{oy,ox,wc[3:0]}:
 ((stage==1||stage==6)?{1'b0,oy[5:0],ox[5:0],wc[4:0]}:
 (stage<=6?{2'b0,oy[5:0],ox[5:0],wc[3:0]}:
 ((stage==7||stage==14)?{2'b0,oy[4:0],ox[4:0],wc}:{3'b0,oy[4:0],ox[4:0],wc[4:0]})));

// Three 8-bit planes retain the same image capacity with two read ports.
(* ram_style="block" *) reg [7:0] pixels_r[0:65535],pixels_g[0:65535],pixels_b[0:65535];
reg [7:0] rqa,gqa,bqa,rqb,gqb,bqb;
wire pixel_write=resetn&&wvalid&&wready&&wa[23:20]==1&&!busy;
wire [15:0] pixel_a_address=pixel_write?wa[17:2]:{iy,ix};
always @(posedge clk) begin
 if(pixel_write||(busy&&stage==0)) begin
  if(pixel_write) begin pixels_r[pixel_a_address]<=wdata[7:0];pixels_g[pixel_a_address]<=wdata[15:8];pixels_b[pixel_a_address]<=wdata[23:16];end
  rqa<=pixels_r[pixel_a_address];gqa<=pixels_g[pixel_a_address];bqa<=pixels_b[pixel_a_address];
 end
end
always @(posedge clk) if(busy&&stage==0) begin rqb<=pixels_r[{iyb,ixb}];gqb<=pixels_g[{iyb,ixb}];bqb<=pixels_b[{iyb,ixb}];end

(* ram_style="block" *) reg [15:0] bank0even[0:131071],bank0odd[0:131071];
(* ram_style="block" *) reg [15:0] bank1even[0:65535],bank1odd[0:65535];
(* ram_style="block" *) reg [15:0] bank2[0:65535],bank3[0:65535];
reg [15:0] b0even_bq,b0odd_bq,b1even_bq,b1odd_bq,b2q,b3q,b2bq,b3bq;
reg b0_select=0,b1_select=0,b0_bselect=0,b1_bselect=0;
reg [17:0] address0=0,address1=0,address2=0;
reg [5:0] channel0=0,channel1=0,channel2=0;
reg valid0=0,valid1=0,valid2=0;
wire [17:0] store_address=address2;
wire write_result=valid2&&resetn;
wire store0=write_result&&(stage==0||stage==2||stage==7||stage==14);
wire store1=write_result&&(stage==1||stage==6||stage==8||stage==12);
wire store2=write_result&&(stage==3||stage==5||stage==9||stage==11||stage==13);
wire store3=write_result&&(stage==4||stage==10);
wire use0=stage==1||stage==3||stage==8||stage==13;
wire use1=stage==2||stage==5||stage==7||stage==9||stage==14;
wire use2=stage==4||stage==6||stage==10||stage==12||stage==14;
wire use3=stage==6||stage==11;
wire [17:0] b0addr=stage==4?address1:in_address;
wire [16:0] b0read=busy?b0addr[17:1]:ra[18:2];
wire [16:0] b1addr=stage==10?address1[16:0]:in_address[16:0];
wire [15:0] b3addr=stage==12?address1[15:0]:in_address[15:0];
wire [15:0] quant_value;
wire [16:0] b0portb=store0?store_address[17:1]:in_address_b[17:1];
wire [15:0] b1portb=store1?store_address[16:1]:in_address_b[16:1];
wire [15:0] b2portb=store2?store_address[15:0]:in_address_b[15:0];
wire [15:0] b3portb=store3?store_address[15:0]:in_address_b[15:0];
// Port A reads; port B writes in destination stages and reads in source stages.
always @(posedge clk) begin
 if(!busy||use0||stage==4) begin b0even_q<=bank0even[b0read];b0odd_q<=bank0odd[b0read];end
 b0_select<=b0addr[0];b0_bselect<=in_address_b[0];
 if(use1||stage==10) begin b1even_q<=bank1even[b1addr[16:1]];b1odd_q<=bank1odd[b1addr[16:1]];end
 b1_select<=b1addr[0];b1_bselect<=in_address_b[0];
 if(use2) b2q<=bank2[in_address[15:0]];
 if(use3||stage==12) b3q<=bank3[b3addr];
end
always @(posedge clk) begin
 if(store0||(busy&&use0)) begin
  if(store0&&!store_address[0]) bank0even[b0portb]<=quant_value;
  if(store0&&store_address[0]) bank0odd[b0portb]<=quant_value;
  b0even_bq<=bank0even[b0portb];b0odd_bq<=bank0odd[b0portb];
 end
 if(store1||(busy&&use1)) begin
  if(store1&&!store_address[0]) bank1even[b1portb]<=quant_value;
  if(store1&&store_address[0]) bank1odd[b1portb]<=quant_value;
  b1even_bq<=bank1even[b1portb];b1odd_bq<=bank1odd[b1portb];
 end
 if(store2||(busy&&use2)) begin
  if(store2) bank2[b2portb]<=quant_value;
  b2bq<=bank2[b2portb];
 end
 if(store3||(busy&&use3)) begin
  if(store3) bank3[b3portb]<=quant_value;
  b3bq<=bank3[b3portb];
 end
end
wire [15:0] b0q=b0_select?b0odd_q:b0even_q;
wire [15:0] b1q=b1_select?b1odd_q:b1even_q;
wire [15:0] b0bq=b0_bselect?b0odd_bq:b0even_bq;
wire [15:0] b1bq=b1_bselect?b1odd_bq:b1even_bq;
wire [7:0] rgb=ic_q==0?rqa:(ic_q==1?gqa:bqa);
wire [7:0] rgb_b=ic_bq==0?rqb:(ic_bq==1?gqb:bqb);
wire [15:0] feature=(stage==1||stage==3||stage==8||stage==13)?b0q:
 ((stage==2||stage==5||stage==7||stage==9)?b1q:
 ((stage==4||stage==10||stage==12)?b2q:
 (stage==11?b3q:(stage==14?(ic_q[5]?b2q:b1q):(ic_q[4]?b2q:b3q)))));
wire [15:0] feature_b=(stage==1||stage==3||stage==8||stage==13)?b0bq:
 ((stage==2||stage==5||stage==7||stage==9)?b1bq:
 ((stage==4||stage==10||stage==12)?b2bq:
 (stage==11?b3bq:(stage==14?(ic_bq[5]?b2bq:b1bq):(ic_bq[4]?b2bq:b3bq)))));
reg zero_q=0,zero_bq=0,mac_valid=0;
always @(posedge clk) begin
 if(!resetn) mac_valid<=0;else mac_valid<=state==2;
 if(state==2) begin ic_q<=ic;ic_bq<=bi;zero_q<=!inside;zero_bq<=!inside_b;end
end
// Keep the selected value at its native signed width. Vivado 2018.3 can
// incorrectly remove the replicated sign bit in nested 17-bit ternaries.
wire signed [15:0] pixel_value=zero_q?16'd0:(stage==0?{8'd0,rgb}:feature);
wire signed [15:0] pixel_value_b=zero_bq?16'd0:(stage==0?{8'd0,rgb_b}:feature_b);
wire signed [31:0] accum[0:31];
wire [10:0] weight_address=WEIGHT_BASES[stage*12+:12]+(group?(last_tap+1'b1):9'd0)+tap;
genvar c;
generate for(c=0;c<32;c=c+1) begin:macs
 (* rom_style="block" *) reg signed [7:0] weights[0:2047];
 (* rom_style="distributed" *) reg signed [31:0] biases[0:31];
 reg signed [7:0] weight_q,weight_bq;
 (* use_dsp="yes" *) reg signed [31:0] acc_a,acc_b;
 (* use_dsp="no" *) reg signed [31:0] sum;
 wire signed [23:0] product_a=$signed(pixel_value)*$signed(weight_q);
 wire signed [23:0] product_b=$signed(pixel_value_b)*$signed(weight_bq);
 if(c==0) begin initial $readmemh("w0.mem",weights); initial $readmemh("bias0.mem",biases); end
 if(c==1) begin initial $readmemh("w1.mem",weights); initial $readmemh("bias1.mem",biases); end
 if(c==2) begin initial $readmemh("w2.mem",weights); initial $readmemh("bias2.mem",biases); end
 if(c==3) begin initial $readmemh("w3.mem",weights); initial $readmemh("bias3.mem",biases); end
 if(c==4) begin initial $readmemh("w4.mem",weights); initial $readmemh("bias4.mem",biases); end
 if(c==5) begin initial $readmemh("w5.mem",weights); initial $readmemh("bias5.mem",biases); end
 if(c==6) begin initial $readmemh("w6.mem",weights); initial $readmemh("bias6.mem",biases); end
 if(c==7) begin initial $readmemh("w7.mem",weights); initial $readmemh("bias7.mem",biases); end
 if(c==8) begin initial $readmemh("w8.mem",weights); initial $readmemh("bias8.mem",biases); end
 if(c==9) begin initial $readmemh("w9.mem",weights); initial $readmemh("bias9.mem",biases); end
 if(c==10) begin initial $readmemh("w10.mem",weights); initial $readmemh("bias10.mem",biases); end
 if(c==11) begin initial $readmemh("w11.mem",weights); initial $readmemh("bias11.mem",biases); end
 if(c==12) begin initial $readmemh("w12.mem",weights); initial $readmemh("bias12.mem",biases); end
 if(c==13) begin initial $readmemh("w13.mem",weights); initial $readmemh("bias13.mem",biases); end
 if(c==14) begin initial $readmemh("w14.mem",weights); initial $readmemh("bias14.mem",biases); end
 if(c==15) begin initial $readmemh("w15.mem",weights); initial $readmemh("bias15.mem",biases); end
 if(c==16) begin initial $readmemh("w16.mem",weights); initial $readmemh("bias16.mem",biases); end
 if(c==17) begin initial $readmemh("w17.mem",weights); initial $readmemh("bias17.mem",biases); end
 if(c==18) begin initial $readmemh("w18.mem",weights); initial $readmemh("bias18.mem",biases); end
 if(c==19) begin initial $readmemh("w19.mem",weights); initial $readmemh("bias19.mem",biases); end
 if(c==20) begin initial $readmemh("w20.mem",weights); initial $readmemh("bias20.mem",biases); end
 if(c==21) begin initial $readmemh("w21.mem",weights); initial $readmemh("bias21.mem",biases); end
 if(c==22) begin initial $readmemh("w22.mem",weights); initial $readmemh("bias22.mem",biases); end
 if(c==23) begin initial $readmemh("w23.mem",weights); initial $readmemh("bias23.mem",biases); end
 if(c==24) begin initial $readmemh("w24.mem",weights); initial $readmemh("bias24.mem",biases); end
 if(c==25) begin initial $readmemh("w25.mem",weights); initial $readmemh("bias25.mem",biases); end
 if(c==26) begin initial $readmemh("w26.mem",weights); initial $readmemh("bias26.mem",biases); end
 if(c==27) begin initial $readmemh("w27.mem",weights); initial $readmemh("bias27.mem",biases); end
 if(c==28) begin initial $readmemh("w28.mem",weights); initial $readmemh("bias28.mem",biases); end
 if(c==29) begin initial $readmemh("w29.mem",weights); initial $readmemh("bias29.mem",biases); end
 if(c==30) begin initial $readmemh("w30.mem",weights); initial $readmemh("bias30.mem",biases); end
 if(c==31) begin initial $readmemh("w31.mem",weights); initial $readmemh("bias31.mem",biases); end
 always @(posedge clk) begin
  weight_q<=weights[weight_address];weight_bq<=weights[weight_address+11'd1];
  if(state==1) begin acc_a<=biases[{stage,group}];acc_b<=0;end
  else if(mac_valid) begin acc_a<=acc_a+product_a;acc_b<=acc_b+product_b;end
  if(state==4) sum<=acc_a+acc_b;
 end
 assign accum[c]=sum;
end endgenerate

// One output is issued per clock. Scaling, lookup and writeback overlap.
(* rom_style="block" *) reg [15:0] silu[0:131071];
initial $readmemh("silu.mem",silu);
(* rom_style="block" *) reg [23:0] coefficients[0:1023];
initial $readmemh("coeff.mem",coefficients);
wire [5:0] coefficient_channel=(state==3||state==4)?{group,5'd0}:((state==5&&wc!=group_last)?wc+1'b1:wc);
reg [23:0] coefficient_q;
always @(posedge clk) coefficient_q<=coefficients[{stage,coefficient_channel}];
reg signed [55:0] scaled=0;
reg [12:0] lut_index=0;
reg [15:0] lut_q=0;
wire signed [32:0] grid=$signed(scaled[55:24])+33'sd4096;
always @(posedge clk) begin
 if(!resetn) begin valid0<=0;valid1<=0;valid2<=0;end
 else begin valid0<=state==5;valid1<=valid0;valid2<=valid1;end
 if(state==5) begin
  scaled<=accum[wc[4:0]]*$signed(coefficient_q);
  address0<=issue_address;channel0<=wc;
  if(oy==0&&ox==0&&wc<4) debug_acc[{stage,wc[1:0]}]<=accum[wc[4:0]];
 end
 if(valid0) begin lut_index<=grid<0?0:(grid>8191?8191:grid[12:0]);address1<=address0;channel1<=channel0;end
 if(valid1) begin lut_q<=silu[{stage,lut_index}];address2<=address1;channel2<=channel1;end
end
wire residual=stage==4||stage==10||stage==12;
wire [15:0] residual_value=stage==4?b0q:(stage==10?b1q:b3q);
wire signed [16:0] residual_sum=$signed({lut_q[15],lut_q})+$signed({residual_value[15],residual_value});
assign quant_value=!residual?lut_q:(residual_sum>32767?16'h7fff:(residual_sum < -32768?16'h8000:residual_sum[15:0]));
always @(posedge clk) begin
 if(!resetn) begin state<=0;busy<=0;done<=0;cycles<=0;stage<=0;group<=0;end
 else begin
  if(busy) cycles<=cycles+1;
  case(state)
   0:if(start) begin stage<=0;state<=1;busy<=1;done<=0;cycles<=0;ox<=0;oy<=0;group<=0;end
   1:begin tap<=0;ic<=0;kx<=0;ky<=0;state<=2;end
   2:if(tap+1'b1==last_tap) begin wc<={group,5'd0};state<=3;end
     else begin tap<=tap+9'd2;kx<=nx;ky<=ny;ic<=ni;end
   3:state<=4;
   4:state<=5;
   5:if(wc==group_last) state<=6;else wc<=wc+1'b1;
   6:state<=6;
   default:state<=0;
  endcase
  if(write_result&&channel2==group_last) begin
   if(!group&&last_c==63) begin group<=1;state<=1;end
   else begin
    group<=0;
    if(ox==last_xy) begin
     ox<=0;
     if(oy==last_xy) begin
      oy<=0;stage_ends[stage]<=cycles+1;
      if(stage==14) begin busy<=0;done<=1;state<=0;end else begin stage<=stage+1'b1;state<=1;end
     end else begin oy<=oy+1'b1;state<=1;end
    end else begin ox<=ox+1'b1;state<=1;end
   end
  end
 end
end

endmodule
