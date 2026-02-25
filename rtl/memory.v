module memory (
    input  wire [31:0] EffAddr,
    input  wire [31:0] StoreData,
    input  wire [2:0]  Func3,
    input  wire        MemRead,
    input  wire        MemWrite,
    input  wire [31:0] i_dmem_rdata,

    output wire [31:0] o_dmem_addr,
    output wire [3:0]  o_dmem_mask,
    output wire [31:0] o_dmem_wdata,
    output wire        o_dmem_ren,
    output wire        o_dmem_wen,

    output wire [31:0] LoadData,
    output wire        MisalignTrap
);

    // RV32I Load/Store helper for word-aligned Data MEM interface:
    // - Align addr down to 32-bit boundary
    // - MisalignTrap for lh/lhu/sh (addr[0]!=0) and lw/sw (addr[1:0]!=0)
    // - Generate byte lane mask
    // - Shift store data into correct lane(s)
    // - Shift/extend load data out of i_dmem_rdata

    wire [1:0] byte_offset = EffAddr[1:0];

    // Data MEM word-aligned address
    assign o_dmem_addr = {EffAddr[31:2], 2'b00};

    // Misalignment checks
    wire misalign_half = EffAddr[0];       // needs addr[0]==0
    wire misalign_word = |EffAddr[1:0];    // needs addr[1:0]==00

    wire misalign_load  = MemRead & (
        ((Func3 == 3'b001) || (Func3 == 3'b101)) ? misalign_half : // lh/lhu
        ((Func3 == 3'b010))                      ? misalign_word : // lw
                                                   1'b0
    );

    wire misalign_store = MemWrite & (
        ((Func3 == 3'b001)) ? misalign_half : // sh
        ((Func3 == 3'b010)) ? misalign_word : // sw
                              1'b0          // sb ok
    );

    assign MisalignTrap = misalign_load | misalign_store;

    // Data MEM read/write enable
    assign o_dmem_ren = MemRead  & ~MisalignTrap;
    assign o_dmem_wen = MemWrite & ~MisalignTrap;

    // Byte mask for the aligned 32-bit word
    reg [3:0] mask_r;
    always @(*) begin
        mask_r = 4'b0000;
        if (MemRead || MemWrite) begin
            case (Func3)
                3'b000, 3'b100: begin // byte (lb/lbu/sb)
                    case (byte_offset)
                        2'b00: mask_r = 4'b0001;
                        2'b01: mask_r = 4'b0010;
                        2'b10: mask_r = 4'b0100;
                        2'b11: mask_r = 4'b1000;
                    endcase
                end
                3'b001, 3'b101: begin // half (lh/lhu/sh)
                    mask_r = byte_offset[1] ? 4'b1100 : 4'b0011;
                end
                3'b010: begin // word (lw/sw)
                    mask_r = 4'b1111;
                end
                default: mask_r = 4'b0000;
            endcase
        end
    end
    assign o_dmem_mask = mask_r;

    // Store data shifted into correct lane(s)
    reg [31:0] wdata_r;
    always @(*) begin
        wdata_r = 32'b0;
        if (MemWrite) begin
            case (Func3)
                3'b000: wdata_r = StoreData << (8  * byte_offset);     // sb
                3'b001: wdata_r = StoreData << (16 * byte_offset[1]);  // sh
                3'b010: wdata_r = StoreData;                        // sw
                default: wdata_r = 32'b0;
            endcase
        end
    end
    assign o_dmem_wdata = wdata_r;

    // Load: shift right to place target byte/half in LSBs, then extend
    wire [31:0] rdata_shifted = i_dmem_rdata >> (8 * byte_offset);
    wire [7:0]  rbyte = rdata_shifted[7:0];
    wire [15:0] rhalf = rdata_shifted[15:0];

    reg [31:0] loaddata_r;
    always @(*) begin
        loaddata_r = 32'b0;
        if (MemRead && ~MisalignTrap) begin
            case (Func3)
                3'b000: loaddata_r = {{24{rbyte[7]}}, rbyte};   // lb
                3'b100: loaddata_r = {24'b0, rbyte};            // lbu
                3'b001: loaddata_r = {{16{rhalf[15]}}, rhalf};  // lh
                3'b101: loaddata_r = {16'b0, rhalf};            // lhu
                3'b010: loaddata_r = rdata_shifted;             // lw (byte_off must be 0)
                default: loaddata_r = 32'b0;
            endcase
        end
    end
    assign LoadData = loaddata_r;


endmodule