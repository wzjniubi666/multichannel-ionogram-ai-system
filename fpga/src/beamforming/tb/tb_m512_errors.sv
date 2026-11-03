`timescale 1ns/1ps
// Adapter contract tests; arithmetic is separately checked by tb_m512_network.
module tb_m512_errors;
    reg clk=0,rst=1,rv=0,rl=0,rb=0,tr=1,ov=0,se=0;
    reg[31:0]rd=0;wire rr,tv,tl,sv,fs,fe,cancel,busy;wire[31:0]td;
    wire[255:0]ii,qq;wire[383:0]sr,si;
    reg[31:0]words[0:263];integer count=0,last_type=0,last_status=0,last_index=0,k,q,cancels=0,captures=0;
    reg[31:0]reply[0:7];integer reply_word=0;
    udp_beamforming512_adapter #(.IDLE_TIMEOUT_CYCLES(5000),.CORE_TIMEOUT_CYCLES(20000))dut(
        .clk(clk),.rst(rst),.rx_valid(rv),.rx_ready(rr),.rx_data(rd),.rx_last(rl),.rx_bad(rb),
        .tx_valid(tv),.tx_ready(tr),.tx_data(td),.tx_last(tl),.sample_valid(sv),.frame_start(fs),.frame_end(fe),
        .in_i_bus(ii),.in_q_bus(qq),.steering_re_bus(sr),.steering_im_bus(si),.capture_ready(1'b1),
        .output_valid(ov),.solver_error(se),.beam_re(48'd0),.beam_im(48'd0),.core_cancel(cancel),.busy(busy));
    always #2.5 clk=~clk;
    always @(posedge clk)if(!rst)begin
        if(cancel)cancels=cancels+1;
        if(sv)captures=captures+1;
        if(tv&&tr)begin
            if(reply_word<8)reply[reply_word]=td;
            if(tl)begin
                if(reply_word!=7)$fatal(1,"M512_ERRORS unexpected data result");
                if(reply[0]!==32'h42464d31||reply[1][31:24]!==8'd2||reply[6]!=={16'd512,16'd16})
                    $fatal(1,"M512_ERRORS wrong response header");
                last_type=reply[1][23:16];last_status=reply[1][15:0];last_index=reply[5][31:16];
                count=count+1;reply_word=0;
            end else reply_word=reply_word+1;
        end
    end
    task make;
        input integer kind,index;
        begin
            for(k=0;k<264;k=k+1)words[k]=0;
            words[0]=32'h42464d31;words[1]={8'd2,8'd0,16'd0}|(kind<<16);
            words[2]=(kind==1)?0:32'h512abc01;words[3]=32'h512c0001;words[4]=32'h00010094;
            words[5]=(index<<16)|((kind==1)?1:32);words[6]={16'd512,16'd16};words[7]=((kind==1)?96:1024)<<16;
        end
    endtask
    task send;
        input integer n,bad;
        begin
            for(k=0;k<n;k=k+1)begin
                @(negedge clk);rv=1;rd=words[k];rl=(k==n-1);rb=bad&&rl;
                @(posedge clk);while(!rr)@(posedge clk);
                @(negedge clk);rv=0;rl=0;rb=0;
            end
        end
    endtask
    task expect_reply;
        input integer wanted_count,kind,status,index;
        begin
            wait(count==wanted_count);@(negedge clk);
            if(last_type!=kind||last_status!=status||last_index!=index)
                $fatal(1,"M512_ERRORS reply count=%0d got=%0d/%0d/%0d expected=%0d/%0d/%0d",count,last_type,last_status,last_index,kind,status,index);
        end
    endtask
    task configure;
        integer start;
        begin start=count;make(1,0);send(32,0);expect_reply(start+1,8'h81,0,0);end
    endtask
    task full_input;
        integer start;
        begin
            for(q=0;q<32;q=q+1)begin start=count;make(2,q);send(264,0);expect_reply(start+1,8'h83,0,q);end
        end
    endtask
    initial begin #3000000;$fatal(1,"M512_ERRORS timeout");end
    integer before_reply,before_cancel;
    initial begin
        repeat(5)@(negedge clk);rst=0;
        make(1,0);words[1][31:24]=1;send(32,0);expect_reply(1,8'hff,1,0);
        configure();
        before_reply=count;make(2,1);send(264,0);expect_reply(before_reply+1,8'hff,4,1);
        before_reply=count;make(2,0);send(264,0);expect_reply(before_reply+1,8'h83,0,0);
        before_reply=count;make(1,0);send(32,0);expect_reply(before_reply+1,8'hff,5,0);
        if(dut.fs!=1||dut.expected_iq!=1)$fatal(1,"M512_ERRORS CONFIG busy destroyed partial frame");
        before_reply=count;make(2,0);send(264,0);expect_reply(before_reply+1,8'hff,4,0);
        before_reply=count;make(2,0);send(264,1);expect_reply(before_reply+1,8'hff,2,0);
        before_reply=count;make(2,0);send(264,0);expect_reply(before_reply+1,8'h83,0,0);
        before_reply=count;expect_reply(before_reply+1,8'hff,6,1);
        if(busy||captures!=0)$fatal(1,"M512_ERRORS partial input reached core");
        before_reply=count;make(2,0);send(264,0);expect_reply(before_reply+1,8'h83,0,0);
        @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
        before_reply=count;make(2,0);send(264,0);expect_reply(before_reply+1,8'hff,3,0);
        configure();
        before_cancel=cancels;full_input();before_reply=count;
        expect_reply(before_reply+1,8'hff,8,0);
        repeat(5)@(negedge clk);
        if(cancels!=before_cancel+1||busy||captures!=512)$fatal(1,"M512_ERRORS core timeout recovery failed");
        before_cancel=cancels;full_input();wait(dut.fs==5);before_reply=count;
        @(negedge clk);se=1;@(negedge clk);se=0;
        expect_reply(before_reply+1,8'hff,7,0);repeat(5)@(negedge clk);
        if(cancels!=before_cancel+1||busy||captures!=1024)$fatal(1,"M512_ERRORS solver cancel failed");
        configure();
        $display("PASS M512_ERRORS: v1 reject, sequence/duplicate/bad packet, BUSY preserves partial, assembly timeout, reset invalidation, core timeout and solver cancel; no partial results");
        $finish;
    end
endmodule
