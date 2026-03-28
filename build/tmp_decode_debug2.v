`timescale 1ns/1ps
module t;
reg clk=0,rst=1; reg [31:0] Inst=0, WriteData=0; reg [4:0] WriteAddr=0; reg WriteEn=0;
wire [4:0] rs1_addr, rs2_addr, rd_addr; wire [31:0] rs1_data, rs2_data, Offset; wire lui,PcSrc,MemWrite,MemRead,MemToReg,AluSrc1,AluSrc2,RegWrite,Jump,Branch,IllegalInst,EBreak; wire [2:0] AluOp;
decode dut(.i_clk(clk),.i_rst(rst),.Inst(Inst),.WriteData(WriteData),.WriteAddr(WriteAddr),.WriteEn(WriteEn),.lui(lui),.PcSrc(PcSrc),.AluOp(AluOp),.MemWrite(MemWrite),.MemRead(MemRead),.MemToReg(MemToReg),.AluSrc1(AluSrc1),.AluSrc2(AluSrc2),.RegWrite(RegWrite),.Jump(Jump),.Branch(Branch),.Offset(Offset),.o_retire_rs1_raddr(rs1_addr),.o_retire_rs2_raddr(rs2_addr),.o_retire_rd_waddr(rd_addr),.o_retire_rs1_rdata(rs1_data),.o_retire_rs2_rdata(rs2_data),.IllegalInst(IllegalInst),.EBreak(EBreak));
initial begin
  @(posedge clk); rst=0;
  WriteAddr=5'd1; WriteData=32'h1111_1111; WriteEn=1'b1;
  @(posedge clk);
  $display("post1 t=%0t w_en=%b w_addr=%d w_data=%h regs1=%h regs2=%h",$time,WriteEn,WriteAddr,WriteData,dut.rf_rw.regs[1],dut.rf_rw.regs[2]);
  WriteAddr=5'd2; WriteData=32'h2222_2222; WriteEn=1'b1;
  @(posedge clk);
  $display("post2 t=%0t w_en=%b w_addr=%d w_data=%h regs1=%h regs2=%h",$time,WriteEn,WriteAddr,WriteData,dut.rf_rw.regs[1],dut.rf_rw.regs[2]);
  #5 $finish;
end
always @(posedge clk) begin
  $display("edge t=%0t rst=%b i_wen=%b i_waddr=%d i_wdata=%h",$time,rst,dut.rf_rw.i_rd_wen,dut.rf_rw.i_rd_waddr,dut.rf_rw.i_rd_wdata);
end
always #5 clk=~clk;
endmodule
