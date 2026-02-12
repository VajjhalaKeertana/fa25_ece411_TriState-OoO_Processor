module rob 
import rv32i_types::*;
#(
    parameter INSTR_WIDTH = 32,
    parameter ARCH_ENTRY = 32,
    parameter ARCH_WIDTH = $clog2(ARCH_ENTRY),
    parameter PRF_ENTRY = 64,
    parameter PRF_WIDTH = $clog2(PRF_ENTRY),
    
   // parameter integer ROB_DEPTH = 32,
    //parameter integer unsigned ROB_WIDTH = $clog2(ROB_DEPTH),
    parameter integer CHANNELS = FU_IDX_COUNT - 1
)(
    input logic clk,
    input logic rst,

    //Rename stage --> appending to ROB
    input logic [WAY-1:0]ren_en,
    input rob_input [WAY-1:0]ren_input,
    //asr output logic ren_resp,
    output logic ren_full,
    output logic [1:0] ren_status,

    //CDB channels
    input logic [CHANNELS-1:0] cdb_valid,
    input logic [ROB_ID_WIDTH-1:0] cdb_rob_id [CHANNELS-1:0],

    //Commit
    output logic [WAY-1:0] commit_valid,
    output logic [ARCH_WIDTH-1:0] commit_arch[WAY],
    output logic [PRF_WIDTH-1:0] commit_phy[WAY],

    //Tail ROB ID,
    output logic [ROB_ID_WIDTH-1:0] rob_id_tail[WAY-1:0],

    //head ROB ID
    output logic [ROB_ID_WIDTH-1:0] rob_id_head,

    //Monitor
    input logic mon_we[WAY-1:0],
    input logic [ROB_ID_WIDTH-1:0] mon_waddr[WAY-1:0],
    input monitor_t mon_wdata[WAY-1:0],
    //output logic [ROB_ID_WIDTH-1:0] commit_rob_id,
    output monitor_t commit_mon[WAY],

    input logic [31:0] mon_cdb_data [CHANNELS-WAY:0],
    input logic [31:0] monitor_rs1_rdata [CHANNELS-1:0],
    input logic [31:0] monitor_rs2_rdata [CHANNELS-1:0],
    input logic [3:0] monitor_mem_wmask,
    input logic [3:0] monitor_mem_rmask,
    input logic [31:0] monitor_mem_addr,
    input logic [31:0] monitor_mem_wdata,
    input logic [31:0] monitor_mem_load_data,

    output logic br_mispredict_flush,
    input logic [ROB_ID_WIDTH-1:0] cdb_rob_id_br,
    input logic cdb_rob_br_taken,
    input [31:0] cdb_br_pc_next,
    //output logic head_branch,
    //output logic head_branch_taken,
    output logic [31:0] br_pc_from_rob,

    //Branch flushing -> PRF
    output logic [ROB_DEPTH-1:0] prf_free_v_flush,
    output logic [PRF_WIDTH-1:0] prf_free_tag_flush [ROB_DEPTH-1:0],

    output logic [ROB_ID_WIDTH-1:0] rob_instr_count,
    output logic rob_al_full,

    output logic [HISTORY_BITS-1:0] bp_index,
    output logic br_commit_is_branch,
    output logic br_commit_taken,
    output logic [31:0] br_commit_pc,
    output logic [31:0] br_commit_target,
    input logic br_jal_flush
);

localparam logic [ROB_ID_WIDTH-1:0] LAST_IDX = ROB_DEPTH-1;
localparam ROB_FULL_THRESHOLD = ROB_DEPTH - WAY;

rob_entry_t rob[ROB_DEPTH-1:0];
monitor_t rob_mon [ROB_DEPTH-1:0];
logic flag;
logic flag_q;
logic rob_id_clear[ROB_DEPTH-1:0];

monitor_t commit_mon_q[WAY];

logic [ROB_ID_WIDTH:0] head_ptr;
logic [ROB_ID_WIDTH:0] tail_ptr;

