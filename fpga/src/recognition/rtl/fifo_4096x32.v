`timescale 1ns/1ps
module fifo_4096x32(
    input             clk,
    input             rst,
    input      [31:0] din,
    input             wr_en,
    input             rd_en,
    output reg [31:0] dout
);
    (* ram_style = "block" *) reg [31:0] memory [0:4095];
    reg [11:0] write_pointer;
    reg [11:0] read_pointer;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_pointer <= 12'd0;
            read_pointer  <= 12'd0;
        end else begin
            if (wr_en)
                write_pointer <= write_pointer + 12'd1;
            if (rd_en)
                read_pointer <= read_pointer + 12'd1;
        end
    end

    always @(posedge clk) begin
        if (wr_en)
            memory[write_pointer] <= din;
        if (rd_en)
            dout <= memory[read_pointer];
    end
endmodule
