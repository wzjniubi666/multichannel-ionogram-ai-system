`timescale 1ns/1ps
// Test-only PHY model decodes the actual MDIO pin stream, not master internals.
// Read data changes 300ns after MDC rising, the manual's worst-case tvalid.
module model_rtl8211 # (parameter [15:0] INITIAL_PAGE=16'h0a43)(
    input wire mdc,reset_n,host_oe,
    inout wire mdio,
    input wire bad_id,no_ack,ignore_tx_write,
    input wire [15:0]status_word,
    input wire autoneg
);
    reg drive=0,value=1,active=0;
    integer bitno=0,transactions=0,writes=0;
    reg [63:0]frame=0;
    reg [15:0]page=INITIAL_PAGE,txreg=16'ha45a,rxreg=16'hb650,bmcr=16'h8140,reply=0;
    reg [4:0]regno=0;
    reg reading=0;
    assign mdio=drive ? value : 1'bz;
    always @(negedge reset_n)begin
        active=0;bitno=0;drive=0;frame=0;page=INITIAL_PAGE;txreg=16'ha45a;rxreg=16'hb650;bmcr=16'h8140;
    end
    always @(posedge mdc)if(reset_n)begin
        if(!active && host_oe)begin active=1;bitno=0;frame=0;end
        if(active)begin
            frame={frame[62:0],mdio};
            // At this point only 46 bits have arrived, so decode the assembled header.
            if(bitno==45)begin
                if(frame[45:14]!==32'hffffffff || frame[13:12]!==2'b01 ||
                   (frame[11:10]!==2'b10 && frame[11:10]!==2'b01) || frame[9:5]!==5'd1)
                    $fatal(1,"bad Clause22 preamble/start/op/address header=%h",frame);
                regno=frame[4:0];reading=frame[11:10]==2'b10;
                case(regno)
                    2:reply=bad_id ? 16'h1234 : 16'h001c;
                    3:reply=16'hc916;
                    31:reply=page;
                    17:reply=(page==16'h0d08) ? txreg : 16'hdead;
                    21:reply=(page==16'h0d08) ? rxreg : 16'hdead;
                    0:reply=bmcr;
                    1:reply=autoneg ? 16'h0024 : 16'h0000;
                    26:reply=(page==16'h0a43) ? status_word : 16'hffff;
                    default:reply=0;
                endcase
            end
            if(bitno>=46 && reading)begin
                if(host_oe)$fatal(1,"host drives MDIO during read turnaround/data bit=%0d",bitno);
                if(bitno==46)begin drive<=#300 !no_ack;value<=#300 0;end
                else if(bitno<63)begin drive<=#300 !no_ack;value<=#300 reply[62-bitno];end
                else drive<=#300 0;
            end
            if(bitno==63)begin
                transactions=transactions+1;
                if(!reading)begin
                    if(frame[17:16]!==2'b10)$fatal(1,"write turnaround invalid");
                    writes=writes+1;
                    case(regno)
                        31:page=frame[15:0];
                        17:if(page==16'h0d08 && !ignore_tx_write)txreg=frame[15:0];
                        21:if(page==16'h0d08)rxreg=frame[15:0];
                        0:bmcr=frame[15:0];
                        default:$fatal(1,"unexpected MDIO write page=%h reg=%d",page,regno);
                    endcase
                end
                active=0;drive<=#600 0;
            end else bitno=bitno+1;
        end
    end
endmodule

module tb_rtl8211_phy_manager;
    reg clk=0,rst=1,bad_id=0,no_ack=0,ignore_tx=0,an=1;
    reg [15:0]status=16'h002c;
    wire mdout,oe,prst,configured,ready;
    wire[3:0]fault;wire[15:0]id1,id2,ps,td,rd;
    tri1 mdio;
    assign mdio=oe ? mdout : 1'bz;
    always #500 clk=~clk;
    rtl8211_phy_manager dut(.mdc_clk(clk),.rst(rst),.mdio_in(mdio),.mdio_out(mdout),.mdio_oe(oe),
        .phy_reset_n(prst),.configured(configured),.link_ready(ready),.fault(fault),
        .phy_id1(id1),.phy_id2(id2),.phy_status(ps),.tx_delay_readback(td),.rx_delay_readback(rd));
    model_rtl8211 phy(.mdc(clk),.reset_n(prst),.host_oe(oe),.mdio(mdio),.bad_id(bad_id),
        .no_ack(no_ack),.ignore_tx_write(ignore_tx),.status_word(status),.autoneg(an));
    time reset_at,release_at;
    integer writes_before;
    always @(negedge prst)reset_at=$time;
    always @(posedge prst)begin
        if($time-reset_at<10000000)$fatal(1,"PHY reset shorter than 10ms");
        release_at=$time;
    end
    always @(posedge oe)if(prst && $time-release_at<30000000)$fatal(1,"MDIO before 30ms settle");
    task restart;
        begin rst=1;repeat(3)@(posedge clk);rst=0;end
    endtask
    task good;
        begin wait(configured);#10;
            if(!ready || id1!==16'h001c || id2!==16'hc916 || td!==16'ha55a || rd!==16'hb658 ||
               phy.page!==16'h0a43 || phy.bmcr!==16'h1340)
                $fatal(1,"PHY ID/RMW/page/BMCR/link mismatch td=%h rd=%h bmcr=%h",td,rd,phy.bmcr);
        end
    endtask
    initial begin #600000000;$fatal(1,"PHY management timeout");end
    initial begin
        reset_at=0;release_at=0;restart();good();
        status=16'h001c;wait(!ready);if(!configured)$fatal(1,"100M incorrectly treated as config failure");
        status=16'h002c;wait(ready);
        status=16'h0028;wait(!ready);status=16'h002c;wait(ready);
        an=0;wait(!ready);an=1;wait(ready);
        bad_id=1;writes_before=phy.writes;restart();wait(fault==2);#10;
        if(ready || configured || phy.writes!=writes_before)$fatal(1,"wrong ID reached private writes");
        bad_id=0;no_ack=1;restart();wait(fault==1);#10;if(ready)$fatal(1,"no-ACK link opened");
        no_ack=0;ignore_tx=1;restart();wait(fault==3 || configured);#10;if(ready || configured)$fatal(1,"bad delay readback opened link");
        ignore_tx=0;wait(configured);good();
        $display("PASS rtl8211_phy_manager: pin-level Clause22, 300ns reads, 10/30ms reset, IDs, RMW/page, speed/AN/drop, faults and automatic retry");$finish;
    end
endmodule
