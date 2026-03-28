`timescale 1ns/1ps
module t;
    reg clk;
    reg rst;

    reg  [4:0] rs1_addr;
    reg  [4:0] rs2_addr;
    reg        wen;
    reg  [4:0] waddr;
    reg  [31:0] wdata;

    wire [31:0] rs1_no_bypass;
    wire [31:0] rs2_no_bypass;
    wire [31:0] rs1_bypass;
    wire [31:0] rs2_bypass;

    rf #(.BYPASS_EN(0)) dut_no_bypass (
        .i_clk      (clk),
        .i_rst      (rst),
        .i_rs1_raddr(rs1_addr),
        .o_rs1_rdata(rs1_no_bypass),
        .i_rs2_raddr(rs2_addr),
        .o_rs2_rdata(rs2_no_bypass),
        .i_rd_wen   (wen),
        .i_rd_waddr (waddr),
        .i_rd_wdata (wdata)
    );

    rf #(.BYPASS_EN(1)) dut_bypass (
        .i_clk      (clk),
        .i_rst      (rst),
        .i_rs1_raddr(rs1_addr),
        .o_rs1_rdata(rs1_bypass),
        .i_rs2_raddr(rs2_addr),
        .o_rs2_rdata(rs2_bypass),
        .i_rd_wen   (wen),
        .i_rd_waddr (waddr),
        .i_rd_wdata (wdata)
    );

    initial begin
        clk = 0;
        rst = 1;
        wen = 0;
        waddr = 0;
        wdata = 0;
        rs1_addr = 0;
        rs2_addr = 0;

        #2;
        rs1_addr = 5'd1;
        rs2_addr = 5'd2;
        #2;
        $display("t=%0t rst=%b rs1_nb=%h rs2_nb=%h", $time, rst, rs1_no_bypass, rs2_no_bypass);

        @(negedge clk);
        rst = 0;

        waddr = 5'd1;
        wdata = 32'hA5A5_A5A5;
        wen   = 1'b1;
        rs1_addr = 5'd1;

        #1;
        $display("t=%0t rst=%b wen=%b rs1_bypass=%h hit=%b", $time, rst, wen, rs1_bypass, dut_bypass.rs1_bypass_hit);
        #20;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
