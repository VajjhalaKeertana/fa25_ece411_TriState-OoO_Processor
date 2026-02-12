module arith_ex_stage
import rv32i_types::*;
#(
    parameter NO_PHY_REGS = 64,
    parameter PHY_WIDTH = $clog2(NO_PHY_REGS)
)
(
  input   res_station_alu_out_s      exec_arith_rs,
  input logic [31:0] ps1_data,
  input logic [31:0] ps2_data,
  output logic prf_rd_en,
  output logic [PHY_WIDTH-1:0] ps1_s,
  output logic [PHY_WIDTH-1:0] ps2_s,
  output  res_station_alu_out_s      alu_cdb_out


);

  // ALU and comparator signals
  logic   [31:0]  a;
  logic   [31:0]  b;
  logic   [2:0]   aluop;
  logic   [2:0]   cmpop;
  logic   [31:0]  aluout;
  logic           cmpout;

  // Comparator
  cmp cmp_i (
    .a      (a),
    .b      (b),
    .cmpop  (cmpop),
    .cmpout (cmpout)
  );

  // ALU
  alu alu(
    .a      (a),
    .b      (b),
    .aluop  (aluop),
    .aluout (aluout)
  );

  always_comb begin
    
    a = 'x;
    b = 'x;
    aluop           = 'x;
    cmpop           = 'x;
    alu_cdb_out     = '0;
    ps1_s           = 'x;
    ps2_s           = 'x;
    //br_taken        = 1'b0;
   
   /* ex_mem_reg_next.order         = exec_arith_rs.order;
    ex_mem_reg_next.inst          = exec_arith_rs.inst;
    ex_mem_reg_next.monitor_valid = exec_arith_rs.monitor_valid;
    ex_mem_reg_next.pc            = exec_arith_rs.pc;
    ex_mem_reg_next.pc_next       = exec_arith_rs.pc_next;

    ex_mem_reg_next.rs1_s         = exec_arith_rs.rs1_s;
    ex_mem_reg_next.rs2_s         = exec_arith_rs.rs2_s;
    ex_mem_reg_next.rs1_v         = exec_arith_rs.rs1_v;
    ex_mem_reg_next.rs2_v         = exec_arith_rs.rs2_v;
    ex_mem_reg_next.funct3        = exec_arith_rs.funct3;*/
   
    //except mem all others will use
   prf_rd_en = 1'b0;

   if(exec_arith_rs.alu_output_valid) begin
    if(exec_arith_rs.opcode != op_auipc) begin
      alu_cdb_out.rob_id = exec_arith_rs.rob_id;
      alu_cdb_out.alu_output_valid = 1'b1;
      prf_rd_en = 1'b1;
      ps1_s = exec_arith_rs.pr1_s;
      a = ps1_data;
      //for the monitor
      alu_cdb_out.alu_rs1_data = ps1_data;
      if(exec_arith_rs.imm_val[32]) begin
        b = exec_arith_rs.imm_val[31:0];
      end else begin
        ps2_s = exec_arith_rs.pr2_s;
        b = ps2_data;
        //for the monitor
        alu_cdb_out.alu_rs2_data = ps2_data;
      end

      unique case (exec_arith_rs.funct3)
        slt: begin
          cmpop = blt;
          alu_cdb_out.alu_output_data = {31'd0, cmpout};
          alu_cdb_out.prd_s = exec_arith_rs.prd_s;
          //ex_mem_reg_next.wb_regf_we = 1'd1;
        end
        sltu: begin
          cmpop = bltu;
          alu_cdb_out.alu_output_data = {31'd0, cmpout};
          alu_cdb_out.prd_s = exec_arith_rs.prd_s;
          //ex_mem_reg_next.wb_regf_we = 1'd1;
        end
        sr: begin
            if (exec_arith_rs.funct7[5]) begin
              aluop = alu_sra;
            end else begin
              aluop = alu_srl;
            end
              alu_cdb_out.alu_output_data = aluout;
              alu_cdb_out.prd_s = exec_arith_rs.prd_s;
              // ex_mem_reg_next.wb_regf_we = 1'd1;
        end
        add: begin
            if (exec_arith_rs.funct7[5]) begin
              aluop = alu_sub;
            end else begin
              aluop = alu_add;
            end
              alu_cdb_out.alu_output_data  =  aluout;
              alu_cdb_out.prd_s            = exec_arith_rs.prd_s;
              //ex_mem_reg_next.wb_regf_we   = 1'd1;
        end
        default: begin
            aluop                      = exec_arith_rs.funct3;
            alu_cdb_out.alu_output_data  = aluout;
            alu_cdb_out.prd_s            = exec_arith_rs.prd_s;
            //ex_mem_reg_next.wb_regf_we = 1'd1;
        end
      endcase
    end else begin
      alu_cdb_out.rob_id = exec_arith_rs.rob_id;
      alu_cdb_out.alu_output_valid = 1'b1;
      alu_cdb_out.prd_s = exec_arith_rs.prd_s;
      a = exec_arith_rs.pc;
      b = exec_arith_rs.imm_val[31:0];
      aluop = alu_add;
      alu_cdb_out.alu_output_data = aluout;
    end
   end
  end 

endmodule : arith_ex_stage
