module rename_nd_dispatch_stage
import rv32i_types::*;
#(
    parameter NO_PHY_REGS = 64,
    parameter WIDTH = $clog2(NO_PHY_REGS)
    //parameter ROB_DEPTH = 32,
    //parameter ROB_ID_WIDTH = $clog2(ROB_DEPTH)
)
(
  input id_rename_nd_dispatch_t     id_rename_nd_dispatch_reg[WAY-1:0],

  input logic [WIDTH -1: 0] pd_s[WAY-1:0], //this is from the free list
  input logic [WIDTH -1: 0] ps1_s[WAY-1:0], //this is from the arf rat
  input logic [WIDTH -1: 0] ps2_s[WAY-1:0], //this is from the arf rat

  input logic free_list_resp,
  input logic [1:0] free_list_status,
  input logic [ROB_ID_WIDTH-1:0]rob_id[WAY-1:0],
  //input monitor monitor_decode,
  output logic rs1_arf_rat_rd[WAY - 1:0],
  output logic rs2_arf_rat_rd[WAY - 1:0],
  output logic [4:0] rs2_s[WAY-1:0],
  output logic [4:0] rs1_s[WAY-1:0],
  output logic [4:0] rd_s[WAY-1:0], 
  output logic [WAY-1:0] rename_en_rat_freelist,
  output logic[31:0] new_phy_count,
  output logic[31:0] new_phy_count_relative[WAY-1:0],
  output logic [31:0] pd_data[WAY - 1:0], //incase of lui instruction
  output logic valid[WAY-1:0],          //incase of lui instruction,
  output logic  [WIDTH-1:0] write_pd_addr[WAY-1:0], //incase of lui instruction,

  output res_station_cols_s issue_next[WAY],
  output rob_input [WAY-1:0]rob_tail,
  output logic free_list_stall,
  output mem_ld_st_unit  mem_inst_to_mem_unit[WAY-1:0],
  //rob outputs
  output logic [WAY-1:0]rob_update_en,
  //Monitor packet to ROB
  output monitor_t mon_wdata[WAY-1:0],
  output logic mon_we[WAY-1:0],
  output logic [ROB_ID_WIDTH-1:0] mon_waddr[WAY-1:0],
  input logic branch_mispredict,
  input logic free_list_empty,
  output logic lui_valid [WAY-1:0]

);




