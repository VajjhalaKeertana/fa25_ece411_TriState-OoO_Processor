module reservation_station_superscaler
import rv32i_types::*;
#(
    parameter integer unsigned DEPTH = 32,
    parameter PHY_REG_COUNT = 64
)
(
    input logic clk,
    input logic rst,
    input res_station_cols_s res_input [WAY], 
    input logic [PHY_REG_COUNT-1:0] prf_valid_bus,
    input cdb_out_signal_s cdb_in,
    input logic branch_taken,
    
    output logic station_is_full,
    output res_station_alu_out_s alu_in,
    output res_station_alu_out_s alu1_in,
    output res_station_alu_out_s alu2_in,
    output res_station_mul_out_s mul_in,
    output res_station_div_out_s div_in,
    output res_station_br_out_s br_in
);
    logic res_V [0:DEPTH-1];
    logic res_ps1_v [0:DEPTH-1];
    logic res_ps2_v [0:DEPTH-1];
    logic [$clog2(PHY_REG_COUNT)-1:0] res_ps1_s [0:DEPTH-1];
    logic [$clog2(PHY_REG_COUNT)-1:0] res_ps2_s [0:DEPTH-1];
    logic [$clog2(PHY_REG_COUNT)-1:0] res_pd_s [0:DEPTH-1];
    logic [$clog2(FU_IDX_COUNT)-1:0] res_fu_idx [0:DEPTH-1];
    logic [ROB_ID_WIDTH-1:0] res_rob_id [0:DEPTH-1];
    logic [31+1:0] res_imm [0:DEPTH-1];
    logic [2:0] res_funct3 [0:DEPTH-1];
    logic [6:0] res_funct7 [0:DEPTH-1];
    rv32i_opcode res_opcode [0:DEPTH-1];
    logic [31:0] res_pc [0:DEPTH-1];
    logic [31:0] res_pc_next [0:DEPTH-1];
    logic res_rs1_s_valid [0:DEPTH-1];
    logic res_rs2_s_valid [0:DEPTH-1];

    logic next_res_V [0:DEPTH-1];
    logic next_res_ps1_v [0:DEPTH-1];
    logic next_res_ps2_v [0:DEPTH-1];
    logic [DEPTH-1:0] entry_we;

    logic ready_for_fu[0:FU_IDX_COUNT-1];
    logic [$clog2(DEPTH)-1:0] ready_for_fu_idx[0:FU_IDX_COUNT-1];

    logic [$clog2(DEPTH):0] free_count;
    logic [$clog2(DEPTH)-1:0] free_slot_indices [0:WAY-1];
    logic [$clog2(WAY):0] slots_found;

    always_comb begin
        free_count = '0;
        slots_found = '0;
        for (integer unsigned w = 0; w < WAY; w++) begin
            free_slot_indices[w] = '0; 
        end

        for (integer unsigned i = 0; i < DEPTH; i++) begin
            if (res_V[i] == 1'b0) begin
                free_count = free_count + 1'b1;
                if(slots_found < $bits(slots_found)'(WAY)) begin
                    free_slot_indices[slots_found] = $clog2(DEPTH)'(i);
                    slots_found = slots_found + 1'b1;
                end
            end
        end

        if (free_count <= 6'(2*(WAY) - 1'b1)) begin
            station_is_full = 1'b1;
        end else begin
            station_is_full = 1'b0;
        end
    end

    always_comb begin
        entry_we = '0;
        for(integer unsigned i=0; i<DEPTH; i++) begin
            next_res_V[i] = res_V[i];
            next_res_ps1_v[i] = res_ps1_v[i];
            next_res_ps2_v[i] = res_ps2_v[i];
        end
        for(integer unsigned i=0; i < DEPTH; i++) begin
            if(res_V[i]) begin
                if(!res_ps1_v[i] && cdb_in.cdb_valid[res_ps1_s[i]]) begin
                    next_res_ps1_v[i] = 1'b1;
                    entry_we[i] = 1'b1;
                end
                if(!res_ps2_v[i] && cdb_in.cdb_valid[res_ps2_s[i]]) begin
                    next_res_ps2_v[i] = 1'b1;
                    entry_we[i] = 1'b1;
                end
            end
        end

        if (free_count >= $bits(free_count)'(WAY)) begin
            for (integer unsigned w = 0; w < WAY; w++) begin
                if (res_input[w].dispatch_to_res_valid) begin
                    logic [$clog2(DEPTH)-1:0] idx;
                    idx = free_slot_indices[w];
                    entry_we[idx] = 1'b1;
                    next_res_V[idx] = 1'b1;
                    if (res_input[w].ps1_v) begin
                         next_res_ps1_v[idx] = 1'b1; 
                    end else begin
                         next_res_ps1_v[idx] = prf_valid_bus[res_input[w].ps1_s] | cdb_in.cdb_valid[res_input[w].ps1_s];
                    end
                    if(res_input[w].opcode != op_br) begin
                        if(res_input[w].imm_flag) next_res_ps2_v[idx] = 1'b1;
                        else next_res_ps2_v[idx] = prf_valid_bus[res_input[w].ps2_s] | cdb_in.cdb_valid[res_input[w].ps2_s];
                    end else begin
                        next_res_ps2_v[idx] = prf_valid_bus[res_input[w].ps2_s] | cdb_in.cdb_valid[res_input[w].ps2_s];
                    end
                end
            end
        end

        for(integer unsigned k=0; k<FU_IDX_COUNT; k++) begin
            ready_for_fu[k] = 1'b0;
            ready_for_fu_idx[k] = '0;
        end

        for(integer unsigned i=0; i<DEPTH; i++) begin
            if(res_V[i] && (next_res_ps1_v[i]) && (next_res_ps2_v[i])) begin
                if (res_fu_idx[i] == 4'(ALU)) begin
                    if(!ready_for_fu[ALU]) begin
                        ready_for_fu[ALU] = 1'b1;
                        ready_for_fu_idx[ALU] = $clog2(DEPTH)'(i);
                        next_res_V[i] = 1'b0;
                        entry_we[i] = 1'b1; 
                    end 
                    else if(!ready_for_fu[ALU1]) begin
                        ready_for_fu[ALU1] = 1'b1;
                        ready_for_fu_idx[ALU1] = $clog2(DEPTH)'(i);
                        next_res_V[i] = 1'b0;
                        entry_we[i] = 1'b1;
                    end 
                    else if(!ready_for_fu[ALU2]) begin
                        ready_for_fu[ALU2] = 1'b1;
                        ready_for_fu_idx[ALU2] = $clog2(DEPTH)'(i);
                        next_res_V[i] = 1'b0;
                        entry_we[i] = 1'b1;
                    end
                end 
                else begin
                    if(!ready_for_fu[res_fu_idx[i]]) begin
                        ready_for_fu[res_fu_idx[i]] = 1'b1;
                        ready_for_fu_idx[res_fu_idx[i]] = $clog2(DEPTH)'(i);
                        next_res_V[i] = 1'b0;
                        entry_we[i] = 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if(rst || branch_taken) begin
            alu_in <= '0;
            alu1_in <= '0;
            alu2_in <= '0;
            mul_in <= '0;
            div_in <= '0;
            br_in  <= '0;
        end else begin
            alu_in.alu_output_valid <= 1'b0;
            alu1_in.alu_output_valid <= 1'b0;
            alu2_in.alu_output_valid <= 1'b0;
            mul_in.mul_output_valid <= 1'b0;
            div_in.div_output_valid <= 1'b0;
            br_in.br_output_valid <= 1'b0;

            if(ready_for_fu[ALU]) begin
                alu_in.pr1_s <= res_ps1_s[ready_for_fu_idx[ALU]];
                alu_in.pr2_s <= res_ps2_s[ready_for_fu_idx[ALU]];
                alu_in.prd_s <= res_pd_s[ready_for_fu_idx[ALU]];
                alu_in.imm_val <= res_imm[ready_for_fu_idx[ALU]];
                alu_in.funct3 <= res_funct3[ready_for_fu_idx[ALU]];
                alu_in.funct7 <= res_funct7[ready_for_fu_idx[ALU]];
                alu_in.rob_id <= res_rob_id[ready_for_fu_idx[ALU]];
                alu_in.opcode <= res_opcode[ready_for_fu_idx[ALU]];
                alu_in.pc <= res_pc[ready_for_fu_idx[ALU]];
                alu_in.alu_output_valid <= 1'b1;
            end 
            if(ready_for_fu[ALU1]) begin
                alu1_in.pr1_s <= res_ps1_s[ready_for_fu_idx[ALU1]];
                alu1_in.pr2_s <= res_ps2_s[ready_for_fu_idx[ALU1]];
                alu1_in.prd_s <= res_pd_s[ready_for_fu_idx[ALU1]];
                alu1_in.imm_val <= res_imm[ready_for_fu_idx[ALU1]];
                alu1_in.funct3 <= res_funct3[ready_for_fu_idx[ALU1]];
                alu1_in.funct7 <= res_funct7[ready_for_fu_idx[ALU1]];
                alu1_in.rob_id <= res_rob_id[ready_for_fu_idx[ALU1]];
                alu1_in.opcode <= res_opcode[ready_for_fu_idx[ALU1]];
                alu1_in.pc <= res_pc[ready_for_fu_idx[ALU1]];
                alu1_in.alu_output_valid <= 1'b1;
            end 
            if(ready_for_fu[ALU2]) begin
                alu2_in.pr1_s <= res_ps1_s[ready_for_fu_idx[ALU2]];
                alu2_in.pr2_s <= res_ps2_s[ready_for_fu_idx[ALU2]];
                alu2_in.prd_s <= res_pd_s[ready_for_fu_idx[ALU2]];
                alu2_in.imm_val <= res_imm[ready_for_fu_idx[ALU2]];
                alu2_in.funct3 <= res_funct3[ready_for_fu_idx[ALU2]];
                alu2_in.funct7 <= res_funct7[ready_for_fu_idx[ALU2]];
                alu2_in.rob_id <= res_rob_id[ready_for_fu_idx[ALU2]];
                alu2_in.opcode <= res_opcode[ready_for_fu_idx[ALU2]];
                alu2_in.pc <= res_pc[ready_for_fu_idx[ALU2]];
                alu2_in.alu_output_valid <= 1'b1;
            end
            if (ready_for_fu[BRANCH]) begin
                br_in.pr1_s <= res_ps1_s[ready_for_fu_idx[BRANCH]];
                br_in.pr2_s <= res_ps2_s[ready_for_fu_idx[BRANCH]];
                br_in.prd_s <= res_pd_s[ready_for_fu_idx[BRANCH]];
                br_in.opcode <= res_opcode[ready_for_fu_idx[BRANCH]];
                br_in.imm_val <= res_imm[ready_for_fu_idx[BRANCH]];
                br_in.funct3 <= res_funct3[ready_for_fu_idx[BRANCH]];
                br_in.funct7 <= res_funct7[ready_for_fu_idx[BRANCH]];
                br_in.rob_id <= res_rob_id[ready_for_fu_idx[BRANCH]];
                br_in.pc <= res_pc[ready_for_fu_idx[BRANCH]];
                br_in.pc_next <= res_pc_next[ready_for_fu_idx[BRANCH]];
                br_in.br_rs1_s_valid <= res_rs1_s_valid[ready_for_fu_idx[BRANCH]];
                br_in.br_rs2_s_valid <= res_rs2_s_valid[ready_for_fu_idx[BRANCH]];
                br_in.br_output_valid <= 1'b1;
            end
            if(ready_for_fu[MUL]) begin
                mul_in.pr1_s <= res_ps1_s[ready_for_fu_idx[MUL]];
                mul_in.pr2_s <= res_ps2_s[ready_for_fu_idx[MUL]];
                mul_in.prd_s <= res_pd_s[ready_for_fu_idx[MUL]];
                mul_in.imm_val <= res_imm[ready_for_fu_idx[MUL]];
                mul_in.funct3 <= res_funct3[ready_for_fu_idx[MUL]];
                mul_in.funct7 <= res_funct7[ready_for_fu_idx[MUL]];
                mul_in.rob_id <= res_rob_id[ready_for_fu_idx[MUL]];
                mul_in.mul_output_valid <= 1'b1;
            end
            if(ready_for_fu[DIV]) begin
                div_in.pr1_s <= res_ps1_s[ready_for_fu_idx[DIV]];
                div_in.pr2_s <= res_ps2_s[ready_for_fu_idx[DIV]];
                div_in.prd_s <= res_pd_s[ready_for_fu_idx[DIV]];
                div_in.imm_val <= res_imm[ready_for_fu_idx[DIV]];
                div_in.funct3 <= res_funct3[ready_for_fu_idx[DIV]];
                div_in.funct7 <= res_funct7[ready_for_fu_idx[DIV]];
                div_in.rob_id <= res_rob_id[ready_for_fu_idx[DIV]];
                div_in.div_output_valid <= 1'b1;
            end
        end
    end
    always_ff @(posedge clk) begin
        if(rst || branch_taken) begin
            for(integer unsigned i = 0; i < DEPTH; ++i) begin
                res_V[i] <= 1'b0;
                res_ps1_s[i] <= '0;
                res_ps1_v[i] <= 1'b0;
                res_ps2_s[i] <= '0;
                res_ps2_v[i] <= 1'b0;
                res_opcode[i] <= op_invalid;
            end
        end else begin
            for(integer unsigned i = 0; i < DEPTH; ++i) begin
                if (entry_we[i]) begin 
                    res_V[i]      <= next_res_V[i];
                    res_ps1_v[i]  <= next_res_ps1_v[i];
                    res_ps2_v[i]  <= next_res_ps2_v[i];
                    if (next_res_V[i] && !res_V[i]) begin
                        logic [$clog2(WAY)-1:0] w_idx;
                        for(integer unsigned w=0; w<WAY; w++) begin
                            if(free_slot_indices[w] == $clog2(DEPTH)'(i) && res_input[w].dispatch_to_res_valid) begin
                                res_ps1_s[i] <= res_input[w].ps1_v ? '0 : res_input[w].ps1_s;
                                if(res_input[w].opcode != op_br)
                                    res_ps2_s[i] <= res_input[w].imm_flag ? '0: res_input[w].ps2_s;
                                else
                                    res_ps2_s[i] <= res_input[w].ps2_s;
                                res_pd_s[i] <= res_input[w].pd_s;
                                res_fu_idx[i] <= res_input[w].fu_idx[$clog2(FU_IDX_COUNT)-1:0];
                                res_rob_id[i] <= res_input[w].rob_id;
                                res_imm[i] <= {res_input[w].imm_flag, res_input[w].imm_val};
                                res_funct3[i] <= res_input[w].funct3;
                                res_funct7[i] <= res_input[w].funct7;
                                res_opcode[i] <= res_input[w].opcode;
                                res_pc[i] <= res_input[w].pc;
                                res_pc_next[i] <= res_input[w].pc_next;
                                res_rs1_s_valid[i] <= res_input[w].rs1_s_valid;
                                res_rs2_s_valid[i] <= res_input[w].rs2_s_valid; 
                            end
                        end
                    end
                end
            end
        end
    end
endmodule : reservation_station_superscaler