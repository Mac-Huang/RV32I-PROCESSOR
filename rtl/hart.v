`default_nettype none

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
    output wire [31:0] o_retire_dmem_addr,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire [31:0] o_retire_dmem_wdata,
    output wire [31:0] o_retire_dmem_rdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc
`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS
`endif
);

    // -------------------------------------------------------------------------
    // Global state
    // -------------------------------------------------------------------------
    reg [31:0] pc_cur;
    reg        halted_cur;

    // -------------------------------------------------------------------------
    // IF stage + IF/ID register
    // -------------------------------------------------------------------------
    wire [31:0] if_pc_cur;
    wire [31:0] if_pc_plus4_cur;
    wire [31:0] if_inst_cur;
    wire [31:0] pc_next;

    reg         if_id_valid_cur;
    reg  [31:0] if_id_pc_cur;
    reg  [31:0] if_id_pc_plus4_cur;
    reg  [31:0] if_id_inst_cur;

    wire        if_id_valid_next;
    wire [31:0] if_id_pc_next;
    wire [31:0] if_id_pc_plus4_next;
    wire [31:0] if_id_inst_next;

    // -------------------------------------------------------------------------
    // ID stage + ID/EX register
    // -------------------------------------------------------------------------
    wire        id_lui_cur;
    wire        id_pc_src_cur;
    wire [2:0]  id_alu_op_cur;
    wire        id_mem_write_cur;
    wire        id_mem_read_cur;
    wire        id_mem_to_reg_cur;
    wire        id_alu_src1_cur;
    wire        id_alu_src2_cur;
    wire        id_reg_write_cur;
    wire        id_jump_cur;
    wire        id_branch_cur;
    wire [31:0] id_offset_cur;
    wire [4:0]  id_rs1_raddr_cur;
    wire [4:0]  id_rs2_raddr_cur;
    wire [4:0]  id_rd_waddr_cur;
    wire [31:0] id_rs1_rdata_cur;
    wire [31:0] id_rs2_rdata_cur;
    wire        id_illegal_inst_cur;
    wire        id_ebreak_cur;

    reg         id_ex_valid_cur;
    reg  [31:0] id_ex_pc_cur;
    reg  [31:0] id_ex_pc_plus4_cur;
    reg  [31:0] id_ex_inst_cur;
    reg  [4:0]  id_ex_rs1_raddr_cur;
    reg  [4:0]  id_ex_rs2_raddr_cur;
    reg  [4:0]  id_ex_rd_waddr_cur;
    reg  [31:0] id_ex_rs1_rdata_cur;
    reg  [31:0] id_ex_rs2_rdata_cur;
    reg  [31:0] id_ex_offset_cur;
    reg  [6:0]  id_ex_opcode_cur;
    reg  [2:0]  id_ex_func3_cur;
    reg  [6:0]  id_ex_func7_cur;
    reg         id_ex_lui_cur;
    reg         id_ex_pc_src_cur;
    reg  [2:0]  id_ex_alu_op_cur;
    reg         id_ex_mem_write_cur;
    reg         id_ex_mem_read_cur;
    reg         id_ex_mem_to_reg_cur;
    reg         id_ex_alu_src1_cur;
    reg         id_ex_alu_src2_cur;
    reg         id_ex_reg_write_cur;
    reg         id_ex_jump_cur;
    reg         id_ex_branch_cur;
    reg         id_ex_illegal_inst_cur;
    reg         id_ex_ebreak_cur;

    wire        id_ex_valid_next;
    wire [31:0] id_ex_pc_next;
    wire [31:0] id_ex_pc_plus4_next;
    wire [31:0] id_ex_inst_next;
    wire [4:0]  id_ex_rs1_raddr_next;
    wire [4:0]  id_ex_rs2_raddr_next;
    wire [4:0]  id_ex_rd_waddr_next;
    wire [31:0] id_ex_rs1_rdata_next;
    wire [31:0] id_ex_rs2_rdata_next;
    wire [31:0] id_ex_offset_next;
    wire [6:0]  id_ex_opcode_next;
    wire [2:0]  id_ex_func3_next;
    wire [6:0]  id_ex_func7_next;
    wire        id_ex_lui_next;
    wire        id_ex_pc_src_next;
    wire [2:0]  id_ex_alu_op_next;
    wire        id_ex_mem_write_next;
    wire        id_ex_mem_read_next;
    wire        id_ex_mem_to_reg_next;
    wire        id_ex_alu_src1_next;
    wire        id_ex_alu_src2_next;
    wire        id_ex_reg_write_next;
    wire        id_ex_jump_next;
    wire        id_ex_branch_next;
    wire        id_ex_illegal_inst_next;
    wire        id_ex_ebreak_next;

    // -------------------------------------------------------------------------
    // EX stage + EX/MEM register
    // -------------------------------------------------------------------------
    wire [31:0] ex_operand1_cur;
    wire [31:0] ex_operand2_cur;
    wire [31:0] ex_rs1_value_cur;
    wire [31:0] ex_rs2_value_cur;
    wire [31:0] ex_store_data_cur;
    wire [31:0] ex_alu_result_cur;
    wire        ex_alu_eq_cur;
    wire        ex_alu_slt_cur;
    wire        ex_branch_taken_cur;
    wire        ex_jump_taken_cur;
    wire        ex_control_taken_cur;
    wire [31:0] ex_branch_target_cur;
    wire [31:0] ex_jump_target_raw_cur;
    wire [31:0] ex_jump_target_cur;
    wire [31:0] ex_control_target_cur;
    wire        ex_pc_misalign_trap_cur;
    wire        ex_redirect_cur;
    wire [31:0] ex_next_pc_cur;
    wire [31:0] ex_mem_forward_data_cur;
    wire [31:0] mem_wb_forward_data_cur;
    wire        ex_ex_match_rs1_cur;
    wire        ex_ex_match_rs2_cur;
    wire        mem_ex_match_rs1_cur;
    wire        mem_ex_match_rs2_cur;
    wire [1:0]  ex_forward_a_sel_cur;
    wire [1:0]  ex_forward_b_sel_cur;
    wire [1:0]  ex_operand1_sel_cur;
    wire [1:0]  ex_operand2_sel_cur;

    reg         ex_mem_valid_cur;
    reg  [31:0] ex_mem_pc_cur;
    reg  [31:0] ex_mem_pc_plus4_cur;
    reg  [31:0] ex_mem_next_pc_cur;
    reg  [31:0] ex_mem_inst_cur;
    reg  [4:0]  ex_mem_rs1_raddr_cur;
    reg  [4:0]  ex_mem_rs2_raddr_cur;
    reg  [4:0]  ex_mem_rd_waddr_cur;
    reg  [31:0] ex_mem_rs1_rdata_cur;
    reg  [31:0] ex_mem_rs2_rdata_cur;
    reg  [31:0] ex_mem_offset_cur;
    reg  [31:0] ex_mem_alu_result_cur;
    reg  [31:0] ex_mem_store_data_cur;
    reg  [2:0]  ex_mem_func3_cur;
    reg         ex_mem_mem_write_cur;
    reg         ex_mem_mem_read_cur;
    reg         ex_mem_mem_to_reg_cur;
    reg         ex_mem_lui_cur;
    reg         ex_mem_jump_cur;
    reg         ex_mem_reg_write_cur;
    reg         ex_mem_illegal_inst_cur;
    reg         ex_mem_pc_misalign_trap_cur;
    reg         ex_mem_ebreak_cur;

    wire        ex_mem_valid_next;
    wire [31:0] ex_mem_pc_next;
    wire [31:0] ex_mem_pc_plus4_next;
    wire [31:0] ex_mem_next_pc_next;
    wire [31:0] ex_mem_inst_next;
    wire [4:0]  ex_mem_rs1_raddr_next;
    wire [4:0]  ex_mem_rs2_raddr_next;
    wire [4:0]  ex_mem_rd_waddr_next;
    wire [31:0] ex_mem_rs1_rdata_next;
    wire [31:0] ex_mem_rs2_rdata_next;
    wire [31:0] ex_mem_offset_next;
    wire [31:0] ex_mem_alu_result_next;
    wire [31:0] ex_mem_store_data_next;
    wire [2:0]  ex_mem_func3_next;
    wire        ex_mem_mem_write_next;
    wire        ex_mem_mem_read_next;
    wire        ex_mem_mem_to_reg_next;
    wire        ex_mem_lui_next;
    wire        ex_mem_jump_next;
    wire        ex_mem_reg_write_next;
    wire        ex_mem_illegal_inst_next;
    wire        ex_mem_pc_misalign_trap_next;
    wire        ex_mem_ebreak_next;

    // -------------------------------------------------------------------------
    // MEM stage + MEM/WB register
    // -------------------------------------------------------------------------
    wire        mem_read_en_cur;
    wire        mem_write_en_cur;
    wire [31:0] mem_dmem_addr_cur;
    wire [3:0]  mem_dmem_mask_cur;
    wire [31:0] mem_dmem_wdata_cur;
    wire        mem_dmem_ren_cur;
    wire        mem_dmem_wen_cur;
    wire [31:0] mem_load_data_cur;
    wire [31:0] mem_store_data_cur;
    wire        mem_misalign_trap_cur;
    wire        mem_store_data_fwd_cur;

    reg         mem_wb_valid_cur;
    reg  [31:0] mem_wb_pc_cur;
    reg  [31:0] mem_wb_pc_plus4_cur;
    reg  [31:0] mem_wb_next_pc_cur;
    reg  [31:0] mem_wb_inst_cur;
    reg  [4:0]  mem_wb_rs1_raddr_cur;
    reg  [4:0]  mem_wb_rs2_raddr_cur;
    reg  [4:0]  mem_wb_rd_waddr_cur;
    reg  [31:0] mem_wb_rs1_rdata_cur;
    reg  [31:0] mem_wb_rs2_rdata_cur;
    reg  [31:0] mem_wb_offset_cur;
    reg  [31:0] mem_wb_alu_result_cur;
    reg  [31:0] mem_wb_load_data_cur;
    reg  [31:0] mem_wb_dmem_addr_cur;
    reg         mem_wb_dmem_ren_cur;
    reg         mem_wb_dmem_wen_cur;
    reg  [3:0]  mem_wb_dmem_mask_cur;
    reg  [31:0] mem_wb_dmem_wdata_cur;
    reg  [31:0] mem_wb_dmem_rdata_cur;
    reg         mem_wb_mem_to_reg_cur;
    reg         mem_wb_lui_cur;
    reg         mem_wb_jump_cur;
    reg         mem_wb_reg_write_cur;
    reg         mem_wb_illegal_inst_cur;
    reg         mem_wb_pc_misalign_trap_cur;
    reg         mem_wb_misalign_trap_cur;
    reg         mem_wb_ebreak_cur;

    wire        mem_wb_valid_next;
    wire [31:0] mem_wb_pc_next;
    wire [31:0] mem_wb_pc_plus4_next;
    wire [31:0] mem_wb_next_pc_next;
    wire [31:0] mem_wb_inst_next;
    wire [4:0]  mem_wb_rs1_raddr_next;
    wire [4:0]  mem_wb_rs2_raddr_next;
    wire [4:0]  mem_wb_rd_waddr_next;
    wire [31:0] mem_wb_rs1_rdata_next;
    wire [31:0] mem_wb_rs2_rdata_next;
    wire [31:0] mem_wb_offset_next;
    wire [31:0] mem_wb_alu_result_next;
    wire [31:0] mem_wb_load_data_next;
    wire [31:0] mem_wb_dmem_addr_next;
    wire        mem_wb_dmem_ren_next;
    wire        mem_wb_dmem_wen_next;
    wire [3:0]  mem_wb_dmem_mask_next;
    wire [31:0] mem_wb_dmem_wdata_next;
    wire [31:0] mem_wb_dmem_rdata_next;
    wire        mem_wb_mem_to_reg_next;
    wire        mem_wb_lui_next;
    wire        mem_wb_jump_next;
    wire        mem_wb_reg_write_next;
    wire        mem_wb_illegal_inst_next;
    wire        mem_wb_pc_misalign_trap_next;
    wire        mem_wb_misalign_trap_next;
    wire        mem_wb_ebreak_next;

    // -------------------------------------------------------------------------
    // WB stage
    // -------------------------------------------------------------------------
    wire [31:0] wb_write_data_cur;
    wire        wb_trap_cur;
    wire        wb_write_enable_cur;
    wire        retire_halt_cur;
    wire [6:0]  id_opcode_cur;
    wire        id_rs1_used_cur;
    wire        id_rs2_used_cur;
    wire        id_rs2_ex_used_cur;
    wire        hazard_ex_cur;
    wire        hazard_mem_cur;
    wire        hazard_wb_cur;
    wire        hazard_stall_cur;

    // -------------------------------------------------------------------------
    // IF stage
    // -------------------------------------------------------------------------
    assign if_pc_cur       = pc_cur;
    assign if_pc_plus4_cur = pc_cur + 32'd4;
    assign if_inst_cur     = i_imem_rdata;
    assign pc_next         = ex_redirect_cur ? ex_control_target_cur : if_pc_plus4_cur;

    assign o_imem_raddr = if_pc_cur;

    assign if_id_valid_next    = 1'b1;
    assign if_id_pc_next       = if_pc_cur;
    assign if_id_pc_plus4_next = if_pc_plus4_cur;
    assign if_id_inst_next     = if_inst_cur;

    // -------------------------------------------------------------------------
    // ID stage
    // -------------------------------------------------------------------------
    decode #(.BYPASS_EN(1)) u_decode (
        .i_clk              (i_clk),
        .i_rst              (i_rst),
        .Inst               (if_id_inst_cur),
        .WriteData          (wb_write_data_cur),
        .WriteAddr          (mem_wb_rd_waddr_cur),
        .WriteEn            (wb_write_enable_cur),
        .lui                (id_lui_cur),
        .PcSrc              (id_pc_src_cur),
        .AluOp              (id_alu_op_cur),
        .MemWrite           (id_mem_write_cur),
        .MemRead            (id_mem_read_cur),
        .MemToReg           (id_mem_to_reg_cur),
        .AluSrc1            (id_alu_src1_cur),
        .AluSrc2            (id_alu_src2_cur),
        .RegWrite           (id_reg_write_cur),
        .Jump               (id_jump_cur),
        .Branch             (id_branch_cur),
        .Offset             (id_offset_cur),
        .o_retire_rs1_raddr (id_rs1_raddr_cur),
        .o_retire_rs2_raddr (id_rs2_raddr_cur),
        .o_retire_rd_waddr  (id_rd_waddr_cur),
        .o_retire_rs1_rdata (id_rs1_rdata_cur),
        .o_retire_rs2_rdata (id_rs2_rdata_cur),
        .IllegalInst        (id_illegal_inst_cur),
        .EBreak             (id_ebreak_cur)
    );

    assign id_opcode_cur = if_id_inst_cur[6:0];

    assign id_rs1_used_cur = (id_opcode_cur == 7'b0110011) |  // R-type
                             (id_opcode_cur == 7'b0010011) |  // I-type ALU
                             (id_opcode_cur == 7'b0000011) |  // load
                             (id_opcode_cur == 7'b0100011) |  // store
                             (id_opcode_cur == 7'b1100011) |  // branch
                             (id_opcode_cur == 7'b1100111);   // jalr

    assign id_rs2_used_cur = (id_opcode_cur == 7'b0110011) |  // R-type
                             (id_opcode_cur == 7'b0100011) |  // store
                             (id_opcode_cur == 7'b1100011);   // branch

    assign id_rs2_ex_used_cur = (id_opcode_cur == 7'b0110011) |  // R-type
                                (id_opcode_cur == 7'b1100011);   // branch

    assign hazard_ex_cur = if_id_valid_cur &
                           id_ex_valid_cur &
                           id_ex_mem_read_cur &
                           (id_ex_rd_waddr_cur != 5'd0) &
                           ((id_rs1_used_cur & (id_rs1_raddr_cur == id_ex_rd_waddr_cur)) |
                            (id_rs2_ex_used_cur & (id_rs2_raddr_cur == id_ex_rd_waddr_cur)));

    assign hazard_mem_cur = 1'b0;

    assign hazard_wb_cur = 1'b0;

    assign hazard_stall_cur = hazard_ex_cur | hazard_mem_cur | hazard_wb_cur;

    assign id_ex_valid_next        = if_id_valid_cur;
    assign id_ex_pc_next           = if_id_pc_cur;
    assign id_ex_pc_plus4_next     = if_id_pc_plus4_cur;
    assign id_ex_inst_next         = if_id_inst_cur;
    assign id_ex_rs1_raddr_next    = id_rs1_raddr_cur;
    assign id_ex_rs2_raddr_next    = id_rs2_raddr_cur;
    assign id_ex_rd_waddr_next     = id_rd_waddr_cur;
    assign id_ex_rs1_rdata_next    = id_rs1_rdata_cur;
    assign id_ex_rs2_rdata_next    = id_rs2_rdata_cur;
    assign id_ex_offset_next       = id_offset_cur;
    assign id_ex_opcode_next       = if_id_inst_cur[6:0];
    assign id_ex_func3_next        = if_id_inst_cur[14:12];
    assign id_ex_func7_next        = if_id_inst_cur[31:25];
    assign id_ex_lui_next          = id_lui_cur;
    assign id_ex_pc_src_next       = id_pc_src_cur;
    assign id_ex_alu_op_next       = id_alu_op_cur;
    assign id_ex_mem_write_next    = id_mem_write_cur;
    assign id_ex_mem_read_next     = id_mem_read_cur;
    assign id_ex_mem_to_reg_next   = id_mem_to_reg_cur;
    assign id_ex_alu_src1_next     = id_alu_src1_cur;
    assign id_ex_alu_src2_next     = id_alu_src2_cur;
    assign id_ex_reg_write_next    = id_reg_write_cur;
    assign id_ex_jump_next         = id_jump_cur;
    assign id_ex_branch_next       = id_branch_cur;
    assign id_ex_illegal_inst_next = id_illegal_inst_cur;
    assign id_ex_ebreak_next       = id_ebreak_cur;

    // -------------------------------------------------------------------------
    // EX stage
    // -------------------------------------------------------------------------
    assign ex_mem_forward_data_cur = ex_mem_jump_cur ? ex_mem_pc_plus4_cur :
                                     ex_mem_lui_cur  ? ex_mem_offset_cur :
                                                       ex_mem_alu_result_cur;
    assign mem_wb_forward_data_cur = wb_write_data_cur;

    assign ex_ex_match_rs1_cur = id_ex_valid_cur &
                                 ex_mem_valid_cur &
                                 ex_mem_reg_write_cur &
                                 ~ex_mem_mem_to_reg_cur &
                                 (ex_mem_rd_waddr_cur != 5'd0) &
                                 (ex_mem_rd_waddr_cur == id_ex_rs1_raddr_cur);
    assign ex_ex_match_rs2_cur = id_ex_valid_cur &
                                 ex_mem_valid_cur &
                                 ex_mem_reg_write_cur &
                                 ~ex_mem_mem_to_reg_cur &
                                 (ex_mem_rd_waddr_cur != 5'd0) &
                                 (ex_mem_rd_waddr_cur == id_ex_rs2_raddr_cur);

    assign mem_ex_match_rs1_cur = id_ex_valid_cur &
                                  mem_wb_valid_cur &
                                  mem_wb_reg_write_cur &
                                  (mem_wb_rd_waddr_cur != 5'd0) &
                                  ~ex_ex_match_rs1_cur &
                                  (mem_wb_rd_waddr_cur == id_ex_rs1_raddr_cur);
    assign mem_ex_match_rs2_cur = id_ex_valid_cur &
                                  mem_wb_valid_cur &
                                  mem_wb_reg_write_cur &
                                  (mem_wb_rd_waddr_cur != 5'd0) &
                                  ~ex_ex_match_rs2_cur &
                                  (mem_wb_rd_waddr_cur == id_ex_rs2_raddr_cur);

    assign ex_forward_a_sel_cur = ex_ex_match_rs1_cur ? 2'b10 :
                                  mem_ex_match_rs1_cur ? 2'b01 :
                                                         2'b00;
    assign ex_forward_b_sel_cur = ex_ex_match_rs2_cur ? 2'b10 :
                                  mem_ex_match_rs2_cur ? 2'b01 :
                                                         2'b00;

    assign ex_operand1_sel_cur = id_ex_alu_src1_cur ? 2'b11 : ex_forward_a_sel_cur;
    assign ex_operand2_sel_cur = id_ex_alu_src2_cur ? 2'b11 : ex_forward_b_sel_cur;

    assign ex_rs1_value_cur = (ex_forward_a_sel_cur == 2'b10) ? ex_mem_forward_data_cur :
                              (ex_forward_a_sel_cur == 2'b01) ? mem_wb_forward_data_cur :
                                                                id_ex_rs1_rdata_cur;
    assign ex_rs2_value_cur = (ex_forward_b_sel_cur == 2'b10) ? ex_mem_forward_data_cur :
                              (ex_forward_b_sel_cur == 2'b01) ? mem_wb_forward_data_cur :
                                                                id_ex_rs2_rdata_cur;

    assign ex_operand1_cur = (ex_operand1_sel_cur == 2'b11) ? id_ex_pc_cur
                                                             : ex_rs1_value_cur;
    assign ex_operand2_cur = (ex_operand2_sel_cur == 2'b11) ? id_ex_offset_cur
                                                             : ex_rs2_value_cur;
    assign ex_store_data_cur = ex_rs2_value_cur;

    execute u_execute (
        .AluOp      (id_ex_alu_op_cur),
        .Func3      (id_ex_func3_cur),
        .Func7      (id_ex_func7_cur),
        .opcode     (id_ex_opcode_cur),
        .Operand1   (ex_operand1_cur),
        .Operand2   (ex_operand2_cur),
        .AluResult  (ex_alu_result_cur),
        .ALUeq      (ex_alu_eq_cur),
        .ALUslt     (ex_alu_slt_cur)
    );

    assign ex_branch_target_cur   = id_ex_pc_cur + id_ex_offset_cur;
    assign ex_jump_target_raw_cur = id_ex_pc_src_cur ? (ex_operand1_cur + id_ex_offset_cur)
                                                      : (id_ex_pc_cur + id_ex_offset_cur);
    assign ex_jump_target_cur     = id_ex_pc_src_cur ? {ex_jump_target_raw_cur[31:1], 1'b0}
                                                     : ex_jump_target_raw_cur;
    assign ex_control_target_cur  = id_ex_jump_cur ? ex_jump_target_cur : ex_branch_target_cur;

    assign ex_branch_taken_cur =
        id_ex_valid_cur & id_ex_branch_cur &
        ((id_ex_func3_cur == 3'b000) ?  ex_alu_eq_cur  : // beq
         (id_ex_func3_cur == 3'b001) ? ~ex_alu_eq_cur  : // bne
         (id_ex_func3_cur == 3'b100) ?  ex_alu_slt_cur : // blt
         (id_ex_func3_cur == 3'b101) ? ~ex_alu_slt_cur : // bge
         (id_ex_func3_cur == 3'b110) ?  ex_alu_slt_cur : // bltu
         (id_ex_func3_cur == 3'b111) ? ~ex_alu_slt_cur : // bgeu
                                        1'b0);
    assign ex_jump_taken_cur      = id_ex_valid_cur & id_ex_jump_cur;
    assign ex_control_taken_cur   = ex_branch_taken_cur | ex_jump_taken_cur;
    assign ex_pc_misalign_trap_cur= ex_control_taken_cur & (|ex_control_target_cur[1:0]);
    assign ex_redirect_cur        = ex_control_taken_cur & ~ex_pc_misalign_trap_cur;
    assign ex_next_pc_cur         = ex_redirect_cur ? ex_control_target_cur : id_ex_pc_plus4_cur;

    assign ex_mem_valid_next        = id_ex_valid_cur;
    assign ex_mem_pc_next           = id_ex_pc_cur;
    assign ex_mem_pc_plus4_next     = id_ex_pc_plus4_cur;
    assign ex_mem_next_pc_next      = ex_next_pc_cur;
    assign ex_mem_inst_next         = id_ex_inst_cur;
    assign ex_mem_rs1_raddr_next    = id_ex_rs1_raddr_cur;
    assign ex_mem_rs2_raddr_next    = id_ex_rs2_raddr_cur;
    assign ex_mem_rd_waddr_next     = id_ex_rd_waddr_cur;
    assign ex_mem_rs1_rdata_next    = ex_rs1_value_cur;
    assign ex_mem_rs2_rdata_next    = ex_rs2_value_cur;
    assign ex_mem_offset_next       = id_ex_offset_cur;
    assign ex_mem_alu_result_next   = ex_alu_result_cur;
    assign ex_mem_store_data_next   = ex_store_data_cur;
    assign ex_mem_func3_next        = id_ex_func3_cur;
    assign ex_mem_mem_write_next    = id_ex_mem_write_cur;
    assign ex_mem_mem_read_next     = id_ex_mem_read_cur;
    assign ex_mem_mem_to_reg_next   = id_ex_mem_to_reg_cur;
    assign ex_mem_lui_next          = id_ex_lui_cur;
    assign ex_mem_jump_next         = id_ex_jump_cur;
    assign ex_mem_reg_write_next    = id_ex_reg_write_cur;
    assign ex_mem_illegal_inst_next = id_ex_illegal_inst_cur;
    assign ex_mem_pc_misalign_trap_next = ex_pc_misalign_trap_cur;
    assign ex_mem_ebreak_next       = id_ex_ebreak_cur;

    // -------------------------------------------------------------------------
    // MEM stage
    // -------------------------------------------------------------------------
    assign mem_read_en_cur  = ex_mem_valid_cur & ex_mem_mem_read_cur;
    assign mem_write_en_cur = ex_mem_valid_cur & ex_mem_mem_write_cur;
    assign mem_store_data_fwd_cur = mem_wb_valid_cur &
                                    mem_wb_mem_to_reg_cur &
                                    ex_mem_valid_cur &
                                    ex_mem_mem_write_cur &
                                    (mem_wb_rd_waddr_cur != 5'd0) &
                                    (mem_wb_rd_waddr_cur == ex_mem_rs2_raddr_cur);
    assign mem_store_data_cur = mem_store_data_fwd_cur ? mem_wb_load_data_cur
                                                       : ex_mem_store_data_cur;

    memory u_memory (
        .EffAddr         (ex_mem_alu_result_cur),
        .StoreData       (mem_store_data_cur),
        .Func3           (ex_mem_func3_cur),
        .MemRead         (mem_read_en_cur),
        .MemWrite        (mem_write_en_cur),
        .i_dmem_rdata    (i_dmem_rdata),
        .o_dmem_addr     (mem_dmem_addr_cur),
        .o_dmem_mask     (mem_dmem_mask_cur),
        .o_dmem_wdata    (mem_dmem_wdata_cur),
        .o_dmem_ren      (mem_dmem_ren_cur),
        .o_dmem_wen      (mem_dmem_wen_cur),
        .LoadData        (mem_load_data_cur),
        .MisalignTrap    (mem_misalign_trap_cur)
    );

    assign o_dmem_addr  = mem_dmem_addr_cur;
    assign o_dmem_mask  = mem_dmem_mask_cur;
    assign o_dmem_wdata = mem_dmem_wdata_cur;
    assign o_dmem_ren   = mem_dmem_ren_cur;
    assign o_dmem_wen   = mem_dmem_wen_cur;

    assign mem_wb_valid_next          = ex_mem_valid_cur;
    assign mem_wb_pc_next             = ex_mem_pc_cur;
    assign mem_wb_pc_plus4_next       = ex_mem_pc_plus4_cur;
    assign mem_wb_next_pc_next        = ex_mem_next_pc_cur;
    assign mem_wb_inst_next           = ex_mem_inst_cur;
    assign mem_wb_rs1_raddr_next      = ex_mem_rs1_raddr_cur;
    assign mem_wb_rs2_raddr_next      = ex_mem_rs2_raddr_cur;
    assign mem_wb_rd_waddr_next       = ex_mem_rd_waddr_cur;
    assign mem_wb_rs1_rdata_next      = ex_mem_rs1_rdata_cur;
    assign mem_wb_rs2_rdata_next      = ex_mem_rs2_rdata_cur;
    assign mem_wb_offset_next         = ex_mem_offset_cur;
    assign mem_wb_alu_result_next     = ex_mem_alu_result_cur;
    assign mem_wb_load_data_next      = mem_load_data_cur;
    assign mem_wb_dmem_addr_next      = mem_dmem_addr_cur;
    assign mem_wb_dmem_ren_next       = mem_dmem_ren_cur;
    assign mem_wb_dmem_wen_next       = mem_dmem_wen_cur;
    assign mem_wb_dmem_mask_next      = mem_dmem_mask_cur;
    assign mem_wb_dmem_wdata_next     = mem_dmem_wdata_cur;
    assign mem_wb_dmem_rdata_next     = i_dmem_rdata;
    assign mem_wb_mem_to_reg_next     = ex_mem_mem_to_reg_cur;
    assign mem_wb_lui_next            = ex_mem_lui_cur;
    assign mem_wb_jump_next           = ex_mem_jump_cur;
    assign mem_wb_reg_write_next      = ex_mem_reg_write_cur;
    assign mem_wb_illegal_inst_next   = ex_mem_illegal_inst_cur;
    assign mem_wb_pc_misalign_trap_next = ex_mem_pc_misalign_trap_cur;
    assign mem_wb_misalign_trap_next  = mem_misalign_trap_cur;
    assign mem_wb_ebreak_next         = ex_mem_ebreak_cur;

    // -------------------------------------------------------------------------
    // WB stage
    // -------------------------------------------------------------------------
    writeback u_writeback (
        .AluResult  (mem_wb_alu_result_cur),
        .LoadData   (mem_wb_load_data_cur),
        .pc_plus4   (mem_wb_pc_plus4_cur),
        .Offset     (mem_wb_offset_cur),
        .MemToReg   (mem_wb_mem_to_reg_cur),
        .lui        (mem_wb_lui_cur),
        .Jump       (mem_wb_jump_cur),
        .WriteData  (wb_write_data_cur)
    );

    assign wb_trap_cur         = mem_wb_illegal_inst_cur |
                                 mem_wb_pc_misalign_trap_cur |
                                 mem_wb_misalign_trap_cur;
    assign wb_write_enable_cur = mem_wb_valid_cur & mem_wb_reg_write_cur & ~wb_trap_cur;
    assign retire_halt_cur     = mem_wb_valid_cur & mem_wb_ebreak_cur;

    // -------------------------------------------------------------------------
    // Retire outputs
    // -------------------------------------------------------------------------
    assign o_retire_valid     = mem_wb_valid_cur;
    assign o_retire_inst      = mem_wb_inst_cur;
    assign o_retire_trap      = mem_wb_valid_cur & wb_trap_cur;
    assign o_retire_halt      = retire_halt_cur;
    assign o_retire_rs1_raddr = mem_wb_rs1_raddr_cur;
    assign o_retire_rs2_raddr = mem_wb_rs2_raddr_cur;
    assign o_retire_rs1_rdata = mem_wb_rs1_rdata_cur;
    assign o_retire_rs2_rdata = mem_wb_rs2_rdata_cur;
    assign o_retire_rd_waddr  = wb_write_enable_cur ? mem_wb_rd_waddr_cur : 5'd0;
    assign o_retire_rd_wdata  = wb_write_data_cur;
    assign o_retire_dmem_addr = mem_wb_dmem_addr_cur;
    assign o_retire_dmem_ren  = mem_wb_dmem_ren_cur;
    assign o_retire_dmem_wen  = mem_wb_dmem_wen_cur;
    assign o_retire_dmem_mask = mem_wb_dmem_mask_cur;
    assign o_retire_dmem_wdata= mem_wb_dmem_wdata_cur;
    assign o_retire_dmem_rdata= mem_wb_dmem_rdata_cur;
    assign o_retire_pc        = mem_wb_pc_cur;
    assign o_retire_next_pc   = mem_wb_next_pc_cur;

    // -------------------------------------------------------------------------
    // Sequential update
    // -------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_cur <= RESET_ADDR;
            halted_cur <= 1'b0;

            if_id_valid_cur <= 1'b0;
            if_id_pc_cur <= 32'd0;
            if_id_pc_plus4_cur <= 32'd0;
            if_id_inst_cur <= 32'd0;

            id_ex_valid_cur <= 1'b0;
            id_ex_pc_cur <= 32'd0;
            id_ex_pc_plus4_cur <= 32'd0;
            id_ex_inst_cur <= 32'd0;
            id_ex_rs1_raddr_cur <= 5'd0;
            id_ex_rs2_raddr_cur <= 5'd0;
            id_ex_rd_waddr_cur <= 5'd0;
            id_ex_rs1_rdata_cur <= 32'd0;
            id_ex_rs2_rdata_cur <= 32'd0;
            id_ex_offset_cur <= 32'd0;
            id_ex_opcode_cur <= 7'd0;
            id_ex_func3_cur <= 3'd0;
            id_ex_func7_cur <= 7'd0;
            id_ex_lui_cur <= 1'b0;
            id_ex_pc_src_cur <= 1'b0;
            id_ex_alu_op_cur <= 3'd0;
            id_ex_mem_write_cur <= 1'b0;
            id_ex_mem_read_cur <= 1'b0;
            id_ex_mem_to_reg_cur <= 1'b0;
            id_ex_alu_src1_cur <= 1'b0;
            id_ex_alu_src2_cur <= 1'b0;
            id_ex_reg_write_cur <= 1'b0;
            id_ex_jump_cur <= 1'b0;
            id_ex_branch_cur <= 1'b0;
            id_ex_illegal_inst_cur <= 1'b0;
            id_ex_ebreak_cur <= 1'b0;

            ex_mem_valid_cur <= 1'b0;
            ex_mem_pc_cur <= 32'd0;
            ex_mem_pc_plus4_cur <= 32'd0;
            ex_mem_next_pc_cur <= 32'd0;
            ex_mem_inst_cur <= 32'd0;
            ex_mem_rs1_raddr_cur <= 5'd0;
            ex_mem_rs2_raddr_cur <= 5'd0;
            ex_mem_rd_waddr_cur <= 5'd0;
            ex_mem_rs1_rdata_cur <= 32'd0;
            ex_mem_rs2_rdata_cur <= 32'd0;
            ex_mem_offset_cur <= 32'd0;
            ex_mem_alu_result_cur <= 32'd0;
            ex_mem_store_data_cur <= 32'd0;
            ex_mem_func3_cur <= 3'd0;
            ex_mem_mem_write_cur <= 1'b0;
            ex_mem_mem_read_cur <= 1'b0;
            ex_mem_mem_to_reg_cur <= 1'b0;
            ex_mem_lui_cur <= 1'b0;
            ex_mem_jump_cur <= 1'b0;
            ex_mem_reg_write_cur <= 1'b0;
            ex_mem_illegal_inst_cur <= 1'b0;
            ex_mem_pc_misalign_trap_cur <= 1'b0;
            ex_mem_ebreak_cur <= 1'b0;

            mem_wb_valid_cur <= 1'b0;
            mem_wb_pc_cur <= 32'd0;
            mem_wb_pc_plus4_cur <= 32'd0;
            mem_wb_next_pc_cur <= 32'd0;
            mem_wb_inst_cur <= 32'd0;
            mem_wb_rs1_raddr_cur <= 5'd0;
            mem_wb_rs2_raddr_cur <= 5'd0;
            mem_wb_rd_waddr_cur <= 5'd0;
            mem_wb_rs1_rdata_cur <= 32'd0;
            mem_wb_rs2_rdata_cur <= 32'd0;
            mem_wb_offset_cur <= 32'd0;
            mem_wb_alu_result_cur <= 32'd0;
            mem_wb_load_data_cur <= 32'd0;
            mem_wb_dmem_addr_cur <= 32'd0;
            mem_wb_dmem_ren_cur <= 1'b0;
            mem_wb_dmem_wen_cur <= 1'b0;
            mem_wb_dmem_mask_cur <= 4'd0;
            mem_wb_dmem_wdata_cur <= 32'd0;
            mem_wb_dmem_rdata_cur <= 32'd0;
            mem_wb_mem_to_reg_cur <= 1'b0;
            mem_wb_lui_cur <= 1'b0;
            mem_wb_jump_cur <= 1'b0;
            mem_wb_reg_write_cur <= 1'b0;
            mem_wb_illegal_inst_cur <= 1'b0;
            mem_wb_pc_misalign_trap_cur <= 1'b0;
            mem_wb_misalign_trap_cur <= 1'b0;
            mem_wb_ebreak_cur <= 1'b0;
        end else if (retire_halt_cur) begin
            halted_cur <= 1'b1;
            if_id_valid_cur <= 1'b0;
            id_ex_valid_cur <= 1'b0;
            ex_mem_valid_cur <= 1'b0;
            mem_wb_valid_cur <= 1'b0;
        end else if (~halted_cur) begin
            if (ex_redirect_cur) begin
                // Taken branch/jump redirects fetch and squashes younger instructions.
                pc_cur <= pc_next;

                if_id_valid_cur <= 1'b0;
                if_id_pc_cur <= 32'd0;
                if_id_pc_plus4_cur <= 32'd0;
                if_id_inst_cur <= 32'd0;

                id_ex_valid_cur <= 1'b0;
                id_ex_pc_cur <= 32'd0;
                id_ex_pc_plus4_cur <= 32'd0;
                id_ex_inst_cur <= 32'd0;
                id_ex_rs1_raddr_cur <= 5'd0;
                id_ex_rs2_raddr_cur <= 5'd0;
                id_ex_rd_waddr_cur <= 5'd0;
                id_ex_rs1_rdata_cur <= 32'd0;
                id_ex_rs2_rdata_cur <= 32'd0;
                id_ex_offset_cur <= 32'd0;
                id_ex_opcode_cur <= 7'd0;
                id_ex_func3_cur <= 3'd0;
                id_ex_func7_cur <= 7'd0;
                id_ex_lui_cur <= 1'b0;
                id_ex_pc_src_cur <= 1'b0;
                id_ex_alu_op_cur <= 3'd0;
                id_ex_mem_write_cur <= 1'b0;
                id_ex_mem_read_cur <= 1'b0;
                id_ex_mem_to_reg_cur <= 1'b0;
                id_ex_alu_src1_cur <= 1'b0;
                id_ex_alu_src2_cur <= 1'b0;
                id_ex_reg_write_cur <= 1'b0;
                id_ex_jump_cur <= 1'b0;
                id_ex_branch_cur <= 1'b0;
                id_ex_illegal_inst_cur <= 1'b0;
                id_ex_ebreak_cur <= 1'b0;
            end else if (hazard_stall_cur) begin
                // Stall fetch/decode and inject bubble into ID/EX.
                pc_cur <= pc_cur;
                if_id_valid_cur <= if_id_valid_cur;
                if_id_pc_cur <= if_id_pc_cur;
                if_id_pc_plus4_cur <= if_id_pc_plus4_cur;
                if_id_inst_cur <= if_id_inst_cur;

                id_ex_valid_cur <= 1'b0;
                id_ex_pc_cur <= 32'd0;
                id_ex_pc_plus4_cur <= 32'd0;
                id_ex_inst_cur <= 32'd0;
                id_ex_rs1_raddr_cur <= 5'd0;
                id_ex_rs2_raddr_cur <= 5'd0;
                id_ex_rd_waddr_cur <= 5'd0;
                id_ex_rs1_rdata_cur <= 32'd0;
                id_ex_rs2_rdata_cur <= 32'd0;
                id_ex_offset_cur <= 32'd0;
                id_ex_opcode_cur <= 7'd0;
                id_ex_func3_cur <= 3'd0;
                id_ex_func7_cur <= 7'd0;
                id_ex_lui_cur <= 1'b0;
                id_ex_pc_src_cur <= 1'b0;
                id_ex_alu_op_cur <= 3'd0;
                id_ex_mem_write_cur <= 1'b0;
                id_ex_mem_read_cur <= 1'b0;
                id_ex_mem_to_reg_cur <= 1'b0;
                id_ex_alu_src1_cur <= 1'b0;
                id_ex_alu_src2_cur <= 1'b0;
                id_ex_reg_write_cur <= 1'b0;
                id_ex_jump_cur <= 1'b0;
                id_ex_branch_cur <= 1'b0;
                id_ex_illegal_inst_cur <= 1'b0;
                id_ex_ebreak_cur <= 1'b0;
            end else begin
                pc_cur <= pc_next;

                if_id_valid_cur <= if_id_valid_next;
                if_id_pc_cur <= if_id_pc_next;
                if_id_pc_plus4_cur <= if_id_pc_plus4_next;
                if_id_inst_cur <= if_id_inst_next;

                id_ex_valid_cur <= id_ex_valid_next;
                id_ex_pc_cur <= id_ex_pc_next;
                id_ex_pc_plus4_cur <= id_ex_pc_plus4_next;
                id_ex_inst_cur <= id_ex_inst_next;
                id_ex_rs1_raddr_cur <= id_ex_rs1_raddr_next;
                id_ex_rs2_raddr_cur <= id_ex_rs2_raddr_next;
                id_ex_rd_waddr_cur <= id_ex_rd_waddr_next;
                id_ex_rs1_rdata_cur <= id_ex_rs1_rdata_next;
                id_ex_rs2_rdata_cur <= id_ex_rs2_rdata_next;
                id_ex_offset_cur <= id_ex_offset_next;
                id_ex_opcode_cur <= id_ex_opcode_next;
                id_ex_func3_cur <= id_ex_func3_next;
                id_ex_func7_cur <= id_ex_func7_next;
                id_ex_lui_cur <= id_ex_lui_next;
                id_ex_pc_src_cur <= id_ex_pc_src_next;
                id_ex_alu_op_cur <= id_ex_alu_op_next;
                id_ex_mem_write_cur <= id_ex_mem_write_next;
                id_ex_mem_read_cur <= id_ex_mem_read_next;
                id_ex_mem_to_reg_cur <= id_ex_mem_to_reg_next;
                id_ex_alu_src1_cur <= id_ex_alu_src1_next;
                id_ex_alu_src2_cur <= id_ex_alu_src2_next;
                id_ex_reg_write_cur <= id_ex_reg_write_next;
                id_ex_jump_cur <= id_ex_jump_next;
                id_ex_branch_cur <= id_ex_branch_next;
                id_ex_illegal_inst_cur <= id_ex_illegal_inst_next;
                id_ex_ebreak_cur <= id_ex_ebreak_next;
            end

            ex_mem_valid_cur <= ex_mem_valid_next;
            ex_mem_pc_cur <= ex_mem_pc_next;
            ex_mem_pc_plus4_cur <= ex_mem_pc_plus4_next;
            ex_mem_next_pc_cur <= ex_mem_next_pc_next;
            ex_mem_inst_cur <= ex_mem_inst_next;
            ex_mem_rs1_raddr_cur <= ex_mem_rs1_raddr_next;
            ex_mem_rs2_raddr_cur <= ex_mem_rs2_raddr_next;
            ex_mem_rd_waddr_cur <= ex_mem_rd_waddr_next;
            ex_mem_rs1_rdata_cur <= ex_mem_rs1_rdata_next;
            ex_mem_rs2_rdata_cur <= ex_mem_rs2_rdata_next;
            ex_mem_offset_cur <= ex_mem_offset_next;
            ex_mem_alu_result_cur <= ex_mem_alu_result_next;
            ex_mem_store_data_cur <= ex_mem_store_data_next;
            ex_mem_func3_cur <= ex_mem_func3_next;
            ex_mem_mem_write_cur <= ex_mem_mem_write_next;
            ex_mem_mem_read_cur <= ex_mem_mem_read_next;
            ex_mem_mem_to_reg_cur <= ex_mem_mem_to_reg_next;
            ex_mem_lui_cur <= ex_mem_lui_next;
            ex_mem_jump_cur <= ex_mem_jump_next;
            ex_mem_reg_write_cur <= ex_mem_reg_write_next;
            ex_mem_illegal_inst_cur <= ex_mem_illegal_inst_next;
            ex_mem_pc_misalign_trap_cur <= ex_mem_pc_misalign_trap_next;
            ex_mem_ebreak_cur <= ex_mem_ebreak_next;

            mem_wb_valid_cur <= mem_wb_valid_next;
            mem_wb_pc_cur <= mem_wb_pc_next;
            mem_wb_pc_plus4_cur <= mem_wb_pc_plus4_next;
            mem_wb_next_pc_cur <= mem_wb_next_pc_next;
            mem_wb_inst_cur <= mem_wb_inst_next;
            mem_wb_rs1_raddr_cur <= mem_wb_rs1_raddr_next;
            mem_wb_rs2_raddr_cur <= mem_wb_rs2_raddr_next;
            mem_wb_rd_waddr_cur <= mem_wb_rd_waddr_next;
            mem_wb_rs1_rdata_cur <= mem_wb_rs1_rdata_next;
            mem_wb_rs2_rdata_cur <= mem_wb_rs2_rdata_next;
            mem_wb_offset_cur <= mem_wb_offset_next;
            mem_wb_alu_result_cur <= mem_wb_alu_result_next;
            mem_wb_load_data_cur <= mem_wb_load_data_next;
            mem_wb_dmem_addr_cur <= mem_wb_dmem_addr_next;
            mem_wb_dmem_ren_cur <= mem_wb_dmem_ren_next;
            mem_wb_dmem_wen_cur <= mem_wb_dmem_wen_next;
            mem_wb_dmem_mask_cur <= mem_wb_dmem_mask_next;
            mem_wb_dmem_wdata_cur <= mem_wb_dmem_wdata_next;
            mem_wb_dmem_rdata_cur <= mem_wb_dmem_rdata_next;
            mem_wb_mem_to_reg_cur <= mem_wb_mem_to_reg_next;
            mem_wb_lui_cur <= mem_wb_lui_next;
            mem_wb_jump_cur <= mem_wb_jump_next;
            mem_wb_reg_write_cur <= mem_wb_reg_write_next;
            mem_wb_illegal_inst_cur <= mem_wb_illegal_inst_next;
            mem_wb_pc_misalign_trap_cur <= mem_wb_pc_misalign_trap_next;
            mem_wb_misalign_trap_cur <= mem_wb_misalign_trap_next;
            mem_wb_ebreak_cur <= mem_wb_ebreak_next;
        end
    end

endmodule

`default_nettype wire
