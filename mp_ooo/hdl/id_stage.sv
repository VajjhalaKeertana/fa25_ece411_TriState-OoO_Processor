module id_stage
import rv32i_types::*;
(

  //asr output logic [4:0] rs1_s,
  //asr output logic [4:0] rs2_s,
  //asr input logic [31:0] rs1_v,
  //asr input logic [31:0] rs2_v,
  //asr input if_id_t      if_id_reg,
  output id_rename_nd_dispatch_t     id_rename_nd_dispatch_next[WAY-1:0],
  input logic  [1:0] iq_status,
  input logic        iq_resp,
  input logic [31:0] iq_rdata[WAY-1:0],
  output logic iq_pop,
  input logic [31:0] pc[WAY-1:0],
  input logic [31:0] pc_next[WAY-1:0],
  //asr output monitor_t monitor_decode,
  input logic back_pressure,
  input logic br_pred_valid [WAY-1:0],
  input logic br_pred_taken [WAY-1:0],
  input logic [31:0] br_pred_target [WAY-1:0],
  input logic [HISTORY_BITS-1:0] br_pred_index [WAY-1:0]
);

 logic   [2:0]   funct3[WAY-1:0];
 logic   [6:0]   funct7[WAY-1:0];
 logic   [6:0]   opcode[WAY-1:0];
 logic   [31:0]  i_imm[WAY-1:0];
 logic   [31:0]  s_imm[WAY-1:0];
 logic   [31:0]  b_imm[WAY-1:0];
 logic   [31:0]  u_imm[WAY-1:0];
 logic   [31:0]  j_imm[WAY-1:0];
 logic   [4:0]   rd_s[WAY-1:0];
 logic   [31:0]  inst[WAY-1:0];

 logic [4:0] rs1_s[WAY-1:0];
 logic [4:0] rs2_s[WAY-1:0];

 always_comb begin
        for(integer unsigned sc_id = 0; sc_id < WAY; ++sc_id) begin
            inst[sc_id] = '0;
        end
        if(iq_status != 2'b01 && back_pressure == 1'b0) begin
            iq_pop = 1'b1;
            if(iq_resp) begin
                for(integer unsigned sc_id = 0; sc_id < WAY; ++sc_id) begin
                    inst[sc_id] = iq_rdata[sc_id];
                end
            end
        end else begin
            iq_pop = 1'b0;
        end
end

