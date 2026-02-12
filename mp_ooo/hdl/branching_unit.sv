module branching_unit
import rv32i_types::*;
#(
    parameter NO_PHY_REGS = 64,
    parameter PHY_WIDTH = $clog2(NO_PHY_REGS)
)
(
  input   res_station_br_out_s      exec_br_rs,
  input logic [31:0] ps1_data,
  input logic [31:0] ps2_data,
  output logic prf_rd_en,
  output logic [PHY_WIDTH-1:0] ps1_s,
  output logic [PHY_WIDTH-1:0] ps2_s,
  output  res_station_br_out_s      br_cdb_out
);

logic [31:0] a,b;
logic [2:0] cmpop;
logic cmpout;

cmp cmp_br (
    .a      (a),
    .b      (b),
    .cmpop  (cmpop),
    .cmpout (cmpout)
);


always_comb begin
    a = 'x;
    b = 'x;
    cmpop           = 'x;
    br_cdb_out      = exec_br_rs;
    ps1_s           = '0;
    ps2_s           = '0;
    prf_rd_en       = 1'b0;

    if(exec_br_rs.br_output_valid) begin
        br_cdb_out.rob_id = exec_br_rs.rob_id;
        br_cdb_out.br_output_valid = 1'b1;
        if(exec_br_rs.br_rs1_s_valid) begin
            prf_rd_en = 1'b1;
            ps1_s = exec_br_rs.pr1_s;
            a = ps1_data;
            br_cdb_out.br_rs1_data = ps1_data;
        end
        if(exec_br_rs.br_rs2_s_valid) begin
            prf_rd_en = 1'b1;
            ps2_s = exec_br_rs.pr2_s;
            b = ps2_data;
            br_cdb_out.br_rs2_data = ps2_data;
        end

        unique case (exec_br_rs.opcode)
            op_br: begin
                cmpop = exec_br_rs.funct3;
                if(cmpout) begin
                    br_cdb_out.pc_next = exec_br_rs.pc + exec_br_rs.imm_val[31:0];
                    br_cdb_out.br_taken = 1'b1;
                end else begin
                    br_cdb_out.pc_next = exec_br_rs.pc + 32'd4;
                    br_cdb_out.br_taken = 1'b0;
                end
                br_cdb_out.br_output_valid = 1'b1;
                br_cdb_out.br_output_data = '0;
            end
            op_jal: begin
                br_cdb_out.pc_next = exec_br_rs.pc + exec_br_rs.imm_val[31:0];
                if(br_cdb_out.pc_next != exec_br_rs.pc_next)
                     br_cdb_out.br_jal_flush = 1'b1;
                br_cdb_out.br_taken = 1'b1;
                br_cdb_out.br_output_valid = 1'b1;
                br_cdb_out.br_output_data = exec_br_rs.pc + 32'd4;
            end
            op_jalr: begin
                br_cdb_out.pc_next = (ps1_data + exec_br_rs.imm_val[31:0]) & 32'hfffffffe;
                if(br_cdb_out.pc_next != exec_br_rs.pc_next)
                     br_cdb_out.br_jal_flush = 1'b1;
                br_cdb_out.br_taken = 1'b1;
                br_cdb_out.br_output_valid = 1'b1;
                br_cdb_out.br_output_data = exec_br_rs.pc + 32'd4;
            end
            default: ;
        endcase
    end
end

endmodule: branching_unit