//rename
always_comb begin


    for(integer unsigned sc_r_d = 0; sc_r_d < WAY; ++sc_r_d) begin
        issue_next[sc_r_d]    = '0;
        rob_tail[sc_r_d]      = '0;
        mem_inst_to_mem_unit[sc_r_d] = '0;

        pd_data[sc_r_d]       = '0;
        write_pd_addr[sc_r_d] = 'x;
        valid[sc_r_d]         = 1'b0;
        rs1_arf_rat_rd[sc_r_d] = 1'b0;
        rs2_arf_rat_rd[sc_r_d] = 1'b0;
        rs1_s[sc_r_d] = 'x;
        rs2_s[sc_r_d] = 'x;
        rd_s[sc_r_d]  = '0;
        rob_update_en[sc_r_d] = 1'b0;
        mon_we[sc_r_d]    = 1'b0;
        mon_waddr[sc_r_d] = '0;
        mon_wdata[sc_r_d] = '0;
        rename_en_rat_freelist[sc_r_d] = 1'b0;
        new_phy_count_relative[sc_r_d] = '0;
        lui_valid[sc_r_d] = '0;
    end

    new_phy_count = '0;

    free_list_stall = 1'b0;

    for(integer unsigned sc_r_d = 0; sc_r_d < WAY; sc_r_d++) begin
        if(id_rename_nd_dispatch_reg[sc_r_d].id_valid ==1'b1 && !branch_mispredict && !free_list_empty) begin
            mon_we[sc_r_d] = 1'b1;
            mon_waddr[sc_r_d] = rob_id[sc_r_d];
            mon_wdata[sc_r_d].valid = 1'b0;
            mon_wdata[sc_r_d].inst = id_rename_nd_dispatch_reg[sc_r_d].inst;
            mon_wdata[sc_r_d].pc_rdata = id_rename_nd_dispatch_reg[sc_r_d].pc;
            mon_wdata[sc_r_d].pc_wdata = id_rename_nd_dispatch_reg[sc_r_d].pc_next;
            mon_wdata[sc_r_d].rs1_addr = id_rename_nd_dispatch_reg[sc_r_d].rs1_s_valid ? id_rename_nd_dispatch_reg[sc_r_d].rs1_s : 5'd0;
            mon_wdata[sc_r_d].rs2_addr = id_rename_nd_dispatch_reg[sc_r_d].rs2_s_valid ? id_rename_nd_dispatch_reg[sc_r_d].rs2_s : 5'd0;
            mon_wdata[sc_r_d].rd_addr  = id_rename_nd_dispatch_reg[sc_r_d].rd_valid ? id_rename_nd_dispatch_reg[sc_r_d].rd_s  : 5'd0;
            rob_tail[sc_r_d].rob_id = rob_id[sc_r_d];
            rob_tail[sc_r_d].pc = id_rename_nd_dispatch_reg[sc_r_d].pc;
            issue_next[sc_r_d].dispatch_to_res_valid  = 1'b1;
            rob_update_en[sc_r_d] = 1'b1;

            if(id_rename_nd_dispatch_reg[sc_r_d].rd_valid) begin  
            if(id_rename_nd_dispatch_reg[sc_r_d].rd_s == '0) begin
                issue_next[sc_r_d].pd_s = '0;
                rob_tail[sc_r_d].pd_s     = '0;
                write_pd_addr[sc_r_d]     = '0;
            end else begin
                free_list_stall = 1'b1;
                if(free_list_status != 2'b01) begin
                    new_phy_count_relative[sc_r_d] = new_phy_count;
                    rename_en_rat_freelist[sc_r_d] = 1'b1;
                    new_phy_count = new_phy_count + 1;
                    if(free_list_resp) begin
                        issue_next[sc_r_d].pd_s   = pd_s[sc_r_d];
                        rob_tail[sc_r_d].pd_s     = pd_s[sc_r_d]; //ROB tail destination register phy addr
                        write_pd_addr[sc_r_d]     = pd_s[sc_r_d];
                        free_list_stall   = 1'b0;
                    end
                end
                rd_s[sc_r_d]                = id_rename_nd_dispatch_reg[sc_r_d].rd_s;         //update ARF and RAT with the destination arch reg and phy addr
                rob_tail[sc_r_d].rd_s       = id_rename_nd_dispatch_reg[sc_r_d].rd_s;        //ROB tail destination register arch address
            end
            end  

            //non propagating, to the ARF + RAT
            if(id_rename_nd_dispatch_reg[sc_r_d].rs1_s_valid != 1'b0) begin
                if(id_rename_nd_dispatch_reg[sc_r_d].rs1_s == 5'd0) begin 
                    issue_next[sc_r_d].ps1_s = 6'd0;
                    //issue_next.ps1_v    = 1'b1;
                end
                else begin
                    rs1_arf_rat_rd[sc_r_d] = 1'b1;
                    rs1_s[sc_r_d] = id_rename_nd_dispatch_reg[sc_r_d].rs1_s;
                    issue_next[sc_r_d].ps1_s  = ps1_s[sc_r_d];
                end
            end 
            if(id_rename_nd_dispatch_reg[sc_r_d].no_rs1 == 1'b1)
                issue_next[sc_r_d].ps1_v = 1'b1;    
            
            if(id_rename_nd_dispatch_reg[sc_r_d].rs2_s_valid != 1'b0) begin
                if(id_rename_nd_dispatch_reg[sc_r_d].rs2_s == 5'd0) begin
                    issue_next[sc_r_d].ps2_s = 6'd0;
                    //issue_next.ps2_v = 1'b1; 
                end else begin
                    rs2_arf_rat_rd[sc_r_d] = 1'b1;
                    rs2_s[sc_r_d] = id_rename_nd_dispatch_reg[sc_r_d].rs2_s;
                    issue_next[sc_r_d].ps2_s  = ps2_s[sc_r_d];
                end
            end


            //propagating information
            issue_next[sc_r_d].fu_idx      = id_rename_nd_dispatch_reg[sc_r_d].fu_idx;
            issue_next[sc_r_d].imm_flag    = id_rename_nd_dispatch_reg[sc_r_d].imm_flag;
            issue_next[sc_r_d].imm_val     = id_rename_nd_dispatch_reg[sc_r_d].imms;
            issue_next[sc_r_d].funct3      = id_rename_nd_dispatch_reg[sc_r_d].funct3;
            issue_next[sc_r_d].funct7      = id_rename_nd_dispatch_reg[sc_r_d].funct7;
            issue_next[sc_r_d].rob_id      = rob_id[sc_r_d];
            issue_next[sc_r_d].pc          = id_rename_nd_dispatch_reg[sc_r_d].pc;
            issue_next[sc_r_d].rs1_s_valid = id_rename_nd_dispatch_reg[sc_r_d].rs1_s_valid;
            issue_next[sc_r_d].rs2_s_valid = id_rename_nd_dispatch_reg[sc_r_d].rs2_s_valid;
            issue_next[sc_r_d].opcode = id_rename_nd_dispatch_reg[sc_r_d].opcode;
            issue_next[sc_r_d].pc_next = id_rename_nd_dispatch_reg[sc_r_d].pc_next;

            //direct prf update
            if(id_rename_nd_dispatch_reg[sc_r_d].fu_idx == (LUI_B + sc_r_d)) begin
                rob_tail[sc_r_d].status = 1'b1;
                pd_data[sc_r_d] = id_rename_nd_dispatch_reg[sc_r_d].imms;
                rob_tail[sc_r_d].lui_wdata = id_rename_nd_dispatch_reg[sc_r_d].imms;
                valid[sc_r_d] = 1'b1;
                issue_next[sc_r_d].dispatch_to_res_valid  = 1'b0;
                lui_valid[sc_r_d] = 1'b1;
                //mon_wdata.lui = 1'b1;
            end

            if(id_rename_nd_dispatch_reg[sc_r_d].fu_idx == MEM_ST || id_rename_nd_dispatch_reg[sc_r_d].fu_idx == MEM_LD) begin
                mem_inst_to_mem_unit[sc_r_d].ps1_s  = issue_next[sc_r_d].ps1_s;
                mem_inst_to_mem_unit[sc_r_d].ps2_s  = issue_next[sc_r_d].ps2_s;
                mem_inst_to_mem_unit[sc_r_d].pd_s   = issue_next[sc_r_d].pd_s;
                mem_inst_to_mem_unit[sc_r_d].imms   = issue_next[sc_r_d].imm_val;
                mem_inst_to_mem_unit[sc_r_d].funct3 = issue_next[sc_r_d].funct3;
                mem_inst_to_mem_unit[sc_r_d].rob_id = issue_next[sc_r_d].rob_id;
                mem_inst_to_mem_unit[sc_r_d].mem_inst_valid = 1'b1;
                mem_inst_to_mem_unit[sc_r_d].pc       = issue_next[sc_r_d].pc;
                if(id_rename_nd_dispatch_reg[sc_r_d].fu_idx == MEM_ST) 
                    mem_inst_to_mem_unit[sc_r_d].load_or_store = 1'b1;
                else 
                    mem_inst_to_mem_unit[sc_r_d].load_or_store = 1'b0;
                
                issue_next[sc_r_d].dispatch_to_res_valid  = 1'b0;
            end

            if(id_rename_nd_dispatch_reg[sc_r_d].fu_idx == BRANCH) begin
                rob_tail[sc_r_d].br_pred_valid = 1'b1;
                rob_tail[sc_r_d].br_pred_taken = id_rename_nd_dispatch_reg[sc_r_d].br_pred_taken;
                rob_tail[sc_r_d].pht_index = id_rename_nd_dispatch_reg[sc_r_d].br_pred_index;
        end else begin
                rob_tail[sc_r_d].br_pred_valid = 1'b0;
                rob_tail[sc_r_d].br_pred_taken = 1'b0;
                rob_tail[sc_r_d].pht_index = '0;
            end        
        end
    end 
end

endmodule : rename_nd_dispatch_stage