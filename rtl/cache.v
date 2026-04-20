`default_nettype none

module cache (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_mem_ready,
    output wire [31:0] o_mem_addr,
    output wire        o_mem_ren,
    output wire        o_mem_wen,
    output wire [31:0] o_mem_wdata,
    input  wire [31:0] i_mem_rdata,
    input  wire        i_mem_valid,
    output wire        o_busy,
    input  wire [31:0] i_req_addr,
    input  wire        i_req_ren,
    input  wire        i_req_wen,
    input  wire [ 3:0] i_req_mask,
    input  wire [31:0] i_req_wdata,
    output wire [31:0] o_res_rdata
);
    localparam O = 4;            // 16 byte cache line
    localparam S = 5;            // 32 sets
    localparam DEPTH = 32;
    localparam T = 23;
    localparam D = 4;            // 4 words per line

    localparam STATE_IDLE        = 2'd0;
    localparam STATE_REFILL_REQ  = 2'd1;
    localparam STATE_REFILL_WAIT = 2'd2;
    localparam STATE_WRITE_REQ   = 2'd3;

    localparam WB_DEPTH   = 8;
    localparam WB_PTR_W   = 3;
    localparam WB_COUNT_W = 4;
    localparam [WB_COUNT_W - 1:0] WB_COUNT_ZERO = 4'd0;
    localparam [WB_COUNT_W - 1:0] WB_COUNT_FULL = 4'd8;
    localparam [1:0] REFILL_LAST_WORD = 2'd3;

    reg [31:0] datas0 [DEPTH - 1:0][D - 1:0];
    reg [31:0] datas1 [DEPTH - 1:0][D - 1:0];
    reg [T - 1:0] tags0 [DEPTH - 1:0];
    reg [T - 1:0] tags1 [DEPTH - 1:0];
    reg [DEPTH - 1:0] valid0;
    reg [DEPTH - 1:0] valid1;
    reg [DEPTH - 1:0] lru;

    reg [31:0] wb_addrs [WB_DEPTH - 1:0];
    reg [31:0] wb_datas [WB_DEPTH - 1:0];
    reg [WB_PTR_W - 1:0] wb_head_cur;
    reg [WB_PTR_W - 1:0] wb_tail_cur;
    reg [WB_COUNT_W - 1:0] wb_count_cur;

    reg [1:0] state_cur;
    reg [T - 1:0] miss_tag_cur;
    reg [S - 1:0] miss_set_cur;
    reg [1:0]     miss_word_cur;
    reg           miss_way_cur;
    reg           miss_is_write_cur;
    reg [3:0]     miss_mask_cur;
    reg [31:0]    miss_wdata_cur;
    reg [1:0]     refill_req_word_cur;
    reg [1:0]     refill_rsp_word_cur;
    reg           refill_req_done_cur;

    wire [T - 1:0] req_tag  = i_req_addr[31:O + S];
    wire [S - 1:0] req_set  = i_req_addr[O + S - 1:O];
    wire [1:0]     req_word = i_req_addr[3:2];

    wire        way0_valid = valid0[req_set];
    wire        way1_valid = valid1[req_set];
    wire        way0_hit   = way0_valid & (tags0[req_set] == req_tag);
    wire        way1_hit   = way1_valid & (tags1[req_set] == req_tag);
    wire        hit        = way0_hit | way1_hit;

    wire [31:0] way0_rword = datas0[req_set][req_word];
    wire [31:0] way1_rword = datas1[req_set][req_word];
    wire [31:0] hit_rword  = way0_hit ? way0_rword : (way1_hit ? way1_rword : 32'b0);

    wire        read_miss  = i_req_ren & ~hit;
    wire        write_miss = i_req_wen & ~hit;
    wire        victim_way = ~way0_valid ? 1'b0 :
                             (~way1_valid ? 1'b1 : lru[req_set]);
    wire        hit_way    = way1_hit;

    wire [31:0] req_byte_mask = {{8{i_req_mask[3]}}, {8{i_req_mask[2]}},
                                 {8{i_req_mask[1]}}, {8{i_req_mask[0]}}};
    wire [31:0] merged_write_word = (hit_rword & ~req_byte_mask) |
                                    (i_req_wdata & req_byte_mask);
    wire [31:0] miss_line_addr    = {miss_tag_cur, miss_set_cur, 4'b0000};
    wire [31:0] refill_word_addr  = miss_line_addr | {28'b0, refill_req_word_cur, 2'b00};
    wire [31:0] miss_word_addr    = {miss_tag_cur, miss_set_cur, miss_word_cur, 2'b00};

    wire [31:0] miss_way_rword = (miss_way_cur == 1'b0) ?
                                 datas0[miss_set_cur][miss_word_cur] :
                                 datas1[miss_set_cur][miss_word_cur];
    wire [31:0] miss_byte_mask = {{8{miss_mask_cur[3]}}, {8{miss_mask_cur[2]}},
                                  {8{miss_mask_cur[1]}}, {8{miss_mask_cur[0]}}};
    wire [31:0] miss_merged_write_word = (miss_way_rword & ~miss_byte_mask) |
                                         (miss_wdata_cur & miss_byte_mask);

    wire        cpu_miss_req_cur = (state_cur == STATE_IDLE) & (read_miss | write_miss);
    wire        refill_req_fire_cur = (state_cur == STATE_REFILL_REQ) &
                                      ~refill_req_done_cur &
                                      i_mem_ready;
    wire        wb_send_cur = (state_cur != STATE_REFILL_REQ) &
                              (state_cur != STATE_REFILL_WAIT) &
                              (wb_count_cur != WB_COUNT_ZERO) &
                              i_mem_ready &
                              ~cpu_miss_req_cur;
    wire        wb_has_push_space_cur = (wb_count_cur != WB_COUNT_FULL) | wb_send_cur;

    wire        write_hit_accept_cur = (state_cur == STATE_IDLE) &
                                       i_req_wen &
                                       hit &
                                       wb_has_push_space_cur;
    wire        write_hit_block_cur  = (state_cur == STATE_IDLE) &
                                       i_req_wen &
                                       hit &
                                       ~wb_has_push_space_cur;
    wire        write_req_commit_cur = (state_cur == STATE_WRITE_REQ) &
                                       wb_has_push_space_cur;

    wire        wb_push_cur = write_hit_accept_cur | write_req_commit_cur;
    wire [31:0] wb_push_addr_cur = write_hit_accept_cur ? i_req_addr : miss_word_addr;
    wire [31:0] wb_push_data_cur = write_hit_accept_cur ? merged_write_word : miss_merged_write_word;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state_cur <= STATE_IDLE;
            miss_tag_cur <= {T{1'b0}};
            miss_set_cur <= {S{1'b0}};
            miss_word_cur <= 2'b00;
            miss_way_cur <= 1'b0;
            miss_is_write_cur <= 1'b0;
            miss_mask_cur <= 4'b0000;
            miss_wdata_cur <= 32'b0;
            refill_req_word_cur <= 2'b00;
            refill_rsp_word_cur <= 2'b00;
            refill_req_done_cur <= 1'b0;
            wb_head_cur <= {WB_PTR_W{1'b0}};
            wb_tail_cur <= {WB_PTR_W{1'b0}};
            wb_count_cur <= {WB_COUNT_W{1'b0}};
            valid0 <= {DEPTH{1'b0}};
            valid1 <= {DEPTH{1'b0}};
            lru <= {DEPTH{1'b0}};
        end else begin
            if (wb_push_cur) begin
                wb_addrs[wb_tail_cur] <= wb_push_addr_cur;
                wb_datas[wb_tail_cur] <= wb_push_data_cur;
            end

            if (wb_send_cur)
                wb_head_cur <= wb_head_cur + 1'b1;
            if (wb_push_cur)
                wb_tail_cur <= wb_tail_cur + 1'b1;

            case ({wb_push_cur, wb_send_cur})
                2'b10: wb_count_cur <= wb_count_cur + 1'b1;
                2'b01: wb_count_cur <= wb_count_cur - 1'b1;
                default: wb_count_cur <= wb_count_cur;
            endcase

            case (state_cur)
                STATE_IDLE: begin
                    if (i_req_ren & hit) begin
                        if (way0_hit)
                            lru[req_set] <= 1'b1;
                        else if (way1_hit)
                            lru[req_set] <= 1'b0;
                    end else if (write_hit_accept_cur) begin
                        if (way0_hit)
                            datas0[req_set][req_word] <= merged_write_word;
                        else
                            datas1[req_set][req_word] <= merged_write_word;

                        if (way0_hit)
                            lru[req_set] <= 1'b1;
                        else if (way1_hit)
                            lru[req_set] <= 1'b0;
                    end else if (write_hit_block_cur) begin
                        miss_tag_cur <= req_tag;
                        miss_set_cur <= req_set;
                        miss_word_cur <= req_word;
                        miss_way_cur <= hit_way;
                        miss_is_write_cur <= 1'b1;
                        miss_mask_cur <= i_req_mask;
                        miss_wdata_cur <= i_req_wdata;
                        state_cur <= STATE_WRITE_REQ;
                    end else if (read_miss | write_miss) begin
                        miss_tag_cur <= req_tag;
                        miss_set_cur <= req_set;
                        miss_word_cur <= req_word;
                        miss_way_cur <= victim_way;
                        miss_is_write_cur <= i_req_wen;
                        miss_mask_cur <= i_req_mask;
                        miss_wdata_cur <= i_req_wdata;
                        refill_req_word_cur <= 2'b00;
                        refill_rsp_word_cur <= 2'b00;
                        refill_req_done_cur <= 1'b0;
                        state_cur <= STATE_REFILL_REQ;
                    end
                end

                STATE_REFILL_REQ: begin
                    if (refill_req_fire_cur) begin
                        if (refill_req_word_cur == REFILL_LAST_WORD)
                            refill_req_done_cur <= 1'b1;
                        else
                            refill_req_word_cur <= refill_req_word_cur + 1'b1;
                    end

                    if (i_mem_valid) begin
                        if (miss_way_cur == 1'b0)
                            datas0[miss_set_cur][refill_rsp_word_cur] <= i_mem_rdata;
                        else
                            datas1[miss_set_cur][refill_rsp_word_cur] <= i_mem_rdata;

                        if (refill_rsp_word_cur == REFILL_LAST_WORD) begin
                            if (miss_way_cur == 1'b0) begin
                                tags0[miss_set_cur] <= miss_tag_cur;
                                valid0[miss_set_cur] <= 1'b1;
                            end else begin
                                tags1[miss_set_cur] <= miss_tag_cur;
                                valid1[miss_set_cur] <= 1'b1;
                            end

                            if (miss_is_write_cur) begin
                                state_cur <= STATE_WRITE_REQ;
                            end else begin
                                lru[miss_set_cur] <= ~miss_way_cur;
                                state_cur <= STATE_IDLE;
                            end
                        end else begin
                            refill_rsp_word_cur <= refill_rsp_word_cur + 1'b1;
                        end
                    end
                end

                STATE_REFILL_WAIT: begin
                    state_cur <= STATE_IDLE;
                end

                STATE_WRITE_REQ: begin
                    if (write_req_commit_cur) begin
                        if (miss_way_cur == 1'b0)
                            datas0[miss_set_cur][miss_word_cur] <= miss_merged_write_word;
                        else
                            datas1[miss_set_cur][miss_word_cur] <= miss_merged_write_word;

                        lru[miss_set_cur] <= ~miss_way_cur;
                        state_cur <= STATE_IDLE;
                    end
                end

                default: begin
                    state_cur <= STATE_IDLE;
                end
            endcase
        end
    end

    assign o_mem_addr  = (state_cur == STATE_REFILL_REQ) ? refill_word_addr :
                         (wb_send_cur ? wb_addrs[wb_head_cur] : 32'b0);
    assign o_mem_ren   = refill_req_fire_cur;
    assign o_mem_wen   = wb_send_cur;
    assign o_mem_wdata = wb_send_cur ? wb_datas[wb_head_cur] : 32'b0;

    assign o_busy = (state_cur != STATE_IDLE) |
                    ((state_cur == STATE_IDLE) & (read_miss | write_miss | write_hit_block_cur));
    assign o_res_rdata = hit_rword;
endmodule

`default_nettype wire
