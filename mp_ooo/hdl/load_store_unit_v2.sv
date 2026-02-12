module load_store_unit_v2
import rv32i_types::*;
#(
    parameter integer DEPTH = 16,
    parameter integer WIDTH = $clog2(DEPTH),
    parameter integer NO_PHY_REGS = 64 ,
    parameter PHY_ADDR_WIDTH = $clog2(NO_PHY_REGS),
    parameter DATA_WIDTH = 32
)
(
    input  logic               clk,
    input  logic               rst,
    input  mem_ld_st_unit      mem_inst_from_rename[WAY-1:0],
    output mem_ld_cdb_t        mem_ld_cdb,

    //memory signals to data cache
    output   logic   [31:0]    dmem_addr,
    output   logic   [3:0]     dmem_rmask,
    output   logic   [3:0]     dmem_wmask,
    input    logic   [31:0]    dmem_rdata,
    output   logic   [31:0]    dmem_wdata,
    input    logic             mem_resp,

    //register reads to the physical register file
    input logic [31:0]         ps1_data_ld,
    input logic [31:0]         ps1_data_st,
    input logic [31:0]         ps2_data_st,
    output logic               prf_st_rd_en,
    output logic               prf_ld_rd_en,
    output logic [PHY_ADDR_WIDTH-1:0] ps1_s_st,
    output logic [PHY_ADDR_WIDTH-1:0] ps1_s_ld,
    output logic [PHY_ADDR_WIDTH-1:0] ps2_s_st,
    input  logic [NO_PHY_REGS-1:0]    p_addr_valid,
    output logic               st_resp,
    output logic               lsq_access_complete,
    input  logic               flush_load_queue,
    input  logic               flush_hold,
    output logic               lsq_full,

    //ROB signals
    input logic [ROB_ID_WIDTH-1:0] head_rob_id_for_st
);

logic   [3:0]   dmem_rmask_copy;

  // load queue
  typedef struct {
      logic [PHY_ADDR_WIDTH-1:0] ps1_s;
      logic ps1_s_ready;
      logic [PHY_ADDR_WIDTH-1:0] pd_s;
      logic [2:0] funct3;
      logic [31:0] imms;
      logic inst_present;
      logic ready;
      
      logic [WIDTH:0] tail_ptr_store_relative; 
      
      logic [ROB_ID_WIDTH-1:0] rob_id;
      logic [31:0] ld_addr;
      logic store_queue_was_empty; 

      //for the monitor
      logic [31:0] rs1_data;
      logic [31:0] pc;
  } load_queue_row;

    // store queue
  typedef struct {
      logic [PHY_ADDR_WIDTH-1:0] ps1_s;
      logic [PHY_ADDR_WIDTH-1:0] ps2_s;
      logic [31:0] ps2_data;
      logic ps2_s_ready;
      logic ps1_s_ready;
      logic [31:0] imms;
      logic [2:0] funct3;
      logic [ROB_ID_WIDTH-1:0] rob_id;
      logic [31:0] st_addr;
      logic inst_present;
      //for the monitor
      logic[31:0] rs1_data;
  } store_queue_row;

logic [31:0] st_addr;
logic [31:0] ld_addr;
logic update_st_addr;
logic update_st_data;
logic update_ld_addr;
integer unsigned ld_update_ptr;
integer unsigned st_update_ptr;
integer unsigned st_update_data_ptr;
logic forwarding ;
integer unsigned forwarding_ptr;
logic load_queue_pop;

logic prf_ps1_st_rd_en;           
logic prf_ps2_st_rd_en;
logic store_queue_head_ptr_ready;
logic load_queue_head_ptr_ready;

load_queue_row  load_queue [0:DEPTH-1];
store_queue_row store_queue[0:DEPTH-1];

logic [WIDTH-1:0] load_head_ptr;

// UPDATED: Global Store Pointers now use Extended Width [WIDTH:0]
logic [WIDTH:0] store_head_ptr;
logic [WIDTH:0] store_tail_ptr;

// Counter for store queue occupancy
logic [$clog2(DEPTH):0] store_count;

