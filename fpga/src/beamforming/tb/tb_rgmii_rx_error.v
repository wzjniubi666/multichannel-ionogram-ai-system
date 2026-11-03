`timescale 1ns/1ps
module tb_rgmii_rx_error;
    reg rc=0,refclk=0,ctl=0;
    reg[3:0]data=0;
    wire gc,dv,er;wire[7:0]gd;
    integer i,saw_good=0,saw_error=0;
    always #4 rc=~rc;
    always #2.5 refclk=~refclk;
    bfm_rgmii_rx dut(.idelay_clk(refclk),.rgmii_rxc(rc),.rgmii_rx_ctl(ctl),.rgmii_rxd(data),
        .gmii_rx_clk(gc),.gmii_rx_en(dv),.gmii_rx_er(er),.gmii_rxd(gd));
    always @(negedge gc)begin
        if(dv && gd==8'hab && !er)saw_good=saw_good+1;
        if(dv && gd==8'hab && er)saw_error=saw_error+1;
    end
    initial begin #10000;$fatal(1,"RGMII primitive test timeout");end
    initial begin
        repeat(20)@(negedge rc);
        for(i=0;i<20;i=i+1)begin
            // Set low nibble/RX_DV ahead of rising edge, high nibble/DV^ER ahead of falling edge.
            #1;data=4'hb;ctl=1;@(posedge rc);#1;data=4'ha;ctl=(i<10);@(negedge rc);
        end
        #1;ctl=0;data=0;repeat(8)@(negedge rc);
        if(saw_good<5 || saw_error<5)$fatal(1,"lost DDR DV/error decode good=%0d error=%0d",saw_good,saw_error);
        $display("PASS rgmii_rx_error: official IDDR/IDELAY datapath preserves DV and XOR RX_ER");$finish;
    end
endmodule
