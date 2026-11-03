`timescale 1ns/1ps
module tb_network_beamforming;
    reg clk=0,rst=1,rx_valid=0,rx_last=0,rx_bad=0,tx_ready=1;
    reg [31:0]rx_data=0;
    wire rx_ready,tx_valid,tx_last,busy;
    wire [31:0] tx_data;
    reg [31:0]cfg[0:31],p0[0:263],p1[0:263];
    reg [15:0]vi[0:511],vq[0:511];reg [23:0]vr[0:15],vm[0:15];
    reg [255:0]ref_i,ref_q;reg [383:0]ref_sr,ref_si;
    wire ref_ov,ref_error,ref_ready;wire [47:0]ref_br,ref_bi;
    reg [47:0]gold_r[0:31],gold_i[0:31];
    reg [31:0]reply_words[0:103];
    integer j,k,captured=0,outputs=0,idx=0,packets=0,tick=0,fd;
    always #5 clk=~clk;
    network_beamforming_top dut(.clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_ready(rx_ready),
        .rx_data(rx_data),.rx_last(rx_last),.rx_bad(rx_bad),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .tx_data(tx_data),.tx_last(tx_last),.busy(busy));
    // Independent direct-input instance: never uses the adapter's IQ or steering buses.
    always @* begin
        for(integer c=0;c<16;c=c+1) begin
            ref_i[c*16 +:16]=vi[(captured%32)*16+c];ref_q[c*16 +:16]=vq[(captured%32)*16+c];
            ref_sr[c*24 +:24]=vr[c];ref_si[c*24 +:24]=vm[c];
        end
    end
    beamforming_top reference_core(.clk(clk),.rst(rst),
        .sample_valid(dut.u_network.sample_valid),.frame_start(dut.u_network.frame_start),
        .frame_end(dut.u_network.frame_end),.in_i_bus(ref_i),.in_q_bus(ref_q),
        .steering_re_bus(ref_sr),.steering_im_bus(ref_si),.capture_ready(ref_ready),
        .output_valid(ref_ov),.beam_re(ref_br),.beam_im(ref_bi),.solver_error(ref_error),
        .covariance_valid(),.weights_valid(),.solver_busy(),.frame_ready(),.replay_valid());
    always @(negedge clk)begin tick=tick+1;tx_ready=tick%7!=0;end
    always @(posedge clk)if(!rst)begin
        if(dut.u_network.sample_valid && dut.u_network.capture_ready)begin
            if(!ref_ready || dut.u_network.in_i_bus!==ref_i || dut.u_network.in_q_bus!==ref_q)
                $fatal(1,"direct-input equivalence record %0d",captured);
            // NBA avoids a reference stimulus race on the accepting edge.
            captured<=captured+1;
        end
        if(ref_error || dut.u_network.solver_error)$fatal(1,"unexpected core error");
        if(ref_ov)begin gold_r[outputs]=ref_br;gold_i[outputs]=ref_bi;outputs=outputs+1;end
        if(tx_valid && tx_ready)begin
            reply_words[idx]=tx_data;
            if(packets==1)$fdisplay(fd,"%08x",tx_data);
            if(tx_last)begin
                if(packets==0)begin
                    if(idx!=7 || reply_words[1]!==32'h01810000 || reply_words[2]!==0)$fatal(1,"ACK mismatch");
                end else begin
                    if(idx!=103 || outputs!=32 || captured!=32 || reply_words[0]!==32'h42464d31 ||
                        reply_words[1]!==32'h01820000 || reply_words[2]!==32'h12345678 ||
                        reply_words[3]!==32'h10203040 || reply_words[4]!==32'h00a00050 ||
                        reply_words[5]!==1 || reply_words[6]!==32'h00200010 || reply_words[7]!==32'h01800000)
                        $fatal(1,"result header/count mismatch");
                    for(k=0;k<32;k=k+1)begin
                        if({reply_words[8+k*3],reply_words[9+k*3][31:16]}!==gold_r[k] ||
                            {reply_words[9+k*3][15:0],reply_words[10+k*3]}!==gold_i[k])
                            $fatal(1,"network vs direct beam[%0d]",k);
                    end
                end
                packets=packets+1;idx=0;
            end else idx=idx+1;
        end
    end
    task send_packet;
        input integer source,count;
        begin
            for(j=0;j<count;j=j+1)begin
                @(negedge clk);rx_valid=1;rx_last=(j==count-1);
                case(source)0:rx_data=cfg[j];1:rx_data=p0[j];2:rx_data=p1[j];endcase
                @(posedge clk);while(!rx_ready)@(posedge clk);
                @(negedge clk);rx_valid=0;rx_last=0;
            end
        end
    endtask
    initial begin #4000000;$fatal(1,"network end-to-end timeout");end
    initial begin
        $readmemh("packets/config.hex",cfg);$readmemh("packets/iq0.hex",p0);$readmemh("packets/iq1.hex",p1);
        $readmemh("sim_vectors/reference_10mhz_gate80/iq_i.hex",vi);$readmemh("sim_vectors/reference_10mhz_gate80/iq_q.hex",vq);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",vr);$readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",vm);
        fd=$fopen("network_result.hex","w");if(!fd)$fatal(1,"cannot write result");
        repeat(4)@(negedge clk);rst=0;
        send_packet(0,32);wait(packets==1);send_packet(1,264);send_packet(2,264);
        wait(packets==2);@(negedge clk);$fclose(fd);
        if(busy)$fatal(1,"ownership not released after complete result TX");
        $display("PASS network_beamforming: COS -> Python BFM1 packets -> real MVDR -> 32 bit-exact direct-core beam records");$finish;
    end
endmodule
