module pipelined_dcache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp,
    output  logic           dcache_ready
);

    typedef enum logic [1:0] {
        IDLE,
        WRITEBACK, 
        ALLOCATE
    } state_enum;

    state_enum state, next_state;
    
    logic stall;
    logic s1_valid;
    logic [31:0] s1_addr;
    logic [3:0] s1_rmask;
    logic [3:0] s1_wmask;
    logic [31:0] s1_wdata;
    
    logic [3:0] s1_set;
    logic [22:0] s1_tag;
    logic [2:0] s1_word_offset;
    logic [4:0] s1_byte_offset;

    logic [3:0] s0_set;
    
    assign s0_set = ufp_addr[8:5];

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s1_addr <= '0;
            s1_rmask <= '0;
            s1_wmask <= '0;
            s1_wdata <= '0;
        end else if (!stall) begin
            s1_valid <= (ufp_rmask != 0) || (ufp_wmask != 0);
            s1_addr <= ufp_addr;
            s1_rmask <= ufp_rmask;
            s1_wmask <= ufp_wmask;
            s1_wdata <= ufp_wdata;
        end 
    end

    assign s1_set = s1_addr[8:5];
    assign s1_tag = s1_addr[31:9];
    assign s1_word_offset = s1_addr[4:2];
    assign s1_byte_offset = s1_addr[4:0];

    logic data_csb[3:0];
    logic data_web[3:0];
    logic [31:0] data_wmask[3:0];
    logic [3:0] data_addr[3:0];
    logic [255:0] data_din[3:0];
    logic [255:0] data_dout[3:0];

    logic tag_csb[3:0];
    logic tag_web[3:0];
    logic [3:0] tag_addr[3:0];
    logic [22:0] tag_din[3:0];
    logic [22:0] tag_dout[3:0];

    logic val_csb[3:0];
    logic val_web[3:0];
    logic [3:0] val_addr[3:0];
    logic val_din[3:0];
    logic val_dout[3:0];

    logic dirt_csb[3:0];
    logic dirt_web[3:0];
    logic [3:0] dirt_addr[3:0];
    logic dirt_din[3:0];
    logic dirt_dout[3:0];

    logic lru_csb;
    logic lru_web;
    logic [3:0] lru_addr;
    logic [2:0] lru_din;
    logic [2:0] lru_dout;

    logic hit;
    logic [1:0] hit_way;
    logic [1:0] evict_way;
    logic [1:0] alloc_way;
    
    function automatic logic [1:0] decode_plru(input logic [2:0] plru_bits);
        decode_plru = 2'd0; 
        unique casez (plru_bits)
            3'b00?: decode_plru = 2'd0;
            3'b01?: decode_plru = 2'd1;
            3'b1?0: decode_plru = 2'd2;
            3'b1?1: decode_plru = 2'd3;
        endcase
    endfunction

    function automatic logic [2:0] update_plru(input logic [2:0] plru_bits,input logic [1:0] accessed_way);
        logic [2:0] next_bits;
        next_bits = plru_bits;
        unique case (accessed_way)
            2'd0: begin next_bits[2] = 1'b1; next_bits[1] = 1'b1; end
            2'd1: begin next_bits[2] = 1'b1; next_bits[1] = 1'b0; end
            2'd2: begin next_bits[2] = 1'b0; next_bits[0] = 1'b1; end
            2'd3: begin next_bits[2] = 1'b0; next_bits[0] = 1'b0; end
        endcase
        return next_bits;
    endfunction

    assign evict_way = decode_plru(lru_dout);

    always_comb begin
        hit = 1'b0;
        hit_way = 2'd0;
        for (integer unsigned w = 0; w < 4; w++) begin
            if (val_dout[w] && (tag_dout[w] == s1_tag)) begin
                hit = 1'b1;
                hit_way = 2'(w);
            end
        end
    end
    assign alloc_way = hit ? hit_way : evict_way;

    // logic dbg_read_hit, dbg_write_hit, dbg_mixed_hit;
    // logic dbg_read_clean_miss, dbg_write_clean_miss;
    // logic dbg_read_dirty_miss, dbg_write_dirty_miss;

    // logic s1_read_op, s1_write_op;
    // assign s1_read_op  = (s1_rmask != 0);
    // assign s1_write_op = (s1_wmask != 0);
    // logic victim_dirty;
    // assign victim_dirty = dirt_dout[evict_way];

    // assign dbg_read_hit  = s1_valid && s1_read_op && !s1_write_op && hit;
    // assign dbg_write_hit = s1_valid && s1_write_op && !s1_read_op && hit;
    // assign dbg_mixed_hit = s1_valid && s1_read_op && s1_write_op && hit;
    // assign dbg_read_clean_miss  = s1_valid && s1_read_op  && !hit && !victim_dirty;
    // assign dbg_write_clean_miss = s1_valid && s1_write_op && !hit && !victim_dirty;
    // assign dbg_read_dirty_miss  = s1_valid && s1_read_op  && !hit && victim_dirty;
    // assign dbg_write_dirty_miss = s1_valid && s1_write_op && !hit && victim_dirty;

    logic [255:0] fill_data;
    logic [31:0] sram_wmask;
    
    always_comb begin
        next_state = state;
        dcache_ready = 1'b0;
        stall = 1'b0;
        ufp_resp = 1'b0;
        ufp_rdata = '0;
        dfp_read = 1'b0;
        dfp_write = 1'b0;
        dfp_addr = '0;
        dfp_wdata = '0;
        for (integer unsigned i=0; i<4; i++) begin
            data_csb[i] = 1'b0;
            data_web[i] = 1'b1; 
            data_wmask[i] = '0; 
            data_din[i] = '0;
            tag_csb[i] = 1'b0; 
            tag_web[i] = 1'b1; 
            tag_din[i] = '0;
            val_csb[i] = 1'b0; 
            val_web[i] = 1'b1; 
            val_din[i] = 1'b0;
            dirt_csb[i] = 1'b0; 
            dirt_web[i] = 1'b1; 
            dirt_din[i] = 1'b0;
        end
        lru_csb = 1'b0; 
        lru_web = 1'b1; 
        lru_din = '0;

        if (state == IDLE) begin
            for(integer unsigned i=0; i<4; i++) begin
                data_addr[i] = s0_set;
                tag_addr[i] = s0_set;
                val_addr[i] = s0_set;
                dirt_addr[i] = s0_set;
            end
            lru_addr = s0_set;
        end else begin
            for(integer unsigned i=0; i<4; i++) begin
                data_addr[i] = s1_set;
                tag_addr[i] = s1_set;
                val_addr[i] = s1_set;
                dirt_addr[i] = s1_set;
            end
            lru_addr = s1_set;
        end

        unique case (state)
            IDLE: begin
                dcache_ready = 1'b1;
                if (s1_valid) begin
                    if (hit) begin
                        ufp_resp = 1'b1;
                        if (s1_rmask != 0) begin
                            ufp_rdata = data_dout[hit_way][s1_word_offset*32 +: 32];
                        end
                        if (s1_wmask != 0) begin
                            sram_wmask = '0;
                            sram_wmask[s1_word_offset*4 +: 4] = s1_wmask;
                            data_addr[hit_way] = s1_set;
                            data_web[hit_way] = 1'b0;
                            data_wmask[hit_way] = sram_wmask;
                            data_din[hit_way] = {8{s1_wdata}};
                            dirt_addr[hit_way] = s1_set;
                            dirt_web[hit_way] = 1'b0;
                            dirt_din[hit_way] = 1'b1;
                        end
                        lru_addr = s1_set;
                        lru_web = 1'b0;
                        lru_din = update_plru(lru_dout, hit_way);
                    end else begin
                        stall = 1'b1; 
                        dcache_ready = 1'b0; 
                        if (val_dout[evict_way] && dirt_dout[evict_way]) begin
                            next_state = WRITEBACK;
                            dfp_addr = {tag_dout[evict_way], s1_set, 5'b0};
                            dfp_write = 1'b1;
                            dfp_wdata = data_dout[evict_way];
                        end else begin
                            next_state = ALLOCATE;
                            dfp_addr = {s1_tag, s1_set, 5'b0};
                            dfp_read = 1'b1;
                        end
                    end
                end
            end

            WRITEBACK: begin
                stall = 1'b1;
                dfp_addr = {tag_dout[evict_way], s1_set, 5'b0};
                dfp_write = 1'b1;
                dfp_wdata = data_dout[evict_way];
                if (dfp_resp) begin
                    dirt_web[evict_way] = 1'b0;
                    dirt_din[evict_way] = 1'b0;
                    // dfp_addr = {s1_tag, s1_set, 5'b0};
                    // dfp_read = 1'b1;
                    // dfp_write = 1'b0;
                    next_state = ALLOCATE;
                end
            end

            ALLOCATE: begin
                stall = 1'b1;
                dfp_addr = {s1_tag, s1_set, 5'b0};
                dfp_read = 1'b1;
                if (dfp_resp) begin
                    fill_data = dfp_rdata;
                    if (s1_wmask != 0) begin
                        logic [31:0] current_word;
                        current_word = fill_data[s1_word_offset*32 +: 32];
                        if (s1_wmask[0]) current_word[7:0] = s1_wdata[7:0];
                        if (s1_wmask[1]) current_word[15:8] = s1_wdata[15:8];
                        if (s1_wmask[2]) current_word[23:16] = s1_wdata[23:16];
                        if (s1_wmask[3]) current_word[31:24] = s1_wdata[31:24];
                        fill_data[s1_word_offset*32 +: 32] = current_word;
                    end
                    data_web[alloc_way] = 1'b0;
                    data_wmask[alloc_way] = '1; 
                    data_din[alloc_way] = fill_data;
                    tag_web[alloc_way] = 1'b0;
                    tag_din[alloc_way] = s1_tag;
                    val_web[alloc_way] = 1'b0;
                    val_din[alloc_way] = 1'b1;
                    dirt_web[alloc_way] = 1'b0;
                    dirt_din[alloc_way] = (s1_wmask != 0);
                    lru_web = 1'b0;
                    lru_din = update_plru(lru_dout, alloc_way);
                    ufp_resp = 1'b1;
                    if (s1_rmask != 0) begin
                        ufp_rdata = fill_data[s1_word_offset*32 +: 32];
                    end
                    stall = 1'b0; 
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    generate
        for (genvar i = 0; i < 4; i++) begin : arrays
            mp_cache_data_array data_array (
                .clk0   (clk && !data_csb[i]),
                .csb0   (data_csb[i]),
                .web0   (data_web[i]),
                .wmask0 (data_wmask[i]),
                .addr0  (data_addr[i]),
                .din0   (data_din[i]),
                .dout0  (data_dout[i])
            );
            mp_cache_tag_array tag_array (
                .clk0   (clk && !tag_csb[i]),
                .csb0   (tag_csb[i]),
                .web0   (tag_web[i]),
                .addr0  (tag_addr[i]),
                .din0   (tag_din[i]),
                .dout0  (tag_dout[i])
            );
            sp_ff_array valid_array (
                .clk0   (clk && !val_csb[i]),
                .rst0   (rst),
                .csb0   (val_csb[i]),
                .web0   (val_web[i]),
                .addr0  (val_addr[i]),
                .din0   (val_din[i]),
                .dout0  (val_dout[i])
            );
            sp_ff_array dirty_bit (
                .clk0   (clk && !dirt_csb[i]),
                .rst0   (rst),
                .csb0   (dirt_csb[i]),
                .web0   (dirt_web[i]),
                .addr0  (dirt_addr[i]),
                .din0   (dirt_din[i]),
                .dout0  (dirt_dout[i])
            );
        end
    endgenerate

    sp_ff_array #(
        .WIDTH (3)
    ) lru_array (
        .clk0   (clk),
        .rst0   (rst),
        .csb0   (lru_csb),
        .web0   (lru_web),
        .addr0  (lru_addr),
        .din0   (lru_din),
        .dout0  (lru_dout)
    );

endmodule