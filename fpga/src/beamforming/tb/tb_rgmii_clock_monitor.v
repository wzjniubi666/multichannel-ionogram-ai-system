`timescale 1ns/1ps
module tb_rgmii_clock_monitor;
    reg core=0,rx=0,rst=1,run=1;
    real half_period=4.0;
    wire ok;
    always #2.5 core=~core;
    always begin #(half_period);if(run)rx=~rx;end
    rgmii_clock_monitor dut(.core_clk(core),.rx_clk(rx),.async_reset(rst),.gigabit_clock_ok(ok));
    initial begin #100000;$fatal(1,"clock monitor timeout");end
    initial begin
        #50;rst=0;wait(ok);
        run=0;#6000;if(ok)$fatal(1,"stopped RX clock accepted");
        run=1;wait(ok);half_period=20;#16000;if(ok)$fatal(1,"25MHz RX accepted as gigabit");
        half_period=4;wait(ok);run=0;rst=1;#20;if(ok)$fatal(1,"async reset failed with RX stopped");
        rst=0;#6000;if(ok)$fatal(1,"reset released without RX clock");
        run=1;wait(ok);
        $display("PASS rgmii_clock_monitor: 125MHz qualify, 25MHz rejection, stopped-clock reset/recovery");$finish;
    end
endmodule