logic load_is_accessing_mem;
logic store_is_accessing_mem;
integer unsigned free_location;
logic memory_access_in_progress;
logic store_memory_access_in_progress;
logic store_queue_full;
logic store_queue_empty;
logic [WIDTH-1:0] j_idx;

logic load_queue_full, load_queue_empty; 
logic store_queue_pop;
logic [WAY-1:0] store_queue_push;

logic [1:0]  byte_offset; 
logic [31:0] load_word; 
logic [15:0] load_half; 
logic [7:0]  load_byte;

logic [WIDTH-1:0] load_active_idx;
logic [WIDTH-1:0] load_eff_idx;
integer unsigned store_queue_relative[WAY];
integer unsigned load_queue_relative[WAY];
integer unsigned current_store_count;
integer unsigned current_load_count;
logic [WIDTH-1:0] head_idx;

// Queue Status Logic


// Store queue is full if we don't have enough space for a full WAY dispatch
assign store_queue_full  = (store_count > ($clog2(DEPTH)+1)'(DEPTH - 'd2*WAY)) ? 1'b1 : 1'b0;
assign store_queue_empty = (store_count == 0) ? 1'b1 : 1'b0;

// Load queue status
always_comb begin
    load_queue_full = 1'b0;
    load_queue_empty = 1'b0;
    if(DEPTH - free_location <= WAY) begin
        load_queue_full = 1'b1;
    end
    if(free_location == 0) begin
        load_queue_empty = 1'b1;
    end
end

assign lsq_full = load_queue_full || store_queue_full;

// Dispatch Count Logic

always_comb begin
    for(integer unsigned sc_lsq = 0; sc_lsq < WAY; ++sc_lsq) begin
        store_queue_relative[sc_lsq] = '0;
        load_queue_relative[sc_lsq]  = '0;
    end
    current_store_count = 0;    
    current_load_count = 0;
    for(integer unsigned sc_lsq = 0; sc_lsq < WAY; ++sc_lsq) begin
        store_queue_relative[sc_lsq] = current_store_count;
        load_queue_relative[sc_lsq]  = current_load_count;
        if (mem_inst_from_rename[sc_lsq].mem_inst_valid && mem_inst_from_rename[sc_lsq].load_or_store) begin
            current_store_count = current_store_count + 1;
        end else if (mem_inst_from_rename[sc_lsq].mem_inst_valid && !mem_inst_from_rename[sc_lsq].load_or_store)begin
            current_load_count = current_load_count + 1;
        end
    end
end

// Load Queue Free List Logic

logic [WIDTH-1:0] load_tail_ptr_stack [DEPTH];

always_ff @(posedge clk) begin
    if (rst || flush_load_queue) begin
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            load_tail_ptr_stack[i] <= WIDTH'(i);
        end
        free_location <= '0;
    end
    else begin
        if ((|current_load_count) && load_queue_pop) begin 
            for(integer unsigned sc_lsq=0; sc_lsq < WAY - 1; ++sc_lsq) begin
                if(sc_lsq < current_load_count) begin 
                    load_tail_ptr_stack[free_location + sc_lsq] <= 'x;
                end
            end
            if(load_is_accessing_mem) begin
                load_tail_ptr_stack[free_location + current_load_count - 1] <= load_active_idx; 
            end else begin 
                load_tail_ptr_stack[free_location + current_load_count - 1] <= load_head_ptr;
            end
            free_location <= free_location + current_load_count - 1;
        end 
        else if (load_queue_pop) begin
            if(load_is_accessing_mem) begin
                load_tail_ptr_stack[free_location - 1] <= load_active_idx; 
            end else begin 
                load_tail_ptr_stack[free_location - 1] <= load_head_ptr;
            end
            free_location <= free_location - 1;
        end 
        else if (|current_load_count) begin
            for(integer unsigned sc_lsq=0; sc_lsq < WAY; ++sc_lsq) begin
                if(sc_lsq < current_load_count) begin
                    load_tail_ptr_stack[free_location + sc_lsq] <= 'x;
                end
            end
            free_location <= free_location + current_load_count;
        end
    end
