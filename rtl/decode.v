module decode (
      parameter BYPASS_EN = 0   // passed down to rf
    ) (
      input  wire        i_clk,
      input  wire        i_rst,
      input  wire [31:0] Inst,
    
      // writeback feed-in (data only)
      // NOTICE!! The writedata in pipeline should be 3 stages later than the readdata! 
      input  wire [31:0] WriteData,
      input  wire [ 4:0] WriteAddr,
      input  wire        WriteEn,
   
      // controls out
      output wire        lui,
      output wire        PcSrc,
      output wire [3:0]  AluOp,
      output wire        MemWrite,
      output wire        MemRead,
      output wire        MemToReg,
      output wire        AluSrc1,
      output wire        AluSrc2,
      output wire        RegWrite,
      output wire        Jump,
      output wire        Branch,

      // immediate out
      output wire [31:0] Offset,
    
      // retire (and also rf addressing) out
      output wire [4:0]  o_retire_rs1_raddr,
      output wire [4:0]  o_retire_rs2_raddr,
      output wire [4:0]  o_retire_rd_waddr,
      output wire [31:0] o_retire_rs1_rdata,
      output wire [31:0] o_retire_rs2_rdata,
    
      // exceptions out
      output wire        IllegalInst,
      output wire        EBreak
    );

    wire        Rs1Used;
    wire        Rs2Used;
    wire        writes_rd;

    wire [5:0]  i_format;
    wire [6:0]  opcode        = Inst[ 6: 0];
    wire [4:0]  rs1_raddr_raw = Inst[19:15];
    wire [4:0]  rs2_raddr_raw = Inst[24:20];
    wire [31:0]  rs1_rdata_raw;
    wire [31:0]  rs2_rdata_raw;
    wire [ 4:0]  rd_waddr_raw;


    assign i_format = 
            (opcode == 7'b0110011) ? 6'b000001 :
            (opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111) ? 6'b000010 :
            (opcode == 7'b0100011) ? 6'b000100 :
            (opcode == 7'b1100011) ? 6'b001000 :
            (opcode == 7'b0110111 || opcode == 7'b0010111) ? 6'b010000 :
            (opcode == 7'b1101111) ? 6'b100000 :
            6'b000000;

    assign IllegalInst = (i_format == 6'b000000);
    assign EBreak = (Inst == 32'h00100073); // System instruction

    // Drive control outputs
    wire [2:0] funct3 = Inst[14:12];
    wire [6:0] funct7 = Inst[31:25];

    assign lui = (opcode == 7'b0110111); // lui
    assign PcSrc = (opcode == 7'1100111); // jalr
    assign AluOp = opcode[6:4];
    assign MemWrite = (opcode == 7'0100011); // store
    assign MemRead = (opcode == 7'0000011); // load
    assign MemToReg = MemRead;
    assign AluSrc1 = (opcode[6:4] != 3'b011);
    assign AluSrc2 = (opcode[6:4] == 3'b110) || (opcode == 7'b0010111);
    assign RegWrite = !((opcode == 7'0100011) || (opcode == 7'1100011));
    assign Jump = (opcode == 7'b1100111) || (opcode == 7'b1101111);
    assign Branch = (opcode[6:4] == 3'b110); // Jump shouldn't include Branch

    // RF
    rf #(.BYPASS_EN(BYPASS_EN)) rf_rw (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(rs1_raddr_raw),
        .o_rs1_rdata(rs1_rdata_raw),
        .i_rs2_raddr(rs2_raddr_raw),
        .o_rs2_rdata(rs2_rdata_raw),
        .i_rd_wen   (WriteEn),
        .i_rd_waddr (WriteAddr),
        .i_rd_wdata (WriteData)
    );

    assign Rs1Used = ~ (i_format[4] || i_format[5]);
    assign Rs2Used = ~ (i_format[1] || i_format[4] || i_format[5]);
    assign writes_rd = ~ (i_format[2] || i_format[3]);
    assign o_retire_rs1_raddr = Rs1Used ? rs1_raddr_raw : 5'b0 ;
    assign o_retire_rs1_rdata = Rs1Used ? rs1_rdata_raw : 32'b0;
    assign o_retire_rs2_raddr = Rs2Used ? rs2_raddr_raw : 5'b0 ;
    assign o_retire_rs2_rdata = Rs2Used ? rs2_rdata_raw : 32'b0;
    assign o_retire_rd_waddr  = (writes_rd && !IllegalInst && !EBreak) ? rd_waddr_raw : 5'b0;

    // Imm
    imm imm_gen (
        .i_inst     (Inst),
        .i_format   (i_format),
        .o_immediate(Offset)
    );

endmodule