logic mon_lui;
logic [WAY-1:0]head_ready_valid;
logic [ROB_ID_WIDTH-1:0] current_head_id;
logic [ROB_ID_WIDTH:0] head_next;
integer unsigned head_next_counter;
logic [ROB_ID_WIDTH:0] head_in_calc;
//logic [ROB_ID_WIDTH-1:0] no_of_instructions;

wire [ROB_ID_WIDTH-1:0] head_idx = head_ptr[ROB_ID_WIDTH-1:0];
wire [ROB_ID_WIDTH-1:0] tail_idx = tail_ptr[ROB_ID_WIDTH-1:0];

logic [ROB_ID_WIDTH:0] num_occupied;
logic [ROB_ID_WIDTH:0] free_slots;
logic rob_full, rob_empty;

always_comb begin
    num_occupied = tail_ptr - head_ptr;              // 0..ROB_DEPTH
    free_slots   = (ROB_ID_WIDTH+1)'(ROB_DEPTH - num_occupied);         // 0..ROB_DEPTH

    rob_empty    = (num_occupied == 0);
    rob_full     = 1'(free_slots < (ROB_ID_WIDTH+1)'('d2 * WAY));               // <--- key line
end
//wire rob_full = (head_ptr[ROB_ID_WIDTH] != tail_ptr[ROB_ID_WIDTH]) && (head_ptr[ROB_ID_WIDTH-1:0] == tail_ptr[ROB_ID_WIDTH-1:0]);
wire rob_almost_full = (head_ptr[ROB_ID_WIDTH] != tail_ptr[ROB_ID_WIDTH]) && ((head_ptr[ROB_ID_WIDTH-1:0] - ROB_ID_WIDTH'(1)) == tail_ptr[ROB_ID_WIDTH-1:0]) || (head_ptr[ROB_ID_WIDTH] == tail_ptr[ROB_ID_WIDTH]) && (head_ptr[ROB_ID_WIDTH-1:0] == 0 && tail_ptr[ROB_ID_WIDTH-1:0] == LAST_IDX);
//wire rob_empty = (head_ptr == tail_ptr);

//head_next = (head_idx == LAST_IDX) ? {~head_ptr[ROB_ID_WIDTH], {ROB_ID_WIDTH{1'b0}}} : (head_ptr + 1'b1);
//wire [ROB_ID_WIDTH:0] tail_next = (tail_idx == LAST_IDX) ? {~tail_ptr[ROB_ID_WIDTH], {ROB_ID_WIDTH{1'b0}}} : (tail_ptr + 1'b1);

always_comb begin
    head_next_counter = '0; 
    head_next = '0;
    for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
        if(head_ready_valid[sc_rob]) begin
            head_next_counter = head_next_counter + 1;
        end
    end
    if(ROB_ID_WIDTH'(head_idx + (ROB_ID_WIDTH+1)'(head_next_counter) - 1'b1) < LAST_IDX) begin
        head_next = head_ptr + (ROB_ID_WIDTH+1)'(head_next_counter);
    end else if (ROB_ID_WIDTH'(head_idx + head_next_counter - 1'b1) == LAST_IDX) begin
        head_next = {~head_ptr[ROB_ID_WIDTH], {ROB_ID_WIDTH{1'b0}}};
    end else begin
        head_in_calc = (ROB_ID_WIDTH+1)'(head_next_counter - (LAST_IDX - head_idx + 'd1));
        head_next = {~head_ptr[ROB_ID_WIDTH], head_in_calc[ROB_ID_WIDTH-1:0]};
    end
end

assign ren_full = rob_full;
assign ren_status = rob_full ? 2'b10 : (rob_empty ? 2'b01 : 2'b00);
assign rob_al_full = rob_almost_full;


// TODO ASR IMPORTANT always_ff @(posedge clk) begin
//   if (rst || (br_mispredict_flush))
//     commit_mon_q <= '0;
//   else if (head_ready_valid)
//     commit_mon_q <= rob_mon[head_idx];
// end

//assign commit_mon = head_ready_valid ? rob_mon[head_idx] : commit_mon_q;

//wire head_ready_valid =(!rob_empty && rob[head_idx].valid && rob[head_idx].ready);
//rob[head_idx + sc_rob].br_pred_valid & (rob[head_idx + sc_rob].br_pred != rob[head_idx + sc_rob].br_result)
always_comb begin
    
    for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
        head_ready_valid[sc_rob] = '0;
        commit_valid[sc_rob] = '0;
        commit_phy[sc_rob]   = '0;
        commit_mon[sc_rob]   = '0;
        commit_arch[sc_rob]  = '0;
    end
    for(integer unsigned rob_depth=0; rob_depth < ROB_DEPTH; ++rob_depth) begin
        rob_id_clear[rob_depth] = 1'b0;
    end

    current_head_id = '0;
    br_mispredict_flush = 1'b0;
    br_pc_from_rob = '0;

    if(head_ptr[ROB_ID_WIDTH] <= tail_ptr[ROB_ID_WIDTH]) begin
        for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
            if(head_ptr + (ROB_ID_WIDTH+1)'(sc_rob) < tail_ptr) begin
                current_head_id = ROB_ID_WIDTH'((head_idx + ROB_ID_WIDTH'(sc_rob)) % ROB_DEPTH);
                if(rob[current_head_id].valid && rob[current_head_id].ready) begin
                    if(rob[current_head_id].br_pred_valid && ((rob[current_head_id].br_pred != rob[current_head_id].br_result)||rob[current_head_id].br_jal_flush)) begin
                        head_ready_valid[sc_rob]      = 1'b1;
                        br_mispredict_flush           = 1'b1;
                        commit_valid[sc_rob]          = 1'b1;
                        commit_arch[sc_rob]           = rob[current_head_id].arch;
                        commit_phy[sc_rob]            = rob[current_head_id].phy;
                        commit_mon[sc_rob]            = rob_mon[current_head_id];
                        rob_id_clear[current_head_id] = 1'b1;
                        br_pc_from_rob                = rob[current_head_id].pc_next;
                        break;
                    end
                    else begin
                        head_ready_valid[sc_rob]    = 1'b1;
                        commit_valid[sc_rob]        = 1'b1;
                        commit_arch[sc_rob]         = rob[current_head_id].arch;
                        commit_phy[sc_rob]          = rob[current_head_id].phy;
                        commit_mon[sc_rob]          = rob_mon[current_head_id];
                        rob_id_clear[current_head_id] = 1'b1;
                    end
                end
                else begin
                    //commit_mon[sc_rob]          = commit_mon_q[sc_rob];
                    break;
                end
            end else begin
                break;
            end
        end     
    end else begin
        for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
            if(head_idx + sc_rob <= { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
                if(rob[head_idx + sc_rob].valid && rob[head_idx + sc_rob].ready) begin
                    if(rob[head_idx + sc_rob].br_pred_valid && ((rob[head_idx + sc_rob].br_pred != rob[head_idx + sc_rob].br_result) || rob[head_idx + sc_rob].br_jal_flush)) begin
                        head_ready_valid[sc_rob]        = 1'b1;
                        br_mispredict_flush             = 1'b1;
                        commit_valid[sc_rob]            = 1'b1;
                        commit_arch[sc_rob]             = rob[head_idx + sc_rob].arch;
                        commit_phy[sc_rob]              = rob[head_idx + sc_rob].phy;
                        commit_mon[sc_rob]              = rob_mon[head_idx + sc_rob];
                        rob_id_clear[head_idx + sc_rob] = 1'b1;
                        br_pc_from_rob                  = rob[head_idx + sc_rob].pc_next;
                        break;
                    end else begin
                        head_ready_valid[sc_rob]    = 1'b1;
                        commit_valid[sc_rob]        = 1'b1;
                        commit_arch[sc_rob]         = rob[head_idx + sc_rob].arch;
                        commit_phy[sc_rob]          = rob[head_idx + sc_rob].phy;
                        commit_mon[sc_rob]          = rob_mon[head_idx + sc_rob];
                        rob_id_clear[head_idx + sc_rob] = 1'b1;                        
                    end
                end else begin
                    //commit_mon[sc_rob]          = commit_mon_q[sc_rob];
                    break;
                end
            end else begin
                if(rob[sc_rob - (LAST_IDX - head_idx + 'd1)].valid && rob[sc_rob - (LAST_IDX - head_idx + 'd1)].ready) begin
                    if(rob[sc_rob - (LAST_IDX - head_idx + 'd1)].br_pred_valid && ((rob[sc_rob - (LAST_IDX - head_idx + 'd1)].br_pred != rob[sc_rob - (LAST_IDX - head_idx + 'd1)].br_result) || rob[sc_rob - (LAST_IDX - head_idx + 'd1)].br_jal_flush)) begin
                        head_ready_valid[sc_rob]    = 1'b1;
                        br_mispredict_flush         = 1'b1;
                        commit_valid[sc_rob]        = 1'b1;
                        commit_arch[sc_rob]         = rob[sc_rob - (LAST_IDX - head_idx + 'd1)].arch;
                        commit_phy[sc_rob]          = rob[sc_rob - (LAST_IDX - head_idx + 'd1)].phy;
                        commit_mon[sc_rob]          = rob_mon[sc_rob - (LAST_IDX - head_idx + 'd1)];
                        rob_id_clear[sc_rob - (LAST_IDX - head_idx + 'd1)] = 1'b1;
                        br_pc_from_rob                  = rob[sc_rob - (LAST_IDX - head_idx + 'd1)].pc_next;
                        break;
                    end else begin
                        head_ready_valid[sc_rob]    = 1'b1;
                        commit_valid[sc_rob]        = 1'b1;
                        commit_arch[sc_rob]         = rob[sc_rob - (LAST_IDX - head_idx + 'd1)].arch;
                        commit_phy[sc_rob]          = rob[sc_rob - (LAST_IDX - head_idx + 'd1)].phy;
                        commit_mon[sc_rob]          = rob_mon[sc_rob - (LAST_IDX - head_idx + 'd1)];
                        rob_id_clear[sc_rob - (LAST_IDX - head_idx + 'd1)] = 1'b1;
                    end
                end else begin
                    //commit_mon[sc_rob]          = commit_mon_q[sc_rob];
                    break;
                end
            end
        end  
    end
end

// assign commit_valid = head_ready_valid;
// assign commit_arch  = rob[head_idx].arch;
// assign commit_phy   = rob[head_idx].phy;

// always_comb begin
//     for(integer sc_rob=0; sc_rob < WAY; ++sc_rob) begin
//         if(sc_rob = )
//     end

// end

always_comb begin // ROB TAIL TO RENAME, FOR UPDATING THE WITH ROB ID
  rob_id_tail = '{default: '0};
    if(tail_ptr[ROB_ID_WIDTH-1:0] + WAY - 1 <= { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
        for(integer unsigned sc_rob=0; sc_rob < WAY; sc_rob++) begin
            rob_id_tail[sc_rob] = tail_ptr[ROB_ID_WIDTH-1:0] + ROB_ID_WIDTH'(sc_rob);
        end
    end else if(tail_ptr[ROB_ID_WIDTH-1:0] + WAY - 1 > { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
        for(integer unsigned sc_rob=0; sc_rob < WAY; sc_rob++) begin
            if(tail_ptr[ROB_ID_WIDTH-1:0] + sc_rob <= { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
                rob_id_tail[sc_rob] = tail_ptr[ROB_ID_WIDTH-1:0] + ROB_ID_WIDTH'(sc_rob);
            end else begin
                rob_id_tail[sc_rob] = ROB_ID_WIDTH'(sc_rob - (LAST_IDX - tail_ptr[ROB_ID_WIDTH-1:0] + 1));
            end       
        end
    end

end
//assign rob_id_tail = tail_idx;

assign rob_id_head = head_idx;
// always_comb begin
    
//     for(integer sc_rob=0; sc_rob < WAY; sc_rob++) begin
        
//         ren_resp[sc_rob] 

//     end

// end
//assign ren_resp = ren_en && ( !rob_full || head_ready_valid ); //TODO ASR


//assign commit_rob_id = head_idx;


logic [CHANNELS-1:0] cdb_hit_vec [0:ROB_DEPTH-1];

logic [ROB_ID_WIDTH-1:0] headn_idx;
assign headn_idx = head_next[ROB_ID_WIDTH-1:0]; // next after head
logic flush_wrap;
assign flush_wrap = (headn_idx > tail_idx);  // using OLD tail_idx
logic [ROB_DEPTH-1:0] flush_vec;

always_comb begin
  flush_vec = '0;
  for (integer unsigned fv = 0; fv < ROB_DEPTH; fv++) begin
    if(head_ptr != tail_ptr) begin
      if(!flush_wrap) begin
        if(((ROB_ID_WIDTH)'(fv) >= headn_idx) && ((ROB_ID_WIDTH)'(fv) < tail_idx)) begin
        if (rob[fv].valid)
          flush_vec[fv] = 1'b1;
        end
      end else begin
        if(((ROB_ID_WIDTH)'(fv) >= headn_idx) || ((ROB_ID_WIDTH)'(fv) < tail_idx)) begin
          flush_vec[fv] = 1'b1;
        end
      end
    end
    //flush_vec[fv] = (head_ptr != tail_ptr) && ((!flush_wrap && ((fv[ROB_ID_WIDTH-1:0] >= headn_idx) && (fv[ROB_ID_WIDTH-1:0] < tail_idx))) || (flush_wrap && ((fv[ROB_ID_WIDTH-1:0] >= headn_idx) || (fv[ROB_ID_WIDTH-1:0] < tail_idx))));
  end
end

assign rob_instr_count = (ROB_ID_WIDTH)'(flush_wrap ? (headn_idx-tail_idx+1) : (ROB_DEPTH-headn_idx+tail_idx+1));

genvar gi, gj;
generate
  for (gi = 0; gi < ROB_DEPTH; gi = gi + 1) begin : G_HITS_ROW
    for (gj = 0; gj < CHANNELS; gj = gj + 1) begin : G_HITS_LANE
      assign cdb_hit_vec[gi][gj] = cdb_valid[gj] && (cdb_rob_id[gj] == gi[ROB_ID_WIDTH-1:0]);
    end
  end
endgenerate

genvar pr;
wire [ROB_DEPTH-1:0] flush_en;

always_comb begin
    prf_free_v_flush = '0;
    prf_free_tag_flush = '{default: '0};
    if(br_mispredict_flush) begin
        for (integer unsigned pr = 0; pr < ROB_DEPTH; pr++) begin
            if((rob[pr].arch != '0)) begin
                //flush_en[pr] =  flush_vec[pr];
                prf_free_v_flush[pr] = flush_vec[pr];
                prf_free_tag_flush[pr] = (flush_vec[pr])? rob[pr].phy : '0;
            end
        end
    end
end

// generate
//   for (pr = 0; pr < ROB_DEPTH; pr++) begin : G_FLUSH_FREE_REG
//     assign flush_en[pr] = br_mispredict_flush & flush_vec[pr] & rob[pr].valid & (rob[pr].arch != '0);
//     always_ff @(posedge clk) begin
//       if (rst) begin
//         prf_free_v_flush[pr] <= 1'b0;
//         prf_free_tag_flush[pr] <= '0;
//       end else begin
//         prf_free_v_flush[pr] <= flush_en[pr];
//         prf_free_tag_flush[pr] <= (flush_en[pr])? rob[pr].phy : '0;
//       end
//     end
//   end
// endgenerate

generate
  for (gi = 0; gi < ROB_DEPTH; gi = gi + 1) begin
    always_ff @(posedge clk) begin
      if (rst || br_mispredict_flush) begin
        rob[gi].valid         <= 1'b0;
        rob[gi].ready         <= 1'b0;
        rob[gi].arch          <= '0;
        rob[gi].phy           <= '0;
        rob[gi].br_pred_valid <= 1'b0;
        rob[gi].br_pred       <= 1'b0;
        rob[gi].br_result     <= 1'b0;
        rob[gi].pc_next       <= 32'b0;
        rob[gi].pht_index     <= '0;
        rob[gi].pc            <= '0;
      end else begin
        if ((cdb_valid[BRANCH]) && gi[ROB_ID_WIDTH-1:0]==cdb_rob_id_br) begin
              rob[gi].pc_next <= cdb_br_pc_next;
              rob[gi].br_jal_flush <= br_jal_flush;
        end
        if (rob_id_clear[gi]) begin
          rob[gi] <= '{default: '0};
        end
        for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
            if (ren_en[sc_rob] && (ren_input[sc_rob].rob_id == gi[ROB_ID_WIDTH-1:0]) ) begin
                rob[gi].valid         <= 1'b1;
                if(ren_input[sc_rob].status)
                    rob[gi].ready     <= 1'b1;
                else 
                    rob[gi].ready     <= 1'b0;
                    rob[gi].arch          <= ren_input[sc_rob].rd_s;
                    rob[gi].phy           <= ren_input[sc_rob].pd_s;
                    rob[gi].br_pred_valid <= ren_input[sc_rob].br_pred_valid;
                    rob[gi].br_pred       <= ren_input[sc_rob].br_pred_taken;
                    rob[gi].pht_index     <= ren_input[sc_rob].pht_index;
                    rob[gi].pc            <= ren_input[sc_rob].pc;
            end
        end

        if (|cdb_hit_vec[gi]) begin
          //rob[gi].valid <= 1'b1;
          rob[gi].ready <= 1'b1;
        end
        if(|cdb_hit_vec[gi] && (gi[ROB_ID_WIDTH-1:0] == cdb_rob_id_br))
          rob[gi].br_result <= cdb_rob_br_taken;
        if(br_mispredict_flush && flush_vec[gi] ) begin
          rob[gi].valid <= 1'b0;
          rob[gi].ready <= 1'b0;
        end
      end
    end
  end
endgenerate

/*always_ff @(posedge clk) begin
  if (rst | br_mispredict_flush) begin
    flag <= 1'b0;
  end else begin
    if (rob[head_idx].valid & rob[head_idx].br_pred_valid & (rob[head_idx].br_pred != rob[head_idx].br_result)) begin
      flag <= 1'b1;
    end else begin
      flag <= 1'b0;
    end
  end
end*/

// assign head_branch = rob[head_idx].br_pred_valid;
// assign head_branch_taken = rob[head_idx].br_result;
//assign br_pc_from_rob = rob[head_idx].pc_next;


// always_ff @(posedge clk) begin
//   if(rst | br_mispredict_flush) begin
//     flag_q <= 1'b0;
//   end else begin
//     flag_q <= flag;
//   end
// end

//assign br_mispredict_flush = flag & !flag_q;

always_ff @(posedge clk) begin
    if (rst || br_mispredict_flush) begin
      head_ptr <= '0;
      tail_ptr <= '0;
    end else begin
        if (|ren_en) begin
            if(tail_ptr[ROB_ID_WIDTH-1:0] + WAY - 'd1 < { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
                tail_ptr <= tail_ptr + (ROB_ID_WIDTH+1)'(WAY);
            end else if (tail_ptr[ROB_ID_WIDTH-1:0] + WAY - 'd1 == { {(32-ROB_ID_WIDTH){1'b0}}, LAST_IDX }) begin
                tail_ptr[ROB_ID_WIDTH-1:0] <= '0;
                tail_ptr[ROB_ID_WIDTH] <= ~tail_ptr[ROB_ID_WIDTH];
            end else begin
                tail_ptr[ROB_ID_WIDTH-1:0] <= ROB_ID_WIDTH'(WAY - (LAST_IDX - tail_ptr[ROB_ID_WIDTH-1:0] + 'd1));
                tail_ptr[ROB_ID_WIDTH] <= ~tail_ptr[ROB_ID_WIDTH];
            end
            //asr tail_ptr <= tail_next;
        end
        if (|head_ready_valid) 
            head_ptr <= head_next;
    end
end

always_ff @(posedge clk) begin
  if (rst || br_mispredict_flush) begin
    rob_mon <= '{default: '0};
    mon_lui <= 1'b0;
  end else begin
    for(integer unsigned sc_rob=0; sc_rob < WAY; ++sc_rob) begin
        if (mon_we[sc_rob]) begin
            rob_mon[mon_waddr[sc_rob]].inst     <= mon_wdata[sc_rob].inst;
            rob_mon[mon_waddr[sc_rob]].rs1_addr <= mon_wdata[sc_rob].rs1_addr;
            rob_mon[mon_waddr[sc_rob]].rs2_addr <= mon_wdata[sc_rob].rs2_addr;
            //rob_mon[mon_waddr].rs1_rdata <= mon_wdata.rs1_rdata;
            //rob_mon[mon_waddr].rs2_rdata <= mon_wdata.rs2_rdata;
            rob_mon[mon_waddr[sc_rob]].rd_addr  <= mon_wdata[sc_rob].rd_addr;
            rob_mon[mon_waddr[sc_rob]].pc_rdata <= mon_wdata[sc_rob].pc_rdata;
            rob_mon[mon_waddr[sc_rob]].pc_wdata <= mon_wdata[sc_rob].pc_wdata;
            //TODO ASR else begin
                //TODO ASR rob_mon[cdb_rob_id_br[sc_rob]].pc_wdata <= cdb_br_pc_next;
            //TODO ASR end
            rob_mon[mon_waddr[sc_rob]].mem_addr  <= mon_wdata[sc_rob].mem_addr;
            rob_mon[mon_waddr[sc_rob]].mem_wdata <= mon_wdata[sc_rob].mem_wdata;
            rob_mon[mon_waddr[sc_rob]].mem_rmask <= mon_wdata[sc_rob].mem_rmask;
            rob_mon[mon_waddr[sc_rob]].mem_wmask <= mon_wdata[sc_rob].mem_wmask;
            rob_mon[mon_waddr[sc_rob]].mem_rdata <= mon_wdata[sc_rob].mem_rdata;
        // mon_lui <= mon_wdata.lui;
        end
        if(ren_input[sc_rob].status) begin
            rob_mon[mon_waddr[sc_rob]].rd_wdata <= ren_input[sc_rob].lui_wdata;
        end
    end
      if(cdb_valid[ALU]) begin
        rob_mon[cdb_rob_id[ALU]].rd_wdata  <= mon_cdb_data[ALU];
        rob_mon[cdb_rob_id[ALU]].rs1_rdata <= monitor_rs1_rdata[ALU];
        rob_mon[cdb_rob_id[ALU]].rs2_rdata <= monitor_rs2_rdata[ALU];

      end
      if(cdb_valid[ALU1]) begin
        rob_mon[cdb_rob_id[ALU1]].rd_wdata  <= mon_cdb_data[ALU1];
        rob_mon[cdb_rob_id[ALU1]].rs1_rdata <= monitor_rs1_rdata[ALU1];
        rob_mon[cdb_rob_id[ALU1]].rs2_rdata <= monitor_rs2_rdata[ALU1];

      end
      if(cdb_valid[ALU2]) begin
        rob_mon[cdb_rob_id[ALU2]].rd_wdata  <= mon_cdb_data[ALU2];
        rob_mon[cdb_rob_id[ALU2]].rs1_rdata <= monitor_rs1_rdata[ALU2];
        rob_mon[cdb_rob_id[ALU2]].rs2_rdata <= monitor_rs2_rdata[ALU2];

      end
      if(cdb_valid[MUL]) begin
        rob_mon[cdb_rob_id[MUL]].rd_wdata  <= mon_cdb_data[MUL];
        rob_mon[cdb_rob_id[MUL]].rs1_rdata <= monitor_rs1_rdata[MUL];
        rob_mon[cdb_rob_id[MUL]].rs2_rdata <= monitor_rs2_rdata[MUL];
      end
      if(cdb_valid[DIV]) begin
        rob_mon[cdb_rob_id[DIV]].rd_wdata  <= mon_cdb_data[DIV];
        rob_mon[cdb_rob_id[DIV]].rs1_rdata <= monitor_rs1_rdata[DIV];
        rob_mon[cdb_rob_id[DIV]].rs2_rdata <= monitor_rs2_rdata[DIV];
      end
      if(cdb_valid[MEM_LD]) begin
        rob_mon[cdb_rob_id[MEM_LD]].rd_wdata   <= mon_cdb_data[MEM_LD];
        rob_mon[cdb_rob_id[MEM_LD]].rs1_rdata  <= monitor_rs1_rdata[MEM_LD];
        rob_mon[cdb_rob_id[MEM_LD]].rs2_rdata  <= monitor_rs2_rdata[MEM_LD];
        rob_mon[cdb_rob_id[MEM_LD]].mem_rmask  <= monitor_mem_rmask;
        rob_mon[cdb_rob_id[MEM_LD]].mem_rdata  <= monitor_mem_load_data;
        rob_mon[cdb_rob_id[MEM_LD]].mem_addr   <= monitor_mem_addr;     
      end
      if(cdb_valid[BRANCH]) begin
        rob_mon[cdb_rob_id[BRANCH]].rd_wdata  <= mon_cdb_data[BRANCH];
        rob_mon[cdb_rob_id[BRANCH]].rs1_rdata <= monitor_rs1_rdata[BRANCH];
        rob_mon[cdb_rob_id[BRANCH]].rs2_rdata <= monitor_rs2_rdata[BRANCH];
        rob_mon[cdb_rob_id_br].pc_wdata       <= cdb_br_pc_next;
      end
      if(cdb_valid[MEM_ST]) begin
        rob_mon[cdb_rob_id[MEM_ST]].rd_wdata  <= '0;
        rob_mon[cdb_rob_id[MEM_ST]].rs1_rdata <= monitor_rs1_rdata[MEM_ST];
        rob_mon[cdb_rob_id[MEM_ST]].rs2_rdata <= monitor_rs2_rdata[MEM_ST];
        rob_mon[cdb_rob_id[MEM_ST]].mem_wmask <= monitor_mem_wmask;
        rob_mon[cdb_rob_id[MEM_ST]].mem_addr  <= monitor_mem_addr;
        rob_mon[cdb_rob_id[MEM_ST]].mem_wdata <= monitor_mem_wdata;
      end

    end
end

always_comb begin
  bp_index = '0;
  br_commit_is_branch = '0;
  br_commit_taken = '0;
  br_commit_pc = '0;
  br_commit_target = '0;
  if (head_ready_valid[0] && rob[head_idx].br_pred_valid) begin
    bp_index            = rob[head_idx].pht_index;
    br_commit_is_branch = 1'b1;
    br_commit_taken     = rob[head_idx].br_result;
    br_commit_pc        = rob[head_idx].pc;
    br_commit_target    = rob[head_idx].pc_next;
  end
end

endmodule
