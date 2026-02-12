module cpu
import rv32i_types::*;
#(
   parameter NUMBER_OF_PHY_REG = 64,
   parameter PRF_WIDTH = $clog2(NUMBER_OF_PHY_REG),
   parameter ARCH_WIDTH = 5,
   parameter CHANNELS = FU_IDX_COUNT - 1
)
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);

//logic   [31:0]  ufp_addr;
//logic   [3:0]   ufp_rmask;
//logic   [3:0]   ufp_wmask;
//logic   [31:0]  imem_rdata;
logic   [31:0]  rdata_lb[WAY-1:0];
logic   [32+32+32+32+1+1+HISTORY_BITS-1:0]  iq_wrdata[WAY-1:0];
logic   [31:0]  rdata_icache[WAY-1:0];
//logic   [31:0]  ufp_wdata;
//logic           ufp_resp;
logic dcache_ready;
//for connection from arbitter to adapter
logic   [31:0]  umem_addr;
logic   [255:0] umem_rdata;
logic   [3:0]   umem_rmask;
logic   [3:0]   umem_wmask;
logic   [255:0]  umem_wdata;
logic   umem_write;
logic   umem_read;
logic           umem_resp;
logic        icache_resp;

logic   [31:0]  dfp_addr;
logic           dfp_read;
logic           dfp_write;
logic   [255:0] dfp_rdata;
logic   [255:0] dfp_wdata;
logic           dfp_resp;

logic   [31:0]  imem_addr;
logic  [3:0]    imem_rmask;
//logic           imem_resp;

logic [255:0]     hit_cacheline;
logic [26:0]      hit_tag;

logic [32+32+32+32+1+1+HISTORY_BITS-1:0] instruction[WAY-1:0];
logic iq_resp,iq_pop;
// logic linebuffer_hit;
logic [31:0] id_inst;
logic [1:0] iq_status;
logic [31:0] pc[WAY-1:0], pc_next[WAY-1:0];

logic bmem_ready_signal;
logic [31:0] bmem_raddr_signal;

//ARF, PRF, RAT. RRAT and Free List related connections
//RRAT signals
logic [PRF_WIDTH-1:0] rrat_prev_phy;
logic rrat_commit_en;
logic [ARCH_WIDTH-1:0] rrat_commit_arch;
logic [PRF_WIDTH-1:0] rrat_commit_phy; //Coming from ROB
logic rrat_rd_valid;

logic [31:0] idfp_addr;
logic [255:0] idfp_rdata;
logic idfp_resp;
logic idfp_read;

logic [255:0] ufp_rdata;
logic ufp_read;

//monitor signals 
logic [3:0] monitor_from_cdb_mem_rmask;
logic [3:0] monitor_from_cdb_mem_wmask;
logic [31:0] monitor_from_cdb_mem_addr;
logic [31:0] monitor_from_cdb_mem_wdata;
//data cache to the arbitter connections
logic [31:0] ddfp_addr;
logic [255:0] ddfp_rdata;
logic ddfp_write;
logic [255:0] ddfp_wdata;
logic ddfp_read;
logic ddfp_resp;

//Free List to rename stage connection
logic [PRF_WIDTH-1:0] pd_s[WAY-1:0];
logic free_list_resp;
logic free_list_stall;
logic [WAY-1:0]rename_en;
logic rs1_arf_rat_rd[WAY-1:0];
logic rs2_arf_rat_rd[WAY-1:0];
logic [1:0] free_list_status;

//arc RAT signals 
logic rat_rd_en;
logic [ARCH_WIDTH-1:0] rs1_s[WAY-1:0];
logic [ARCH_WIDTH-1:0] rs2_s[WAY-1:0];
logic [PRF_WIDTH-1:0] ps1_s[WAY-1:0];
logic [PRF_WIDTH-1:0] ps2_s[WAY-1:0];
logic [ARCH_WIDTH-1:0] rd_s[WAY-1:0];
logic [ARCH_ENTRY-1:0][PRF_WIDTH-1:0] rrat;

//PRF signalsmem_inst_rename
logic  prf_write_en[CHANNELS:0];
logic  [PRF_WIDTH-1:0] prf_addr[CHANNELS:0];
logic  [31:0] prf_data_update [CHANNELS:0];

logic prf_rd_en[CHANNELS-WAY:0];
logic  [PRF_WIDTH-1:0] prf_pr1s[CHANNELS-WAY:0];
logic  [PRF_WIDTH-1:0] prf_pr2s[CHANNELS-WAY:0];
logic [31:0] prf_pr1_rdata[CHANNELS-WAY:0];
logic [31:0] prf_pr2_rdata[CHANNELS-WAY:0];

logic [NUMBER_OF_PHY_REG-1:0] prf_valid_array;

//load store unit 

mem_ld_cdb_t ld_unit_to_cdb;
logic store_done;
logic lsq_full;

//memory signals to data cache
logic   [31:0]  lsq_dmem_addr;
logic   [3:0]   lsq_dmem_rmask;
logic   [3:0]   lsq_dmem_wmask;
logic   [31:0]  lsq_dmem_rdata;
logic   [31:0]  lsq_dmem_wdata;
logic           lsq_mem_resp;

//ROB signals
logic [WAY-1:0]rob_update_en;
//logic rob_update_resp;
logic [WAY-1:0]commit_valid;
logic [ARCH_WIDTH-1:0] commit_arch[WAY];
logic [PRF_WIDTH-1:0] commit_phy[WAY];
logic [31:0] cdb_mon_rs1_data[CHANNELS-1:0];
logic [31:0] cdb_mon_rs2_data[CHANNELS-1:0];
//Retired to Free list
logic [PRF_WIDTH-1:0] free_list_update_reg[WAY];

//stall signals
//logic           global_stall;
logic [1:0] arbiter_busy;
logic[31:0] new_phy_count;
logic[31:0] new_phy_count_relative[WAY-1:0];

