module cdb 
import rv32i_types::*;
#(
    parameter integer FU_CHANNELS = FU_IDX_COUNT -1,
    parameter PRF_ENTRY = 64,
    parameter REGISTER_OUTPUTS = 0 
)
(
//  input logic clk,
 // input logic rst,

  input res_station_alu_out_s exec_arithmetic_in,
  input res_station_alu_out_s exec_arithmetic1_in,
  input res_station_alu_out_s exec_arithmetic2_in,
  input res_station_mul_out_s exec_mul_in,
  input res_station_div_out_s exec_div_in,
  input mem_ld_cdb_t ld_st_unit_in,
  input res_station_br_out_s exec_br_in,
  input logic [PRF_WIDTH-1:0] lui_reg_add[WAY-1:0],
  input logic lui_valid[WAY-1:0],

  // CDB outputs
  output logic  write_en[FU_CHANNELS - WAY:0],
  output logic  [$clog2(PRF_ENTRY)-1:0] write_tag[FU_CHANNELS-WAY:0] ,
  output logic  [31:0] write_data [FU_CHANNELS-WAY:0],

  output logic  [FU_CHANNELS-1:0] rob_valid,
  output logic [ROB_ID_WIDTH - 1: 0] rob_id[FU_CHANNELS-1:0],
  output cdb_out_signal_s cdb_out,
  
  // For the monitor
  output logic [31:0] rs1_rdata[FU_CHANNELS-1:0],
  output logic [31:0] rs2_rdata[FU_CHANNELS-1:0],
  output logic [3:0] monitor_mem_rmask,
  output logic [3:0] monitor_mem_wmask,
  output logic [31:0] monitor_mem_addr,
  output logic [31:0] monitor_mem_wdata,
  output logic [31:0] monitor_mem_load_data,

  output logic branch_taken,
  output logic [ROB_ID_WIDTH - 1: 0] branch_taken_rob_id,
  output logic [31:0] branch_next_pc,
  output logic br_jal_flush
);

    logic  next_write_en[FU_CHANNELS - WAY:0];
    logic  [$clog2(PRF_ENTRY)-1:0] next_write_tag[FU_CHANNELS-WAY:0];
    logic  [31:0] next_write_data [FU_CHANNELS-WAY:0];
    logic  [FU_CHANNELS-1:0] next_rob_valid;
    logic  [ROB_ID_WIDTH - 1: 0] next_rob_id[FU_CHANNELS-1:0];
    cdb_out_signal_s next_cdb_out;
    logic  [31:0] next_rs1_rdata[FU_CHANNELS-1:0];
    logic  [31:0] next_rs2_rdata[FU_CHANNELS-1:0];
    logic  [3:0] next_monitor_mem_rmask;
    logic  [3:0] next_monitor_mem_wmask;
    logic  [31:0] next_monitor_mem_addr;
    logic  [31:0] next_monitor_mem_wdata;
    logic  [31:0] next_monitor_mem_load_data;
    logic  next_branch_taken;
    logic  [ROB_ID_WIDTH - 1: 0] next_branch_taken_rob_id;
    logic  [31:0] next_branch_next_pc;
    logic  next_br_jal_flush;

    // logic  reg_write_en[FU_CHANNELS - WAY:0];
    // logic  [$clog2(PRF_ENTRY)-1:0] reg_write_tag[FU_CHANNELS-WAY:0];
    // logic  [31:0] reg_write_data [FU_CHANNELS-WAY:0];
    // logic  [FU_CHANNELS-1:0] reg_rob_valid;
    // logic  [ROB_ID_WIDTH - 1: 0] reg_rob_id[FU_CHANNELS-1:0];
    // cdb_out_signal_s reg_cdb_out;
    // logic  [31:0] reg_rs1_rdata[FU_CHANNELS-1:0];
    // logic  [31:0] reg_rs2_rdata[FU_CHANNELS-1:0];
    // logic  [3:0] reg_monitor_mem_rmask;
    // logic  [3:0] reg_monitor_mem_wmask;
    // logic  [31:0] reg_monitor_mem_addr;
    // logic  [31:0] reg_monitor_mem_wdata;
    // logic  [31:0] reg_monitor_mem_load_data;
    // logic  reg_branch_taken;
    // logic  [ROB_ID_WIDTH - 1: 0] reg_branch_taken_rob_id;
    // logic  [31:0] reg_branch_next_pc;
    // logic  reg_br_jal_flush;


 always_comb begin
        next_write_data = '{default: '0};
        next_write_en = '{default: '0};
        next_write_tag = '{default: '0};
        for(integer i = 0; i < FU_CHANNELS; ++i) begin
            next_rob_valid[i] = 1'b0;
            next_rob_id[i] = '0;
            next_rs1_rdata[i] = 32'd0;
            next_rs2_rdata[i] = 32'd0;
        end
        next_cdb_out = '0;
        next_branch_taken = 1'b0;
        next_branch_taken_rob_id = '0;
        next_branch_next_pc = '0;
        next_monitor_mem_rmask = '0;
        next_monitor_mem_wmask = '0;
        next_monitor_mem_addr = '0;
        next_monitor_mem_load_data ='0;
        next_monitor_mem_wdata = '0;
        next_br_jal_flush = '0;

        if(exec_arithmetic_in.alu_output_valid) begin
            next_rob_valid[ALU] = 1'b1;
            next_rob_id[ALU] = exec_arithmetic_in.rob_id;
            next_cdb_out.cdb_valid[exec_arithmetic_in.prd_s] = 1'b1;
            next_cdb_out.cdb_phy_reg = exec_arithmetic_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_arithmetic_in.rob_id;
            //for the monitor
            next_rs1_rdata[ALU] = exec_arithmetic_in.alu_rs1_data;
            next_rs2_rdata[ALU] = exec_arithmetic_in.alu_rs2_data;
            next_write_data[ALU] = exec_arithmetic_in.alu_output_data;
            next_write_tag[ALU]  = exec_arithmetic_in.prd_s;
            next_write_en[ALU]   = 1'b1;
        end
        if(exec_arithmetic1_in.alu_output_valid) begin
            next_rob_valid[ALU1] = 1'b1;
            next_rob_id[ALU1] = exec_arithmetic1_in.rob_id;
            next_cdb_out.cdb_valid[exec_arithmetic1_in.prd_s] = 1'b1;
            next_cdb_out.cdb_phy_reg = exec_arithmetic1_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_arithmetic1_in.rob_id;
            //for the monitor
            next_rs1_rdata[ALU1] = exec_arithmetic1_in.alu_rs1_data;
            next_rs2_rdata[ALU1] = exec_arithmetic1_in.alu_rs2_data;
            next_write_data[ALU1] = exec_arithmetic1_in.alu_output_data;
            next_write_tag[ALU1]  = exec_arithmetic1_in.prd_s;
            next_write_en[ALU1]   = 1'b1;
        end
        if(exec_arithmetic2_in.alu_output_valid) begin
            next_rob_valid[ALU2] = 1'b1;
            next_rob_id[ALU2] = exec_arithmetic2_in.rob_id;
            next_cdb_out.cdb_valid[exec_arithmetic2_in.prd_s] = 1'b1;
            next_cdb_out.cdb_phy_reg = exec_arithmetic2_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_arithmetic2_in.rob_id;
            //for the monitor
            next_rs1_rdata[ALU2] = exec_arithmetic2_in.alu_rs1_data;
            next_rs2_rdata[ALU2] = exec_arithmetic2_in.alu_rs2_data;
            next_write_data[ALU2] = exec_arithmetic2_in.alu_output_data;
            next_write_tag[ALU2]  = exec_arithmetic2_in.prd_s;
            next_write_en[ALU2]   = 1'b1;
        end
        if(exec_mul_in.mul_output_valid) begin
            next_rob_valid[MUL] = 1'b1;
            next_rob_id[MUL] = exec_mul_in.rob_id;
            next_cdb_out.cdb_valid[exec_mul_in.prd_s] = 1'b1;
            next_cdb_out.cdb_phy_reg = exec_mul_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_mul_in.rob_id;
            //for the monitor
            next_rs1_rdata[MUL] = exec_mul_in.mul_rs1_data;
            next_rs2_rdata[MUL] = exec_mul_in.mul_rs2_data;
            next_write_data[MUL] = exec_mul_in.mul_output_data;
            next_write_tag[MUL]  = exec_mul_in.prd_s;
            next_write_en[MUL]   = 1'b1;
        end
        if(exec_div_in.div_output_valid) begin
            next_rob_valid[DIV] = 1'b1;
            next_rob_id[DIV] = exec_div_in.rob_id;
            next_cdb_out.cdb_valid[exec_div_in.prd_s] = 1'b1;
            next_rs1_rdata[DIV] = exec_div_in.div_rs1_data;
            next_rs2_rdata[DIV] = exec_div_in.div_rs2_data;
            next_cdb_out.cdb_phy_reg = exec_div_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_div_in.rob_id;
            next_write_data[DIV] = exec_div_in.div_output_data;
            next_write_tag[DIV]  = exec_div_in.prd_s;
            next_write_en[DIV]   = 1'b1;
        end
        if(ld_st_unit_in.mem_valid && !ld_st_unit_in.store_or_load) begin
            next_rob_valid[MEM_LD] = 1'b1;
            next_rob_id[MEM_LD]    = ld_st_unit_in.rob_id;
            next_cdb_out.cdb_valid[ld_st_unit_in.pd_s] = 1'b1;
            next_rs1_rdata[MEM_LD] = ld_st_unit_in.rs1_data;
            next_rs2_rdata[MEM_LD] = '0;
            next_cdb_out.cdb_phy_reg = ld_st_unit_in.pd_s;
            next_cdb_out.cdb_rob_id = ld_st_unit_in.rob_id;
            next_write_data[MEM_LD] = ld_st_unit_in.mem_rd_data;
            next_write_tag[MEM_LD]  = ld_st_unit_in.pd_s;
            next_write_en[MEM_LD]   = 1'b1;
            next_monitor_mem_load_data = ld_st_unit_in.mem_load_data;
            next_monitor_mem_rmask  = ld_st_unit_in.rmask;
            next_monitor_mem_addr   = ld_st_unit_in.ld_addr;
        end else if(ld_st_unit_in.mem_valid && ld_st_unit_in.store_or_load) begin
            next_rob_id[MEM_ST]    =  ld_st_unit_in.rob_id;
            next_rob_valid[MEM_ST]  = 1'b1;
            next_rs1_rdata[MEM_ST] = ld_st_unit_in.rs1_data;
            next_rs2_rdata[MEM_ST] = ld_st_unit_in.rs2_data;
            next_monitor_mem_wmask = ld_st_unit_in.wmask;
            next_monitor_mem_addr  = ld_st_unit_in.st_addr;
            next_monitor_mem_wdata = ld_st_unit_in.mem_wdata;
        end
        if(exec_br_in.br_output_valid) begin
            next_rob_valid[BRANCH] = 1'b1;
            next_rob_id[BRANCH] = exec_br_in.rob_id;
            next_cdb_out.cdb_valid[exec_br_in.prd_s] = 1'b1;
            next_rs1_rdata[BRANCH] = exec_br_in.br_rs1_data;
            next_rs2_rdata[BRANCH] = exec_br_in.br_rs2_data;
            next_cdb_out.cdb_phy_reg = exec_br_in.prd_s;
            next_cdb_out.cdb_rob_id = exec_br_in.rob_id;
            next_write_data[BRANCH] = exec_br_in.br_output_data;
            next_write_tag[BRANCH]  = exec_br_in.prd_s;
            if(exec_br_in.opcode != op_br) begin
                next_write_en[BRANCH]   = 1'b1;
            end else begin
                next_write_en[BRANCH]   = 1'b0;
            end
            next_branch_taken = exec_br_in.br_taken;
            next_branch_next_pc = exec_br_in.pc_next;
            next_branch_taken_rob_id = exec_br_in.rob_id;
            next_br_jal_flush  = exec_br_in.br_jal_flush;
        end

        for(integer unsigned sc_cdb=0; sc_cdb < WAY; ++sc_cdb) begin
            if(lui_valid[sc_cdb])
                next_cdb_out.cdb_valid[lui_reg_add[sc_cdb]] = 1'b1;
        end 
    end

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             reg_write_en <= '{default: '0};
//             reg_write_tag <= '{default: '0};
//             reg_write_data <= '{default: '0};
//             reg_rob_valid <= '0;
//             reg_rob_id <= '{default: '0};
//             reg_cdb_out <= '0; 
//             reg_rs1_rdata <= '{default: '0};
//             reg_rs2_rdata <= '{default: '0};
//             reg_monitor_mem_rmask <= '0;
//             reg_monitor_mem_wmask <= '0;
//             reg_monitor_mem_addr <= '0;
//             reg_monitor_mem_wdata <= '0;
//             reg_monitor_mem_load_data <= '0;
//             reg_branch_taken <= 1'b0;
//             reg_branch_taken_rob_id <= '0;
//             reg_branch_next_pc <= '0;
//             reg_br_jal_flush <= '0;
//         end else begin
//             reg_write_en <= next_write_en;
//             reg_write_tag <= next_write_tag;
//             reg_write_data <= next_write_data;
//             reg_rob_valid <= next_rob_valid;
//             reg_rob_id <= next_rob_id;
//             reg_cdb_out <= next_cdb_out;
//             reg_rs1_rdata <= next_rs1_rdata;
//             reg_rs2_rdata <= next_rs2_rdata;
//             reg_monitor_mem_rmask <= next_monitor_mem_rmask;
//             reg_monitor_mem_wmask <= next_monitor_mem_wmask;
//             reg_monitor_mem_addr <= next_monitor_mem_addr;
//             reg_monitor_mem_wdata <= next_monitor_mem_wdata;
//             reg_monitor_mem_load_data <= next_monitor_mem_load_data;
//             reg_branch_taken <= next_branch_taken;
//             reg_branch_taken_rob_id <= next_branch_taken_rob_id;
//             reg_branch_next_pc <= next_branch_next_pc;
//             reg_br_jal_flush <= next_br_jal_flush;
//             end
//  end

    assign write_en =  next_write_en;
    assign write_tag =  next_write_tag;
    assign write_data =  next_write_data;
    assign rob_valid =  next_rob_valid;
    assign rob_id =  next_rob_id;
    assign cdb_out =  next_cdb_out;
    assign rs1_rdata =  next_rs1_rdata;
    assign rs2_rdata =  next_rs2_rdata;
    assign monitor_mem_rmask =  next_monitor_mem_rmask;
    assign monitor_mem_wmask = next_monitor_mem_wmask;
    assign monitor_mem_addr = next_monitor_mem_addr;
    assign monitor_mem_wdata =  next_monitor_mem_wdata;
    assign monitor_mem_load_data = next_monitor_mem_load_data;
    assign branch_taken =  next_branch_taken;
    assign branch_taken_rob_id =  next_branch_taken_rob_id;
    assign branch_next_pc =  next_branch_next_pc;
    assign br_jal_flush =  next_br_jal_flush;

endmodule : cdb
