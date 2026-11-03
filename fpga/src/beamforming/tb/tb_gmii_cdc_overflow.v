`timescale 1ns/1ps
module tb_gmii_cdc_overflow;
    reg rc=0,cc=0,tc=0,reset=1,dv=0,allow=0;
    reg[7:0]rxd=0,wire_bytes[0:1599];
    wire cr,valid,last,ready_tx,te,rd_error,td_error,tover;
    wire[31:0]data,accepted,rejected,overflow;wire[7:0]td;
    reg[31:0]cfg[0:31],iq0[0:263],iq1[0:263];
    integer i,packet_index=0,word_index=0;
    reg[31:0]expected;
    always #4 rc=~rc;always #2.5 cc=~cc;always #4.3 tc=~tc;
    gmii_payload_transport dut(.async_reset(reset),.rx_clk(rc),.core_clk(cc),.tx_clk(tc),
        .gmii_rx_dv(dv),.gmii_rx_er(1'b0),.gmii_rxd(rxd),.tx_allow(1'b0),.gmii_tx_en(te),.gmii_txd(td),
        .core_rst(cr),.core_rx_valid(valid),.core_rx_ready(allow),.core_rx_last(last),.core_rx_data(data),
        .core_tx_valid(1'b0),.core_tx_last(1'b0),.core_tx_ready(ready_tx),.core_tx_data(32'd0),
        .rx_accepted(accepted),.rx_rejected(rejected),.rx_overflow(overflow),
        .rx_desc_error(rd_error),.tx_desc_error(td_error),.tx_overflow(tover));
    always @(posedge cc)if(!cr && valid && allow)begin
        case(packet_index)0:expected=cfg[word_index];1:expected=iq0[word_index];2:expected=iq1[word_index];
            default:$fatal(1,"unexpected duplicate packet");endcase
        if(data!==expected || last!==((packet_index==0 && word_index==31) || (packet_index!=0 && word_index==263)))
            $fatal(1,"full queue corrupted packet=%0d word=%0d",packet_index,word_index);
        if(last)begin packet_index=packet_index+1;word_index=0;end else word_index=word_index+1;
    end
    task send_frame;
        input[511:0]path;input integer length;
        begin
            $readmemh(path,wire_bytes,0,length-1);
            for(i=0;i<length;i=i+1)begin @(negedge rc);dv=1;rxd=wire_bytes[i];end
            @(negedge rc);dv=0;repeat(12)@(negedge rc);
        end
    endtask
    initial begin #1000000;$fatal(1,"wire CDC overflow timeout");end
    initial begin
        $readmemh("packets/config.hex",cfg);$readmemh("packets/iq0.hex",iq0);$readmemh("packets/iq1.hex",iq1);
        repeat(4)@(negedge rc);reset=0;repeat(12)@(negedge rc);
        send_frame("gmii/config.hex",182);send_frame("gmii/iq0.hex",1110);send_frame("gmii/iq1.hex",1110);
        if(accepted!=2 || overflow!=1 || rejected!=0)$fatal(1,"wire full policy accepted=%0d overflow=%0d",accepted,overflow);
        allow=1;wait(packet_index==2);repeat(12)@(negedge rc);
        send_frame("gmii/iq1.hex",1110);wait(packet_index==3);repeat(12)@(negedge rc);
        if(accepted!=3 || overflow!=1 || rd_error || td_error || tover || valid)$fatal(1,"full queue did not recover");
        $display("PASS gmii_cdc_overflow: third wire packet dropped whole, two owned slots intact, post-ack reuse exact");$finish;
    end
endmodule
