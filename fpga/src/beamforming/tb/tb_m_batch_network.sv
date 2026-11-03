`timescale 1ns/1ps
// Nine prepared real-M frames, one reset, changing frequency/lag/config IDs.
module tb_m_batch_network;
    localparam integer F=9;
    reg clk=0,rst=1,rx_valid=0,rx_last=0,tx_ready=0;
    reg [31:0] rx_data=0;
    wire rx_ready,tx_valid,tx_last,busy;
    wire [31:0] tx_data;
    reg [31:0] configs[0:F*32-1],iq0[0:F*264-1],iq1[0:F*264-1],expected[0:F*112-1];
    integer tick=0,packets=0,word_index=0,frame,s,k,base,fd,captures=0,weight_sets=0;
    reg stalled=0;reg[31:0]held_data;reg held_last;
    always #2.5 clk=~clk;
    network_beamforming_top dut(.clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),
        .rx_data(rx_data),.rx_last(rx_last),.rx_bad(1'b0),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .tx_data(tx_data),.tx_last(tx_last),.busy(busy));
    always @(negedge clk)begin tick=tick+1;tx_ready=(tick%7!=0 && tick%11!=0);end
    always @(posedge clk)begin
        if(rst)stalled=0;
        else begin
            if(stalled && (!tx_valid || tx_data!==held_data || tx_last!==held_last))
                $fatal(1,"BATCH_NET stalled TX changed");
            stalled=tx_valid && !tx_ready;held_data=tx_data;held_last=tx_last;
            if(dut.u_network.sample_valid && dut.u_network.capture_ready)captures=captures+1;
            if(dut.u_core.weights_valid)weight_sets=weight_sets+1;
            if(dut.u_core.solver_error)$fatal(1,"BATCH_NET solver error");
            if(tx_valid && tx_ready)begin
                if(packets>=2*F)$fatal(1,"BATCH_NET unexpected packet");
                base=(packets/2)*112+((packets%2) ? 8:0)+word_index;
                if(tx_data!==expected[base])$fatal(1,"BATCH_NET payload mismatch packet=%0d word=%0d",packets,word_index);
                if(tx_last!==((packets%2) ? word_index==103:word_index==7))
                    $fatal(1,"BATCH_NET tx_last mismatch");
                $fdisplay(fd,"%08x",tx_data);
                if(tx_last)begin packets=packets+1;word_index=0;end
                else word_index=word_index+1;
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
                case(kind)
                    0:rx_data=configs[which*32+k];
                    1:rx_data=iq0[which*264+k];
                    2:rx_data=iq1[which*264+k];
                endcase
                @(posedge clk);while(!rx_ready)@(posedge clk);
                @(negedge clk);rx_valid=0;rx_last=0;
            end
        end
    endtask
    initial begin #20000000;$fatal(1,"BATCH_NET timeout");end
    initial begin
        $readmemh("configs.hex",configs);$readmemh("iq0.hex",iq0);$readmemh("iq1.hex",iq1);
        $readmemh("expected_tx.hex",expected);
        fd=$fopen("rtl_tx_payloads.hex","w");if(!fd)$fatal(1,"BATCH_NET open output");
        repeat(5)@(negedge clk);rst=0;
        for(frame=0;frame<F;frame=frame+1)begin
            send(0,frame,32);wait(packets==frame*2+1);
            send(1,frame,264);send(2,frame,264);wait(packets==frame*2+2);
        end
        repeat(30)@(negedge clk);$fclose(fd);
        if(busy || captures!=F*32 || weight_sets!=F || packets!=F*2)
            $fatal(1,"BATCH_NET totals captures=%0d weights=%0d packets=%0d",captures,weight_sets,packets);
        $display("PASS M_BATCH_NETWORK: 9 changing M frames, 18 exact ACK/RESULT packets, TX stalls, RX gaps, no reset between frames");
        $finish;
    end
endmodule
