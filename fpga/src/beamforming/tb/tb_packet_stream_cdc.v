`timescale 1ns/1ps
module tb_packet_stream_cdc;
    real SOURCE_HALF=4.0,DEST_HALF=2.5;
    reg sc=0,mc=0,reset=1,run_mc=1,sv=0,sl=0,mr=0,allow=0;
    reg [31:0]sd=0;
    wire sr,mv,ml,srst,mrst,overflow,descriptor_error;
    wire [31:0]md;
    integer expected_id=0,expected_word=0,done=0,tick=0,j,held_count=0;
    reg stalled=0;reg[31:0]held;reg held_last;
    reg[31:0]rng=32'h81234abc;
    always #(SOURCE_HALF)sc=~sc;
    initial begin #1.3;forever begin #(DEST_HALF);if(run_mc)mc=~mc;end end
    packet_stream_cdc dut(.async_reset(reset),.s_clk(sc),.m_clk(mc),.s_rst(srst),.m_rst(mrst),
        .s_valid(sv),.s_ready(sr),.s_data(sd),.s_last(sl),.m_valid(mv),.m_ready(mr),
        .m_data(md),.m_last(ml),.overflow(overflow),.descriptor_error(descriptor_error));
    function integer length;
        input integer id;
        begin case(id%5)0:length=1;1:length=8;2:length=264;3:length=104;default:length=17+id%200;endcase end
    endfunction
    function [31:0] value;
        input integer id,w;
        begin value=(id<<20)^(w*32'h10203)^32'hdeadbeef;end
    endfunction
    always @(negedge mc)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};mr=allow && rng[2:0]!=0;
    end
    always @(posedge mc)begin
        if(mrst)stalled=0;
        else begin
            if(stalled && (!mv || md!==held || ml!==held_last))$fatal(1,"CDC stalled data changed");
            stalled=mv&&!mr;held=md;held_last=ml;
            if(mv&&mr)begin
                if(md!==value(expected_id,expected_word) || ml!==(expected_word==length(expected_id)-1))
                    $fatal(1,"CDC order/data id=%0d word=%0d got=%h expected=%h",expected_id,expected_word,md,value(expected_id,expected_word));
                if(ml)begin expected_id=expected_id+1;expected_word=0;done=done+1;end
                else expected_word=expected_word+1;
            end
        end
    end
    task send;
        input integer id;
        integer w;
        begin
            for(w=0;w<length(id);w=w+1)begin
                @(negedge sc);sv=1;sl=(w==length(id)-1);sd=value(id,w);
                @(posedge sc);while(!sr)@(posedge sc);
                @(negedge sc);sv=0;sl=0;
            end
        end
    endtask
    initial begin #2000000;$fatal(1,"CDC mailbox timeout");end
    initial begin
        repeat(4)@(negedge sc);reset=0;wait(!srst && !mrst);
        send(0);send(1);repeat(12)@(negedge sc);
        if(sr)$fatal(1,"two full slots not backpressured");allow=1;
        for(j=2;j<80;j=j+1)send(j);
        wait(done==80);allow=0;reset=1;expected_id=0;expected_word=0;done=0;
        SOURCE_HALF=2.5;DEST_HALF=6.5;
        repeat(6)@(negedge sc);reset=0;wait(!srst && !mrst);
        send(0);send(1);repeat(12)@(negedge sc);
        if(sr)$fatal(1,"reverse ratio two-slot full check failed");allow=1;
        for(j=2;j<80;j=j+1)send(j);
        wait(done==80);allow=0;repeat(6)@(negedge mc);
        send(100);send(101);wait(mv);@(negedge mc);run_mc=0;
        #1;reset=1;sv=0;#3;
        if(dut.u_store.request_toggle!==0 || dut.u_store.acknowledge_toggle!==0)
            $fatal(1,"reset did not clear ownership with stopped destination clock");
        expected_id=200;expected_word=0;done=0;stalled=0;
        repeat(4)@(negedge sc);reset=0;wait(!srst);
        send(200);repeat(12)@(negedge sc);run_mc=1;allow=1;
        send(201);send(202);wait(done==3);
        repeat(20)@(negedge mc);
        if(mv || overflow || descriptor_error)$fatal(1,"ghost packet/overflow/descriptor error after reset");
        $display("PASS packet_stream_cdc: 125->200 and 200->76.9 MHz, 160 packets, full/wrap/stalls, stopped-clock reset, no ghost data");$finish;
    end
endmodule

