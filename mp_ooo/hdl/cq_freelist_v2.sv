module cq_freelist_v2 
import rv32i_types::*;
#(
    parameter integer DEPTH = 32,
    parameter integer WIDTH = $clog2(DEPTH),
    parameter DATA_WIDTH = 32,
    parameter integer WIDTH_32 = 32,
    parameter FULL_AT_RESET = 0
)
(
    input   logic               clk,
    input   logic               rst,

    input   logic   [DATA_WIDTH - 1:0]      iq_wrdata[WAY],
    input   logic   [WAY-1:0]   iq_push,
    input   logic    [WAY-1:0]  iq_pop,
    output  logic   [DATA_WIDTH - 1:0]      iq_rdata[WAY-1:0],
    output  logic               iq_resp,
    output  logic [1:0]         iq_status,
    
    // CHANGED: integer -> logic [31:0]
    input logic [31:0] commit_count,
    input logic [31:0] new_phy_count,
    input logic [31:0] new_phy_count_relative[WAY-1:0],

    input logic br_mispredict_flush,
    input logic [ROB_DEPTH-1:0] prf_free_v_flush,
    input logic [DATA_WIDTH-1:0] prf_free_tag_flush [ROB_DEPTH-1:0],
    
    // CHANGED: integer -> logic [31:0]
    input logic [31:0] commit_count_relative[WAY],
    input logic [WAY-1:0] commit_phy_reg_valid
);

localparam logic [WIDTH-1:0] LAST_PTR = DEPTH - 2;

logic [DATA_WIDTH -1:0] circular_buffer[0:DEPTH-1];
logic [WIDTH:0] head_ptr;
logic [WIDTH:0] tail_ptr;

logic iq_full, iq_empty;
logic [ROB_ID_WIDTH:0] flush_free_count;

// CHANGED: integer -> logic [31:0]
// This prevents signed arithmetic bloat during synthesis
logic [31:0] flush_count_relative[ROB_DEPTH-1:0];
logic flag_wrap;

// NEW: Optimization signal
logic [31:0] slots_remaining_at_tail;

logic [ROB_DEPTH-1:0] effective_free_mask;
logic [31:0] next_tail_ptr_calc;
//logic [ROB_DEPTH-1:0] prefix_mask;

