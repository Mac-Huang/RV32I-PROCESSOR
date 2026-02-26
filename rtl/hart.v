module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Instruction fetch goes through a read only instruction memory (imem)
    // port. The port accepts a 32-bit address (e.g. from the program counter)
    // per cycle and combinationally returns a 32-bit instruction word. This
    // is not representative of a realistic memory interface; it has been
    // modeled as more similar to a DFF or SRAM to simplify phase 3. In
    // later phases, you will replace this with a more realistic memory.
    //
    // 32-bit read address for the instruction memory. This is expected to be
    // 4 byte aligned - that is, the two LSBs should be zero.
    output wire [31:0] o_imem_raddr,
    // Instruction word fetched from memory, available on the same cycle.
    input  wire [31:0] i_imem_rdata,
    // Data memory accesses go through a separate read/write data memory (dmem)
    // that is shared between read (load) and write (stored). The port accepts
    // a 32-bit address, read or write enable, and mask (explained below) each
    // cycle. Reads are combinational - values are available immediately after
    // updating the address and asserting read enable. Writes occur on (and
    // are visible at) the next clock edge.
    //
    // Read/write address for the data memory. This should be 32-bit aligned
    // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
    // half-word and byte accesses at unaligned addresses.
    output wire [31:0] o_dmem_addr,
    // When asserted, the memory will perform a read at the aligned address
    // specified by `i_addr` and return the 32-bit word at that address
    // immediately (i.e. combinationally). It is illegal to assert this and
    // `o_dmem_wen` on the same cycle.
    output wire        o_dmem_ren,
    // When asserted, the memory will perform a write to the aligned address
    // `o_dmem_addr`. When asserted, the memory will write the bytes in
    // `o_dmem_wdata` (specified by the mask) to memory at the specified
    // address on the next rising clock edge. It is illegal to assert this and
    // `o_dmem_ren` on the same cycle.
    output wire        o_dmem_wen,
    // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
    // write enable is asserted, the byte lanes specified by the mask will be
    // written to the memory word at the aligned address at the next rising
    // clock edge. The other byte lanes of the word will be unaffected.
    output wire [31:0] o_dmem_wdata,
    // The dmem interface expects word (32 bit) aligned addresses. However,
    // WISC-25 supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    //
    // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
    // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
    // indicate that only the upper two bytes should be read. Only the upper
    // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
    // calculate the final value of the `lh[u]` instruction, shift the rdata
    // word right by 16 bits and sign/zero extend as appropriate.
    //
    // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
    // `0x00002000`, assert `o_dmem_wen`, and set the mask to 0b1000 to
    // indicate that only the upper byte should be written. On the next clock
    // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
    // the other three bytes of the aligned word unaffected. Remember to shift
    // the value of the `sb` instruction left by 24 bits to place it in the
    // appropriate byte lane.
    output wire [ 3:0] o_dmem_mask,
    // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
    // this will immediately reflect the contents of memory at the specified
    // address, for the bytes enabled by the mask. When read enable is not
    // asserted, or for bytes not set in the mask, the value is undefined.
    input  wire [31:0] i_dmem_rdata,
	// The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);

    // =========================================================================
    // 0) TOP-LEVEL INTERNAL WIRES / STATE
    // =========================================================================

    // PC register
    reg  [31:0] pc;

    // Instruction word (fetched)
    wire [31:0] Inst;            // alias for i_imem_rdata in core
    assign Inst = i_imem_rdata;

    // Basic fields
    wire [6:0] opcode;
    wire [2:0] Func3;
    wire [6:0] Func7;

    // Control signals
    wire        lui;     
    wire        PcSrc;   
    wire [2:0]  AluOp;   
    wire        MemWrite;
    wire        MemRead; 
    wire        MemToReg;
    wire        AluSrc1; 
    wire        AluSrc2;
    // Both RegWrite are the same before being pipelined
    wire        EX_RegWrite;
    wire        WB_RegWrite;
    wire [4:0]  EX_WriteAddr;
    wire [4:0]  WB_WriteAddr;
    wire        Jump;    
    wire        Branch;  

    // Immediate
    wire [31:0] Offset;          // output of Immediate Generator

    // Register file connections
    // Read addresses: from decode
    // Write address: from decode
    // Read data: from regfile
    wire [4:0]  rs1_raddr = o_retire_rs1_raddr;
    wire [4:0]  rs2_raddr = o_retire_rs2_raddr;
    wire [4:0]  rd_waddr  = o_retire_rd_waddr;

    // Operand mux outputs
    wire [31:0] Operand1;
    wire [31:0] Operand2;

    // ALU outputs from alu.v module
    wire [31:0] AluResult;
    wire        ALUeq;      
    wire        ALUslt;             

    // =========================================================================
    // LSU pack/unpack intermediates
    wire [31:0] EffAddr;          // effective address (usually AluResult)
    assign EffAddr = AluResult;

    wire [31:0] LoadData;         // unpacked + sign/zero-extended load value

    // Writeback bus
    wire [31:0] WriteData;         // final data to regfile (also o_retire_rd_wdata)

    // Next PC logic
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] NextPC;
    wire        BranchTaken;       // computed from branch/jump unit

    // Trap/halt (retire)
    wire        IllegalInst;       // decoder says illegal
    wire        MisalignTrap;      // LSU / PC target misalign
    wire        EBreak;            // decoder says ebreak

    assign o_imem_raddr   = pc;
    assign o_retire_pc    = pc;
    assign o_retire_inst  = Inst;
    assign o_retire_valid = ~i_rst;
    assign o_retire_halt  = EBreak;

    assign opcode = Inst[6:0];
    assign Func3  = Inst[14:12];
    assign Func7  = Inst[31:25];

    // =========================================================================
    // 1) PC REGISTER + INSTRUCTION FETCH "MODULE"
    // =========================================================================
    // Spec: Instruction memory is combinational read.
    // - Provide address = pc (4-byte aligned expected)
    // - Receive Inst = i_imem_rdata same cycle

    // PC flop: single-cycle retires each cycle unless reset/stop.
    // NOTE: if you want halt to freeze, gate update with ~EBreak.
    always @(posedge i_clk) begin
        if (i_rst) pc <= RESET_ADDR;
        else if (EBreak) pc <= pc;      // freeze
        else pc <= NextPC;
    end

    // NextPC to be computed below
    // Jump/Branch logic is seperated for future pipelining
    assign BranchTaken = 
        (Func3 == 3'b000) ?  ALUeq :
        (Func3 == 3'b001) ? ~ALUeq :
        (Func3 == 3'b100) ?  ALUslt :
        (Func3 == 3'b101) ? ~ALUslt :
        (Func3 == 3'b110) ?  ALUslt :
        (Func3 == 3'b111) ? ~ALUslt :
        1'b0;

    wire do_branch = Branch & BranchTaken;
    wire do_jump   = Jump;

    wire [31:0] nextpc_base = PcSrc ? o_retire_rs1_rdata : pc;
    wire [31:0] nextpc_add  = (do_jump | do_branch) ? Offset : 32'd4;
    wire [31:0] nextpc_raw  = nextpc_base + nextpc_add;

    // JALR requires bit0 = 0 (RISC-V spec)
    wire [31:0] nextpc_masked = (do_jump & PcSrc) ? (nextpc_raw & 32'hFFFF_FFFE) : nextpc_raw;
    assign NextPC = nextpc_masked;

    // Instruction address must be 4-byte aligned for RV32I (no C extension).
    wire MisalignPC = (do_jump | do_branch) & (nextpc_masked[1:0] != 2'b00);

    assign o_retire_next_pc = NextPC;
    assign o_retire_trap    = IllegalInst | MisalignTrap | MisalignPC;

    // =========================================================================
    // 2) DECODE MODULE (COMBINATIONAL) — control + reg addrs + imm
    // =========================================================================
    //
    // Inputs:
    //   - i_clk, i_rst, Inst (32-bit), WriteData, WB_RegWrite
    //
    // Outputs:
    //   - CONTROLs:
    //       lui, PcSrc, AluOp,
    //       MemWrite, MemRead, MemToReg,
    //       AluSrc1, AluSrc2,
    //       EX_RegWrite, Jump, Branch
    //
    //   - Retire register fields (already “semantic”, already zeroed when unused):
    //       o_retire_rs1_raddr, o_retire_rs2_raddr, o_retire_rd_waddr
    //       o_retire_rs1_rdata, o_retire_rs2_rdata
    //
    //   - Exception flags:
    //       IllegalInst, EBreak
    //

    decode #(.BYPASS_EN(0)) u_decode (
      .i_clk            (i_clk),
      .i_rst            (i_rst),
      .Inst             (Inst),
      // NOTICE!! The writedata in pipeline should be 3 stages later than the readdata! 
      .WriteData        (WriteData),
      .WriteAddr        (WB_WriteAddr),
      .WriteEn          (WB_RegWrite),
    
      .lui              (lui),
      .PcSrc            (PcSrc),
      .AluOp            (AluOp),
      .MemWrite         (MemWrite),
      .MemRead          (MemRead),
      .MemToReg         (MemToReg),
      .AluSrc1          (AluSrc1),
      .AluSrc2          (AluSrc2),
      .RegWrite         (EX_RegWrite),
      .Jump             (Jump),
      .Branch           (Branch),

      .Offset           (Offset),
    
      .o_retire_rs1_raddr(o_retire_rs1_raddr),
      .o_retire_rs2_raddr(o_retire_rs2_raddr),
      .o_retire_rd_waddr (o_retire_rd_waddr), // EX_WriteAddr
      .o_retire_rs1_rdata(o_retire_rs1_rdata),
      .o_retire_rs2_rdata(o_retire_rs2_rdata),
    
      .IllegalInst      (IllegalInst),
      .EBreak           (EBreak)
    );

    assign EX_WriteAddr = o_retire_rd_waddr; 
    assign WB_WriteAddr = EX_WriteAddr; 
    assign WB_RegWrite  = EX_RegWrite; // It's the same in one cycle design
    // It might be confusing that EX_RegWrite is the output while
    // WB_RegWrite is the input. Then how come assign the output to the input.
    // The answer is that it's asynchronous when the Instruction decoder
    // decoding the instruction to controls (RegRead), and the write reg is synchronous,
    // which is not triggered before `assign WB_RegWrite = EX_RegWrite;`

    // I seperate 2 AluSrc Mux from Exeecute Module
    // because these two mux will be modified for pipelined
    assign Operand1 = AluSrc1 ? o_retire_pc : o_retire_rs1_rdata;
    assign Operand2 = AluSrc2 ? Offset      : o_retire_rs2_rdata;

    // =========================================================================
    // 3) EXECUTE MODULE — ALU CONTROL UNIT + ALU
    // =========================================================================
    //
    // Goal:
    //   - Turn decoded AluOp into the *actual* ALU control pins required by alu.v
    //   - Compute AluResult + flags (ALUeq, ALUslt)
    //
    // Inputs:
    //   CONTROLs:
    //     AluOp      [2:0]
    //
    //   DATA:
    //     Operand1   [31:0]
    //     Operand2   [31:0]
    //
    //   INST bits needed for ALU-control refinement:
    //     Func3      [2:0]
    //     Func7      [6:0]
    //     opcode     [6:0] (optional, depends on how you encoded AluOp)
    //
    // Outputs:
    //   AluResult  [31:0]  (goes to EffAddr for loads/stores; also WB for ALU ops)
    //   ALUeq              (branch compare eq)
    //   ALUslt             (branch compare lt/slt result depending on unsigned control)

    execute u_execute (
        .AluOp     (AluOp),
        .Func3     (Func3),
        .Func7     (Func7),
        .opcode    (opcode),
        .Operand1  (Operand1),
        .Operand2  (Operand2),
        .AluResult (AluResult),
        .ALUeq     (ALUeq),
        .ALUslt    (ALUslt)
    );

    // =========================================================================
    // 4) MEMORY
    // =========================================================================
    // 
    // NOTE:
    //   - o_dmem_addr must be word-aligned
    //   - mask (I don't get it, Like; figure that out and teach me)
    //   - Exclusive ren and wen
    //
    // Inputs (from earlier stages):
    //   EffAddr       [31:0]   (already assigned with AluResult)
    //   StoreData     [31:0]   (o_retire_rs2_rdata)
    //   Func3         [2:0]    (Func3)
    //   MemRead, MemWrite
    //
    // Outputs (to top-level dmem port):
    //   o_dmem_addr   [31:0]   aligned
    //   o_dmem_mask   [3:0]
    //   o_dmem_wdata  [31:0]   lane-shifted
    //   o_dmem_ren, o_dmem_wen
    //   MisalignTrap
    //
    // Output (to WB):
    //   LoadData      [31:0]   final value for lb/lh/lw etc.

    memory u_memory (
        .EffAddr        (EffAddr),
        .StoreData      (o_retire_rs2_rdata),
        .Func3          (Func3),
        .MemRead        (MemRead),
        .MemWrite       (MemWrite),
        .i_dmem_rdata   (i_dmem_rdata),

        .o_dmem_addr    (o_dmem_addr),
        .o_dmem_mask    (o_dmem_mask),
        .o_dmem_wdata   (o_dmem_wdata),
        .o_dmem_ren     (o_dmem_ren),
        .o_dmem_wen     (o_dmem_wen),

        .LoadData       (LoadData),
        .MisalignTrap   (MisalignTrap)
    );


    // =========================================================================
    // 5) WRITEBACK
    // =========================================================================
    //
    // Inputs:
    //   AluResult  [31:0]
    //   LoadData   [31:0]
    //   pc_plus4   [31:0]
    //   Offset     [31:0]   (for LUI, and for AUIPC if you implement that style)
    //   CONTROLs: MemToReg, lui, Jump
    //
    // Output:
    //   WriteData  [31:0]

    writeback u_writeback (
        .AluResult (AluResult),
        .LoadData  (LoadData),
        .pc_plus4  (pc_plus4),
        .Offset    (Offset),
        .MemToReg  (MemToReg),
        .lui       (lui),
        .Jump      (Jump),
        .WriteData (WriteData)
    );    

    assign o_retire_rd_wdata = WriteData;

endmodule

`default_nettype wire