end

// Load Queue Update Logic

always_ff @(posedge clk) begin
    if(rst || flush_load_queue) begin
        load_is_accessing_mem  <= 1'b0;
        load_active_idx        <= '0;
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            load_queue[i] <= '{default: '0};
        end
    end else begin
        // Enqueue Loads
        for(integer unsigned sc_lsq =0; sc_lsq < WAY; ++sc_lsq) begin
            if(mem_inst_from_rename[sc_lsq].mem_inst_valid && !mem_inst_from_rename[sc_lsq].load_or_store) begin
                logic [WIDTH-1:0] alloc_idx;
                alloc_idx = load_tail_ptr_stack[free_location + load_queue_relative[sc_lsq]];

                load_queue[alloc_idx].inst_present            <= 1'b1;
                load_queue[alloc_idx].ps1_s                   <= mem_inst_from_rename[sc_lsq].ps1_s;
                load_queue[alloc_idx].imms                    <= mem_inst_from_rename[sc_lsq].imms;
                load_queue[alloc_idx].funct3                  <= mem_inst_from_rename[sc_lsq].funct3;
                load_queue[alloc_idx].pd_s                    <= mem_inst_from_rename[sc_lsq].pd_s;
                
                // --- SNAPSHOT STORE TAIL POINTER (Extended) ---
                if(store_queue_empty && (store_queue_relative[sc_lsq] == 0) ) begin
                    load_queue[alloc_idx].tail_ptr_store_relative <= '0; 
                    load_queue[alloc_idx].store_queue_was_empty   <= 1'b1;
                end
                else begin
                    // Calculate extended tail. If result wraps (e.g., 0 - 1), it correctly becomes
                    // 111...11, representing the previous index in the previous phase.
                    load_queue[alloc_idx].tail_ptr_store_relative <= (WIDTH+1)'(store_tail_ptr + store_queue_relative[sc_lsq] - 1'b1);
                    load_queue[alloc_idx].store_queue_was_empty   <= 1'b0;
                end

                load_queue[alloc_idx].rob_id                  <= mem_inst_from_rename[sc_lsq].rob_id; 
                load_queue[alloc_idx].pc                      <= mem_inst_from_rename[sc_lsq].pc;                    
            end 
        end

        // Address Calc Update
        if(update_ld_addr) begin
            load_queue[ld_update_ptr].rs1_data      <= ps1_data_ld;
            load_queue[ld_update_ptr].ld_addr       <= ld_addr;
            load_queue[ld_update_ptr].ps1_s_ready   <= 1'b1;
        end

        // Dequeue / Access Logic
        if(load_queue_pop) begin
            load_is_accessing_mem <= 1'b0;
            if (load_is_accessing_mem)
                load_queue[load_active_idx] <= '{default: '0};
            else
                load_queue[load_head_ptr]   <= '{default: '0};
        end 
        else if(memory_access_in_progress) begin
            if (!load_is_accessing_mem) begin
                load_active_idx <= load_head_ptr;
            end
            load_is_accessing_mem <= 1'b1;
        end
    end
end


// Store Queue Logic 

