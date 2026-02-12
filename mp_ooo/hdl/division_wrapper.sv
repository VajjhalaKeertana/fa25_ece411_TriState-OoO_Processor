module division_wrapper 
import rv32i_types::*;
#(
    parameter NO_PHY_REGS = 64,
    parameter PHY_WIDTH = $clog2(NO_PHY_REGS)
)
(
    input clk,
    input rst,
    input   res_station_div_out_s      exec_div_rs,
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,
    output logic prf_rd_en,
    output logic [PHY_WIDTH-1:0] ps1_s,
    output logic [PHY_WIDTH-1:0] ps2_s,
    output  res_station_div_out_s      div_cdb_out
);

logic   [31:0]  a;
logic   [31:0]  b;
logic   [31:0]  quotient;
logic   [31:0]  remainder;
logic           divide_by_0;

DW_div_pipe_inst  wrapper_to_div (
    .inst_clk(clk),   
    .inst_rst_n(~rst),   
    .inst_en(1'b1),  
    .inst_a(a),   
    .inst_b(b),         
    .quotient_inst(quotient),        
    .remainder_inst(remainder),   
    .divide_by_0_inst(divide_by_0)
);

logic valid_hold;
res_station_div_out_s exec_div_rs_hold;
logic [31:0] ps1_data_hold;
logic [31:0] ps2_data_hold;

always_ff @(posedge clk) begin
    if (rst) begin
        valid_hold <= 1'b0;
        exec_div_rs_hold <= '0;
        ps1_data_hold <= 'x;
        ps2_data_hold <= 'x;
    end else begin
        valid_hold <= exec_div_rs.div_output_valid;
        exec_div_rs_hold <= exec_div_rs;
        ps1_data_hold <= ps1_data;
        ps2_data_hold <= ps2_data;
    end
end

always_comb begin
    div_cdb_out = '0;
    if(valid_hold) begin
        div_cdb_out = exec_div_rs_hold;
        div_cdb_out.div_output_valid = 1'b1;
        div_cdb_out.div_rs1_data = ps1_data_hold;
        div_cdb_out.div_rs2_data = ps2_data_hold;   
        unique case (exec_div_rs_hold.funct3)
            div: begin
                div_cdb_out.div_output_data = divide_by_0 ? '1 : (ps1_data_hold[31] ^ ps2_data_hold[31] ? (~quotient+32'b1):quotient);
            end
            divu: begin
                div_cdb_out.div_output_data = divide_by_0 ? '1 : quotient;
            end
            rem: begin
                div_cdb_out.div_output_data = divide_by_0 ? ps1_data_hold : (ps1_data_hold[31] ? (~remainder+32'b1) : remainder);
            end
            remu: begin
                div_cdb_out.div_output_data = divide_by_0 ? ps1_data_hold : remainder;
            end
            default: ;
        endcase
    end
end

always_comb begin
    a = 'x;
    b = 'x;
    prf_rd_en = 1'b0;
    ps1_s = 'x;
    ps2_s = 'x;
    if(exec_div_rs.div_output_valid) begin
        ps1_s = exec_div_rs.pr1_s;
        ps2_s = exec_div_rs.pr2_s;
        prf_rd_en = 1'b1;
        unique case (exec_div_rs.funct3)
            div,rem: begin
                a = ps1_data[31]?(~ps1_data + 32'b1):ps1_data;
                b = ps2_data[31]?(~ps2_data + 32'b1):ps2_data;
            end
            divu,remu: begin
                a = ps1_data;
                b = ps2_data;
            end
            default: ;
        endcase
    end
end
endmodule : division_wrapper

module DW_div_pipe_inst(inst_clk, inst_rst_n, inst_en, inst_a, inst_b, quotient_inst, remainder_inst, divide_by_0_inst );  
parameter inst_a_width = 32;  
parameter inst_b_width = 32;  
parameter inst_tc_mode = 0;  
parameter inst_rem_mode = 1;  
parameter inst_num_stages = 2;  
parameter inst_stall_mode = 1;  
parameter inst_rst_mode = 1;  
parameter inst_op_iso_mode = 0;  
input inst_clk;  
input inst_rst_n;  
input inst_en;  
input [inst_a_width-1 : 0] inst_a;  
input [inst_b_width-1 : 0] inst_b;  
output [inst_a_width-1 : 0] quotient_inst;  
output [inst_b_width-1 : 0] remainder_inst;  
output divide_by_0_inst;  
// Instance of DW_div_pipe  
DW_div_pipe #(
    inst_a_width,   
    inst_b_width,   
    inst_tc_mode,  
    inst_rem_mode,                
    inst_num_stages,   
    inst_stall_mode,   
    inst_rst_mode,   
    inst_op_iso_mode
) U1 (
    .clk(inst_clk),
    .rst_n(inst_rst_n),   
    .en(inst_en),        
    .a(inst_a),   
    .b(inst_b),   
    .quotient(quotient_inst),        
    .remainder(remainder_inst),   
    .divide_by_0(divide_by_0_inst) 
);
endmodule : DW_div_pipe_inst
