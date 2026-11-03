`timescale 1ns/1ps
module solver_equivalence_case #(parameter integer N=16)(output reg finished=0);
    reg clk=0,rst=1,request=0,busy_probe=0;
    reg signed [N*N*48-1:0] rr=0,ri=0;
    reg signed [N*24-1:0] sr=0,si=0;
    wire bv,nv,bb,nb,ne;
    wire signed [N*24-1:0] bwr,bwi,nwr,nwi;
    reg signed [N*24-1:0] saved_re,saved_im;
    reg baseline_seen=0;
    reg [47:0] file_rr[0:255],file_ri[0:255];
    reg [23:0] file_sr[0:15],file_si[0:15];
    integer frame_no,i,j,ir,iq,jr,jq;
    integer cycles=0,started_at;
    always #5 clk=~clk;
    always @(posedge clk) begin
        cycles=cycles+1;
        #1;
        if(!rst && bv) begin saved_re=bwr; saved_im=bwi; baseline_seen=1; end
        if(!rst && ne) $fatal(1,"unexpected solver error N=%0d frame=%0d",N,frame_no);
    end
    mvdr_solver_baseline #(.N_CH(N)) baseline(.clk(clk),.rst(rst),.matrix_valid(request),
        .r_re_bus(rr),.r_im_bus(ri),.steering_re_bus(sr),.steering_im_bus(si),
        .weights_valid(bv),.busy(bb),.weight_re_bus(bwr),.weight_im_bus(bwi));
    mvdr_solver_stub #(.N_CH(N)) candidate(.clk(clk),.rst(rst),.matrix_valid(request||busy_probe),
        .r_re_bus(rr),.r_im_bus(ri),.steering_re_bus(sr),.steering_im_bus(si),
        .weights_valid(nv),.busy(nb),.weight_re_bus(nwr),.weight_im_bus(nwi),.solver_error(ne));
    task fill_inputs;
        input integer mode;
        begin
            rr=0; ri=0;
            for(i=0;i<N;i=i+1) begin
                sr[i*24 +: 24]=file_sr[i]; si[i*24 +: 24]=file_si[i];
                for(j=0;j<N;j=j+1) begin
                    if(N==16 && mode==0) begin
                        rr[(i*N+j)*48 +: 48]=file_rr[i*16+j];
                        ri[(i*N+j)*48 +: 48]=file_ri[i*16+j];
                    end else if(mode==1) begin
                        rr[(i*N+j)*48 +: 48]=(i==j) ? (i+1)*100000 : 0;
                    end else begin
                        ir=(i%3-1)*40; iq=(i%5-2)*31;
                        jr=(j%3-1)*40; jq=(j%5-2)*31;
                        rr[(i*N+j)*48 +: 48]=ir*jr+iq*jq+((i==j) ? 100000+mode*1000 : 0);
                        ri[(i*N+j)*48 +: 48]=iq*jr-ir*jq;
                    end
                end
            end
        end
    endtask
    task compare_frame;
        input integer mode;
        begin
            @(negedge clk); fill_inputs(mode); baseline_seen=0; request=1; started_at=cycles;
            @(negedge clk); request=0;
            if(!nb || !bb) $fatal(1,"matrix not accepted N=%0d",N);
            // Both solvers promise a snapshot. Mutate every input and send an
            // extra request only to the busy candidate; neither may affect it.
            rr=0; ri=0; sr=0; si=0;
            repeat(5) @(negedge clk); busy_probe=1;
            @(negedge clk); busy_probe=0;
            wait(nv===1'b1); #1;
            if(!baseline_seen) $fatal(1,"baseline did not finish first");
            if(nwr!==saved_re || nwi!==saved_im) begin
                for(i=0;i<N;i=i+1)
                    if(nwr[i*24 +: 24]!==saved_re[i*24 +: 24] || nwi[i*24 +: 24]!==saved_im[i*24 +: 24])
                        $display("N=%0d frame=%0d weight=%0d new=(%0d,%0d) old=(%0d,%0d)",N,mode,i,
                            $signed(nwr[i*24 +: 24]),$signed(nwi[i*24 +: 24]),
                            $signed(saved_re[i*24 +: 24]),$signed(saved_im[i*24 +: 24]));
                $fatal(1,"solver bit equivalence failed");
            end
            $display("MATCH solver N=%0d frame=%0d cycles=%0d",N,mode,cycles-started_at);
            repeat(2) @(negedge clk);
            if(nb || nv || ne) $fatal(1,"solver completion was not a pulse");
        end
    endtask
    initial begin
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_re.hex",file_rr);
        $readmemh("sim_vectors/reference_10mhz_gate80/cov_im.hex",file_ri);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_re.hex",file_sr);
        $readmemh("sim_vectors/reference_10mhz_gate80/steering_im.hex",file_si);
        repeat(3) @(negedge clk); rst=0;
        for(frame_no=0;frame_no<3;frame_no=frame_no+1) compare_frame(frame_no);
        // Reset during matrix loading, then require a clean subsequent solve.
        @(negedge clk); fill_inputs(4); request=1;
        @(negedge clk); request=0;
        repeat(100) @(negedge clk); rst=1;
        repeat(2) @(negedge clk); rst=0;
        repeat(150) begin @(negedge clk); if(nv || nb || ne) $fatal(1,"stale transaction after reset"); end
        frame_no=4; compare_frame(4);
        $display("PASS solver_equivalence_case N=%0d: four frames, exact weights, input snapshot, busy, reset",N);
        finished=1;
    end
endmodule

module tb_mvdr_solver_equivalence;
    wire a,b,c;
    solver_equivalence_case #(.N(1)) singleton(a);
    solver_equivalence_case #(.N(3)) non_power_of_two(b);
    solver_equivalence_case #(.N(16)) current_size(c);
    initial begin #10000000; $fatal(1,"solver equivalence timeout"); end
    initial begin wait(a&&b&&c); $display("PASS mvdr_solver_equivalence:"); $finish; end
endmodule