//stage registers
if_id_t  if_id_reg,  if_id_reg_next;
id_rename_nd_dispatch_t     id_rename_nd_dispatch_next[WAY-1:0], id_rename_nd_dispatch_reg[WAY-1:0];
res_station_cols_s issue_next[WAY];
res_station_alu_out_s rs_to_ex_alu, alu_to_cdb;
res_station_alu_out_s rs_to_ex_alu1, alu1_to_cdb;
res_station_alu_out_s rs_to_ex_alu2, alu2_to_cdb;
res_station_mul_out_s rs_to_ex_mul, mul_to_cdb;
res_station_div_out_s rs_to_ex_div, div_to_cdb;
res_station_br_out_s rs_to_ex_br, br_to_cdb;
cdb_out_signal_s cdb_to_rs;
mem_ld_st_unit mem_inst_rename[WAY-1:0];

//asr monitor_t monitor_decode ;
logic mon_we_rnm[WAY-1:0]; // signals from rename to the rob inside which they connect to monitor
logic [ROB_ID_WIDTH-1:0] mon_waddr_rnm[WAY-1:0]; // signals from rename to the rob inside which they connect to monitor
monitor_t mon_wdata_rnm[WAY-1:0]; // signals from rename to the rob inside which they connect to monitor
//logic mon_we_to_rob;
logic [ROB_ID_WIDTH-1:0] mon_waddr_to_rob;
//monitor_t mon_wdata_to_rob;
monitor_t commit_mon[WAY];
//logic [ROB_ID_WIDTH-1:0] commit_rob_id;

//rob
rob_input [WAY-1:0]rob_tail;
logic rob_full;
logic rob_almost_full;
logic[ROB_ID_WIDTH -1: 0] rob_id[WAY-1:0]; 
logic[ROB_ID_WIDTH -1: 0] head_rob_id;
logic [31:0] monitor_mem_load_data;

logic [CHANNELS-1:0]rob_valid_cdb;
logic [ROB_ID_WIDTH - 1: 0] rob_id_cdb[CHANNELS-1:0];
//asr logic [ARCH_WIDTH-1:0] rob_arch1[WAY], rob_arch2[WAY];
//asr logic [PRF_WIDTH-1:0] prf_phy1[WAY], prf_phy2[WAY];
//asr logic [31:0] prf_phy1_data, prf_phy2_data;
logic [31:0] mon_rd_wdata_imm;
logic br_mispredict_flush;
logic [ROB_DEPTH-1:0] prf_free_v_flush;
logic [PRF_WIDTH-1:0] prf_free_tag_flush [ROB_DEPTH-1:0];
logic [ROB_ID_WIDTH - 1: 0] branch_taken_rob_id;
logic [31:0] br_pc_from_rob;
logic [31:0] cdb_br_pc_next;
logic icache_ready;

logic [31:0] rob_branch_target_pc_hold;
logic rob_branch_valid_hold;
logic cache_stall_next;
logic cache_stall;

//logic head_branch;
logic branch_taken;
//logic head_branch_taken;
logic lsq_access_complete;
logic reservation_station_full;
logic [ROB_ID_WIDTH-1:0] rob_instr_count;
logic umem_resp_imm;
logic free_list_empty;

//supescalar
logic branch_at_odd_word;
logic branch_at_odd_word_trig;
logic [31:0] pc_id[WAY-1:0];
logic [31:0] pc_next_id[WAY-1:0];
logic [31:0] iq_rdata_id[WAY-1:0];
logic [31:0] commit_count;
logic [31:0] commit_count_relative[WAY];
logic [WAY-1:0] commit_phy_reg_valid;

logic pc_valid_bp;
logic pred_valid;
logic pred_taken;
logic [HISTORY_BITS-1:0] pred_index;
logic c_resolve_valid [WAY-1:0];
logic c_is_branch [WAY-1:0];
logic c_taken [WAY-1:0];
logic [HISTORY_BITS-1:0] c_index [WAY-1:0];

logic bp_resolve_valid;
logic bp_is_branch;
logic bp_taken;
logic [HISTORY_BITS-1:0] bp_index;
logic br_commit_is_branch;
logic br_commit_taken;
logic [31:0] br_commit_pc;
logic [31:0] br_commit_target;

logic btb_hit;
logic [31:0] btb_target;
logic [31:0] pc_fetch_next [WAY-1:0];
logic [31:0] base_next;
logic pc_valid_resp;
integer unsigned index_pc;
integer unsigned index_pc_reg;

logic predict0, predict1;

logic br_pred_valid [WAY-1:0];
logic br_pred_taken [WAY-1:0];
logic [31:0] br_pred_target [WAY-1:0];
logic [HISTORY_BITS-1:0] br_pred_index [WAY-1:0];
logic br_jal_flush;
logic lui_valid[WAY-1:0];
//logic [PRF_WIDTH-1:0] lui_reg_add[WAY-1:0];
logic [31:0]  prefetch_addr;
logic [255:0] prefetch_rdata;
logic         prefetch_resp;
logic [31:0] incoming_prefetch_addr;

always_ff @( posedge clk ) begin
    if(rst) begin
        rob_branch_target_pc_hold <= '0;
        rob_branch_valid_hold <= 1'b0;
    end else if(br_mispredict_flush && !cache_stall_next) begin
        rob_branch_target_pc_hold <= br_pc_from_rob;
        rob_branch_valid_hold <= 1'b1;
    end else if(cache_stall_next) begin
        rob_branch_valid_hold <= 1'b0;
    end
end
assign cache_stall_next = icache_ready && dcache_ready;

always_ff @( posedge clk ) begin
    if(rst) begin
        cache_stall <= '0;

    end else begin
        cache_stall <= cache_stall_next;
    end
end

//assign imem_rdata = linebuffer_hit ? rdata_lb : rdata_icache;
//assign pc_next = (iq_status == 2'b10)? pc : pc + 4;
// assign pc_next = pc + 32'd4;
assign pc_valid_bp = icache_resp && !br_mispredict_flush && !rob_branch_valid_hold;

