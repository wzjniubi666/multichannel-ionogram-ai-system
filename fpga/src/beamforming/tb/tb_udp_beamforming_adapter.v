`timescale 1ns/1ps
module tb_udp_beamforming_adapter;
    reg clk=0,rst=1,rx_valid=0,rx_last=0,rx_bad=0;
    reg [31:0] rx_data=0;
    wire rx_ready,tx_valid,tx_last,busy,sv,sof,eof,cancel;
    wire [31:0] tx_data;
    reg tx_ready=0,enable_tx=1,cr=1,ov=0,err=0;
    wire [255:0] ii,qq;
    wire [383:0] sr,si;
    reg [47:0] br=0,bi=0;
    reg [31:0] cfg[0:31],p0[0:263],p1[0:263],packet[0:299];
    reg [15:0] vi[0:511],vq[0:511];
    reg [23:0] vr[0:15],vm[0:15];
    reg [31:0] received[0:8191];
    integer lengths[0:127],starts[0:127];
    integer tick=0,words=0,replies=0,current_start=0,seen=0,captures=0,cancels=0;
    integer j,k,n,a,b;
    reg stalled=0;
    reg [31:0] held;
    reg held_last;
    always #5 clk=~clk;
    udp_beamforming_adapter #(.IDLE_TIMEOUT_CYCLES(100),.CORE_TIMEOUT_CYCLES(6000)) dut(
        .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_data(rx_data),
        .rx_last(rx_last),.rx_bad(rx_bad),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .tx_data(tx_data),.tx_last(tx_last),.sample_valid(sv),.frame_start(sof),.frame_end(eof),
        .in_i_bus(ii),.in_q_bus(qq),.steering_re_bus(sr),.steering_im_bus(si),
        .capture_ready(cr),.output_valid(ov),.solver_error(err),.beam_re(br),.beam_im(bi),
        .core_cancel(cancel),.busy(busy));
    always @(negedge clk) begin
        tick=tick+1; tx_ready=enable_tx && tick%5!=0; cr=(tick%7!=0);
    end
    always @(posedge clk) begin
        if(rst) stalled=0;
        else begin
            if(stalled && (!tx_valid || tx_data!==held || tx_last!==held_last))
                $fatal(1,"TX changed while stalled");
            stalled=tx_valid && !tx_ready; held=tx_data; held_last=tx_last;
            if(cancel) cancels=cancels+1;
            if(sv && cr) begin
                if(sof !== (captures%32==0) || eof !== (captures%32==31)) $fatal(1,"frame markers");
                for(k=0;k<16;k=k+1) begin
                    if(ii[k*16 +:16]!==vi[(captures%32)*16+k] || qq[k*16 +:16]!==vq[(captures%32)*16+k])
                        $fatal(1,"IQ mapping record=%0d channel=%0d",captures%32,k);
                    if(sr[k*24 +:24]!==vr[k] || si[k*24 +:24]!==vm[k]) $fatal(1,"steering mapping/snapshot");
                end
                captures=captures+1;
            end
            if(tx_valid && tx_ready) begin
                received[words]=tx_data; words=words+1;
                if(tx_last) begin
                    starts[replies]=current_start; lengths[replies]=words-current_start;
                    current_start=words; replies=replies+1;
                end
            end
        end
    end
    task send_packet;
        input integer source,count;
        input bad;
        begin
            for(j=0;j<count;j=j+1) begin
                @(negedge clk);
                case(source)
                    0:rx_data=cfg[j]; 1:rx_data=p0[j]; 2:rx_data=p1[j]; default:rx_data=packet[j];
                endcase
                rx_valid=1; rx_last=(j==count-1); rx_bad=bad && rx_last;
                @(posedge clk); while(!rx_ready) @(posedge clk);
                @(negedge clk); rx_valid=0; rx_last=0; rx_bad=0;
            end
        end
    endtask
    task reply;
        input [7:0] kind;
        input [15:0] code;
        input [31:0] fid;
        integer base;
        begin
            wait(replies>seen); @(negedge clk); base=starts[seen];
            if(received[base]!==32'h42464d31 || received[base+1]!=={8'd1,kind,code} ||
               received[base+2]!==fid || received[base+3]!==32'h10203040 ||
               received[base+4]!=={16'd160,16'd80} || received[base+6]!=={16'd32,16'd16})
                $fatal(1,"reply[%0d] kind/status/fid=%h %h expected %h/%0d/%h",seen,received[base+1],received[base+2],kind,code,fid);
            if(kind==8'h82) begin
                if(lengths[seen]!=104 || received[base+7]!=={16'd384,16'd0}) $fatal(1,"result length");
                for(n=0;n<32;n=n+1) begin
                    if({received[base+8+n*3],received[base+9+n*3][31:16]} !== (48'h800000000000+n) ||
                       {received[base+9+n*3][15:0],received[base+10+n*3]} !== (48'h7fffffffffff-n))
                        $fatal(1,"result signed48 packing at %0d",n);
                end
            end else if(lengths[seen]!=8 || received[base+7]!=0) $fatal(1,"header-only response length");
            seen=seen+1;
        end
    endtask
    task beams;
        begin
            for(a=0;a<32;a=a+1) begin
                @(negedge clk); ov=1; br=48'h800000000000+a; bi=48'h7fffffffffff-a;
            end
            @(negedge clk); ov=0;
        end
    endtask
    task pulse_error;
        begin @(negedge clk);err=1; @(negedge clk);err=0; end
    endtask
    initial begin #2000000; $fatal(1,"adapter test timeout"); end
    initial begin
        $readmemh("packets/config.hex",cfg); $readmemh("packets/iq0.hex",p0); $readmemh("packets/iq1.hex",p1);
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_i.hex",vi);
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_q.hex",vq);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",vr);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",vm);
        repeat(4) @(negedge clk);rst=0;
        send_packet(1,264,0);reply(8'hff,3,32'h12345678); // no config
        send_packet(0,32,1);reply(8'hff,2,0); // rejected config cannot become active
        if(dut.configured) $fatal(1,"bad config committed");
        cfg[0]=0;send_packet(0,32,0);reply(8'hff,1,0);cfg[0]=32'h42464d31;
        send_packet(0,32,0);reply(8'h81,0,0);
        send_packet(2,264,0);reply(8'hff,4,32'h12345678); // reorder
        send_packet(1,263,0);reply(8'hff,1,32'h12345678); // short packet
        p0[7]={16'd1020,16'd0};send_packet(1,264,0);reply(8'hff,1,32'h12345678);p0[7]={16'd1024,16'd0};
        for(b=0;b<264;b=b+1)packet[b]=p0[b];packet[264]=0;packet[265]=0;
        send_packet(3,266,0);reply(8'hff,2,32'h12345678);
        send_packet(1,264,1);reply(8'hff,2,32'h12345678);
        send_packet(1,264,0);send_packet(1,264,0);reply(8'hff,4,32'h12345678); // duplicate
        send_packet(1,264,0);p1[2]=9;send_packet(2,264,0);reply(8'hff,4,9);p1[2]=32'h12345678;
        send_packet(1,264,0);p1[4]=0;send_packet(2,264,0);
        // The response echoes the offending metadata.
        wait(replies>seen); if(received[starts[seen]+1]!==32'h01ff0003 || received[starts[seen]+4]!==0)
            $fatal(1,"config mismatch error");seen=seen+1;p1[4]={16'd160,16'd80};
        send_packet(1,264,0);reply(8'hff,6,32'h12345678); // missing packet
        // Half packet timeout, with enough header words to echo metadata.
        for(b=0;b<8;b=b+1)begin
            @(negedge clk);rx_valid=1;rx_data=p0[b];rx_last=0;
            @(posedge clk);while(!rx_ready)@(posedge clk);
        end
        @(negedge clk);rx_valid=0;reply(8'hff,6,32'h12345678);
        if(captures!=0) $fatal(1,"partial/bad frame reached core");
        // Configuration during assembly returns BUSY and preserves frame/config.
        send_packet(1,264,0);cfg[8]=0;send_packet(0,32,0);reply(8'hff,5,0);
        send_packet(2,264,0);wait(captures==32);
        // Ready may reopen before the last beam; ownership must remain busy.
        if(!busy) $fatal(1,"released frame before beam completion");
        send_packet(1,264,0);reply(8'hff,5,32'h12345678);
        enable_tx=0;beams();repeat(20)@(negedge clk);
        if(!busy || !tx_valid || rx_ready) $fatal(1,"result stall ownership");
        enable_tx=1;reply(8'h82,0,32'h12345678);wait(!busy);
        // A stalled BUSY response cannot overwrite an independent solver error.
        send_packet(1,264,0);send_packet(2,264,0);wait(captures==64);
        enable_tx=0;send_packet(1,264,0);repeat(4)@(negedge clk);pulse_error();
        repeat(10)@(negedge clk);enable_tx=1;
        reply(8'hff,5,32'h12345678);reply(8'hff,7,32'h12345678);wait(!busy);
        send_packet(1,264,0);send_packet(2,264,0);wait(captures==96);
        reply(8'hff,8,32'h12345678);wait(!busy);
        if(cancels!=2) $fatal(1,"core cancel count=%0d",cancels);
        send_packet(1,264,0);send_packet(2,264,0);wait(captures==128);beams();reply(8'h82,0,32'h12345678);
        // Reset drops a partially received packet and invalidates configuration.
        @(negedge clk);rx_valid=1;rx_data=cfg[0];@(negedge clk);rx_valid=0;rst=1;
        repeat(3)@(negedge clk);rst=0;
        send_packet(1,264,0);reply(8'hff,3,32'h12345678);
        if(busy || dut.configured) $fatal(1,"reset failed to flush ownership");
        $display("PASS udp_beamforming_adapter: packet validation/order/loss/timeout, atomic config, exact IQ, TX stalls, errors/reset");$finish;
    end
endmodule