always_comb begin
    for(integer unsigned sc_id=0; sc_id < WAY; ++sc_id) begin
         funct3[sc_id] = inst[sc_id][14:12];
         funct7[sc_id] = inst[sc_id][31:25];
         opcode[sc_id] = inst[sc_id][6:0];
         i_imm[sc_id]  = {{21{inst[sc_id][31]}}, inst[sc_id][30:20]};
         s_imm[sc_id]  = {{21{inst[sc_id][31]}}, inst[sc_id][30:25], inst[sc_id][11:7]};
         b_imm[sc_id]  = {{20{inst[sc_id][31]}}, inst[sc_id][7], inst[sc_id][30:25], inst[sc_id][11:8], 1'b0};
         u_imm[sc_id]  = {inst[sc_id][31:12], 12'h000};
         j_imm[sc_id]  = {{12{inst[sc_id][31]}}, inst[sc_id][19:12], inst[sc_id][20], inst[sc_id][30:21], 1'b0};
         rs1_s[sc_id]  = inst[sc_id][19:15];
         rs2_s[sc_id]  = ((inst[sc_id][6:0] == 7'b0110011)|(inst[sc_id][6:0] == 7'b0100011)|(inst[sc_id][6:0] == 7'b1100011))? inst[sc_id][24:20] : 5'd0;
         rd_s[sc_id]   = inst[sc_id][11:7];

    end
end

//  assign funct3 = inst[14:12];
//  assign funct7 = inst[31:25];
//  assign opcode = inst[6:0];
//  assign i_imm  = {{21{inst[31]}}, inst[30:20]};
//  assign s_imm  = {{21{inst[31]}}, inst[30:25], inst[11:7]};
//  assign b_imm  = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
//  assign u_imm  = {inst[31:12], 12'h000};
//  assign j_imm  = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
//  assign rs1_s  = inst[19:15];
//  assign rs2_s  = ((inst[6:0] == 7'b0110011)|(inst[6:0] == 7'b0100011)|(inst[6:0] == 7'b1100011))? inst[24:20] : 5'd0;
//  assign rd_s   = inst[11:7];



always_comb begin

    for(integer unsigned sc_id = 0; sc_id < WAY; ++sc_id) begin
        id_rename_nd_dispatch_next[sc_id]               = '0;
        id_rename_nd_dispatch_next[sc_id].rd_valid      = 1'b0;
        id_rename_nd_dispatch_next[sc_id].inst          = inst[sc_id];
        id_rename_nd_dispatch_next[sc_id].pc            = pc[sc_id];
        id_rename_nd_dispatch_next[sc_id].pc_next       = pc_next[sc_id];
        
        id_rename_nd_dispatch_next[sc_id].br_pred_valid  = br_pred_valid[sc_id];
        id_rename_nd_dispatch_next[sc_id].br_pred_taken  = br_pred_taken[sc_id];
        id_rename_nd_dispatch_next[sc_id].br_pred_target = br_pred_target[sc_id];
        id_rename_nd_dispatch_next[sc_id].br_pred_index  = br_pred_index[sc_id];

        unique case (opcode[sc_id])
            op_lui  : begin //U type instructions
                            id_rename_nd_dispatch_next[sc_id].imms        = u_imm[sc_id];
                            id_rename_nd_dispatch_next[sc_id].rd_s        = rd_s[sc_id];
                            id_rename_nd_dispatch_next[sc_id].fu_idx      = fu_idx_e'(LUI_B + sc_id);
                            id_rename_nd_dispatch_next[sc_id].rd_valid    = 1'b1;
                            id_rename_nd_dispatch_next[sc_id].id_valid    = 1'b1;
                            id_rename_nd_dispatch_next[sc_id].opcode      = op_lui;
                        end
            op_auipc: begin //U type instructions //check the implementation at execute 
                             id_rename_nd_dispatch_next[sc_id].pc          = pc[sc_id];
                             id_rename_nd_dispatch_next[sc_id].imms        = u_imm[sc_id];
                             id_rename_nd_dispatch_next[sc_id].imm_flag    = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].rd_s        = rd_s[sc_id];
                             id_rename_nd_dispatch_next[sc_id].rd_valid    = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].fu_idx      = ALU;
                             id_rename_nd_dispatch_next[sc_id].id_valid    = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].opcode      = op_auipc;
                        end
            op_jal: begin //check the implementation at execute TODO
                        //  id_rename_nd_dispatch_next[sc_id].rd_v_data      = pc + 'd4; //TODO
                             id_rename_nd_dispatch_next[sc_id].rd_s           = rd_s[sc_id];
                             id_rename_nd_dispatch_next[sc_id].rd_valid       = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].jump_valid     = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].imms           = j_imm[sc_id];
                             id_rename_nd_dispatch_next[sc_id].imm_flag       = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].fu_idx         = BRANCH; 
                             id_rename_nd_dispatch_next[sc_id].opcode         = op_jal;
                             id_rename_nd_dispatch_next[sc_id].id_valid       = 1'b1;

                        end
            op_jalr: begin //check the implementation at execute TODO

                             id_rename_nd_dispatch_next[sc_id].rd_s           = rd_s[sc_id];
                             id_rename_nd_dispatch_next[sc_id].rd_valid       = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].rs1_s          = rs1_s[sc_id];
                             id_rename_nd_dispatch_next[sc_id].rs1_s_valid    = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].jump_valid     = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].imms           = i_imm[sc_id];
                             id_rename_nd_dispatch_next[sc_id].imm_flag       = 1'b1;
                             id_rename_nd_dispatch_next[sc_id].fu_idx         = BRANCH;
                             id_rename_nd_dispatch_next[sc_id].opcode         = op_jalr;
                             id_rename_nd_dispatch_next[sc_id].id_valid       = 1'b1;
                  end
            op_br: begin
                        
                         id_rename_nd_dispatch_next[sc_id].funct3          = funct3[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s           = rs1_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs2_s           = rs2_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s_valid     = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rs2_s_valid     = 1'b1;                
                         id_rename_nd_dispatch_next[sc_id].br_valid        = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].imms            = b_imm[sc_id];
                         id_rename_nd_dispatch_next[sc_id].imm_flag        = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].fu_idx          = BRANCH;
                         id_rename_nd_dispatch_next[sc_id].opcode          = op_br;
                         id_rename_nd_dispatch_next[sc_id].id_valid        = 1'b1;
                  end
            op_load: begin //I type instructions
                         id_rename_nd_dispatch_next[sc_id].mem_stage_valid = 1'd1;
                         id_rename_nd_dispatch_next[sc_id].rs1_s           = rs1_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s_valid     = 1'b1;             
                         id_rename_nd_dispatch_next[sc_id].imms            = i_imm[sc_id];
                         id_rename_nd_dispatch_next[sc_id].imm_flag        = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rd_s            = rd_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rd_valid        = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].funct3          = funct3[sc_id];
                         id_rename_nd_dispatch_next[sc_id].fu_idx          = MEM_LD;
                         id_rename_nd_dispatch_next[sc_id].id_valid        = 1'b1;

                        end
            op_store: begin //S type instruction
                         id_rename_nd_dispatch_next[sc_id].rs1_s           = rs1_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs2_s           = rs2_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s_valid     = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rs2_s_valid     = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].imms            = s_imm[sc_id];
                         id_rename_nd_dispatch_next[sc_id].imm_flag        = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].funct3          = funct3[sc_id];
                         id_rename_nd_dispatch_next[sc_id].fu_idx          = MEM_ST;
                         id_rename_nd_dispatch_next[sc_id].id_valid        = 1'b1;


                        end
            op_imm: begin //I type instruction 

                         id_rename_nd_dispatch_next[sc_id].imms                      = i_imm[sc_id];
                         id_rename_nd_dispatch_next[sc_id].imm_flag                  = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].funct3                    = funct3[sc_id];
                        if(funct3[sc_id] == 3'd5)  id_rename_nd_dispatch_next[sc_id].funct7 = funct7[sc_id];
                        else  id_rename_nd_dispatch_next[sc_id].funct7               = 7'd0;
                         id_rename_nd_dispatch_next[sc_id].rd_s                      = rd_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rd_valid                  = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rs1_s                     = rs1_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s_valid               = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].fu_idx                    = ALU;
                         id_rename_nd_dispatch_next[sc_id].id_valid                  = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].opcode                    = op_imm;
                        end
            op_reg: begin //R type instruction

                         id_rename_nd_dispatch_next[sc_id].funct3                    = funct3[sc_id];
                         id_rename_nd_dispatch_next[sc_id].funct7                    = funct7[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rd_s                      = rd_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s                     = rs1_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs2_s                     = rs2_s[sc_id];
                         id_rename_nd_dispatch_next[sc_id].rs1_s_valid               = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rs2_s_valid               = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].rd_valid                  = 1'b1;
                        if(funct7[sc_id][0] == 1'b1) begin
                            unique casez (funct3[sc_id])
                                3'b0??:  id_rename_nd_dispatch_next[sc_id].fu_idx       = MUL;
                                3'b1??:  id_rename_nd_dispatch_next[sc_id].fu_idx       = DIV;
                            endcase
                        end else begin
                             id_rename_nd_dispatch_next[sc_id].fu_idx                 = ALU;
                        end
                         id_rename_nd_dispatch_next[sc_id].id_valid                  = 1'b1;
                         id_rename_nd_dispatch_next[sc_id].opcode                    = op_reg;
                    end
            default   :  id_rename_nd_dispatch_next[sc_id] = '0;
        endcase
    end
end

/* asr
always_comb begin
    monitor_decode.valid        = id_rename_nd_dispatch_next.id_valid;
    monitor_decode.inst         = inst;
    monitor_decode.rs1_addr     = id_rename_nd_dispatch_next.rs1_s_valid ? id_rename_nd_dispatch_next.rs1_s : '0;
    monitor_decode.rs2_addr     = id_rename_nd_dispatch_next.rs2_s_valid ? id_rename_nd_dispatch_next.rs2_s : '0;
    monitor_decode.rs1_rdata    = '0;
    monitor_decode.rs2_rdata    = '0;
    monitor_decode.rd_addr      = id_rename_nd_dispatch_next.rd_valid ? id_rename_nd_dispatch_next.rd_s : '0;
    monitor_decode.rd_wdata     = '0;
    monitor_decode.pc_rdata     = id_rename_nd_dispatch_next.pc;
    monitor_decode.pc_wdata     = id_rename_nd_dispatch_next.pc_next;
    monitor_decode.mem_addr     = '0;
    monitor_decode.mem_wmask    = '0;
    monitor_decode.mem_rdata    = '0;
    monitor_decode.mem_wdata    = '0;
end
*/

endmodule : id_stage
