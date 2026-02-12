module load_store_unit
import rv32i_types::*;
#(
    parameter integer DEPTH = 32,
    parameter integer WIDTH = $clog2(DEPTH),
    parameter NO_PHY_REGS = 128 ,
    parameter PHY_ADDR_WIDTH = $clog2(NO_PHY_REGS),
    parameter DATA_WIDTH = 32,
    parameter ROB_ENTRY = 32,
    parameter ROB_WIDTH = $clog2(ROB_ENTRY)
)
(
    input  logic               clk,
    input  logic               rst,
    input  mem_ld_st_unit      mem_inst_from_rename,
    output mem_ld_cdb_t        mem_ld_cdb,

    //memory signals to data cache
    output   logic   [31:0]    dmem_addr,
    output   logic   [3:0]     dmem_rmask,
    output   logic   [3:0]     dmem_wmask,
    input    logic   [31:0]    dmem_rdata,
    output   logic   [31:0]    dmem_wdata,
    input    logic             mem_resp,

    //register reads to the physical register file
    input  logic [31:0]        ps1_data_ld,
    input  logic [31:0]        ps1_data_st,
    input  logic [31:0]        ps2_data_st,
    output logic               prf_st_rd_en,
    output logic               prf_ld_rd_en,
    output logic [PHY_ADDR_WIDTH-1:0] ps1_s_st,
    output logic [PHY_ADDR_WIDTH-1:0] ps1_s_ld,
    output logic [PHY_ADDR_WIDTH-1:0] ps2_s_st,
    input  logic [NO_PHY_REGS-1:0]    p_addr_valid,
    output logic               st_resp,
    output logic               lsq_access_complete,
    input  logic               flush,
    output logic               lsq_full,

    //ROB signals
    input  logic [ROB_WIDTH-1:0] head_rob_id_for_st
);

  // load queue
  typedef struct packed {
      logic [PHY_ADDR_WIDTH-1:0] ps1_s;
      logic                      ps1_s_ready;
      logic [PHY_ADDR_WIDTH-1:0] pd_s;
      logic [2:0]                funct3;
      logic [31:0]               imms;
      logic                      inst_present;
      logic                      ready;
      logic [WIDTH-1:0]          tail_ptr_store_relative;
      logic [ROB_WIDTH-1:0]      rob_id;
      logic [31:0]               ld_addr;

      //for the monitor
      logic [31:0]               rs1_data;
      logic [31:0]               pc;
  } load_queue_row;

  // store queue
  typedef struct packed {
      logic [PHY_ADDR_WIDTH-1:0] ps1_s;
      logic [PHY_ADDR_WIDTH-1:0] ps2_s;
      logic [31:0]               ps2_data;
      logic                      ps2_s_ready;
      logic                      ps1_s_ready;
      logic [31:0]               imms;
      logic [2:0]                funct3;
      logic [ROB_WIDTH-1:0]      rob_id;
      logic [31:0]               st_addr;
      logic                      inst_present;
      //for the monitor
      logic [31:0]               rs1_data;
  } store_queue_row;

  localparam logic [WIDTH-1:0] LAST_PTR = DEPTH - 1;

  // common state
  load_queue_row load_queue  [0:DEPTH-1];
  store_queue_row store_queue[0:DEPTH-1];

  logic [WIDTH-1:0] load_head_ptr;
  logic [WIDTH-1:0] store_head_ptr;
  logic [WIDTH-1:0] store_tail_ptr;

  logic [WIDTH:0]   store_count;          // occupancy counter

  logic [31:0]      st_addr;
  logic [31:0]      ld_addr;
  logic             update_st_addr;
  logic             update_st_data;
  logic             update_ld_addr;
  integer           ld_update_ptr;
  integer           st_update_ptr;
  integer           st_update_data_ptr;
  logic             forwarding;
  integer           forwarding_ptr;
  logic             load_queue_pop;

  logic             prf_ps1_st_rd_en;
  logic             prf_ps2_st_rd_en;
  logic             store_queue_head_ptr_ready;
  logic             load_queue_head_ptr_ready;

  logic             load_is_accessing_mem;
  logic             store_is_accessing_mem;
  logic             memory_access_in_progress;
  logic             store_memory_access_in_progress;

  logic             load_queue_full;
  logic             load_queue_empty;
  logic             store_queue_full;
  logic             store_queue_empty;

  integer           load_free_location;

  // convenience indices
  wire [WIDTH-1:0] store_head_idx = store_head_ptr;
  wire [WIDTH-1:0] store_tail_idx = store_tail_ptr;

  // store queue full/empty from occupancy
  assign store_queue_empty = (store_count == '0);
  assign store_queue_full  = (store_count == DEPTH);

  // lsq full when either queue is full
  assign lsq_full = load_queue_full || store_queue_full;

  // =========================
  // Load queue full/empty + free slot
  // =========================
  always_comb begin
    load_queue_full       = 1'b1;
    load_queue_empty      = 1'b1;
    load_free_location    = '0;

    for (int i = 0; i < DEPTH; ++i) begin
      if (load_queue[i].inst_present) begin
        load_queue_empty = 1'b0;
      end else begin
        if (load_queue_full) begin
          // first free slot
          load_free_location = i;
        end
        load_queue_full = 1'b0;
      end
    end
  end

  // =========================
  // Load queue logic
  // =========================
  always_ff @(posedge clk) begin
    if (rst || flush) begin
      load_is_accessing_mem <= 1'b0;
      for (int i = 0; i < DEPTH; i++) begin
        load_queue[i] <= '{default: '0};
      end
    end else begin
      // enqueue new load (if not full)
      if (mem_inst_from_rename.mem_inst_valid &&
          !mem_inst_from_rename.load_or_store &&
          !load_queue_full) begin

        load_queue[load_free_location].inst_present <= 1'b1;
        load_queue[load_free_location].ps1_s        <= mem_inst_from_rename.ps1_s;
        load_queue[load_free_location].imms         <= mem_inst_from_rename.imms;
        load_queue[load_free_location].funct3       <= mem_inst_from_rename.funct3;
        load_queue[load_free_location].pd_s         <= mem_inst_from_rename.pd_s;
        if (store_tail_ptr == '0)
          load_queue[load_free_location].tail_ptr_store_relative <= store_tail_ptr;
        else
          load_queue[load_free_location].tail_ptr_store_relative <= store_tail_ptr - 1'b1;
        load_queue[load_free_location].rob_id <= mem_inst_from_rename.rob_id;
        load_queue[load_free_location].pc     <= mem_inst_from_rename.pc;
      end

      // update address/rs1 data when ps1 ready
      if (update_ld_addr) begin
        load_queue[ld_update_ptr].rs1_data    <= ps1_data_ld;
        load_queue[ld_update_ptr].ld_addr     <= ld_addr;
        load_queue[ld_update_ptr].ps1_s_ready <= 1'b1;
      end

      // pop completed load
      if (load_queue_pop) begin
        load_is_accessing_mem    <= 1'b0;
        load_queue[load_head_ptr] <= '{default: '0};
      end else if (memory_access_in_progress) begin
        load_is_accessing_mem    <= 1'b1;
      end
    end
  end

  // =========================
  // Store queue push/pop + state
  // =========================
  wire store_queue_push = mem_inst_from_rename.mem_inst_valid &&
                          mem_inst_from_rename.load_or_store;
  logic store_queue_pop;

  always_ff @(posedge clk) begin
    if (rst || flush) begin
      store_head_ptr             <= '0;
      store_tail_ptr             <= '0;
      store_count                <= '0;
      for (int i = 0; i < DEPTH; i++) begin
        store_queue[i] <= '{default: '0};
      end
      st_resp                    <= 1'b0;
      store_is_accessing_mem     <= 1'b0;
    end else begin
      // PUSH
      if (store_queue_push && !store_queue_full) begin
        store_queue[store_tail_idx].ps1_s        <= mem_inst_from_rename.ps1_s;
        store_queue[store_tail_idx].ps2_s        <= mem_inst_from_rename.ps2_s;
        store_queue[store_tail_idx].imms         <= mem_inst_from_rename.imms;
        store_queue[store_tail_idx].funct3       <= mem_inst_from_rename.funct3;
        store_queue[store_tail_idx].rob_id       <= mem_inst_from_rename.rob_id;
        store_queue[store_tail_idx].inst_present <= 1'b1;

        store_tail_ptr <= (store_tail_ptr == LAST_PTR) ? '0 : store_tail_ptr + 1'b1;
      end

      // POP
      if (store_queue_pop && !store_queue_empty) begin
        store_is_accessing_mem       <= 1'b0;
        store_queue[store_head_idx]  <= '{default: '0};
        store_head_ptr               <= (store_head_ptr == LAST_PTR) ? '0 : store_head_ptr + 1'b1;
      end else if (store_memory_access_in_progress) begin
        store_is_accessing_mem       <= 1'b1;
      end

      // occupancy counter
      unique case ({store_queue_push && !store_queue_full, store_queue_pop && !store_queue_empty})
        2'b10: store_count <= store_count + 1'b1;
        2'b01: store_count <= store_count - 1'b1;
        default: ; // no change
      endcase

      // store address update
      if (update_st_addr) begin
        store_queue[st_update_ptr].st_addr     <= st_addr;
        store_queue[st_update_ptr].ps1_s_ready <= 1'b1;
        store_queue[st_update_ptr].rs1_data    <= ps1_data_st;
      end

      // store data update
      if (update_st_data) begin
        store_queue[st_update_data_ptr].ps2_data    <= ps2_data_st;
        store_queue[st_update_data_ptr].ps2_s_ready <= 1'b1;
      end

      // st_resp pulse when a store actually pops/commits
      if (store_queue_pop && !store_queue_empty) begin
        st_resp <= 1'b1;
      end else begin
        st_resp <= 1'b0;
      end
    end
  end

  // =========================
  // Main memory access arbiter
  // =========================
  always_comb begin
    store_queue_pop                = 1'b0;
    dmem_addr                      = '0;
    memory_access_in_progress      = 1'b0;
    mem_ld_cdb                     = '0;
    dmem_wmask                     = '0;
    dmem_rmask                     = '0;
    dmem_wdata                     = 'x;
    load_queue_pop                 = 1'b0;
    store_memory_access_in_progress= 1'b0;
    lsq_access_complete            = 1'b0;

    // LOAD takes priority if ready and no store currently accessing
    if (((load_queue_head_ptr_ready) || (load_is_accessing_mem)) &&
        (!store_is_accessing_mem)) begin

      memory_access_in_progress = 1'b1;

      unique case (load_queue[load_head_ptr].funct3)
        lb, lbu: dmem_rmask = 4'b0001 << load_queue[load_head_ptr].ld_addr[1:0];
        lh, lhu: dmem_rmask = 4'b0011 << load_queue[load_head_ptr].ld_addr[1:0];
        lw    : dmem_rmask  = 4'b1111;
        default: dmem_rmask = 'x;
      endcase

      dmem_addr[31:2] = load_queue[load_head_ptr].ld_addr[31:2];

      if (forwarding) begin
        mem_ld_cdb.mem_valid   = 1'b1;
        mem_ld_cdb.rob_id      = load_queue[load_head_ptr].rob_id;
        mem_ld_cdb.pd_s        = load_queue[load_head_ptr].pd_s;
        mem_ld_cdb.mem_rd_data = store_queue[forwarding_ptr].ps2_data;
        mem_ld_cdb.rs1_data    = load_queue[load_head_ptr].rs1_data;
        mem_ld_cdb.rmask       = dmem_rmask;
        mem_ld_cdb.ld_addr     = dmem_addr;
        load_queue_pop         = 1'b1;
        lsq_access_complete    = 1'b1; // treating forwarded as completed
      end else if (mem_resp) begin
        mem_ld_cdb.mem_valid   = 1'b1;
        mem_ld_cdb.rob_id      = load_queue[load_head_ptr].rob_id;
        mem_ld_cdb.pd_s        = load_queue[load_head_ptr].pd_s;
        mem_ld_cdb.mem_rd_data = dmem_rdata;
        mem_ld_cdb.rs1_data    = load_queue[load_head_ptr].rs1_data;
        mem_ld_cdb.rmask       = dmem_rmask;
        mem_ld_cdb.ld_addr     = dmem_addr;
        load_queue_pop         = 1'b1;
        lsq_access_complete    = 1'b1;
      end

    end else if (store_queue_head_ptr_ready || store_is_accessing_mem) begin
      // STORE path
      store_memory_access_in_progress = 1'b1;

      unique case (store_queue[store_head_idx].funct3)
        sb: dmem_wmask = 4'b0001 << store_queue[store_head_idx].st_addr[1:0];
        sh: dmem_wmask = 4'b0011 << store_queue[store_head_idx].st_addr[1:0];
        sw: dmem_wmask = 4'b1111;
        default: dmem_wmask = 'x;
      endcase

      unique case (store_queue[store_head_idx].funct3)
        sb: dmem_wdata[8*store_queue[store_head_idx].st_addr[1:0] +: 8]   = store_queue[store_head_idx].ps2_data[7:0];
        sh: dmem_wdata[16*store_queue[store_head_idx].st_addr[1]   +:16] = store_queue[store_head_idx].ps2_data[15:0];
        sw: dmem_wdata = store_queue[store_head_idx].ps2_data;
        default: dmem_wdata = 'x;
      endcase

      dmem_addr[31:2] = store_queue[store_head_idx].st_addr[31:2];

      if (mem_resp) begin
        store_queue_pop             = 1'b1;
        mem_ld_cdb.mem_valid        = 1'b1;
        mem_ld_cdb.store_or_load    = 1'b1;
        mem_ld_cdb.rob_id           = store_queue[store_head_idx].rob_id;
        mem_ld_cdb.rs1_data         = store_queue[store_head_idx].rs1_data;
        mem_ld_cdb.rs2_data         = store_queue[store_head_idx].ps2_data;
        mem_ld_cdb.wmask            = dmem_wmask;
        mem_ld_cdb.st_addr          = dmem_addr;
        lsq_access_complete         = 1'b1;
      end
    end
  end

  // =========================
  // Store address ready logic
  // =========================
  always_comb begin
    update_st_addr    = 1'b0;
    prf_ps1_st_rd_en  = 1'b0;
    ps1_s_st          = '0;
    st_addr           = '0;
    st_update_ptr     = '0;

    for (int k = 0; k < DEPTH; ++k) begin
      if (store_queue[k].inst_present &&
          !store_queue[k].ps1_s_ready &&
          p_addr_valid[store_queue[k].ps1_s]) begin
        prf_ps1_st_rd_en = 1'b1;
        ps1_s_st         = store_queue[k].ps1_s;
        st_addr          = ps1_data_st + store_queue[k].imms;
        update_st_addr   = 1'b1;
        st_update_ptr    = k;
        break; // first matching store
      end
    end
  end

  // =========================
  // Store data ready logic
  // =========================
  always_comb begin
    update_st_data      = 1'b0;
    st_update_data_ptr  = '0;
    prf_ps2_st_rd_en    = 1'b0;
    ps2_s_st            = '0;

    for (int l = 0; l < DEPTH; ++l) begin
      if (store_queue[l].inst_present &&
          !store_queue[l].ps2_s_ready &&
          p_addr_valid[store_queue[l].ps2_s]) begin
        prf_ps2_st_rd_en   = 1'b1;
        ps2_s_st           = store_queue[l].ps2_s;
        update_st_data     = 1'b1;
        st_update_data_ptr = l;
        break; // first matching store
      end
    end
  end

  assign prf_st_rd_en = prf_ps1_st_rd_en || prf_ps2_st_rd_en;

  // =========================
  // Load address ready logic
  // =========================
  always_comb begin
    update_ld_addr = 1'b0;
    ld_update_ptr  = '0;
    ld_addr        = '0;
    prf_ld_rd_en   = 1'b0;
    ps1_s_ld       = '0;

    for (int m = 0; m < DEPTH; ++m) begin
      if (load_queue[m].inst_present &&
          !load_queue[m].ps1_s_ready &&
          p_addr_valid[load_queue[m].ps1_s]) begin
        prf_ld_rd_en  = 1'b1;
        ps1_s_ld      = load_queue[m].ps1_s;
        ld_addr       = ps1_data_ld + load_queue[m].imms;
        update_ld_addr= 1'b1;
        ld_update_ptr = m;
        break; // first matching load
      end
    end
  end

  // =========================
  // Store and load head ready + forwarding
  // =========================
  always_comb begin
    load_head_ptr               = 'x;
    store_queue_head_ptr_ready  = 1'b0;
    load_queue_head_ptr_ready   = 1'b0;
    forwarding                  = 1'b0;
    forwarding_ptr              = '0;

    // store ready when head is addr+data ready and at ROB head
    if (store_queue[store_head_idx].inst_present &&
        store_queue[store_head_idx].ps2_s_ready &&
        store_queue[store_head_idx].ps1_s_ready &&
        (store_queue[store_head_idx].rob_id == head_rob_id_for_st)) begin
      store_queue_head_ptr_ready = 1'b1;
    end

    // load ready / forwarding logic
    for (int i = 0; i < DEPTH; ++i) begin
      if (load_queue[i].inst_present && load_queue[i].ps1_s_ready) begin
        // if NO stores -> load can go
        if (store_queue_empty) begin
          load_queue_head_ptr_ready = 1'b1;
          load_head_ptr             = WIDTH'(i);
          break;
        end else begin
          // There ARE stores; need to check ordering and possible forwarding
          if (store_head_ptr > load_queue[i].tail_ptr_store_relative) begin
            // all older stores drained
            load_queue_head_ptr_ready = 1'b1;
            load_head_ptr             = WIDTH'(i);
          end else begin
            // search stores in [store_head_ptr .. tail_ptr_store_relative]
            for (int j = DEPTH-1; j >= 0; --j) begin
              if ((WIDTH'(j) >= store_head_ptr) &&
                  (WIDTH'(j) <= load_queue[i].tail_ptr_store_relative)) begin
                // if any store in window not data-ready, block
                if (!p_addr_valid[store_queue[j].ps2_s]) begin
                  break;
                end else begin
                  if (store_queue[j].st_addr == load_queue[i].ld_addr) begin
                    if (store_queue[j].ps1_s_ready) begin
                      load_head_ptr             = WIDTH'(i);
                      forwarding                = 1'b1;
                      load_queue_head_ptr_ready = 1'b1;
                      forwarding_ptr            = j;
                      break;
                    end else begin
                      break;
                    end
                  end
                end
              end
            end
          end
          break; // we decided about this load (ready or blocked)
        end
      end
    end
  end

endmodule

`ifndef SYNTHESIS
// Open file once (keep your existing initial $fopen if you already added it)
integer rob_log_fd;
initial begin
  rob_log_fd = $fopen("rob_trace.log", "w"); // truncates existing file or creates new
  if (rob_log_fd == 0) $fatal(1, "ROB: could not open rob_trace.log");
end

// 2-state helper for dump trigger
function automatic bit is1(input logic v);
  return (v === 1'b1);
endfunction

// Trigger: ROB activity, CDB, or branch mispredict / branch CDB
logic dump_now;
always_comb begin
  dump_now = is1(ren_resp) | is1(head_ready_valid) | is1(mon_we);
  for (int k = 0; k < CHANNELS; k++) begin
    dump_now |= is1(cdb_valid[k]);
  end
  // Also trigger when branch result or mispredict flush happens
  dump_now |= is1(br_mispredict_flush);
  dump_now |= is1(cdb_rob_br_taken);
end

// ---- INLINE PRINTER (no tasks, all temps are block-local automatic) ----
always_ff @(posedge clk) begin
  if (!rst | br_mispredict_flush && dump_now) begin
    // locals live only in this process → no multi-driver
    int total_lane_hits; 
    total_lane_hits = 0;

    $display("\n[%0t] ROB DUMP  (trig: ren=%0b commit=%0b mon_we=%0b cdb_any=%0b mispred_flush=%0b)",
             $time, ren_resp, head_ready_valid, mon_we, (|cdb_valid), br_mispredict_flush);
    $fdisplay(rob_log_fd,
              "\n[%0t] ROB DUMP  (trig: ren=%0b commit=%0b mon_we=%0b cdb_any=%0b mispred_flush=%0b)",
              $time, ren_resp, head_ready_valid, mon_we, (|cdb_valid), br_mispredict_flush);

    $display("  head_ptr=%0d tail_ptr=%0d  head_idx=%0d tail_idx=%0d  commit_valid=%0b  ren_full=%0b  rob_empty=%0b",
             head_ptr, tail_ptr, head_idx, tail_idx, commit_valid, ren_full, rob_empty);
    $fdisplay(rob_log_fd,
              "  head_ptr=%0d tail_ptr=%0d  head_idx=%0d tail_idx=%0d  commit_valid=%0b  ren_full=%0b  rob_empty=%0b",
              head_ptr, tail_ptr, head_idx, tail_idx, commit_valid, ren_full, rob_empty);

    // Branch / flush status summary
    $display("  BR_CTRL: flag=%0b flag_q=%0b br_mispredict_flush=%0b  cdb_rob_id_br=%0d br_taken=%0b br_pc_next=%08h",
             flag, flag_q, br_mispredict_flush, cdb_rob_id_br, cdb_rob_br_taken, cdb_br_pc_next);
    $fdisplay(rob_log_fd,
              "  BR_CTRL: flag=%0b flag_q=%0b br_mispredict_flush=%0b  cdb_rob_id_br=%0d br_taken=%0b br_pc_next=%08h",
              flag, flag_q, br_mispredict_flush, cdb_rob_id_br, cdb_rob_br_taken, cdb_br_pc_next);

    $display("  FLUSH_WIN: head_next_idx=%0d  flush_wrap=%0b  flush_vec=%b",
             headn_idx, flush_wrap, flush_vec);
    $fdisplay(rob_log_fd,
              "  FLUSH_WIN: head_next_idx=%0d  flush_wrap=%0b  flush_vec=%b",
              headn_idx, flush_wrap, flush_vec);

    // Per-channel CDB status
    for (int j = 0; j < CHANNELS; j++) begin
      $display("  CDB[%0d]: valid=%0b rob_id=%0d data=%08h",
               j, cdb_valid[j], cdb_rob_id[j], mon_cdb_data[j]);
      $fdisplay(rob_log_fd,
                "  CDB[%0d]: valid=%0b rob_id=%0d data=%08h",
                j, cdb_valid[j], cdb_rob_id[j], mon_cdb_data[j]);
    end

    $display("  idx | V R | arch  phy  | cdb_hit     | rd_wdata   | inst      | brV brP brR | flush");
    $fdisplay(rob_log_fd,
              "  idx | V R | arch  phy  | cdb_hit     | rd_wdata   | inst      | brV brP brR | flush");

    for (int i = 0; i < ROB_ENTRY; i++) begin
      bit row_hit = 0;

      $display("  %02d | %1b %1b | %3d  %3d | %b | %08h | %08h |  %1b   %1b   %1b |   %1b",
               i,
               rob[i].valid, rob[i].ready,
               rob[i].arch, rob[i].phy,
               cdb_hit_vec[i],
               rob_mon[i].rd_wdata, rob_mon[i].inst,
               rob[i].br_pred_valid, rob[i].br_pred, rob[i].br_result,
               flush_vec[i]);
      $fdisplay(rob_log_fd,
                "  %02d | %1b %1b | %3d  %3d | %b | %08h | %08h |  %1b   %1b   %1b |   %1b",
                i,
                rob[i].valid, rob[i].ready,
                rob[i].arch, rob[i].phy,
                cdb_hit_vec[i],
                rob_mon[i].rd_wdata, rob_mon[i].inst,
                rob[i].br_pred_valid, rob[i].br_pred, rob[i].br_result,
                flush_vec[i]);

      // per-row hit details
      for (int j = 0; j < CHANNELS; j++) begin
        if (cdb_hit_vec[i][j] === 1'b1) begin
          row_hit = 1;
          total_lane_hits++;
          $display("      -> HIT row %0d by lane %0d : rob_id=%0d data=%08h",
                   i, j, cdb_rob_id[j], mon_cdb_data[j]);
          $fdisplay(rob_log_fd,
                    "      -> HIT row %0d by lane %0d : rob_id=%0d data=%08h",
                    i, j, cdb_rob_id[j], mon_cdb_data[j]);
        end
      end

      // Extra branch-specific commentary
      if (rob[i].valid && rob[i].br_pred_valid) begin
        $display("      BR meta: pred=%0b result=%0b  %s  (head=%0d)",
                 rob[i].br_pred,
                 rob[i].br_result,
                 (rob[i].br_pred != rob[i].br_result) ? "MISPRED_CAND" : "OK",
                 head_idx);
        $fdisplay(rob_log_fd,
                  "      BR meta: pred=%0b result=%0b  %s  (head=%0d)",
                  rob[i].br_pred,
                  rob[i].br_result,
                  (rob[i].br_pred != rob[i].br_result) ? "MISPRED_CAND" : "OK",
                  head_idx);
      end

      if (br_mispredict_flush && flush_vec[i]) begin
        $display("      -> WILL FLUSH on mispredict (entry in flush window)");
        $fdisplay(rob_log_fd,
                  "      -> WILL FLUSH on mispredict (entry in flush window)");
      end

      if (!row_hit && rob[i].valid && !rob[i].ready) begin
        $display("      .. waiting: no CDB hit yet (or head not advanced)");
        $fdisplay(rob_log_fd,
                  "      .. waiting: no CDB hit yet (or head not advanced)");
      end
    end

    $display("  total_lane_hits_this_cycle=%0d", total_lane_hits);
    $fdisplay(rob_log_fd, "  total_lane_hits_this_cycle=%0d", total_lane_hits);
  end
end

final begin
  if (rob_log_fd) $fclose(rob_log_fd);
end
`endif

FREELIST
`ifndef SYNTHESIS
// ---------------- FREELIST TRACE DUMP ----------------
integer cq_log_fd;
// Static index for dump loop (avoid automatic var issue)
integer dump_idx;

initial begin
  cq_log_fd = $fopen("freelist_trace.log", "w"); // truncates or creates
  if (cq_log_fd == 0) $fatal(1, "FREELIST: could not open freelist_trace.log");
end

// 2-state helper
function automatic bit is1(input logic v);
  return (v === 1'b1);
endfunction

logic cq_dump_now;
logic cq_flush_any;

// decide when to dump
always_comb begin
  cq_flush_any = (|prf_free_v_flush);

  cq_dump_now = 1'b0;
  // any enqueue / dequeue
  cq_dump_now |= is1(iq_push);
  cq_dump_now |= is1(iq_pop);
  // any flush-based frees
  cq_dump_now |= cq_flush_any;
end

// ---- INLINE PRINTER ----
always_ff @(posedge clk) begin
  if (!rst && cq_dump_now) begin
    int flush_cnt;
    int head_idx_int;
    int tail_idx_int;
    flush_cnt = 0;

    $display("\n[%0t] FREELIST DUMP (push=%0b pop=%0b status=%02b flush_any=%0b)",
             $time, iq_push, iq_pop, iq_status, cq_flush_any);
    $fdisplay(cq_log_fd,
              "\n[%0t] FREELIST DUMP (push=%0b pop=%0b status=%02b flush_any=%0b)",
              $time, iq_push, iq_pop, iq_status, cq_flush_any);

    // head/tail pointers
    $display("  PTRS: head_ptr=%0d (idx=%0d)  tail_ptr=%0d (idx=%0d)  empty=%0b full=%0b",
             head_ptr, head_ptr[WIDTH-1:0],
             tail_ptr, tail_ptr[WIDTH-1:0],
             iq_empty, iq_full);
    $fdisplay(cq_log_fd,
              "  PTRS: head_ptr=%0d (idx=%0d)  tail_ptr=%0d (idx=%0d)  empty=%0b full=%0b",
              head_ptr, head_ptr[WIDTH-1:0],
              tail_ptr, tail_ptr[WIDTH-1:0],
              iq_empty, iq_full);

    // push / pop data
    if (iq_push) begin
      $display("  PUSH: data=%08h -> idx=%0d", iq_wrdata, tail_ptr[WIDTH-1:0]);
      $fdisplay(cq_log_fd,
                "  PUSH: data=%08h -> idx=%0d", iq_wrdata, tail_ptr[WIDTH-1:0]);
    end

    if (iq_pop && iq_resp) begin
      $display("  POP : data=%08h <- idx=%0d", iq_rdata, head_ptr[WIDTH-1:0]);
      $fdisplay(cq_log_fd,
                "  POP : data=%08h <- idx=%0d", iq_rdata, head_ptr[WIDTH-1:0]);
    end

    // flush frees
    if (cq_flush_any) begin
      $display("  FLUSH_FREE (rob_instr_count=%0d):", rob_instr_count);
      $fdisplay(cq_log_fd, "  FLUSH_FREE (rob_instr_count=%0d):", rob_instr_count);
      for (int f = 0; f < ROB_ENTRY; f++) begin
        if (prf_free_v_flush[f]) begin
          flush_cnt++;
          $display("    slot=%0d  prf_tag=%08h  wr_idx=%0d",
                   f, prf_free_tag_flush[f], wr_idx[f]);
          $fdisplay(cq_log_fd,
                    "    slot=%0d  prf_tag=%08h  wr_idx=%0d",
                    f, prf_free_tag_flush[f], wr_idx[f]);
        end
      end
      if (!flush_cnt) begin
        $display("    (none set despite cq_flush_any=1)");
        $fdisplay(cq_log_fd, "    (none set despite cq_flush_any=1)");
      end
    end

        // queue contents
    $display("  QUEUE STATE (DEPTH=%0d, LAST_PTR=%0d):", DEPTH, LAST_PTR);
    $fdisplay(cq_log_fd, "  QUEUE STATE (DEPTH=%0d, LAST_PTR=%0d):", DEPTH, LAST_PTR);
    $display("    idx | data              markers");
    $fdisplay(cq_log_fd, "    idx | data              markers");

    // cast pointer indices to ints once

    for (integer dump_idx = 0; dump_idx < DEPTH; dump_idx++) begin

      if ((dump_idx == head_ptr[WIDTH-1:0]) && (dump_idx == tail_ptr[WIDTH-1:0])) begin
        $display( "    %02d  | %08h  <-head_ptr,tail_ptr", dump_idx, circular_buffer[dump_idx]);
        $fdisplay(cq_log_fd,
                  "    %02d  | %08h  <-head_ptr,tail_ptr", dump_idx, circular_buffer[dump_idx]);
      end
      else if ((dump_idx == head_ptr[WIDTH-1:0])) begin
        $display( "    %02d  | %08h  <-head_ptr", dump_idx, circular_buffer[dump_idx]);
        $fdisplay(cq_log_fd,
                  "    %02d  | %08h  <-head_ptr", dump_idx, circular_buffer[dump_idx]);
      end
      else if ((dump_idx == tail_ptr[WIDTH-1:0])) begin
        $display( "    %02d  | %08h  <-tail_ptr", dump_idx, circular_buffer[dump_idx]);
        $fdisplay(cq_log_fd,
                  "    %02d  | %08h  <-tail_ptr", dump_idx, circular_buffer[dump_idx]);
      end
      else begin
        $display( "    %02d  | %08h", dump_idx, circular_buffer[dump_idx]);
        $fdisplay(cq_log_fd,
                  "    %02d  | %08h", dump_idx, circular_buffer[dump_idx]);
      end
    end
  end
end

final begin
  if (cq_log_fd) $fclose(cq_log_fd);
end
`endif


// PRF
`ifndef SYNTHESIS
// ---------------- PRF TRACE DUMP ----------------
integer prf_log_fd;

initial begin
  prf_log_fd = $fopen("prf_trace.log", "w"); // truncates existing file or creates new
  if (prf_log_fd == 0) $fatal(1, "PRF: could not open prf_trace.log");
end

// 2-state helper
function automatic bit is1(input logic v);
  return (v === 1'b1);
endfunction

// Trigger + summary flags
logic        prf_dump_now;
logic        prf_wr_any;
logic        prf_rd_any;
logic        prf_flush_any;

always_comb begin
  prf_wr_any    = 1'b0;
  prf_rd_any    = 1'b0;
  prf_flush_any = (|prf_free_v_flush);

  // any write on any FU channel
  for (int k = 0; k <= CHANNELS; k++) begin
    prf_wr_any |= is1(write_en[k]);
  end

  // any read port active
  for (int k = 0; k < CHANNELS; k++) begin
    prf_rd_any |= is1(read_en[k]);
  end

  prf_dump_now = prf_wr_any |
                 prf_rd_any |
                 is1(free_en) |
                 prf_flush_any |
                 is1(br_mispredict_flush);
end

// ---- INLINE PRINTER ----
always_ff @(posedge clk) begin
  if (!rst && prf_dump_now) begin
    int wr_cnt;
    wr_cnt = 0;

    $display("\n[%0t] PRF DUMP  (wr_any=%0b rd_any=%0b free_en=%0b flush_any=%0b br_flush=%0b)",
             $time, prf_wr_any, prf_rd_any, free_en, prf_flush_any, br_mispredict_flush);
    $fdisplay(prf_log_fd,
              "\n[%0t] PRF DUMP  (wr_any=%0b rd_any=%0b free_en=%0b flush_any=%0b br_flush=%0b)",
              $time, prf_wr_any, prf_rd_any, free_en, prf_flush_any, br_mispredict_flush);

    // --- Writes this cycle ---
    for (int j = 0; j <= CHANNELS; j++) begin
      if (write_en[j]) begin
        wr_cnt++;
        $display("  WR[%0d]: tag=%0d data=%08h", j, write_tag[j], write_data[j]);
        $fdisplay(prf_log_fd,
                  "  WR[%0d]: tag=%0d data=%08h", j, write_tag[j], write_data[j]);
      end
    end
    if (!wr_cnt)
      $fdisplay(prf_log_fd, "  WR: (none)");

    // --- Free from freelist ---
    if (free_en) begin
      $display("  FREE: tag=%0d", free_tag);
      $fdisplay(prf_log_fd, "  FREE: tag=%0d", free_tag);
    end

    // --- Free due to flush window ---
    if (prf_flush_any) begin
      $display("  FLUSH_FREE:");
      $fdisplay(prf_log_fd, "  FLUSH_FREE:");
      for (int f = 0; f < ROB_ENTRY; f++) begin
        if (prf_free_v_flush[f]) begin
          $display("    rob_slot=%0d prf_tag=%0d", f, prf_free_tag_flush[f]);
          $fdisplay(prf_log_fd,
                    "    rob_slot=%0d prf_tag=%0d", f, prf_free_tag_flush[f]);
        end
      end
    end

    // --- Read ports this cycle ---
    if (prf_rd_any) begin
      for (int j = 0; j < CHANNELS; j++) begin
        if (read_en[j]) begin
          logic [DATA_WIDTH-1:0] rd1, rd2;
          rd1 = (pr1_s[j] == '0) ? '0 : row[pr1_s[j]].data;
          rd2 = (pr2_s[j] == '0) ? '0 : row[pr2_s[j]].data;
          $display("  RD[%0d]: pr1=%0d data=%08h | pr2=%0d data=%08h",
                   j, pr1_s[j], rd1, pr2_s[j], rd2);
          $fdisplay(prf_log_fd,
                    "  RD[%0d]: pr1=%0d data=%08h | pr2=%0d data=%08h",
                    j, pr1_s[j], rd1, pr2_s[j], rd2);
        end
      end
    end else begin
      $fdisplay(prf_log_fd, "  RD: (none)");
    end

    // --- Direct PHY taps (bypass reads) ---
    $display("  PHY_TAPS: p1=%0d data=%08h  p2=%0d data=%08h",
             prf_phy1, prf_phy1_data, prf_phy2, prf_phy2_data);
    $fdisplay(prf_log_fd,
              "  PHY_TAPS: p1=%0d data=%08h  p2=%0d data=%08h",
              prf_phy1, prf_phy1_data, prf_phy2, prf_phy2_data);

    // --- Valid map summary ---
    $display("  VALID_ARRAY[0..%0d]: %b", PRF_ENTRY-1, valid_array);
    $fdisplay(prf_log_fd,
              "  VALID_ARRAY[0..%0d]: %b", PRF_ENTRY-1, valid_array);

    // --- Full PRF contents ---
    $display("  idx | V | DATA");
    $fdisplay(prf_log_fd, "  idx | V | DATA");
    for (int i = 0; i < PRF_ENTRY; i++) begin
      $display("  %03d | %1b | %08h", i, row[i].valid, row[i].data);
      $fdisplay(prf_log_fd,
                "  %03d | %1b | %08h", i, row[i].valid, row[i].data);
    end
  end
end

final begin
  if (prf_log_fd) $fclose(prf_log_fd);
end
`endif


RESERVATION_STATION

`ifndef SYNTHESIS
integer rs_log_fd;
integer rs_dump_idx;

function automatic bit is1(input logic v);
  return (v === 1'b1);
endfunction

logic rs_dump_now;

// decide when to dump: on dispatch, issue, or branch flush
always_comb begin
  rs_dump_now = 1'b0;
  rs_dump_now |= is1(res_input.dispatch_to_res_valid && station_free);
  rs_dump_now |= is1(branch_taken);
  for (int fu = 0; fu < FU_IDX_COUNT; fu++) begin
    rs_dump_now |= is1(ready_for_fu[fu]);
  end
end

initial begin
  rs_log_fd = $fopen("reservation_station_trace.log", "w");
  if (rs_log_fd == 0) $fatal(1, "RS: could not open reservation_station_trace.log");
end

always_ff @(posedge clk) begin
  if (!rst && rs_dump_now) begin
    $display("\n[%0t] RS DUMP (dispatch=%0b station_free=%0b full=%0b br_taken=%0b)",
             $time, res_input.dispatch_to_res_valid, station_free, station_is_full, branch_taken);
    $fdisplay(rs_log_fd,
              "\n[%0t] RS DUMP (dispatch=%0b station_free=%0b full=%0b br_taken=%0b)",
              $time, res_input.dispatch_to_res_valid, station_free, station_is_full, branch_taken);

    // FU issue flags
    $display("  ISSUE FLAGS: ALU=%0b MUL=%0b DIV=%0b BR=%0b",
             ready_for_fu[ALU], ready_for_fu[MUL], ready_for_fu[DIV], ready_for_fu[BRANCH]);
    $fdisplay(rs_log_fd, "  ISSUE FLAGS: ALU=%0b MUL=%0b DIV=%0b BR=%0b",
              ready_for_fu[ALU], ready_for_fu[MUL], ready_for_fu[DIV], ready_for_fu[BRANCH]);

    $display("  ENTRIES (DEPTH=%0d):", DEPTH);
    $fdisplay(rs_log_fd, "  ENTRIES (DEPTH=%0d):", DEPTH);
    $display("    idx | V ps1_v ps1_s  ps2_v ps2_s  pd_s  fu rob_id  imm_flag imm_val        pc          opcode");
    $fdisplay(rs_log_fd,
              "    idx | V ps1_v ps1_s  ps2_v ps2_s  pd_s  fu rob_id  imm_flag imm_val        pc          opcode");

    for (rs_dump_idx = 0; rs_dump_idx < DEPTH; rs_dump_idx++) begin
      bit is_issue_slot;
      is_issue_slot = 1'b0;
      for (int fu = 0; fu < FU_IDX_COUNT; fu++) begin
        if (ready_for_fu[fu] && (ready_for_fu_idx[fu] == rs_dump_idx[$clog2(DEPTH)-1:0]))
          is_issue_slot = 1'b1;
      end

      $display("    %02d | %0b   %0b    %03d    %0b    %03d   %03d  %0d  %03d      %0b      %08h  %08h  %02h%s",
               rs_dump_idx,
               res_V[rs_dump_idx],
               res_ps1_v[rs_dump_idx],
               res_ps1_s[rs_dump_idx],
               res_ps2_v[rs_dump_idx],
               res_ps2_s[rs_dump_idx],
               res_pd_s[rs_dump_idx],
               res_fu_idx[rs_dump_idx],
               res_rob_id[rs_dump_idx],
               res_imm[rs_dump_idx][32],           // imm_flag
               res_imm[rs_dump_idx][31:0],         // imm_val
               res_pc[rs_dump_idx],
               res_opcode[rs_dump_idx],
               (is_issue_slot ? " <-ISSUE" : "")
      );

      $fdisplay(rs_log_fd,
                "    %02d | %0b   %0b    %03d    %0b    %03d   %03d  %0d  %03d      %0b      %08h  %08h  %02h%s",
                rs_dump_idx,
                res_V[rs_dump_idx],
                res_ps1_v[rs_dump_idx],
                res_ps1_s[rs_dump_idx],
                res_ps2_v[rs_dump_idx],
                res_ps2_s[rs_dump_idx],
                res_pd_s[rs_dump_idx],
                res_fu_idx[rs_dump_idx],
                res_rob_id[rs_dump_idx],
                res_imm[rs_dump_idx][32],
                res_imm[rs_dump_idx][31:0],
                res_pc[rs_dump_idx],
                res_opcode[rs_dump_idx],
                (is_issue_slot ? " <-ISSUE" : "")
      );
    end
  end
end

final begin
  if (rs_log_fd) $fclose(rs_log_fd);
end
`endif


  // ======================================================
  // LSQ TRACE DUMP (LOAD/STORE QUEUES + PRF + CDB)
  // ======================================================
// ======================================================
// LSQ TRACE DUMP (LOAD/STORE QUEUES + PRF + CDB)
// ======================================================
`ifndef SYNTHESIS
integer lsq_log_fd;
// Static index for dump loop
integer lsq_dump_idx;

// Any enqueue this cycle across all WAYs
logic lsq_any_mem_valid;

always_comb begin
  lsq_any_mem_valid = 1'b0;
  for (int w = 0; w < WAY; w++) begin
    lsq_any_mem_valid |= mem_inst_from_rename[w].mem_inst_valid;
  end
end

initial begin
  lsq_log_fd = $fopen("lsq_trace.log", "w"); // truncates or creates
  if (lsq_log_fd == 0) $fatal(1, "LSQ: could not open lsq_trace.log");
end

// 2-state helper (local to LSQ)
function automatic bit is1_lsq(input logic v);
  return (v === 1'b1);
endfunction

// trigger for dumping
logic lsq_dump_now;

always_comb begin
  lsq_dump_now = 1'b0;

  // enqueue (any way)
  lsq_dump_now |= is1_lsq(lsq_any_mem_valid);

  // PRF reads for addr/data
  lsq_dump_now |= is1_lsq(prf_ld_rd_en);
  lsq_dump_now |= is1_lsq(prf_st_rd_en);

  // queue pops / memory completion / forwarding
  lsq_dump_now |= is1_lsq(load_queue_pop);
  lsq_dump_now |= is1_lsq(store_queue_pop);
  lsq_dump_now |= is1_lsq(lsq_access_complete);
  lsq_dump_now |= is1_lsq(forwarding);

  // flushes
  lsq_dump_now |= is1_lsq(flush_load_queue);
end

// ---- INLINE PRINTER ----
always_ff @(posedge clk) begin
  if (!rst && lsq_dump_now) begin
    int flush_cnt;
    flush_cnt = 0;

    // --------- Summary header ----------
    $display("\n[%0t] LSQ DUMP (mem_valid_any=%0b LQ_full=%0b SQ_full=%0b LQ_empty=%0b SQ_empty=%0b access_done=%0b load_flush=%0b)",
             $time,
             lsq_any_mem_valid,
             load_queue_full, store_queue_full,
             load_queue_empty, store_queue_empty,
             lsq_access_complete, flush_load_queue);
    $fdisplay(lsq_log_fd,
              "\n[%0t] LSQ DUMP (mem_valid_any=%0b LQ_full=%0b SQ_full=%0b LQ_empty=%0b SQ_empty=%0b access_done=%0b load_flush=%0b)",
              $time,
              lsq_any_mem_valid,
              load_queue_full, store_queue_full,
              load_queue_empty, store_queue_empty,
              lsq_access_complete, flush_load_queue);

    // store pointers
    $display("  STORE_PTRS: head_ptr=%0d  tail_ptr=%0d  count=%0d  head_ready=%0b  busy=%0b",
             store_head_ptr, store_tail_ptr, store_tail_ptr - store_head_ptr,
             store_queue_head_ptr_ready, store_is_accessing_mem);
    $fdisplay(lsq_log_fd,
              "  STORE_PTRS: head_ptr=%0d  tail_ptr=%0d  count=%0d  head_ready=%0b  busy=%0b",
              store_head_ptr, store_tail_ptr, store_tail_ptr - store_head_ptr,
              store_queue_head_ptr_ready, store_is_accessing_mem);

    // load header
    $display("  LOAD_HDR : head_idx=%0d  head_ready=%0b  busy=%0b  forwarding=%0b fwd_ptr=%0d",
             load_head_ptr, load_queue_head_ptr_ready,
             load_is_accessing_mem, forwarding, forwarding_ptr);
    $fdisplay(lsq_log_fd,
              "  LOAD_HDR : head_idx=%0d  head_ready=%0b  busy=%0b  forwarding=%0b fwd_ptr=%0d",
              load_head_ptr, load_queue_head_ptr_ready,
              load_is_accessing_mem, forwarding, forwarding_ptr);

    // --------- PRF reads this cycle ----------
    if (prf_ld_rd_en || prf_st_rd_en) begin
      $display("  PRF READS:");
      $fdisplay(lsq_log_fd, "  PRF READS:");

      if (prf_ld_rd_en) begin
        $display("    LD : ps1_s_ld=%0d  rs1_data(ld)=%08h  (ld_update_ptr=%0d update_ld_addr=%0b)",
                 ps1_s_ld, ps1_data_ld, ld_update_ptr, update_ld_addr);
        $fdisplay(lsq_log_fd,
                  "    LD : ps1_s_ld=%0d  rs1_data(ld)=%08h  (ld_update_ptr=%0d update_ld_addr=%0b)",
                  ps1_s_ld, ps1_data_ld, ld_update_ptr, update_ld_addr);
      end

      if (prf_st_rd_en) begin
        $display("    ST : ps1_s_st=%0d rs1_data(st)=%08h (update_st_addr=%0b ptr=%0d) | ps2_s_st=%0d ps2_data(st)=%08h (update_st_data=%0b ptr=%0d)",
                 ps1_s_st, ps1_data_st, update_st_addr, st_update_ptr,
                 ps2_s_st, ps2_data_st, update_st_data, st_update_data_ptr);
        $fdisplay(lsq_log_fd,
                  "    ST : ps1_s_st=%0d rs1_data(st)=%08h (update_st_addr=%0b ptr=%0d) | ps2_s_st=%0d ps2_data(st)=%08h (update_st_data=%0b ptr=%0d)",
                  ps1_s_st, ps1_data_st, update_st_addr, st_update_ptr,
                  ps2_s_st, ps2_data_st, update_st_data, st_update_data_ptr);
      end
    end

    // --------- CDB / ROB interface ----------
    if (mem_ld_cdb.mem_valid) begin
      $display("  CDB OUT: type=%s rob_id=%0d pd_s=%0d rd_data=%08h rs1=%08h rs2=%08h rmask=%4b wmask=%4b ld_addr=%08h st_addr=%08h",
               (mem_ld_cdb.store_or_load ? "STORE" : "LOAD"),
               mem_ld_cdb.rob_id, mem_ld_cdb.pd_s,
               mem_ld_cdb.mem_rd_data,
               mem_ld_cdb.rs1_data, mem_ld_cdb.rs2_data,
               mem_ld_cdb.rmask, mem_ld_cdb.wmask,
               mem_ld_cdb.ld_addr, mem_ld_cdb.st_addr);
      $fdisplay(lsq_log_fd,
                "  CDB OUT: type=%s rob_id=%0d pd_s=%0d rd_data=%08h rs1=%08h rs2=%08h rmask=%4b wmask=%4b ld_addr=%08h st_addr=%08h",
                (mem_ld_cdb.store_or_load ? "STORE" : "LOAD"),
                mem_ld_cdb.rob_id, mem_ld_cdb.pd_s,
                mem_ld_cdb.mem_rd_data,
                mem_ld_cdb.rs1_data, mem_ld_cdb.rs2_data,
                mem_ld_cdb.rmask, mem_ld_cdb.wmask,
                mem_ld_cdb.ld_addr, mem_ld_cdb.st_addr);
    end

    // --------- LOAD QUEUE STATE ----------
    $display("  LOAD QUEUE STATE (DEPTH=%0d):", DEPTH);
    $fdisplay(lsq_log_fd, "  LOAD QUEUE STATE (DEPTH=%0d):", DEPTH);
    $display("    idx | V ps1_rdy | rob  ps1_s pd_s | tail_rel | ld_addr   rs1_data   f3  pc        markers");
    $fdisplay(lsq_log_fd,
              "    idx | V ps1_rdy | rob  ps1_s pd_s | tail_rel | ld_addr   rs1_data   f3  pc        markers");

    for (lsq_dump_idx = 0; lsq_dump_idx < DEPTH; lsq_dump_idx++) begin
      if (load_queue[lsq_dump_idx].inst_present &&
          (lsq_dump_idx == load_head_ptr)) begin
        // row is load head
        $display("    %02d  | %1b    %1b   | %3d  %5d %5d | %8d | %08h %08h  %1d  %08h <-load_head_ptr",
                 lsq_dump_idx,
                 load_queue[lsq_dump_idx].inst_present,
                 load_queue[lsq_dump_idx].ps1_s_ready,
                 load_queue[lsq_dump_idx].rob_id,
                 load_queue[lsq_dump_idx].ps1_s,
                 load_queue[lsq_dump_idx].pd_s,
                 load_queue[lsq_dump_idx].tail_ptr_store_relative,
                 load_queue[lsq_dump_idx].ld_addr,
                 load_queue[lsq_dump_idx].rs1_data,
                 load_queue[lsq_dump_idx].funct3,
                 load_queue[lsq_dump_idx].pc);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b    %1b   | %3d  %5d %5d | %8d | %08h %08h  %1d  %08h <-load_head_ptr",
                  lsq_dump_idx,
                  load_queue[lsq_dump_idx].inst_present,
                  load_queue[lsq_dump_idx].ps1_s_ready,
                  load_queue[lsq_dump_idx].rob_id,
                  load_queue[lsq_dump_idx].ps1_s,
                  load_queue[lsq_dump_idx].pd_s,
                  load_queue[lsq_dump_idx].tail_ptr_store_relative,
                  load_queue[lsq_dump_idx].ld_addr,
                  load_queue[lsq_dump_idx].rs1_data,
                  load_queue[lsq_dump_idx].funct3,
                  load_queue[lsq_dump_idx].pc);
      end else begin
        // normal row
        $display("    %02d  | %1b    %1b   | %3d  %5d %5d | %8d | %08h %08h  %1d  %08h",
                 lsq_dump_idx,
                 load_queue[lsq_dump_idx].inst_present,
                 load_queue[lsq_dump_idx].ps1_s_ready,
                 load_queue[lsq_dump_idx].rob_id,
                 load_queue[lsq_dump_idx].ps1_s,
                 load_queue[lsq_dump_idx].pd_s,
                 load_queue[lsq_dump_idx].tail_ptr_store_relative,
                 load_queue[lsq_dump_idx].ld_addr,
                 load_queue[lsq_dump_idx].rs1_data,
                 load_queue[lsq_dump_idx].funct3,
                 load_queue[lsq_dump_idx].pc);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b    %1b   | %3d  %5d %5d | %8d | %08h %08h  %1d  %08h",
                  lsq_dump_idx,
                  load_queue[lsq_dump_idx].inst_present,
                  load_queue[lsq_dump_idx].ps1_s_ready,
                  load_queue[lsq_dump_idx].rob_id,
                  load_queue[lsq_dump_idx].ps1_s,
                  load_queue[lsq_dump_idx].pd_s,
                  load_queue[lsq_dump_idx].tail_ptr_store_relative,
                  load_queue[lsq_dump_idx].ld_addr,
                  load_queue[lsq_dump_idx].rs1_data,
                  load_queue[lsq_dump_idx].funct3,
                  load_queue[lsq_dump_idx].pc);
      end
    end

    // --------- STORE QUEUE STATE ----------
    $display("  STORE QUEUE STATE (DEPTH=%0d):", DEPTH);
    $fdisplay(lsq_log_fd, "  STORE QUEUE STATE (DEPTH=%0d):", DEPTH);
    $display("    idx | V ps1 ps2 | rob  ps1_s ps2_s | st_addr   rs1_data   ps2_data   f3  markers");
    $fdisplay(lsq_log_fd,
              "    idx | V ps1 ps2 | rob  ps1_s ps2_s | st_addr   rs1_data   ps2_data   f3  markers");

    for (lsq_dump_idx = 0; lsq_dump_idx < DEPTH; lsq_dump_idx++) begin
      if (store_queue[lsq_dump_idx].inst_present &&
          (lsq_dump_idx == store_head_ptr) &&
          (lsq_dump_idx == store_tail_ptr)) begin
        $display("    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_head_ptr,store_tail_ptr",
                 lsq_dump_idx,
                 store_queue[lsq_dump_idx].inst_present,
                 store_queue[lsq_dump_idx].ps1_s_ready,
                 store_queue[lsq_dump_idx].ps2_s_ready,
                 store_queue[lsq_dump_idx].rob_id,
                 store_queue[lsq_dump_idx].ps1_s,
                 store_queue[lsq_dump_idx].ps2_s,
                 store_queue[lsq_dump_idx].st_addr,
                 store_queue[lsq_dump_idx].rs1_data,
                 store_queue[lsq_dump_idx].ps2_data,
                 store_queue[lsq_dump_idx].funct3);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_head_ptr,store_tail_ptr",
                  lsq_dump_idx,
                  store_queue[lsq_dump_idx].inst_present,
                  store_queue[lsq_dump_idx].ps1_s_ready,
                  store_queue[lsq_dump_idx].ps2_s_ready,
                  store_queue[lsq_dump_idx].rob_id,
                  store_queue[lsq_dump_idx].ps1_s,
                  store_queue[lsq_dump_idx].ps2_s,
                  store_queue[lsq_dump_idx].st_addr,
                  store_queue[lsq_dump_idx].rs1_data,
                  store_queue[lsq_dump_idx].ps2_data,
                  store_queue[lsq_dump_idx].funct3);
      end else if (store_queue[lsq_dump_idx].inst_present &&
                   (lsq_dump_idx == store_head_ptr)) begin
        $display("    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_head_ptr",
                 lsq_dump_idx,
                 store_queue[lsq_dump_idx].inst_present,
                 store_queue[lsq_dump_idx].ps1_s_ready,
                 store_queue[lsq_dump_idx].ps2_s_ready,
                 store_queue[lsq_dump_idx].rob_id,
                 store_queue[lsq_dump_idx].ps1_s,
                 store_queue[lsq_dump_idx].ps2_s,
                 store_queue[lsq_dump_idx].st_addr,
                 store_queue[lsq_dump_idx].rs1_data,
                 store_queue[lsq_dump_idx].ps2_data,
                 store_queue[lsq_dump_idx].funct3);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_head_ptr",
                  lsq_dump_idx,
                  store_queue[lsq_dump_idx].inst_present,
                  store_queue[lsq_dump_idx].ps1_s_ready,
                  store_queue[lsq_dump_idx].ps2_s_ready,
                  store_queue[lsq_dump_idx].rob_id,
                  store_queue[lsq_dump_idx].ps1_s,
                  store_queue[lsq_dump_idx].ps2_s,
                  store_queue[lsq_dump_idx].st_addr,
                  store_queue[lsq_dump_idx].rs1_data,
                  store_queue[lsq_dump_idx].ps2_data,
                  store_queue[lsq_dump_idx].funct3);
      end else if (store_queue[lsq_dump_idx].inst_present &&
                   (lsq_dump_idx == store_tail_ptr)) begin
        $display("    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_tail_ptr",
                 lsq_dump_idx,
                 store_queue[lsq_dump_idx].inst_present,
                 store_queue[lsq_dump_idx].ps1_s_ready,
                 store_queue[lsq_dump_idx].ps2_s_ready,
                 store_queue[lsq_dump_idx].rob_id,
                 store_queue[lsq_dump_idx].ps1_s,
                 store_queue[lsq_dump_idx].ps2_s,
                 store_queue[lsq_dump_idx].st_addr,
                 store_queue[lsq_dump_idx].rs1_data,
                 store_queue[lsq_dump_idx].ps2_data,
                 store_queue[lsq_dump_idx].funct3);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d <-store_tail_ptr",
                  lsq_dump_idx,
                  store_queue[lsq_dump_idx].inst_present,
                  store_queue[lsq_dump_idx].ps1_s_ready,
                  store_queue[lsq_dump_idx].ps2_s_ready,
                  store_queue[lsq_dump_idx].rob_id,
                  store_queue[lsq_dump_idx].ps1_s,
                  store_queue[lsq_dump_idx].ps2_s,
                  store_queue[lsq_dump_idx].st_addr,
                  store_queue[lsq_dump_idx].rs1_data,
                  store_queue[lsq_dump_idx].ps2_data,
                  store_queue[lsq_dump_idx].funct3);
      end else begin
        // normal row
        $display("    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d",
                 lsq_dump_idx,
                 store_queue[lsq_dump_idx].inst_present,
                 store_queue[lsq_dump_idx].ps1_s_ready,
                 store_queue[lsq_dump_idx].ps2_s_ready,
                 store_queue[lsq_dump_idx].rob_id,
                 store_queue[lsq_dump_idx].ps1_s,
                 store_queue[lsq_dump_idx].ps2_s,
                 store_queue[lsq_dump_idx].st_addr,
                 store_queue[lsq_dump_idx].rs1_data,
                 store_queue[lsq_dump_idx].ps2_data,
                 store_queue[lsq_dump_idx].funct3);
        $fdisplay(lsq_log_fd,
                  "    %02d  | %1b  %1b   %1b | %3d  %5d %5d | %08h %08h %08h  %1d",
                  lsq_dump_idx,
                  store_queue[lsq_dump_idx].inst_present,
                  store_queue[lsq_dump_idx].ps1_s_ready,
                  store_queue[lsq_dump_idx].ps2_s_ready,
                  store_queue[lsq_dump_idx].rob_id,
                  store_queue[lsq_dump_idx].ps1_s,
                  store_queue[lsq_dump_idx].ps2_s,
                  store_queue[lsq_dump_idx].st_addr,
                  store_queue[lsq_dump_idx].rs1_data,
                  store_queue[lsq_dump_idx].ps2_data,
                  store_queue[lsq_dump_idx].funct3);
      end

      // extra line if this slot is the forwarding source
      if (forwarding && (lsq_dump_idx == forwarding_ptr) && store_queue[lsq_dump_idx].inst_present) begin
        $display("          -> forward_src (rob_id=%0d st_addr=%08h)",
                 store_queue[lsq_dump_idx].rob_id, store_queue[lsq_dump_idx].st_addr);
        $fdisplay(lsq_log_fd,
                  "          -> forward_src (rob_id=%0d st_addr=%08h)",
                  store_queue[lsq_dump_idx].rob_id, store_queue[lsq_dump_idx].st_addr);
      end
    end
  end
end

final begin
  if (lsq_log_fd) $fclose(lsq_log_fd);
end
`endif
endmodule   