// always_comb begin
//     for(integer iq_way = 0; iq_way < WAY; ++iq_way) begin
//         if(iq_way == 'd1) begin
//             if (btb_hit)
//                 iq_wrdata[iq_way] = {pred_valid, pred_taken, btb_target, pred_index, rdata_lb[iq_way], pc[iq_way], btb_target + 32'd4};
//             else
//                 iq_wrdata[iq_way] = {pred_valid, pred_taken, btb_target, pred_index, rdata_lb[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};    
//         end else begin 
//             if (btb_hit)
//                 iq_wrdata[iq_way] = {1'b0, 1'b0, 32'b0, {HISTORY_BITS{1'b0}}, rdata_lb[iq_way], pc[iq_way], btb_target};
//             else
//                 iq_wrdata[iq_way] = {1'b0, 1'b0, 32'b0, {HISTORY_BITS{1'b0}}, rdata_lb[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};
//         end
//     end
// end


// always_comb begin
//     for (integer iq_way = 0; iq_way < WAY; ++iq_way) begin
//         if (iq_way == 'd1) begin
//             // SLOT 1: this is the only place we attach branch prediction info
//             if (btb_hit && pred_valid && pred_taken) begin
//                 // taken prediction
//                 iq_wrdata[iq_way] =
//                     { pred_valid, pred_taken,
//                       btb_target, pred_index,
//                       rdata_lb[iq_way], pc[iq_way],
//                       btb_target // or btb_target, depending on what Spike expects as pc_wdata for taken branches
//                     };
//             end else begin
//                 // no BTB hit or predicted not taken => sequential
//                 iq_wrdata[iq_way] =
//                     { pred_valid, pred_taken,
//                       btb_target, pred_index,   // you may even zero these when no hit, your choice
//                       rdata_lb[iq_way], pc[iq_way],
//                       pc[iq_way] + 32'd4   // normal path
//                     };
//             end
//         end else begin
//             // SLOT 0: never use BTB target as pc_next
//             iq_wrdata[iq_way] =
//                 { 1'b0, 1'b0,
//                   32'b0, {HISTORY_BITS{1'b0}},
//                   rdata_lb[iq_way], pc[iq_way],
//                   pc_next[iq_way] - 32'd4       // always sequential
//                 };
//         end
//     end
// end


