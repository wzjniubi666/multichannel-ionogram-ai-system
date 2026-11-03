`timescale 1ns/1ps
module tb_kt325t_network_board;
    reg sysclk=0,rstn=0,rxclk=0,rxctl=0,rx_run=1;
    reg[15:0]phy_status=16'h002c;
    reg [3:0]rxd=0;
    wire txclk,txctl,mdc,prst;wire[3:0]txd;wire[4:0]led;
    tri1 mdio;
    reg[7:0]bytes_mem[0:1599];
    reg[3:0]low_nibble;reg low_control;
    integer i,fd,frames=0,frame_bytes=0,idle_bytes=100,captures=0;
    reg active=0;
    always #2.5 sysclk=~sysclk;
    always begin #4;if(rx_run)rxclk=~rxclk;end
    kt325t_network_board_top #(.PHY_RESET_CYCLES(10),.PHY_SETTLE_CYCLES(30)) dut(
        .sys_clk_p(sysclk),.sys_clk_n(~sysclk),.sys_rstn(rstn),.rgmii_rxc(rxclk),
        .rgmii_rx_ctl(rxctl),.rgmii_rxd(rxd),.rgmii_txc(txclk),.rgmii_tx_ctl(txctl),
        .rgmii_txd(txd),.phy_mdc(mdc),.phy_mdio(mdio),.phy_reset_n(prst),.led(led));
    model_rtl8211 #(.INITIAL_PAGE(16'h0000)) phy(.mdc(mdc),.reset_n(prst),.host_oe(dut.mdio_oe),.mdio(mdio),
        .bad_id(1'b0),.no_ack(1'b0),.ignore_tx_write(1'b0),.status_word(phy_status),.autoneg(1'b1));
    always @(posedge dut.core_clk)if(!dut.data_reset && !dut.u_network.core_rst)
        if(dut.u_network.u_application.u_network.sample_valid && dut.u_network.u_application.u_network.capture_ready)
            captures=captures+1;
    always @(posedge txclk)begin #1;low_nibble=txd;low_control=txctl;end
    always @(negedge txclk)begin
        #1;
        if(!dut.data_reset && txctl!==low_control)$fatal(1,"TX control DDR mismatch");
        if(!dut.data_reset && low_control)begin
            if(!active)begin
                if(idle_bytes<12)$fatal(1,"board TX IFG %0d",idle_bytes);
                active=1;frame_bytes=0;$fdisplay(fd,"START");
            end
            $fdisplay(fd,"%02x",{txd,low_nibble});frame_bytes=frame_bytes+1;idle_bytes=0;
        end else begin
            idle_bytes=idle_bytes+1;
            if(active)begin active=0;frames=frames+1;$fdisplay(fd,"END");end
        end
    end
    task send_frame;
        input[511:0]path;input integer length;
        begin
            $readmemh(path,bytes_mem,0,length-1);
            for(i=0;i<length;i=i+1)begin
                @(negedge rxclk);#1;rxctl=1;rxd=bytes_mem[i][3:0];
                @(posedge rxclk);#1;rxctl=1;rxd=bytes_mem[i][7:4];
            end
            @(negedge rxclk);#1;rxctl=0;rxd=0;repeat(16)@(negedge rxclk);
        end
    endtask
    initial begin #8000000;$fatal(1,"board integration timeout");end
    initial begin
        fd=$fopen("gmii_tx_frames.txt","w");if(!fd)$fatal(1,"capture open failed");
        #1000;rstn=1;wait(!dut.data_reset);repeat(20)@(negedge rxclk);
        if(!prst || !dut.configured || !dut.link_ready || !dut.rx_clock_ok || !dut.idelay_ready)
            $fatal(1,"data released before PHY/clock/calibration");
        send_frame("gmii/bad_fcs.hex",182);
        send_frame("gmii/arp.hex",72);wait(frames==1);
        send_frame("gmii/config.hex",182);wait(frames==2);
        send_frame("gmii/iq0.hex",1110);send_frame("gmii/iq1.hex",1110);
        wait(frames==2 && active && frame_bytes>60);send_frame("gmii/arp.hex",72);
        wait(frames==4);repeat(20)@(negedge rxclk);$fclose(fd);
        if(captures!=32 || dut.busy || dut.data_reset)$fatal(1,"board totals or reset capture=%0d",captures);
        if(led[2:0]!==3'b111 || led[4]!==0)$fatal(1,"core LED polarity/status mismatch");
        phy_status=16'h001c;wait(dut.data_reset);wait(dut.u_network.core_rst);
        phy_status=16'h002c;wait(!dut.data_reset);
        rx_run=0;#6000;if(!dut.data_reset || !dut.u_network.core_rst)$fatal(1,"RX stop did not reset data/core");
        rx_run=1;wait(!dut.data_reset);repeat(40)@(negedge rxclk);
        if(frames!=4)$fatal(1,"ghost TX after link/reset recovery");
        $display("PASS kt325t_network_board: physical RGMII DDR/ODDR, managed PHY, calibrated delay, real MVDR and 4 wire frames");$finish;
    end
endmodule
