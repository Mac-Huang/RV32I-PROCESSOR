module decode #(
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
      output wire [2:0]  AluOp,
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
      output wire [ 4:0]  o_retire_rs1_raddr,
      output wire [ 4:0]  o_retire_rs2_raddr,
      output wire [ 4:0]  o_retire_rd_waddr,
      output wire [31:0] o_retire_rs1_rdata,
      output wire [31:0] o_retire_rs2_rdata,
    
      // exceptions out
      output wire        IllegalInst,
      output wire        EBreak
    );

    wire        Rs1Used;
    wire        Rs2Used;
    wire        writes_rd;

    wire [ 5:0]  i_format;
    wire [ 6:0]  opcode        = Inst[ 6: 0];
    wire [ 4:0]  rd_waddr_raw  = Inst[11: 7];
    wire [ 4:0]  rs1_raddr_raw = Inst[19:15];
    wire [ 4:0]  rs2_raddr_raw = Inst[24:20];
    wire [31:0]  rs1_rdata_raw;
    wire [31:0]  rs2_rdata_raw;

    wire is_rtype     = (opcode == 7'b0110011);
    wire is_itype_alu = (opcode == 7'b0010011);
    wire is_load      = (opcode == 7'b0000011);
    wire is_store     = (opcode == 7'b0100011);
    wire is_branch    = (opcode == 7'b1100011);
    wire is_lui       = (opcode == 7'b0110111);
    wire is_auipc     = (opcode == 7'b0010111);
    wire is_jal       = (opcode == 7'b1101111);
    wire is_jalr      = (opcode == 7'b1100111);
    wire is_ebreak    = (Inst   == 32'h00100073);

    assign i_format =
            is_rtype                         ? 6'b000001 :
            (is_itype_alu || is_load || is_jalr) ? 6'b000010 :
            is_store                         ? 6'b000100 :
            is_branch                        ? 6'b001000 :
            (is_lui || is_auipc)             ? 6'b010000 :
            is_jal                           ? 6'b100000 :
                                               6'b000000;

    assign EBreak = is_ebreak;
    assign IllegalInst = ~(is_rtype | is_itype_alu | is_load | is_store |
                           is_branch | is_lui | is_auipc | is_jal | is_jalr | is_ebreak);

    // Control outputs
    assign lui      = is_lui;
    assign PcSrc    = is_jalr;
    assign AluOp    = opcode[6:4];
    assign MemWrite = is_store;
    assign MemRead  = is_load;
    assign MemToReg = is_load;

    // ALU operand select:
    //   AluSrc1 = 1 uses PC (AUIPC)
    //   AluSrc2 = 1 uses immediate
    assign AluSrc1 = is_auipc;
    assign AluSrc2 = is_itype_alu | is_load | is_store | is_auipc | is_jalr;

    assign RegWrite = is_rtype | is_itype_alu | is_load | is_lui | is_auipc | is_jal | is_jalr;
    assign Jump     = is_jal | is_jalr;
    assign Branch   = is_branch;

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

    assign Rs1Used = is_rtype | is_itype_alu | is_load | is_store | is_branch | is_jalr;
    assign Rs2Used = is_rtype | is_store | is_branch;
    assign writes_rd = RegWrite;
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