always_comb begin
    for(integer unsigned sc_lsq=0; sc_lsq < WAY; ++sc_lsq) begin
        store_queue_push[sc_lsq] = 1'b0;
        if(mem_inst_from_rename[sc_lsq].mem_inst_valid && mem_inst_from_rename[sc_lsq].load_or_store) begin
            store_queue_push[sc_lsq] = 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst || flush_load_queue) begin
        store_head_ptr <= '0;
        store_tail_ptr <= '0;
        store_count    <= '0;
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            store_queue[i] <= '{default: '0};
        end
        st_resp                <= 1'b0;
        store_is_accessing_mem <= 1'b0;
    end else begin

        if(|store_queue_push) begin
            for(integer unsigned sc_lsq = 0; sc_lsq < WAY; ++sc_lsq) begin
                if (store_queue_push[sc_lsq]) begin

                    logic [WIDTH:0] write_ptr_ext;
                    logic [WIDTH-1:0] write_idx;
                    
                    write_ptr_ext = (WIDTH+1)'(store_tail_ptr + store_queue_relative[sc_lsq]);
                    write_idx     = write_ptr_ext[WIDTH-1:0];
                    
                    store_queue[write_idx].ps1_s        <= mem_inst_from_rename[sc_lsq].ps1_s;
                    store_queue[write_idx].ps2_s        <= mem_inst_from_rename[sc_lsq].ps2_s;
                    store_queue[write_idx].imms         <= mem_inst_from_rename[sc_lsq].imms;
                    store_queue[write_idx].funct3       <= mem_inst_from_rename[sc_lsq].funct3;
                    store_queue[write_idx].rob_id       <= mem_inst_from_rename[sc_lsq].rob_id;
                    store_queue[write_idx].inst_present <= 1'b1;
                    store_queue[write_idx].ps1_s_ready  <= 1'b0;
                    store_queue[write_idx].ps2_s_ready  <= 1'b0;
                end                        
            end
            // Extended pointer increments naturally (no manual wrap needed)
            store_tail_ptr <= (WIDTH+1)'(store_tail_ptr + current_store_count);
        end


        if (store_queue_pop) begin
            store_is_accessing_mem <= 1'b0;
  
            store_queue[store_head_ptr[WIDTH-1:0]] <= '{default: '0}; 

            store_head_ptr <= store_head_ptr + 1'b1; 
        end else if(store_memory_access_in_progress) begin
            store_is_accessing_mem <= 1'b1;
        end 


        if ((|store_queue_push) && store_queue_pop)
            store_count <= ($clog2(DEPTH)+1)'(store_count + current_store_count - 1'b1);
        else if (|store_queue_push)
            store_count <= ($clog2(DEPTH)+1)'(store_count + current_store_count);
        else if (store_queue_pop)
            store_count <= ($clog2(DEPTH)+1)'(store_count - 1'b1);


        if(update_st_addr) begin
            store_queue[st_update_ptr].st_addr      <= st_addr;
            store_queue[st_update_ptr].ps1_s_ready  <= 1'b1;
            store_queue[st_update_ptr].rs1_data     <= ps1_data_st;
        end
        if(update_st_data) begin
            store_queue[st_update_data_ptr].ps2_data    <= ps2_data_st;
            store_queue[st_update_data_ptr].ps2_s_ready <= 1'b1;
        end
      
        if(store_queue_pop) begin
            st_resp <= 1'b1;
        end else begin
            st_resp <= 1'b0;
        end
    end
end

// Memory Access Logic

