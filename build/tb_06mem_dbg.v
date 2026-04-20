`timescale 1ns / 1ps
module hart_tb_dbg ();
    reg clk, rst;
    wire [31:0] imem_raddr, dmem_addr;
    wire imem_ready, imem_ren, imem_valid;
    wire [31:0] imem_rdata;
    wire dmem_ready, dmem_ren, dmem_wen;
    wire [3:0] dmem_mask;
    wire [31:0] dmem_wdata, dmem_rdata;
    wire dmem_rvalid, dmem_wdone;
    wire valid, trap, halt;
    wire [31:0] inst, pc, next_pc;
    wire [4:0] rs1_raddr, rs2_raddr, rd_waddr;
    wire [31:0] rs1_rdata, rs2_rdata, rd_wdata;
    wire [31:0] retire_dmem_addr, retire_dmem_rdata, retire_dmem_wdata;
    wire retire_dmem_ren, retire_dmem_wen;
    wire [3:0] retire_dmem_mask;

    hart #(.RESET_ADDR(32'h0)) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_imem_ready(imem_ready),
        .o_imem_raddr(imem_raddr),
        .o_imem_ren(imem_ren),
        .i_imem_valid(imem_valid),
        .i_imem_rdata(imem_rdata),
        .i_dmem_ready(dmem_ready),
        .o_dmem_addr(dmem_addr),
        .o_dmem_ren(dmem_ren),
        .o_dmem_wen(dmem_wen),
        .o_dmem_wdata(dmem_wdata),
        .o_dmem_mask(dmem_mask),
        .i_dmem_valid(dmem_rvalid),
        .i_dmem_rdata(dmem_rdata),
        .o_retire_valid(valid),
        .o_retire_inst(inst),
        .o_retire_trap(trap),
        .o_retire_halt(halt),
        .o_retire_rs1_raddr(rs1_raddr),
        .o_retire_rs2_raddr(rs2_raddr),
        .o_retire_rs1_rdata(rs1_rdata),
        .o_retire_rs2_rdata(rs2_rdata),
        .o_retire_rd_waddr(rd_waddr),
        .o_retire_rd_wdata(rd_wdata),
        .o_retire_dmem_addr(retire_dmem_addr),
        .o_retire_dmem_mask(retire_dmem_mask),
        .o_retire_dmem_ren(retire_dmem_ren),
        .o_retire_dmem_wen(retire_dmem_wen),
        .o_retire_dmem_rdata(retire_dmem_rdata),
        .o_retire_dmem_wdata(retire_dmem_wdata),
        .o_retire_pc(pc),
        .o_retire_next_pc(next_pc)
    );

    tb_memory #(.SIZE(1024), .LATENCY(4), .INTERVAL(2)) u_imem (
        .i_clk(clk), .i_rst(rst), .o_ready(imem_ready), .i_addr(imem_raddr),
        .i_ren(imem_ren), .i_wen(1'b0), .i_mask(4'b1111), .i_wdata(32'd0),
        .o_valid(imem_valid), .o_addr(), .o_wdone(), .o_rdata(imem_rdata)
    );

    tb_memory #(.SIZE(1024), .LATENCY(4), .INTERVAL(2)) u_dmem (
        .i_clk(clk), .i_rst(rst), .o_ready(dmem_ready), .i_addr(dmem_addr),
        .i_ren(dmem_ren), .i_wen(dmem_wen), .i_mask(dmem_mask), .i_wdata(dmem_wdata),
        .o_valid(dmem_rvalid), .o_addr(), .o_wdone(dmem_wdone), .o_rdata(dmem_rdata)
    );

    integer i;
    integer cycles;
    initial begin
        clk = 1'b1;
        rst = 1'b0;
        for (i = 0; i < 1024; i = i + 1) begin
            u_imem.mem[i] = 8'h00;
            u_dmem.mem[i] = 8'h00;
        end
        $readmemh("build/06memory_program_bytes.mem", u_imem.mem);
        @(negedge clk); rst = 1'b1;
        @(negedge clk);
        @(negedge clk);
        @(negedge clk); rst = 1'b0;
        cycles = 0;
        while (cycles < 200) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (valid) begin
                $write("[%08h] %08h", pc, inst);
                if (rd_waddr != 5'd0) $write(" w[%0d]=%08h", rd_waddr, rd_wdata);
                if (retire_dmem_ren) $write(" l[%08h,%04b]=%08h", retire_dmem_addr, retire_dmem_mask, retire_dmem_rdata);
                if (retire_dmem_wen) $write(" s[%08h,%04b]=%08h", retire_dmem_addr, retire_dmem_mask, retire_dmem_wdata);
                if (trap) $write(" TRAP");
                $display();
            end
            if ((cycles > 20) && !valid && dut.ex_mem_valid_cur) begin
                $display("STALL cycle=%0d pc=%08h exmem_inst=%08h req_sent=%b dready=%b dvalid=%b rvalid=%b wdone=%b dwen=%b dren=%b",
                    cycles, dut.ex_mem_pc_cur, dut.ex_mem_inst_cur, dut.ex_mem_dmem_req_sent_cur,
                    dmem_ready, dut.i_dmem_valid, dmem_rvalid, dmem_wdone, dmem_wen, dmem_ren);
            end
            if (halt) $finish;
        end
        $finish;
    end

    always #5 clk = ~clk;
endmodule
