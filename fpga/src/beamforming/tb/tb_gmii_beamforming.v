`timescale 1ns/1ps
module tb_gmii_beamforming;
    reg rx_clk=0,core_clk=0,tx_clk=0,reset=1,dv=0,er=0,tx_allow=1;
    reg [7:0]rxd=0,bytes_mem[0:1599];
    wire tx_en,busy;wire[7:0]txd;
    wire[31:0]accepted,rejected,overflow;
    reg[15:0]vi[0:511],vq[0:511];reg[23:0]sr[0:15],si[0:15];
    integer i,ch,captured=0,frames=0,frame_bytes=0,idle_clocks=100,fd;
    reg active=0;
    always #4 rx_clk=~rx_clk;
    always #2.5 core_clk=~core_clk;
    // Deliberately asynchronous to RX and core, including a different frequency.
    initial begin #1.7;forever #4.1 tx_clk=~tx_clk;end
    gmii_beamforming_top dut(.async_reset(reset),.rx_clk(rx_clk),.core_clk(core_clk),.tx_clk(tx_clk),
        .gmii_rx_dv(dv),.gmii_rx_er(er),.gmii_rxd(rxd),.tx_allow(tx_allow),
        .gmii_tx_en(tx_en),.gmii_txd(txd),.busy(busy),
        .rx_accepted(accepted),.rx_rejected(rejected),.rx_overflow(overflow));
    always @(posedge core_clk)if(!dut.core_rst)begin
        if(dut.u_application.u_network.sample_valid && dut.u_application.u_network.capture_ready)begin
            for(ch=0;ch<16;ch=ch+1)begin
                if(dut.u_application.u_network.in_i_bus[ch*16 +:16]!==vi[captured*16+ch] ||
                   dut.u_application.u_network.in_q_bus[ch*16 +:16]!==vq[captured*16+ch] ||
                   dut.u_application.u_network.steering_re_bus[ch*24 +:24]!==sr[ch] ||
                   dut.u_application.u_network.steering_im_bus[ch*24 +:24]!==si[ch])
                    $fatal(1,"wire->CDC->core IQ/config mismatch record=%0d ch=%0d",captured,ch);
            end
            captured=captured+1;
        end
        if(dut.rx_desc_error || dut.tx_desc_error || dut.tx_overflow)$fatal(1,"CDC descriptor/overflow fault");
    end
    always @(posedge tx_clk)begin
        if(tx_en)begin
            if(!active)begin
                if(idle_clocks<12)$fatal(1,"Ethernet IFG too short: %0d",idle_clocks);
                active=1;frame_bytes=0;$fdisplay(fd,"START");
            end
            $fdisplay(fd,"%02x",txd);frame_bytes=frame_bytes+1;idle_clocks=0;
        end else begin
            idle_clocks=idle_clocks+1;
            if(active)begin active=0;frames=frames+1;$fdisplay(fd,"END");end
        end
    end
    task send_frame;
        input [511:0]path;input integer length;
        begin
            $readmemh(path,bytes_mem,0,length-1);
            for(i=0;i<length;i=i+1)begin @(negedge rx_clk);dv=1;rxd=bytes_mem[i];end
            @(negedge rx_clk);dv=0;repeat(12)@(negedge rx_clk);
        end
    endtask
    initial begin #5000000;$fatal(1,"GMII real-core integration timeout");end
    initial begin
        fd=$fopen("gmii_tx_frames.txt","w");if(!fd)$fatal(1,"cannot write TX capture");
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_i.hex",vi);$readmemh("sim_vectors/reference_10mhz_gate80/iq_q.hex",vq);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",sr);$readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",si);
        repeat(4)@(negedge rx_clk);reset=0;repeat(12)@(negedge rx_clk);
        send_frame("gmii/bad_fcs.hex",182);
        send_frame("gmii/arp.hex",72);wait(frames==1);
        tx_allow=0;send_frame("gmii/config.hex",182);
        wait(dut.u_transport.u_tx.state==2);repeat(20)@(negedge tx_clk);
        if(tx_en)$fatal(1,"TX start gate ignored");tx_allow=1;wait(frames==2);
        send_frame("gmii/iq0.hex",1110);send_frame("gmii/iq1.hex",1110);
        wait(frames==2 && active && frame_bytes>60);
        // A request during the result frame must wait for complete UDP and IFG.
        send_frame("gmii/arp.hex",72);
        wait(frames==4);repeat(20)@(negedge tx_clk);$fclose(fd);
        if(captured!=32 || accepted!=3 || rejected!=1 || overflow!=0 || busy)
            $fatal(1,"GMII totals captures=%0d accepted=%0d rejected=%0d overflow=%0d",captured,accepted,rejected,overflow);
        $display("PASS gmii_beamforming: independent RX/core/TX, checksummed COS -> real MVDR -> wire result, ARP arbitration/IFG");$finish;
    end
endmodule
