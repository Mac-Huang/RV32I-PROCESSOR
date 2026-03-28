`timescale 1ns/1ps
module t;
    reg clk;
    reg rst;
    reg [31:0] Inst;
    reg [31:0] WriteData;
    reg [4:0]  WriteAddr;
    reg        WriteEn;

    wire        lui;
    wire        PcSrc;
    wire [2:0]  AluOp;
    wire        MemWrite;
    wire        MemRead;
    wire        MemToReg;
    wire        AluSrc1;
    wire        AluSrc2;
    wire        RegWrite;
    wire        Jump;
    wire        Branch;
    wire [31:0] Offset;
    wire [4:0]  rs1_addr;
    wire [4:0]  rs2_addr;
    wire [4:0]  rd_addr;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire        IllegalInst;
    wire        EBreak;

    decode dut (
        .i_clk            (clk),
        .i_rst            (rst),
        .Inst             (Inst),
        .WriteData        (WriteData),
        .WriteAddr        (WriteAddr),
        .WriteEn          (WriteEn),
        .lui              (lui),
        .PcSrc            (PcSrc),
        .AluOp            (AluOp),
        .MemWrite         (MemWrite),
        .MemRead          (MemRead),
        .MemToReg         (MemToReg),
        .AluSrc1          (AluSrc1),
        .AluSrc2          (AluSrc2),
        .RegWrite         (RegWrite),
        .Jump             (Jump),
        .Branch           (Branch),
        .Offset           (Offset),
        .o_retire_rs1_raddr(rs1_addr),
        .o_retire_rs2_raddr(rs2_addr),
        .o_retire_rd_waddr (rd_addr),
        .o_retire_rs1_rdata(rs1_data),
        .o_retire_rs2_rdata(rs2_data),
        .IllegalInst      (IllegalInst),
        .EBreak           (EBreak)
    );

    initial begin
        clk = 0;
        rst = 1;
        Inst = 32'b0;
        WriteData = 32'b0;
        WriteAddr = 5'b0;
        WriteEn = 1'b0;

        @(posedge clk);
        rst = 0;

        WriteAddr = 5'd1; WriteData = 32'h1111_1111; WriteEn = 1'b1;
        @(posedge clk);
        $display("after write1 t=%0t regs1=%h regs2=%h rs2_raw=%h", $time, dut.rf_rw.regs[1], dut.rf_rw.regs[2], dut.rs2_rdata_raw);
        WriteAddr = 5'd2; WriteData = 32'h2222_2222; WriteEn = 1'b1;
        @(posedge clk);
        $display("after write2 t=%0t regs1=%h regs2=%h rs2_raw=%h", $time, dut.rf_rw.regs[1], dut.rf_rw.regs[2], dut.rs2_rdata_raw);
        WriteEn = 1'b0;

        Inst = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011};
        #1;
        $display("rtype t=%0t rs1=%d rs2=%d rs1_data=%h rs2_data=%h rs2_raw=%h", $time, rs1_addr, rs2_addr, rs1_data, rs2_data, dut.rs2_rdata_raw);
        #10;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
