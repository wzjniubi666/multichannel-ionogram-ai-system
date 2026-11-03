`timescale 1ns/1ps
module tb_m512_network;
    localparam integer F=9,WORDS_PER_FRAME=1928;
    reg clk=0,rst=1,rx_valid=0,rx_last=0,tx_ready=0;
    reg [31:0]rx_data=0;
    wire rx_ready,tx_valid,tx_last,busy;wire[31:0]tx_data;
    reg[31:0]configs[0:F*32-1],iq[0:F*32*264-1],expected[0:F*WORDS_PER_FRAME-1];
    integer tick=0,packets=0,word_index=0,frame,q,k,base,packet_in_frame,fd,captures=0,weight_sets=0;
    reg stalled=0;reg[31:0]held_data;reg held_last;
    network_beamforming512_top dut(.clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_data(rx_data),
        .rx_last(rx_last),.rx_bad(1'b0),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_data(tx_data),.tx_last(tx_last),.busy(busy));
    always #2.5 clk=~clk;
    always @(negedge clk)begin tick=tick+1;tx_ready=(tick%7!=0&&tick%11!=0);end
    always @(posedge clk)begin
        if(rst)stalled=0;
        else begin
            if(stalled&&(!tx_valid||tx_data!==held_data||tx_last!==held_last))$fatal(1,"M512 stalled TX changed");
            stalled=tx_valid&&!tx_ready;held_data=tx_data;held_last=tx_last;
            if(dut.u_network.sample_valid&&dut.u_network.capture_ready)captures=captures+1;
            if(dut.u_core.weights_valid)weight_sets=weight_sets+1;
            if(dut.u_core.solver_error)$fatal(1,"M512 solver error");
            if(tx_valid&&tx_ready)begin
                if(packets>=F*49)$fatal(1,"M512 extra packet");
                packet_in_frame=packets%49;
                base=(packets/49)*WORDS_PER_FRAME+((packet_in_frame<33)?packet_in_frame*8:264+(packet_in_frame-33)*104)+word_index;
                if(tx_data!==expected[base])$fatal(1,"M512 payload mismatch packet=%0d word=%0d actual=%08x expected=%08x",packets,word_index,tx_data,expected[base]);
                if(tx_last!==((packet_in_frame<33)?word_index==7:word_index==103))$fatal(1,"M512 tx_last mismatch");
                $fdisplay(fd,"%08x",tx_data);
                if(tx_last)begin packets=packets+1;word_index=0;end else word_index=word_index+1;
            end
        end
    end
    task send;
        input integer kind,which,count;
        begin
            for(k=0;k<count;k=k+1)begin
                @(negedge clk);
                if(k%13==5)begin rx_valid=0;rx_last=0;@(negedge clk);end
                rx_valid=1;rx_last=(k==count-1);
                rx_data=(kind==0)?configs[which*32+k]:iq[which*264+k];
                @(posedge clk);while(!rx_ready)@(posedge clk);
                @(negedge clk);rx_valid=0;rx_last=0;
            end
        end
    endtask
    initial begin #40000000;$fatal(1,"M512 simulation timeout");end
    initial begin
        $readmemh("configs.hex",configs);$readmemh("iq.hex",iq);$readmemh("expected_tx.hex",expected);
        fd=$fopen("rtl_tx_payloads.hex","w");if(!fd)$fatal(1,"M512 open output");
        repeat(5)@(negedge clk);rst=0;
        for(frame=0;frame<F;frame=frame+1)begin
            send(0,frame,32);wait(packets==frame*49+1);
            for(q=0;q<32;q=q+1)begin send(1,frame*32+q,264);wait(packets==frame*49+q+2);end
            wait(packets==(frame+1)*49);
        end
        repeat(30)@(negedge clk);$fclose(fd);
        if(busy||captures!=F*512||weight_sets!=F||packets!=F*49)
            $fatal(1,"M512 totals captures=%0d weights=%0d packets=%0d",captures,weight_sets,packets);
        $display("PASS M512_NETWORK: 9 joint512 frames, 441 exact ACK/RESULT packets, RX gaps/TX stalls, one weight set per512, no reset between frames");
        $finish;
    end
endmodule
