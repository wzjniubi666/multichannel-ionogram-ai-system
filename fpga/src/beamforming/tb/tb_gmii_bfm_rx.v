`timescale 1ns/1ps
module tb_gmii_bfm_rx;
    reg clk=0,rst=1,dv=0,er=0,available=1;
    reg [7:0]data=0,bytes_mem[0:1599];
    wire we,commit,arp;
    wire [8:0]addr,words;
    wire [31:0]wd,accepted,rejected,overflow;
    reg [31:0]cfg[0:31];
    reg checking=1;
    integer commits=0,arps=0,writes=0,i,old_commits,old_rejects;
    always #4 clk=~clk;
    gmii_bfm_rx dut(.clk(clk),.rst(rst),.gmii_rx_dv(dv),.gmii_rx_er(er),.gmii_rxd(data),
        .store_available(available),.arp_ready(1'b1),.store_we(we),.store_commit(commit),
        .store_addr(addr),.store_words(words),.store_data(wd),.arp_request(arp),
        .accepted_packets(accepted),.rejected_frames(rejected),.overflow_frames(overflow));
    always @(posedge clk)if(!rst)begin
        if(we)begin
            if(checking && (addr!==writes || wd!==cfg[writes]))$fatal(1,"RX big-endian payload mapping word %0d",writes);
            writes=writes+1;
        end
        if(commit)begin if(words!=32 || writes!=32)$fatal(1,"commit word count");commits=commits+1;end
        if(arp)arps=arps+1;
    end
    task frame;
        input [511:0]name;
        input integer count,error_index;
        begin
            writes=0;$readmemh(name,bytes_mem,0,count-1);
            for(i=0;i<count;i=i+1)begin
                @(negedge clk);dv=1;data=bytes_mem[i];er=(i==error_index);
            end
            @(negedge clk);dv=0;er=0;repeat(16)@(negedge clk);
        end
    endtask
    task bad_frame;
        input [511:0]name;
        input integer count,error_index;
        begin
            old_commits=commits;old_rejects=rejected;
            // Speculative payloads of negative fixtures need not match CONFIG.
            checking=0;frame(name,count,error_index);checking=1;
            if(commits!=old_commits || rejected!=old_rejects+1)$fatal(1,"bad packet accepted: %s",name);
        end
    endtask
    initial begin #1000000;$fatal(1,"GMII RX test timeout");end
    initial begin
        $readmemh("packets/config.hex",cfg);
        repeat(4)@(negedge clk);rst=0;
        frame("gmii/config.hex",182,-1);
        if(commits!=1 || accepted!=1 || rejected!=0)$fatal(1,"valid UDP rejected");
        bad_frame("gmii/bad_fcs.hex",182,-1);
        bad_frame("gmii/bad_ip.hex",182,-1);bad_frame("gmii/bad_udp.hex",182,-1);
        bad_frame("gmii/zero_udp.hex",182,-1);bad_frame("gmii/fragment.hex",182,-1);
        bad_frame("gmii/fragment_offset.hex",182,-1);bad_frame("gmii/protocol.hex",182,-1);
        bad_frame("gmii/options.hex",182,-1);bad_frame("gmii/foreign_ip.hex",182,-1);
        bad_frame("gmii/port.hex",182,-1);bad_frame("gmii/source_port.hex",182,-1);
        bad_frame("gmii/udp_length.hex",182,-1);bad_frame("gmii/ip_length.hex",182,-1);
        bad_frame("gmii/bad_preamble.hex",182,-1);bad_frame("gmii/truncated.hex",175,-1);
        bad_frame("gmii/unaligned.hex",183,-1);bad_frame("gmii/oversized.hex",1114,-1);
        bad_frame("gmii/config.hex",182,80);
        available=0;checking=0;frame("gmii/config.hex",182,-1);checking=1;
        if(overflow!=1 || commits!=1)$fatal(1,"full slot not dropped atomically");available=1;
        checking=0;frame("gmii/arp.hex",72,-1);checking=1;
        if(arps!=1)$fatal(1,"valid ARP request not delivered");
        // Reset during speculative data must not publish it.
        writes=0;$readmemh("gmii/config.hex",bytes_mem,0,181);
        for(i=0;i<100;i=i+1)begin @(negedge clk);dv=1;data=bytes_mem[i];end
        @(negedge clk);rst=1;dv=0;repeat(4)@(negedge clk);rst=0;
        checking=1;frame("gmii/config.hex",182,-1);
        if(accepted!=1)$fatal(1,"RX failed after reset");
        $display("PASS gmii_bfm_rx: valid UDP/ARP, FCS/IP/UDP/fragment/port/length/RX_ER rejection, full drop, reset");$finish;
    end
endmodule