always_comb begin
    store_queue_pop                 = 1'b0;
    dmem_addr                       = '0;
    memory_access_in_progress       = 1'b0;
    mem_ld_cdb                      = '0;
    dmem_wmask                      = '0;
    dmem_rmask                      = '0;
    dmem_rmask_copy                 = '0;
    dmem_wdata                      = 'x;
    load_queue_pop                  = 1'b0;
    store_memory_access_in_progress = 1'b0;
    lsq_access_complete             = 1'b0;
    load_word                       = '0;
    load_half                       = '0;
    load_byte                       = '0;
    byte_offset                     = '0;

    load_eff_idx = load_head_ptr;
    if (load_is_accessing_mem)
        load_eff_idx = load_active_idx;

    // --- Load Execution ---
    if(((load_queue_head_ptr_ready) || (load_is_accessing_mem)) &&
       (!store_is_accessing_mem) && !flush_load_queue) begin
        memory_access_in_progress = 1'b1;

        unique case (load_queue[load_eff_idx].funct3)
            lb, lbu: begin
                dmem_rmask      = forwarding ? '0 : 4'b0001 << load_queue[load_eff_idx].ld_addr[1:0];
                dmem_rmask_copy =               4'b0001 << load_queue[load_eff_idx].ld_addr[1:0];
            end
            lh, lhu: begin
                dmem_rmask      = forwarding ? '0 : 4'b0011 << load_queue[load_eff_idx].ld_addr[1:0];
                dmem_rmask_copy =               4'b0011 << load_queue[load_eff_idx].ld_addr[1:0];
            end
            lw     : begin
                dmem_rmask      = forwarding ? '0 : 4'b1111;
                dmem_rmask_copy =               4'b1111;
            end
            default : begin
                dmem_rmask      = '0; 
                dmem_rmask_copy = '0; 
            end
        endcase

        dmem_addr[31:2] = load_queue[load_eff_idx].ld_addr[31:2]; 

        if      (forwarding ? dmem_rmask_copy[0] : dmem_rmask[0]) byte_offset = 2'd0;
        else if (forwarding ? dmem_rmask_copy[1] : dmem_rmask[1]) byte_offset = 2'd1;
        else if (forwarding ? dmem_rmask_copy[2] : dmem_rmask[2]) byte_offset = 2'd2;
        else if (forwarding ? dmem_rmask_copy[3] : dmem_rmask[3]) byte_offset = 2'd3;
        else                                                      byte_offset = 2'd0;

        if(forwarding && !load_is_accessing_mem) begin
            if(!flush_hold) begin   
                load_word = store_queue[forwarding_ptr].ps2_data;
                load_byte = load_word[8*byte_offset +: 8]; 
                load_half = load_word[16*byte_offset[1] +: 16];

                mem_ld_cdb.mem_valid      = 1'b1;
                mem_ld_cdb.rob_id         = load_queue[load_eff_idx].rob_id;
                mem_ld_cdb.pd_s           = load_queue[load_eff_idx].pd_s;
                mem_ld_cdb.mem_load_data  = store_queue[forwarding_ptr].ps2_data;
                unique case(load_queue[load_eff_idx].funct3)
                    lb : mem_ld_cdb.mem_rd_data = {{24{load_byte[7]}},  load_byte};
                    lbu: mem_ld_cdb.mem_rd_data = {24'b0,              load_byte};
                    lh : mem_ld_cdb.mem_rd_data = {{16{load_half[15]}}, load_half};
                    lhu: mem_ld_cdb.mem_rd_data = {16'b0,              load_half};
                    default: mem_ld_cdb.mem_rd_data = load_word;
                endcase
                mem_ld_cdb.rs1_data     = load_queue[load_eff_idx].rs1_data;
                mem_ld_cdb.rmask        = dmem_rmask_copy;
                mem_ld_cdb.ld_addr      = dmem_addr;
            end
            load_queue_pop          = 1'b1;
        end
        else if(mem_resp) begin
            if(!flush_hold) begin
                load_word = dmem_rdata;
                load_byte = load_word[8*byte_offset +: 8]; 
                load_half = load_word[16*byte_offset[1] +: 16];

                mem_ld_cdb.mem_valid     = 1'b1;
                mem_ld_cdb.rob_id        = load_queue[load_eff_idx].rob_id;
                mem_ld_cdb.pd_s          = load_queue[load_eff_idx].pd_s;
                mem_ld_cdb.mem_load_data = dmem_rdata;

                unique case(load_queue[load_eff_idx].funct3)
                    lb : mem_ld_cdb.mem_rd_data = {{24{load_byte[7]}},  load_byte};
                    lbu: mem_ld_cdb.mem_rd_data = {24'b0,              load_byte};
                    lh : mem_ld_cdb.mem_rd_data = {{16{load_half[15]}}, load_half};
                    lhu: mem_ld_cdb.mem_rd_data = {16'b0,              load_half};
                    default: mem_ld_cdb.mem_rd_data = load_word;
                endcase
                mem_ld_cdb.rs1_data     = load_queue[load_eff_idx].rs1_data;
                mem_ld_cdb.rmask        = dmem_rmask_copy;
                mem_ld_cdb.ld_addr      = dmem_addr;
            end
            load_queue_pop          = 1'b1;
            lsq_access_complete     = 1'b1;
        end
        if (load_is_accessing_mem) begin
            dmem_rmask = '0;
        end
    end 
    
    // --- Store Execution ---
    else if((store_queue_head_ptr_ready || store_is_accessing_mem) && !flush_load_queue) begin


        head_idx = store_head_ptr[WIDTH-1:0];

        store_memory_access_in_progress = 1'b1;

        unique case (store_queue[head_idx].funct3)
            sb: begin
                dmem_wmask = 4'b0001 << store_queue[head_idx].st_addr[1:0];
                dmem_wdata = 32'(store_queue[head_idx].ps2_data[7:0] << (8 * store_queue[head_idx].st_addr[1:0]));
            end
            sh: begin
                dmem_wmask = 4'b0011 << store_queue[head_idx].st_addr[1:0];
                dmem_wdata = 32'(store_queue[head_idx].ps2_data[15:0] << (8 * store_queue[head_idx].st_addr[1:0]));
            end
            sw: begin
                dmem_wmask = 4'b1111;
                dmem_wdata = store_queue[head_idx].ps2_data;
            end
            default: begin
                dmem_wmask = '0; 
                dmem_wdata = '0;
            end
        endcase

        dmem_addr[31:2] = store_queue[head_idx].st_addr[31:2];

        if(mem_resp) begin
            store_queue_pop          = 1'b1;
            mem_ld_cdb.mem_valid     = 1'b1;
            mem_ld_cdb.store_or_load = 1'b1;
            mem_ld_cdb.rob_id        = store_queue[head_idx].rob_id;
            mem_ld_cdb.rs1_data      = store_queue[head_idx].rs1_data;
            mem_ld_cdb.rs2_data      = store_queue[head_idx].ps2_data;
            mem_ld_cdb.wmask         = dmem_wmask;
            mem_ld_cdb.st_addr       = dmem_addr;
            mem_ld_cdb.mem_wdata     = dmem_wdata;
            lsq_access_complete      = 1'b1;
        end
        if (store_is_accessing_mem) begin
            dmem_wmask = '0;
        end
    end
end


// Store Address Ready Logic

always_comb begin
    update_st_addr   = 1'b0;
    prf_ps1_st_rd_en = 1'b0;
    ps1_s_st         = '0;
    st_addr          = '0;
    st_update_ptr    = '0;
    for(integer unsigned k = 0; k < DEPTH; ++k) begin
        if(store_queue[k].inst_present &&
           p_addr_valid[store_queue[k].ps1_s] &&
          !store_queue[k].ps1_s_ready) begin
            prf_ps1_st_rd_en = 1'b1;
            ps1_s_st         = store_queue[k].ps1_s;
            st_addr          = ps1_data_st + store_queue[k].imms;
            update_st_addr   = 1'b1;
            st_update_ptr    = k;
            break;
        end
    end
end

// Store Data Ready Logic

always_comb begin
    update_st_data      = 1'b0;
    st_update_data_ptr  = '0;
    prf_ps2_st_rd_en    = 1'b0;
    ps2_s_st            = '0;
    for(integer unsigned l = 0; l < DEPTH; ++l) begin
        if(store_queue[l].inst_present &&
           p_addr_valid[store_queue[l].ps2_s] &&
          !store_queue[l].ps2_s_ready) begin
            prf_ps2_st_rd_en    = 1'b1;
            ps2_s_st            = store_queue[l].ps2_s;
            update_st_data      = 1'b1;
            st_update_data_ptr  = l;
            break;
        end
    end
end
assign prf_st_rd_en = prf_ps1_st_rd_en || prf_ps2_st_rd_en;

// Load Address Ready Logic

always_comb begin
    update_ld_addr = 1'b0;
    ld_update_ptr  = '0;
    ld_addr        = '0;
    prf_ld_rd_en   = 1'b0;
    ps1_s_ld       = '0;
    for(integer unsigned m = 0; m < DEPTH; ++m) begin
        if(load_queue[m].inst_present &&
           p_addr_valid[load_queue[m].ps1_s] &&
          !load_queue[m].ps1_s_ready) begin
            prf_ld_rd_en  = 1'b1;
            ps1_s_ld      = load_queue[m].ps1_s;
            ld_addr       = ps1_data_ld + load_queue[m].imms;
            update_ld_addr= 1'b1;
            ld_update_ptr = m;
            break;
        end
    end
end



// Forwarding Logic

logic hazard;
logic fwd_hit;
logic [WIDTH-1:0] fwd_idx;
logic [3:0] st_mask;
logic [3:0] ld_mask;
     
logic [WIDTH:0] raw_ptr;
logic [WIDTH-1:0] check_idx;
logic [WIDTH:0]   search_dist;
logic [WIDTH:0]   dist_diff;

always_comb begin
    load_head_ptr              = '0;
    store_queue_head_ptr_ready = 1'b0;
    load_queue_head_ptr_ready  = 1'b0;
    forwarding                 = 1'b0;
    forwarding_ptr             = '0;

    // Check Head Store (Use [WIDTH-1:0] index)
    if ((store_queue[store_head_ptr[WIDTH-1:0]].ps2_s_ready && 
         store_queue[store_head_ptr[WIDTH-1:0]].ps1_s_ready) &&
        (store_queue[store_head_ptr[WIDTH-1:0]].rob_id == head_rob_id_for_st) && 
        !store_queue_empty) begin
        store_queue_head_ptr_ready = 1'b1;
    end

    // Loop through Load Queue entries
    for (integer unsigned i = 0; i < DEPTH; ++i) begin
        if (!load_queue[i].inst_present || !load_queue[i].ps1_s_ready)
            continue;

        if (load_queue[i].store_queue_was_empty) begin
            load_queue_head_ptr_ready = 1'b1;
            load_head_ptr             = WIDTH'(i);
            break;
        end

        hazard  = 1'b0;
        fwd_hit = 1'b0;
        fwd_idx = '0;


        dist_diff = load_queue[i].tail_ptr_store_relative - store_head_ptr;

        if (dist_diff[WIDTH] == 1'b1) begin

             search_dist = '0; 
        end else begin
             search_dist = dist_diff;
        end


        for (integer unsigned k = 0; k < DEPTH; k++) begin
            if ((WIDTH+1)'(k) > search_dist) break; 

     

            raw_ptr   = load_queue[i].tail_ptr_store_relative - (WIDTH+1)'(k);
            check_idx = raw_ptr[WIDTH-1:0];

            if (!store_queue[check_idx].inst_present) continue;


            if (!store_queue[check_idx].ps1_s_ready) begin
                hazard = 1'b1;
                break;
            end

            // 4. Address Match Check
            if (store_queue[check_idx].st_addr[31:2] == load_queue[i].ld_addr[31:2]) begin
                
                unique case (store_queue[check_idx].funct3)
                    sb: st_mask = 4'b0001 << store_queue[check_idx].st_addr[1:0];
                    sh: st_mask = 4'b0011 << store_queue[check_idx].st_addr[1:0];
                    sw: st_mask = 4'b1111;
                    default: st_mask = 4'b0000;
                endcase

                unique case (load_queue[i].funct3)
                    lb, lbu: ld_mask = 4'b0001 << load_queue[i].ld_addr[1:0];
                    lh, lhu: ld_mask = 4'b0011 << load_queue[i].ld_addr[1:0];
                    lw     : ld_mask = 4'b1111;
                    default: ld_mask = 4'b0000;
                endcase

                if ((st_mask & ld_mask) != 4'b0000) begin
                    // Overlap found
                    if (!store_queue[check_idx].ps2_s_ready) begin
                        hazard = 1'b1; 
                    end else begin
                        if(store_queue[check_idx].funct3 == sw) begin
                            fwd_hit = 1'b1;
                            fwd_idx = check_idx;
                        end else begin
                            hazard = 1'b1; 
                        end
                    end
                    break; 
                end
            end
        end

        if (hazard)
            continue; 

        // No hazards found
        load_queue_head_ptr_ready = 1'b1;
        load_head_ptr             = WIDTH'(i);

        if (fwd_hit) begin
            forwarding     = 1'b1;
            forwarding_ptr = {{(32-WIDTH){1'b0}}, fwd_idx};
        end
        break; 
    end
end

endmodule