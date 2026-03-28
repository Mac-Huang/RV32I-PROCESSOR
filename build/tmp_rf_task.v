`timescale 1ns/1ps
module tb;
reg clk,rst,wen; reg [4:0] rs1_addr,rs2_addr,waddr; reg [31:0] wdata; wire [31:0] rs1;
rf #(.BYPASS_EN(1)) dut(.i_clk(clk),.i_rst(rst),.i_rs1_raddr(rs1_addr),.o_rs1_rdata(rs1),.i_rs2_raddr(rs2_addr),.o_rs2_rdata(),.i_rd_wen(wen),.i_rd_waddr(waddr),.i_rd_wdata(wdata));
task check; input [31:0] got; begin #1; $display("t=%0t got=%h rst=%b wen=%b waddr=%d rs1_addr=%d",$time,got,rst,wen,waddr,rs1_addr); end endtask
initial begin clk=0; rst=1; wen=0; waddr=0; wdata=0; rs1_addr=0; rs2_addr=0; #2; rs1_addr=5'd1; rs2_addr=5'd2; check(rs1); check(rs1); @(negedge clk); rst=0; waddr=5'd1; wdata=32'hA5A5_A5A5; wen=1'b1; rs1_addr=5'd1; check(rs1); #20; $finish; end
always #5 clk=~clk;
endmodule
