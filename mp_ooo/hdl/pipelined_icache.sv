module pipelined_icache 
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    output  logic   [31:0]  ufp_rdata[WAY-1:0],
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    input   logic   [255:0] dfp_rdata,
    input   logic           dfp_resp,
    output  logic           icache_ready,
    input   logic   [31:0]  branch_target_addr,
    input   logic           branch_predicted,
    input   logic   [31:0]  prefetch_addr,
    output   logic   [31:0]  prefetch_outgoing_addr,
    input   logic   [255:0] prefetch_rdata,
    input   logic           prefetch_resp
);

    typedef enum logic {
        IDLE,
        ALLOCATE
    } state_enum;

    state_enum state, next_state;
    
    logic stall;
    logic s1_valid;
    logic [31:0] s1_addr;
    logic [3:0] s1_rmask;
    
    logic [3:0] s1_set;
    logic [22:0] s1_tag;
    logic [2:0] s1_word_offset;

    logic [3:0] s0_set;
    
    assign prefetch_outgoing_addr = {branch_predicted ? branch_target_addr[31:5] : dfp_addr[31:5] + 5'd1 , 5'b0};
    
    assign s0_set = ufp_addr[8:5];

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s1_addr <= '0;
            s1_rmask <= '0;
        end else if (!stall || dfp_resp) begin
            s1_valid <= (ufp_rmask != 0); 
            s1_addr <= ufp_addr;
            s1_rmask <= ufp_rmask;
        end 
    end

    logic [22:0] tag_hold;
    logic [255:0] data_hold;
    logic hold_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            tag_hold <= '0;
            data_hold <= '0;
            hold_valid <= 1'b0;
        end else if (dfp_resp && state == ALLOCATE) begin
            tag_hold <= s1_tag;
            data_hold <= dfp_rdata;
            hold_valid <= 1'b1;
        end else begin
            hold_valid <= 1'b0;
            tag_hold <= '0;
            data_hold <= '0;
        end
    end


    assign s1_set = s1_addr[8:5];
    assign s1_tag = s1_addr[31:9];
    assign s1_word_offset = s1_addr[4:2];

    logic data_write_csb;
    logic [31:0] data_wmask;
    logic [255:0] data_din;
    logic data_read_csb;
    logic [255:0] data_dout;

    logic tag_write_csb;
    logic [22:0] tag_din;
    logic tag_read_csb;  
    logic [22:0] tag_dout;

    logic val_csb;
    logic val_web; 
    logic [3:0] val_addr;
    logic val_din;
    logic val_dout;

    logic hit;
    logic hit_hold;
    logic [255:0] fill_data;

    assign hit = val_dout && (tag_dout == s1_tag);
    assign hit_hold = hold_valid && (tag_hold == s1_tag);

    logic [31:0] prefetch_addr_q;
    logic [255:0] prefetch_rdata_q;
    logic prefetch_valid_q;       
    logic prefetch_pending_write; 

    wire [3:0] prefetch_set_q = prefetch_addr_q[8:5];
    wire [22:0] prefetch_tag_q = prefetch_addr_q[31:9];

    logic prefetch_hit;
    logic prefetch_immediate_hit;
    logic prefetch_do_write;

    assign prefetch_hit = prefetch_valid_q && (prefetch_set_q == s1_set) && (prefetch_tag_q == s1_tag);
    assign prefetch_immediate_hit = prefetch_resp && (prefetch_addr[8:5] == s1_set) && (prefetch_addr[31:9] == s1_tag);

    always_ff @(posedge clk) begin
        if (rst) begin
            prefetch_addr_q <= '0;
            prefetch_rdata_q <= '0;
            prefetch_valid_q <= 1'b0;
            prefetch_pending_write <= 1'b0;
        end else begin
            if (prefetch_resp) begin
                prefetch_addr_q <= prefetch_addr;
                prefetch_rdata_q <= prefetch_rdata;
                prefetch_valid_q <= 1'b1;
                prefetch_pending_write <= 1'b1;
            end
            if (prefetch_pending_write && prefetch_do_write) begin
                prefetch_pending_write <= 1'b0;
            end
            if (prefetch_valid_q && dfp_resp &&
                {s1_tag, s1_set} == {prefetch_tag_q, prefetch_set_q}) begin
                prefetch_valid_q <= 1'b0;
            end
        end
    end

    always_comb begin
        next_state = state;
        icache_ready = 1'b0;
        stall = 1'b0;
        ufp_resp = 1'b0;
        for(integer unsigned sc_lb= 0; sc_lb < WAY; ++sc_lb) begin
            ufp_rdata[sc_lb] = '0;
        end
        dfp_read = 1'b0;
        dfp_addr = '0;
        
        data_read_csb = 1'b0; 
        tag_read_csb = 1'b0;
        data_write_csb = 1'b1; 
        data_wmask = '0; 
        data_din = '0;
        tag_write_csb = 1'b1; 
        tag_din = '0;
        
        val_csb = 1'b0;
        val_web = 1'b1;
        val_din = 1'b0;
        val_addr = s0_set;
        fill_data = '0;
        prefetch_do_write = 1'b0;
        unique case (state)
            IDLE: begin
                icache_ready = 1'b1;
                val_addr = s0_set;
                if (s1_valid) begin
                    if (hit) begin
                        ufp_resp = 1'b1;
                        if (s1_rmask != 0) begin
                            for(integer unsigned sc_lb=0; sc_lb < WAY; ++sc_lb) begin
                                if ((integer'(s1_word_offset) + sc_lb) < 8) begin
                                    ufp_rdata[sc_lb] = data_dout[(s1_word_offset + 3'(sc_lb))*32 +: 32];
                                end else begin
                                    ufp_rdata[sc_lb] = '0;
                                end
                            end
                        end
                    end else if(hit_hold) begin
                        ufp_resp = 1'b1;
                        if (s1_rmask != 0) begin
                            for(integer unsigned sc_lb=0; sc_lb < WAY; ++sc_lb) begin
                                if ((integer'(s1_word_offset) + sc_lb) < 8) begin
                                    ufp_rdata[sc_lb] = data_hold[(s1_word_offset + 3'(sc_lb))*32 +: 32];
                                end else begin
                                    ufp_rdata[sc_lb] = '0;
                                end
                            end
                        end
                    end else if (prefetch_immediate_hit) begin
                        ufp_resp = 1'b1;
                        if (s1_rmask != 0) begin
                            for (integer unsigned sc_lb = 0; sc_lb < WAY; ++sc_lb) begin
                                if ((integer'(s1_word_offset) + sc_lb) < 8) begin
                                    ufp_rdata[sc_lb] =prefetch_rdata[(s1_word_offset + 3'(sc_lb))*32 +: 32];
                                end else begin
                                    ufp_rdata[sc_lb] = '0;
                                end
                            end
                        end
                    end else if (prefetch_hit) begin
                        ufp_resp = 1'b1;
                        if (s1_rmask != 0) begin
                            for (integer unsigned sc_lb = 0; sc_lb < WAY; ++sc_lb) begin
                                if ((integer'(s1_word_offset) + sc_lb) < 8) begin
                                    ufp_rdata[sc_lb] =prefetch_rdata_q[(s1_word_offset + 3'(sc_lb))*32 +: 32];
                                end else begin
                                    ufp_rdata[sc_lb] = '0;
                                end
                            end
                        end
                    end else begin
                        stall = 1'b1; 
                        icache_ready = 1'b0; 
                        next_state = ALLOCATE;
                        dfp_addr = {s1_tag, s1_set, 5'b0};
                        dfp_read = 1'b1;
                    end
                end

                if (prefetch_pending_write && !s1_valid) begin
                    data_write_csb = 1'b0;
                    data_wmask = '1;
                    data_din = prefetch_rdata_q;
                    tag_write_csb = 1'b0;
                    tag_din = prefetch_tag_q;
                    val_addr = prefetch_set_q;
                    val_web = 1'b0;
                    val_din = 1'b1;
                    prefetch_do_write = 1'b1;
                end
            end

            ALLOCATE: begin
                stall = 1'b1;
                dfp_addr = {s1_tag, s1_set, 5'b0};
                dfp_read = 1'b1;
                val_addr = s1_set;

                if (dfp_resp) begin
                    fill_data = dfp_rdata;
                    data_write_csb = 1'b0;
                    data_wmask = '1;
                    data_din = fill_data;
                    tag_write_csb = 1'b0;
                    tag_din = s1_tag;
                    val_web = 1'b0;
                    val_din = 1'b1;

                    // ufp_resp = 1'b1;
                    // if (s1_rmask != 0) begin
                    //     for(integer unsigned sc_lb=0; sc_lb < WAY; ++sc_lb) begin
                    //         if ((integer'(s1_word_offset) + sc_lb) < 8) begin
                    //             ufp_rdata[sc_lb] = fill_data[(s1_word_offset + sc_lb[2:0])*32 +: 32];
                    //         end else begin
                    //             ufp_rdata[sc_lb] = '0;
                    //         end
                    //     end
                    // end
                    
                    stall = 1'b0; 
                    next_state = IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    logic [3:0] mem_write_addr;
    assign mem_write_addr = prefetch_do_write ? prefetch_set_q : s1_set;

    icache_data_array data_array (
        .clk0   (clk),
        .csb0   (data_write_csb),
        .wmask0 (data_wmask),
        .addr0  (mem_write_addr), 
        .din0   (data_din),
        
        .clk1   (clk),
        .csb1   (data_read_csb),
        .addr1  (s0_set),
        .dout1  (data_dout)
    );

    icache_tag_array tag_array (
        .clk0   (clk),
        .csb0   (tag_write_csb),
        .addr0  (mem_write_addr),
        .din0   (tag_din),
        
        .clk1   (clk),
        .csb1   (tag_read_csb),
        .addr1  (s0_set),
        .dout1  (tag_dout)
    );

    sp_ff_array valid_array (
        .clk0   (clk),
        .rst0   (rst),
        .csb0   (val_csb),
        .web0   (val_web),
        .addr0  (val_addr),
        .din0   (val_din),
        .dout0  (val_dout)
    );

endmodule