always_comb begin
    iq_empty = 1'b0;

    if(head_ptr == tail_ptr) begin
        iq_empty = 1'b1;
    end else if (head_ptr[WIDTH] == tail_ptr[WIDTH] || (tail_ptr[WIDTH] < head_ptr[WIDTH])) begin
        if(tail_ptr[WIDTH-1:0] - head_ptr[WIDTH-1:0] < WIDTH'(WAY)) begin
            iq_empty = 1'b1;
        end
    end else if ((tail_ptr[WIDTH] > head_ptr[WIDTH]) && (tail_ptr[WIDTH-1:0] > head_ptr[WIDTH-1:0])) begin
        if(tail_ptr[WIDTH-1:0] - head_ptr[WIDTH-1:0] < WIDTH'(WAY)) begin
            iq_empty = 1'b1;
        end
    end
end

assign iq_full = (head_ptr[WIDTH] != tail_ptr[WIDTH]) && (head_ptr[WIDTH-1:0] == tail_ptr[WIDTH-1:0]);

always_comb begin
    if (iq_full) begin
        iq_status = 2'b10; // full
    end else if (iq_empty) begin
        iq_status = 2'b01; // empty
    end else begin
        iq_status = 2'b00; // normal   
    end
end

// Read Logic
always_comb begin
    for(integer unsigned sc_fl=0; sc_fl < WAY; sc_fl++) begin
        iq_rdata[sc_fl] = 'x;
    end
    iq_resp = 1'b0;

    if (((|iq_pop)&& !iq_empty) ) begin
        if(head_ptr[WIDTH-1:0] + WIDTH'(new_phy_count) - 1'b1 <= WIDTH'(LAST_PTR)) begin
            for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                if(iq_pop[sc_fl]) begin
                    iq_rdata[sc_fl] = WIDTH'(circular_buffer[head_ptr[WIDTH-1:0] + new_phy_count_relative[sc_fl]]);
                end
            end
        end else if (head_ptr[WIDTH-1:0] + WIDTH'(new_phy_count) - 1'b1 > WIDTH'(LAST_PTR)) begin
            for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                if(iq_pop[sc_fl]) begin
                    if(head_ptr[WIDTH-1:0] + WIDTH'(new_phy_count_relative[sc_fl]) <= WIDTH'(LAST_PTR)) begin
                        iq_rdata[sc_fl] = circular_buffer[head_ptr[WIDTH-1:0] + new_phy_count_relative[sc_fl]];
                    end else begin
                        iq_rdata[sc_fl] = circular_buffer[new_phy_count_relative[sc_fl] - (LAST_PTR - head_ptr[WIDTH-1:0] + 'd1)];
                    end
                end 
            end
        end
        iq_resp = 1'b1;
    end
end

// Main Sequential Logic
always_ff @(posedge clk) begin

    if (rst) begin
        if(FULL_AT_RESET) begin
            head_ptr <= '0;
            tail_ptr <= {1'b1, {(WIDTH){1'b0}} };
            for (integer unsigned i = 1; i <= DEPTH; i++) begin
                circular_buffer[i-1] <= ({(DATA_WIDTH){1'b0}} | DATA_WIDTH'(i));
            end
            circular_buffer[DEPTH - 1] <= '0;
        end else begin
            head_ptr <= '0;
            tail_ptr <= '0;
            for (integer i = 0; i < DEPTH; i++) begin
                circular_buffer[i] <= 'x;
            end
        end
    end else begin
        if (br_mispredict_flush && !(|iq_push)) begin

            if(tail_ptr[WIDTH-1:0] + flush_free_count - 1 < { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                for (integer unsigned f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                    end 
                end
                tail_ptr <= tail_ptr + flush_free_count;
            end else if (tail_ptr[WIDTH-1:0] + flush_free_count - 1 == { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                for (integer unsigned f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                    end 
                end
                tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                tail_ptr[WIDTH-1:0] <= '0;
            end else begin
                for (integer f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        if(tail_ptr[WIDTH-1:0] + flush_count_relative[f] <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                            circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                        end else begin
                            // OPTIMIZATION: Used pre-calculated logic signal
                            circular_buffer[flush_count_relative[f] - slots_remaining_at_tail] <= prf_free_tag_flush[f];
                        end
                    end        
                end
                tail_ptr[WIDTH]     <= ~tail_ptr[WIDTH];
                tail_ptr[WIDTH-1:0] <= WIDTH'(32'(flush_free_count) - slots_remaining_at_tail);
            end
        end else if (br_mispredict_flush && (|iq_push) && flush_free_count != 0) begin
            
            if(tail_ptr[WIDTH-1:0] + flush_free_count + commit_count - 1 < { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                for (integer f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                    end 
                end

                for(integer unsigned sc_fl=0; sc_fl < WAY; sc_fl++) begin
                    if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_free_count + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                    end
                end
                tail_ptr <= (WIDTH+1)'(tail_ptr + flush_free_count + commit_count);

            end else if (tail_ptr[WIDTH-1:0] + flush_free_count + commit_count - 1 == { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                
                for (integer f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                    end 
                end

                for(integer unsigned sc_fl=0; sc_fl < WAY; sc_fl++) begin
                    if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + flush_free_count + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                    end
                end
                tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                tail_ptr[WIDTH-1:0] <= '0;
            end else begin
                for (integer f = 0; f < ROB_DEPTH; f++) begin
                    if (effective_free_mask[f]) begin
                        if(tail_ptr[WIDTH-1:0] + flush_count_relative[f] <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                            circular_buffer[tail_ptr[WIDTH-1:0] + flush_count_relative[f]] <= prf_free_tag_flush[f];
                        end else begin
                            circular_buffer[flush_count_relative[f] - slots_remaining_at_tail] <=  prf_free_tag_flush[f];
                        end
                    end        
                end

                // Note: flag_wrap logic was slightly ambiguous in original, 
                // but if we are here (else block), wrapping is implied for the WHOLE block (flush + commit)
                // However, split the logic carefully:
                
                for(integer unsigned sc_fl=0; sc_fl < WAY; sc_fl++) begin
                        if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                            if ((tail_ptr[WIDTH-1:0] + flush_free_count + commit_count_relative[sc_fl]) <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                                circular_buffer[tail_ptr[WIDTH-1:0] + flush_free_count + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                            end else begin
                                // Optimized math
                                circular_buffer[commit_count_relative[sc_fl] - (slots_remaining_at_tail - flush_free_count)] <= iq_wrdata[sc_fl];
                            end
                        end
                end
                
                tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                // Optimized math
                tail_ptr[WIDTH-1:0] <= WIDTH'(flush_free_count + commit_count - slots_remaining_at_tail);
            end
        end  else begin
            if (|iq_push && (!iq_full) && (commit_count !='0)) begin
                if(tail_ptr[WIDTH-1:0] + commit_count - 1 < { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                        if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                            circular_buffer[tail_ptr[WIDTH-1:0] + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                        end
                    end
                    tail_ptr <= (WIDTH+1)'(tail_ptr + commit_count);
                end else if(tail_ptr[WIDTH-1:0] + commit_count - 1 == { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                        if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                            circular_buffer[tail_ptr[WIDTH-1:0] + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                        end
                    end
                    tail_ptr[WIDTH-1:0] <= '0;
                    tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                end else begin
                    for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                        if(iq_push[sc_fl] && commit_phy_reg_valid[sc_fl]) begin
                            if(tail_ptr[WIDTH-1:0] + commit_count_relative[sc_fl] <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                                circular_buffer[tail_ptr[WIDTH-1:0] + commit_count_relative[sc_fl]] <= iq_wrdata[sc_fl];
                            end else begin
                                // Optimized math
                                circular_buffer[commit_count_relative[sc_fl] - slots_remaining_at_tail] <= iq_wrdata[sc_fl];
                            end
                        end
                    end
                    tail_ptr[WIDTH-1:0] <= WIDTH'(commit_count - slots_remaining_at_tail);
                    tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                end
            end
            if (((|iq_pop) && !iq_empty) ) begin
                if(head_ptr[WIDTH-1:0] + new_phy_count - 'd1 <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                        if(iq_pop[sc_fl]) begin
                            circular_buffer[head_ptr[WIDTH-1:0] + new_phy_count_relative[sc_fl]] <= '0;
                        end
                    end
                end else if (head_ptr[WIDTH-1:0] + new_phy_count - 'd1 > { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    for(integer unsigned sc_fl=0; sc_fl < WAY; ++sc_fl) begin
                        if(iq_pop[sc_fl]) begin
                            if(head_ptr[WIDTH-1:0] + new_phy_count_relative[sc_fl] <= { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                                circular_buffer[head_ptr[WIDTH-1:0] + new_phy_count_relative[sc_fl]] <= '0;
                            end else begin
                                circular_buffer[new_phy_count_relative[sc_fl] - (LAST_PTR - head_ptr[WIDTH-1:0] + 'd1)] <= '0;
                            end
                        end
                    end
                end

                if(head_ptr[WIDTH-1:0] + new_phy_count - 'd1 < { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    head_ptr[WIDTH-1:0] <= WIDTH'(head_ptr[WIDTH-1:0] + new_phy_count);
                end else if (head_ptr[WIDTH-1:0] + new_phy_count - 'd1 == { {(32-WIDTH){1'b0}}, LAST_PTR }) begin
                    head_ptr[WIDTH-1:0] <= '0;
                    head_ptr[WIDTH] <= ~head_ptr[WIDTH];
                end else begin
                    head_ptr[WIDTH-1:0] <= WIDTH'(new_phy_count - (LAST_PTR - head_ptr[WIDTH-1:0] + 'd1));
                    head_ptr[WIDTH] <= ~head_ptr[WIDTH];
                end
            end
        end
    end
end

// always_comb begin
//     for(integer f=0; f < ROB_DEPTH; ++f) begin
//         flush_count_relative[f] = '0;
//     end

//     flush_free_count = '0;
//     flag_wrap = '0;

//     for (integer f = 0; f < ROB_DEPTH; f++) begin
//         if (prf_free_v_flush[f] && prf_free_tag_flush[f] != '0) begin
//             flush_count_relative[f] = 32'(flush_free_count);
//             flush_free_count = flush_free_count + 1;
//         end
//     end

//     for (integer f = 0; f < ROB_DEPTH; f++) begin
//         if (prf_free_v_flush[f] && (prf_free_tag_flush[f] != '0)) begin
//             if(tail_ptr[WIDTH-1:0] + flush_count_relative[f] <= LAST_PTR) begin
//              flag_wrap = '0;
//             end else begin
//              flag_wrap = 1'b1;
//             end
//         end        
//     end
// end


logic [31:0] running_count;
always_comb begin

    slots_remaining_at_tail = 32'(LAST_PTR) - 32'(tail_ptr[WIDTH-1:0]) + 32'd1;
    
    for (integer unsigned i = 0; i < ROB_DEPTH; i++) begin
        effective_free_mask[i] = prf_free_v_flush[i] && (prf_free_tag_flush[i] != '0);
    end
    running_count = '0;
    //flush_free_count = (ROB_ID_WIDTH+1)'( (ROB_ID_WIDTH+1)'($countones(effective_free_mask)) );
    //flush_free_count = (ROB_ID_WIDTH + 1)'(unsigned'($countones(effective_free_mask)));
    //flush_count_relative[f] = 32'(unsigned'($countones(effective_free_mask & ((ROB_DEPTH'(1'b1) << f) - 1'b1))));

    for (integer unsigned f = 0; f < ROB_DEPTH; f++) begin
        flush_count_relative[f] = '0;
        if (effective_free_mask[f]) begin
            flush_count_relative[f] = running_count;
            //prefix_mask = (1'b1 << f) - 1'b1;
            //flush_count_relative[f] = 32'($countones(effective_free_mask & ((1'b1 << f) - 1'b1)));
            //flush_count_relative[f] = 32'(unsigned'($countones(effective_free_mask & ((ROB_DEPTH'(1'b1) << f) - 1'b1))));
            running_count = running_count + 1;
        end
    end
    flush_free_count = (ROB_ID_WIDTH + 1)'(running_count);

    next_tail_ptr_calc = 32'(tail_ptr[WIDTH-1:0]) + 32'(flush_free_count);
    
    if ((flush_free_count > 0) && (next_tail_ptr_calc > 32'(LAST_PTR))) begin
        flag_wrap = 1'b1;
    end else begin
        flag_wrap = 1'b0;
    end

end

endmodule : cq_freelist_v2