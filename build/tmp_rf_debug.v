`timescale 1ns/1ps
module t;
  reg clk=0, rst=1;
  reg [4:0] rs1_addr=0, rs2_addr=0, waddr=0;
  reg wen=0;
  reg [31:0] wdata=0;
  wire [31:0] rs1;
  rf #(.BYPASS_EN(1)) dut (
    .i_clk(clk), .i_rst(rst), .i_rs1_raddr(rs1_addr), .o_rs1_rdata(rs1),
    .i_rs2_raddr(rs2_addr), .o_rs2_rdata(), .i_rd_wen(wen), .i_rd_waddr(waddr), .i_rd_wdata(wdata)
  );
  initial begin
    #2; rs1_addr=5'd1; rs2_addr=5'd2;
    #8; // reach t10
    rst=0;
    waddr=5'd1; wdata=32'hA5A5_A5A5; wen=1'b1; rs1_addr=5'd1;
    #1;
    $display("t=%0t rst=%b wen=%b waddr=%0d rs1_addr=%0d hit=%b rs1=%h", $time, rst, wen, waddr, rs1_addr, dut.rs1_bypass_hit, rs1);
    #20; $finish;
  end
  always #5 clk=~clk;
endmodule