always_comb begin 
    branch_at_odd_word_trig = '0;
    predict0 = pred_valid && btb_hit && pred_taken;
    index_pc = '0;
    if(br_mispredict_flush) begin
        index_pc = br_pc_from_rob[4:2]%WAY;
        if(br_pc_from_rob[4:2]%2 == 0) begin
            pc_next[0] = br_pc_from_rob;
            pc_next[1] = br_pc_from_rob + 32'd4; 
        end else begin
            pc_next[0] = br_pc_from_rob - 32'd4;
            pc_next[1] = br_pc_from_rob;
            branch_at_odd_word_trig = 1'b1;
        end
    end
    else if(rob_branch_valid_hold) begin
        index_pc = rob_branch_target_pc_hold[4:2]%WAY;
        if(rob_branch_target_pc_hold[4:2]%2 == 0) begin
            pc_next[0] = rob_branch_target_pc_hold;
            pc_next[1] = rob_branch_target_pc_hold + 32'd4;
        end else begin
            pc_next[0] = rob_branch_target_pc_hold - 32'd4;
            pc_next[1] = rob_branch_target_pc_hold;
            //branch_at_odd_word = 1'b1;
        end
    end

    else begin
        if (predict0) begin
            //pc_next[0] = btb_target;
            //pc_next[0] = btb_target;
            index_pc = btb_target[4:2]%WAY;
            for(integer unsigned sc=0; sc < WAY; ++sc) begin
                if(sc < index_pc) begin
                    pc_next[sc] = btb_target - (index_pc - sc)*32'd4;
                end else if(sc == index_pc) begin
                     pc_next[sc] = btb_target;
                end else begin
                    pc_next[sc] = btb_target + (sc-index_pc)*32'd4; 
                end
            end
            if(index_pc != '0) begin
                branch_at_odd_word_trig = 1'b1;
            end else begin
                branch_at_odd_word_trig = 1'b0;
            end
        end else begin
            for(integer unsigned sc=0; sc < WAY; ++sc) begin
                pc_next[sc] = pc[sc] + 32'd8;
            end
        end
    end
end


always_comb begin
    for(integer unsigned iq_way = 0; iq_way < WAY; ++iq_way) begin
        if(iq_way == WAY - 'd1) begin
            if(btb_hit)
                iq_wrdata[iq_way] = {pred_valid, pred_taken, btb_target, pred_index, rdata_icache[iq_way], pc[iq_way], btb_target};
            else
                iq_wrdata[iq_way] = {pred_valid, 1'b0, btb_target, pred_index, rdata_icache[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};    
        end else begin 
            if(btb_hit)
                iq_wrdata[iq_way] = {1'b0, 1'b0, 32'b0, {HISTORY_BITS{1'b0}}, rdata_icache[iq_way], pc[iq_way], pc[iq_way] + 32'd4};
            else 
                iq_wrdata[iq_way] = {1'b0, 1'b0, 32'b0, {HISTORY_BITS{1'b0}}, rdata_icache[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};
        end
    end
end

//assign pc_next = rob_branch_valid_hold ? rob_branch_target_pc_hold : pc + 32'd4;
// assign global_stall = !linebuffer_hit;

//assign mon_waddr_to_rob = mon_waddr_rnm; //TODO ASR why is this going from outside? why not direct connection?
//assign mon_wdata_to_rob = mon_wdata_rnm; //TODO ASR
//assign mon_we_to_rob = mon_we_rnm & rob_update_resp; //TODO ASR

assign bmem_ready_signal = bmem_ready;
assign bmem_raddr_signal = bmem_raddr;

assign free_list_empty = (free_list_status==2'b01)? 1'b1 : 1'b0;

//generate for (genvar sc_pc = 0; sc_pc < WAY; sc_pc++) begin : pc_way

    always_ff @(posedge clk) begin //TODO: check logic
        if (rst) begin
            // Add reset logic here
            //for(integer sc_pc= 0; sc_pc < WAY; ++sc_pc) begin
                pc[0] <= 32'haaaaa000;
                pc[1] <= 32'haaaaa004;
            //end
            for(integer unsigned sc_r_d = 0; sc_r_d < WAY; ++ sc_r_d) begin
                id_rename_nd_dispatch_reg[sc_r_d] <= '0;
            end
            branch_at_odd_word <= '0;
        end else begin
            for(integer unsigned sc_pc= 0; sc_pc < WAY; ++sc_pc) begin
                if (iq_status == 2'b10 && (!cache_stall_next && (rob_branch_valid_hold || br_mispredict_flush))) begin
                    pc[sc_pc] <= pc[sc_pc];
                // end else if (linebuffer_hit|| ((rob_branch_valid_hold || br_mispredict_flush) && cache_stall_next)) begin
                end else if ((icache_resp) || ((rob_branch_valid_hold || br_mispredict_flush) && cache_stall_next)) begin
                    pc[sc_pc] <= pc_next[sc_pc];
                    //branch_at_odd_word <= '0;
                end 
            end
            if (iq_status != 2'b01 && rob_full == 1'b0 && lsq_full == 1'b0 && reservation_station_full == 1'b0 && free_list_empty == 1'b0) begin
                for(integer unsigned sc_r_d = 0; sc_r_d < WAY; ++ sc_r_d) begin
                    id_rename_nd_dispatch_reg[sc_r_d] <= id_rename_nd_dispatch_next[sc_r_d];
                end
            end else if (!free_list_empty) begin
                for(integer unsigned sc_r_d = 0; sc_r_d < WAY; ++ sc_r_d) begin
                    id_rename_nd_dispatch_reg[sc_r_d] <= '0;
                end
            end 
            if(rob_branch_valid_hold || br_mispredict_flush) begin
                for(integer unsigned sc_r_d = 0; sc_r_d < WAY; ++ sc_r_d) begin
                    id_rename_nd_dispatch_reg[sc_r_d] <= '0;
                end
            end
            if(branch_at_odd_word_trig) begin
                branch_at_odd_word <= 1'b1;
                index_pc_reg       <= index_pc;
            // end else if (linebuffer_hit) begin
            end else if (icache_resp || br_mispredict_flush) begin
                branch_at_odd_word <= 1'b0;
                index_pc_reg       <= '0;
            end
        end
    end

//end endgenerate

if_stage if_stage_inst
(
    .pc         (pc[0]),
    .pc_next    (pc_next[0]),
    .iq_status  (iq_status),
    .imem_addr  (imem_addr),
    .imem_mask  (imem_rmask),
    .icache_resp  (icache_resp),
    .stall      (rob_branch_valid_hold || br_mispredict_flush)
);

always_comb begin
    for(integer unsigned sc_id=0; sc_id < WAY; ++sc_id) begin
        iq_rdata_id[sc_id] = instruction[sc_id][95:64];
        pc_id[sc_id]       = instruction[sc_id][63:32];
        pc_next_id[sc_id]  = instruction[sc_id][31:0];
        br_pred_valid[sc_id] = instruction[sc_id][137];
        br_pred_taken[sc_id] = instruction[sc_id][136];
        br_pred_target[sc_id] = instruction[sc_id][96+HISTORY_BITS+32-1:96+HISTORY_BITS];
        br_pred_index[sc_id] = instruction[sc_id][96+HISTORY_BITS-1:96];
    end
end

btb branch_target_buffer(
    .clk(clk),
    .rst(rst),

    .pc(pc[1]),
    .pc_valid(pc_valid_bp),
    .btb_hit(btb_hit),
    .btb_target(btb_target),

    //.c_valid(commit_valid[1]),
    .c_is_branch(br_commit_is_branch),
    .c_taken(br_commit_taken),
    .c_pc(br_commit_pc),
    .c_target(br_commit_target),

    .br_mispredict_flush(br_mispredict_flush),
    .pc_valid_resp(pc_valid_resp)
);

gshare_predictor gshare(
    .clk(clk),
    .rst(rst),

    .pc(pc[1]),
    .pc_valid(pc_valid_bp),
    .pred_valid(pred_valid),
    .pred_taken(pred_taken),
    .pred_index(pred_index),

    //.c_resolve_valid(commit_valid[1]),
    .c_is_branch(br_commit_is_branch),
    .c_taken(br_commit_taken),
    .c_index(bp_index)
);

id_stage id_stage_inst
(

    .iq_status  (iq_status),
    .iq_rdata   (iq_rdata_id),
    .iq_resp    (iq_resp),
    .iq_pop     (iq_pop),
    .pc         (pc_id),
    .pc_next    (pc_next_id),
    .id_rename_nd_dispatch_next (id_rename_nd_dispatch_next),
    //asr .monitor_decode (monitor_decode),
    .br_pred_valid (br_pred_valid),
    .br_pred_taken (br_pred_taken),
    .br_pred_target(br_pred_target),
    .br_pred_index (br_pred_index),
    .back_pressure(rob_almost_full || lsq_full || reservation_station_full || rob_full || free_list_empty)
);

rename_nd_dispatch_stage rename_nd_dispatch(
    .id_rename_nd_dispatch_reg(id_rename_nd_dispatch_reg),
    .free_list_resp(free_list_resp),
    .free_list_stall(free_list_stall),
    .pd_s(pd_s),
    .rename_en_rat_freelist(rename_en),
    .rd_s(rd_s),
    .free_list_status(free_list_status),
    .rs1_arf_rat_rd(rs1_arf_rat_rd),
    .rs2_arf_rat_rd(rs2_arf_rat_rd),
    .rs1_s(rs1_s),
    .rs2_s(rs2_s),
    .ps1_s(ps1_s),
    .ps2_s(ps2_s),
    .new_phy_count(new_phy_count),
    .new_phy_count_relative(new_phy_count_relative),
    .issue_next(issue_next),
    .rob_tail(rob_tail),
    .pd_data(prf_data_update[CHANNELS:CHANNELS - WAY + 'd1]),
    .valid(prf_write_en[CHANNELS:CHANNELS - WAY + 'd1]),
    .write_pd_addr(prf_addr[CHANNELS:CHANNELS - WAY + 'd1]),
    .rob_update_en(rob_update_en),
    .rob_id(rob_id),
    .mem_inst_to_mem_unit(mem_inst_rename),
    //.monitor_decode(monitor_decode),
    .mon_we (mon_we_rnm),
    .mon_waddr (mon_waddr_rnm),
    .mon_wdata (mon_wdata_rnm),
    .branch_mispredict(br_mispredict_flush),
    .free_list_empty(free_list_empty),
    .lui_valid(lui_valid)
);

rob The_OG_ROB(
    .clk(clk),
    .rst(rst),
    //Rename stage --> appending to ROB
    .ren_en(rob_update_en),
    //asr .ren_resp(rob_update_resp),
    .ren_full(rob_full),
    .ren_input(rob_tail),
    // output logic [1:0] ren_status

    //CDB channels
    .cdb_valid(rob_valid_cdb),
    .cdb_rob_id(rob_id_cdb),

    //Commit
    .commit_valid(commit_valid),
    .commit_arch(commit_arch),
    .commit_phy(commit_phy),

    //Tail ROB ID,
    .rob_id_tail(rob_id),

    //Head ROB ID,
    .rob_id_head(head_rob_id),

    //Monitor
    .mon_we (mon_we_rnm),
    .mon_waddr (mon_waddr_rnm),
    .mon_wdata (mon_wdata_rnm),
    //.commit_rob_id (commit_rob_id),
    .commit_mon (commit_mon),

    .mon_cdb_data (prf_data_update[CHANNELS - WAY:0]),
    .monitor_rs1_rdata(cdb_mon_rs1_data),
    .monitor_rs2_rdata(cdb_mon_rs2_data),
    .monitor_mem_rmask(monitor_from_cdb_mem_rmask),
    .monitor_mem_wmask(monitor_from_cdb_mem_wmask),
    .monitor_mem_addr(monitor_from_cdb_mem_addr),
    .monitor_mem_wdata(monitor_from_cdb_mem_wdata),

    .br_mispredict_flush(br_mispredict_flush),
    .cdb_rob_id_br(branch_taken_rob_id),
    .cdb_rob_br_taken(branch_taken),
    .cdb_br_pc_next(cdb_br_pc_next),
    .prf_free_v_flush(prf_free_v_flush),
    .prf_free_tag_flush(prf_free_tag_flush),
    //.head_branch(head_branch),
    //.head_branch_taken(head_branch_taken),
    .br_pc_from_rob(br_pc_from_rob),

    .rob_instr_count(rob_instr_count),
    .rob_al_full(rob_almost_full),
    .monitor_mem_load_data(monitor_mem_load_data),

    .bp_index(bp_index),
    .br_commit_is_branch(br_commit_is_branch),
    .br_commit_taken(br_commit_taken),
    .br_commit_pc(br_commit_pc),
    .br_commit_target(br_commit_target),
    .br_jal_flush(br_jal_flush)
);

cdb central_data_bus(
    //.clk(clk),
    //.rst(rst || br_mispredict_flush),
    .exec_arithmetic_in(alu_to_cdb),
    .exec_arithmetic1_in(alu1_to_cdb),
    .exec_arithmetic2_in(alu2_to_cdb),
    .exec_mul_in(mul_to_cdb), //TODO
    .exec_div_in(div_to_cdb), //TODO
    .ld_st_unit_in(ld_unit_to_cdb),
    .exec_br_in(br_to_cdb),
    .rob_valid(rob_valid_cdb),
    .rob_id(rob_id_cdb),
    .cdb_out(cdb_to_rs),
    .write_en(prf_write_en[CHANNELS - WAY:0]),
    .write_tag(prf_addr[CHANNELS - WAY:0]),
    .write_data(prf_data_update[CHANNELS - WAY:0]),
    .rs1_rdata(cdb_mon_rs1_data),
    .rs2_rdata(cdb_mon_rs2_data),
    .monitor_mem_rmask(monitor_from_cdb_mem_rmask),
    .monitor_mem_wmask(monitor_from_cdb_mem_wmask),
    .monitor_mem_addr(monitor_from_cdb_mem_addr),
    .monitor_mem_wdata(monitor_from_cdb_mem_wdata),
    .branch_taken(branch_taken),
    .branch_taken_rob_id(branch_taken_rob_id),
    .branch_next_pc(cdb_br_pc_next),
    .monitor_mem_load_data(monitor_mem_load_data),
    .br_jal_flush(br_jal_flush),
    .lui_valid(lui_valid),
    .lui_reg_add(prf_addr[CHANNELS:CHANNELS - WAY + 'd1])
);

reservation_station_superscaler RS_unified(
    .clk(clk),
    .rst(rst),
    .res_input(issue_next),
    .prf_valid_bus(prf_valid_array),
    .cdb_in(cdb_to_rs),
    .alu_in(rs_to_ex_alu),
    .alu1_in(rs_to_ex_alu1),
    .alu2_in(rs_to_ex_alu2),
    .mul_in(rs_to_ex_mul),
    .div_in(rs_to_ex_div),
    .br_in(rs_to_ex_br),
    .branch_taken(br_mispredict_flush),
    .station_is_full(reservation_station_full)
    // .branch_taken(1'b0)
    // .branch_taken(head_branch && head_branch_taken)
);

arith_ex_stage exec_alu(

      .ps1_s(prf_pr1s[ALU]),
      .ps2_s(prf_pr2s[ALU]),
      .ps1_data(prf_pr1_rdata[ALU]),
      .ps2_data(prf_pr2_rdata[ALU]),
      .prf_rd_en(prf_rd_en[ALU]),
      .exec_arith_rs(rs_to_ex_alu),
      .alu_cdb_out(alu_to_cdb)
);

arith_ex_stage exec_alu1(

      .ps1_s(prf_pr1s[ALU1]),
      .ps2_s(prf_pr2s[ALU1]),
      .ps1_data(prf_pr1_rdata[ALU1]),
      .ps2_data(prf_pr2_rdata[ALU1]),
      .prf_rd_en(prf_rd_en[ALU1]),
      .exec_arith_rs(rs_to_ex_alu1),
      .alu_cdb_out(alu1_to_cdb)
);

arith_ex_stage exec_alu2(

      .ps1_s(prf_pr1s[ALU2]),
      .ps2_s(prf_pr2s[ALU2]),
      .ps1_data(prf_pr1_rdata[ALU2]),
      .ps2_data(prf_pr2_rdata[ALU2]),
      .prf_rd_en(prf_rd_en[ALU2]),
      .exec_arith_rs(rs_to_ex_alu2),
      .alu_cdb_out(alu2_to_cdb)
);

multiply_wrapper exec_mul(
    .clk(clk),
    .rst(rst || br_mispredict_flush),
    .ps1_s(prf_pr1s[MUL]),
    .ps2_s(prf_pr2s[MUL]),
    .exec_mul_rs(rs_to_ex_mul),
    .ps1_data(prf_pr1_rdata[MUL]),
    .ps2_data(prf_pr2_rdata[MUL]),
    .prf_rd_en(prf_rd_en[MUL]),
    .mul_cdb_out(mul_to_cdb)
);

division_wrapper exec_div(
    .clk(clk),
    .rst(rst || br_mispredict_flush),
    .ps1_s(prf_pr1s[DIV]),
    .ps2_s(prf_pr2s[DIV]),
    .exec_div_rs(rs_to_ex_div),
    .ps1_data(prf_pr1_rdata[DIV]),
    .ps2_data(prf_pr2_rdata[DIV]),
    .prf_rd_en(prf_rd_en[DIV]),
    .div_cdb_out(div_to_cdb)
);
load_store_unit_v2 load_store_unit_inst(
    .clk(clk),
    .rst(rst),
    .mem_inst_from_rename(mem_inst_rename),
    .head_rob_id_for_st(head_rob_id),
    .mem_ld_cdb(ld_unit_to_cdb),
    .st_resp(store_done),

    .ps1_data_ld(prf_pr1_rdata[MEM_LD]),
    .ps1_data_st(prf_pr1_rdata[MEM_ST]),
    .ps2_data_st(prf_pr2_rdata[MEM_ST]),
    .prf_st_rd_en(prf_rd_en[MEM_ST]),
    .prf_ld_rd_en(prf_rd_en[MEM_LD]),
    .ps1_s_st(prf_pr1s[MEM_ST]),
    .ps1_s_ld(prf_pr1s[MEM_LD]),
    .ps2_s_st(prf_pr2s[MEM_ST]),
    .p_addr_valid(prf_valid_array),

    .dmem_addr(lsq_dmem_addr),
    .dmem_rmask(lsq_dmem_rmask),
    .dmem_wmask(lsq_dmem_wmask),
    .dmem_rdata(lsq_dmem_rdata),
    .dmem_wdata(lsq_dmem_wdata),
    .mem_resp(lsq_mem_resp),
    .lsq_access_complete(lsq_access_complete),
    .flush_load_queue((rob_branch_valid_hold || br_mispredict_flush) && cache_stall_next    ),
    .flush_hold(rob_branch_valid_hold || br_mispredict_flush),
    .lsq_full(lsq_full)

);

assign prf_pr2s[MEM_LD] = 6'b0;

branching_unit exec_br(
    .ps1_s(prf_pr1s[BRANCH]),
    .ps2_s(prf_pr2s[BRANCH]),
    .exec_br_rs(rs_to_ex_br),
    .ps1_data(prf_pr1_rdata[BRANCH]),
    .ps2_data(prf_pr2_rdata[BRANCH]),
    .prf_rd_en(prf_rd_en[BRANCH]),
    .br_cdb_out(br_to_cdb)
);

// always_comb begin
//     for(integer iq_way = 0; iq_way < WAY; ++iq_way) begin
//         // iq_wrdata[iq_way] = {rdata_lb[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};
//         iq_wrdata[iq_way] = {rdata_icache[iq_way], pc[iq_way], pc_next[iq_way] - 32'd4};
//     end

// end
circular_queue #(
    .DEPTH      (32),
    .DATA_WIDTH (32+32+32+32+1+1+HISTORY_BITS)  //Storing instruction, PC and PC next data
) iq_inst
(
    .clk        (clk),
    .rst        (rst || br_mispredict_flush),
    .iq_wrdata  (iq_wrdata),
    // .iq_push    (linebuffer_hit),
    .iq_push    (icache_resp),
    .iq_status  (iq_status),
    .iq_pop     (iq_pop),
    .iq_rdata   (instruction),
    .iq_resp    (iq_resp),
    .branch_at_odd_word(branch_at_odd_word),
    .index_pc(index_pc_reg)
);

// cache_arbiter cache_arbiter_inst
// (
//     .clk(clk),
//     .rst(rst),

//     .imem_addr(idfp_addr),
//     .imem_rdata(idfp_rdata),
//     .imem_resp(idfp_resp),
//     .iq_empty((iq_status==2'b01) ? 1'b1 : 1'b0),
//     .imem_req(idfp_read),

//     .dmem_addr(ddfp_addr),
//     .dmem_rdata(ddfp_rdata),
//     .dmem_resp(ddfp_resp),
//     .dmem_req(ddfp_read || ddfp_write),
//     .dmem_write_req(ddfp_write),
//     .dmem_wdata(ddfp_wdata),
    
//     .umem_addr(umem_addr),
//     .umem_rdata(umem_rdata),
//     .umem_read(umem_read),
//     .umem_write(umem_write),
//     .umem_wdata(umem_wdata),
//     .umem_resp(umem_resp),
//     .grant_lock(arbiter_busy)
// );

// line_buffer line_buffer_inst
// (
//     .clk            (clk),
//     .rst            (rst),
//     .ufp_addr   (imem_addr),
//     .ufp_rmask  (imem_rmask),
//     .hit_cacheline  (hit_cacheline),
//     .hit_tag        (hit_tag),
//     .ufp_rdata  (rdata_lb),
//     .ufp_resp   (icache_resp),
//     .linebuffer_hit (linebuffer_hit)
//    // .branch_at_odd_word(branch_at_odd_word)
// );

pipelined_icache icache_inst
(
    .clk            (clk),
    .rst            (rst),
    .ufp_addr   (imem_addr),
    // .ufp_rmask  (linebuffer_hit ? '0 : imem_rmask),
    .ufp_rmask  (imem_rmask),
    // .ufp_wmask  ('0),
    .ufp_rdata  (rdata_icache),
    // .ufp_wdata  ('0),
    .ufp_resp   (icache_resp),

    .dfp_addr   (idfp_addr),
    .dfp_read   (idfp_read),
    //.dfp_write  (),
    .dfp_rdata  (idfp_rdata),
    //.dfp_wdata  (),
    .dfp_resp   (idfp_resp),
    // .hit_cacheline  (hit_cacheline),
    // .hit_tag        (hit_tag),
    .icache_ready   (icache_ready),
    .prefetch_addr (prefetch_addr),
    .prefetch_rdata (prefetch_rdata),
    .prefetch_resp (prefetch_resp),
    .branch_target_addr (btb_target),
    .branch_predicted (predict0),
    .prefetch_outgoing_addr (incoming_prefetch_addr)
);

pipelined_dcache dcache_inst
(
    .clk            (clk),
    .rst            (rst),
    .ufp_addr   (lsq_dmem_addr),
    .ufp_rmask  (lsq_dmem_rmask),
    .ufp_wmask  (lsq_dmem_wmask),
    .ufp_rdata  (lsq_dmem_rdata),
    .ufp_wdata  (lsq_dmem_wdata),
    .ufp_resp   (lsq_mem_resp),

    .dfp_addr   (ddfp_addr),
    .dfp_read   (ddfp_read),
    .dfp_write  (ddfp_write),
    .dfp_rdata  (ddfp_rdata),
    .dfp_wdata  (ddfp_wdata),
    .dfp_resp   (ddfp_resp),

    .dcache_ready(dcache_ready)
    //.hit_cacheline  (hit_cacheline),
    //.hit_tag        (hit_tag)
);

// cacheline_adapter cacheline_adapter_inst
// (
//     .clk            (clk),
//     .rst            (rst),

//     .umem_addr      (umem_addr),
//     .umem_read      (umem_read),
//     .umem_write     (umem_write),
//     .umem_wdata     (umem_wdata),

//     .bmem_rdata    (bmem_rdata),
//     .bmem_rvalid   (bmem_rvalid),

//     .bmem_addr     (bmem_addr),
//     .bmem_read     (bmem_read),
//     .umem_rdata     (umem_rdata),
//     .umem_resp      (umem_resp),

//     .bmem_write    (bmem_write),
//     .bmem_wdata    (bmem_wdata)
// );

dram_wrapper dram_wrapper_inst
(
    .clk        (clk),
    .rst        (rst),
    .imem_addr  (idfp_addr),
    .imem_rdata (idfp_rdata),
    .imem_resp  (idfp_resp),
    .iq_empty   ((iq_status == 2'b01) ? 1'b1 : 1'b0),
    .imem_req   (idfp_read),
    .dmem_addr      (ddfp_addr),
    .dmem_rdata     (ddfp_rdata),
    .dmem_resp      (ddfp_resp),
    .dmem_req       (ddfp_read || ddfp_write),
    .dmem_wdata     (ddfp_wdata),
    .dmem_write_req (ddfp_write),
    .bmem_addr  (bmem_addr),
    .bmem_read  (bmem_read),
    .bmem_write (bmem_write),
    .bmem_wdata (bmem_wdata),
    .bmem_ready (bmem_ready),
    .bmem_raddr (bmem_raddr),
    .bmem_rdata (bmem_rdata),
    .bmem_rvalid(bmem_rvalid),
    .grant_lock (arbiter_busy),
    .prefetch_addr (prefetch_addr),
    .prefetch_rdata (prefetch_rdata),
    .prefetch_resp (prefetch_resp),
    .incoming_prefetcher_addr (incoming_prefetch_addr)
);

prf_table prf
(
    .clk (clk),
    .rst (rst),

    .free_en (commit_valid),
    .free_tag (free_list_update_reg),

    .read_en(prf_rd_en/*{1'b0, prf_rd_en[DIV], prf_rd_en[MUL], prf_rd_en[BRANCH], prf_rd_en[ALU]}*/),
    .pr1_s(prf_pr1s/*{7'd0, prf_pr1s[DIV], prf_pr1s[MUL], prf_pr1s[BRANCH], prf_pr1s[ALU]}*/), //TODO cdb should drive 0
    .pr2_s(prf_pr2s/*{7'd0, prf_pr2s[DIV], prf_pr2s[MUL], prf_pr2s[BRANCH], prf_pr2s[ALU]}*/), //TODO cdb should drive 0
    .pr1_data(prf_pr1_rdata),
    .pr2_data(prf_pr2_rdata),

    .valid_array (prf_valid_array),

    .write_en (prf_write_en),       
    .write_tag (prf_addr),
    .write_data (prf_data_update),

    //Monitor purpose
    //asr .prf_phy1 (prf_phy1),
    //asr .prf_phy2 (prf_phy2),
    //asr .prf_phy1_data (prf_phy1_data),
    //asr .prf_phy2_data (prf_phy2_data),

    //.br_mispredict_flush(br_mispredict_flush),
    .prf_free_v_flush(prf_free_v_flush),
    .prf_free_tag_flush(prf_free_tag_flush)
);

cq_freelist_v2 #(
    .DEPTH(64),
    .DATA_WIDTH(6),
    .FULL_AT_RESET(1))
free_list
(
    .clk (clk),
    .rst (rst),
    .iq_wrdata (free_list_update_reg),
    .iq_push (commit_valid),
    .iq_status (free_list_status),
    .iq_pop (rename_en),
    .new_phy_count(new_phy_count),
    .new_phy_count_relative(new_phy_count_relative),
    .iq_rdata (pd_s),
    .iq_resp (free_list_resp),
    .prf_free_v_flush(prf_free_v_flush),
    .prf_free_tag_flush(prf_free_tag_flush),
    .br_mispredict_flush(br_mispredict_flush),
    .commit_count(commit_count),
    .commit_count_relative(commit_count_relative),
    .commit_phy_reg_valid(commit_phy_reg_valid)
);


arf_rat_table arf_rat
(
    .clk (clk),
    .rst (rst),

    .en (rename_en),
    .rs1_arch_read(rs1_arf_rat_rd),
    .rs2_arch_read(rs2_arf_rat_rd),
    .rd_arch (rd_s),       
    .new_phy_reg (pd_s),

    //.rd_en (rat_rd_en),
    .rs_arch1 (rs1_s),
    .rs_arch2 (rs2_s),
    .rs_phy1  (ps1_s),
    .rs_phy2  (ps2_s),

    .br_mispredict_flush (br_mispredict_flush),
    .rrat (rrat),
    .commit_valid(commit_valid),
    .commit_arch(commit_arch),
    .commit_phy(commit_phy)
);

//asr  always_comb begin

//asr     for(integer sc_rrat=0; sc_rrat < WAY; ++sc_rrat) begin
//asr         rob_arch1[sc_rrat] = commit_mon[sc_rrat].rs1_addr;
//asr         rob_arch2[sc_rrat] = commit_mon[sc_rrat].rs2_addr;
//asr     end

//asr end

retired_rat_table retired_rat_table
(
    .clk (clk),
    .rst (rst),

    .en (commit_valid),
    .rd_arch (commit_arch),
    .new_phy_reg (commit_phy),

    .rd_phy (free_list_update_reg),
    .commit_count(commit_count),
    .commit_count_relative(commit_count_relative),
    .commit_phy_reg_valid(commit_phy_reg_valid),

    //ROB monitor related info: rs1_rdata and rs2_rdata
    //asr .rob_arch1 (rob_arch1),
    //asr .rob_arch2 (rob_arch2),
    //asr .prf_phy1 (prf_phy1),
    //asr .prf_phy2 (prf_phy2),

    .rrat (rrat)
);

logic [63:0] order;
integer unsigned order_number;
logic           monitor_valid[WAY];
logic   [63:0]  monitor_order[WAY];
logic   [31:0]  monitor_inst[WAY];
logic   [4:0]   monitor_rs1_addr[WAY];
logic   [4:0]   monitor_rs2_addr[WAY];
logic   [31:0]  monitor_rs1_rdata[WAY];
logic   [31:0]  monitor_rs2_rdata[WAY];
logic           monitor_regf_we[WAY];
logic   [4:0]   monitor_rd_addr[WAY];
logic   [31:0]  monitor_rd_wdata[WAY];
logic   [31:0]  monitor_pc_rdata[WAY];
logic   [31:0]  monitor_pc_wdata[WAY];
logic   [31:0]  monitor_mem_addr[WAY];
logic   [3:0]   monitor_mem_rmask[WAY];
logic   [3:0]   monitor_mem_wmask[WAY];
logic   [31:0]  monitor_mem_rdata[WAY];
logic   [31:0]  monitor_mem_wdata[WAY];

always_comb begin

    for(integer unsigned sc_mon=0; sc_mon < WAY; ++ sc_mon) begin
        monitor_valid[sc_mon]     = commit_valid[sc_mon];
        monitor_order[sc_mon]     = order + sc_mon;
        monitor_inst[sc_mon]      = commit_mon[sc_mon].inst;
        monitor_rs1_addr[sc_mon]  = commit_mon[sc_mon].rs1_addr;
        monitor_rs2_addr[sc_mon]  = commit_mon[sc_mon].rs2_addr;
        monitor_rs1_rdata[sc_mon] = commit_mon[sc_mon].rs1_rdata;//prf_phy1_data;
        monitor_rs2_rdata[sc_mon] = commit_mon[sc_mon].rs2_rdata;//prf_phy2_data;
        monitor_rd_addr[sc_mon]   = commit_mon[sc_mon].rd_addr;
        monitor_rd_wdata[sc_mon]  = commit_mon[sc_mon].rd_wdata;
        monitor_pc_rdata[sc_mon]  = commit_mon[sc_mon].pc_rdata;
        monitor_pc_wdata[sc_mon]  = commit_mon[sc_mon].pc_wdata;
        monitor_mem_addr[sc_mon]  = commit_mon[sc_mon].mem_addr; //imem_addr;
        monitor_mem_rmask[sc_mon] = commit_mon[sc_mon].mem_rmask; //imem_rmask;
        monitor_mem_wmask[sc_mon] = commit_mon[sc_mon].mem_wmask; //dmem_wmask;
        monitor_mem_rdata[sc_mon] = commit_mon[sc_mon].mem_rdata;
        monitor_mem_wdata[sc_mon] = commit_mon[sc_mon].mem_wdata;
    end 
end

always_ff @(posedge clk) begin
  if (rst) 
    order <= '0;
  else if (|commit_valid) 
        order <= order + order_number;
end   


always_comb begin
    order_number = '0;
    for(integer unsigned sc_order=0; sc_order < WAY; sc_order++) begin
        if(commit_valid[sc_order]) begin
            order_number = order_number + 1;
        end
    end
end

endmodule : cpu
