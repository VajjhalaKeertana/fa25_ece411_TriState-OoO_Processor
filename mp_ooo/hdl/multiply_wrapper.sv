module multiply_wrapper 
import rv32i_types::*;
#(
    parameter NO_PHY_REGS = 64,
    parameter PHY_WIDTH = $clog2(NO_PHY_REGS)
)
(
    input clk,
    input rst,
    input   res_station_mul_out_s      exec_mul_rs,
    input logic [31:0] ps1_data,
    input logic [31:0] ps2_data,
    output logic prf_rd_en,
    output logic [PHY_WIDTH-1:0] ps1_s,
    output logic [PHY_WIDTH-1:0] ps2_s,
    output  res_station_mul_out_s      mul_cdb_out
);

logic   [31:0]  a;
logic   [31:0]  b;
logic           tc_in;
logic   [63:0]  product;

DW_mult_pipe_inst  wrapper_to_mul (
    .inst_clk(clk),   
    .inst_rst_n(~rst),   
    .inst_en(1'b1),        
    .inst_tc(tc_in),   
    .inst_a(a),   
    .inst_b(b),         
    .product_inst(product) 
);

logic valid_hold;
res_station_mul_out_s exec_mul_rs_hold;
logic [31:0] ps1_data_hold;
logic [31:0] ps2_data_hold;

always_ff @(posedge clk) begin
    if (rst) begin
        valid_hold <= 1'b0;
        exec_mul_rs_hold <= '0;
        ps1_data_hold <= 'x;
        ps2_data_hold <= 'x;
    end else begin
        valid_hold <= exec_mul_rs.mul_output_valid;
        exec_mul_rs_hold <= exec_mul_rs;
        ps1_data_hold <= ps1_data;
        ps2_data_hold <= ps2_data;
        //mul_cdb_out.mul_rs1_data <= ps1_data;
        //mul_cdb_out.mul_rs2_data <= ps2_data;
    end
end

always_comb begin
    mul_cdb_out = '0;
    if(valid_hold) begin
        mul_cdb_out = exec_mul_rs_hold;
        mul_cdb_out.mul_rs1_data = ps1_data_hold;
        mul_cdb_out.mul_rs2_data = ps2_data_hold;    
        mul_cdb_out.mul_output_valid = 1'b1;
        unique case (exec_mul_rs_hold.funct3)
            mul: begin
                mul_cdb_out.mul_output_data = product[31:0];
            end
            mulh: begin
                mul_cdb_out.mul_output_data = product[63:32];
            end
            mulhsu: begin
                logic [63:0] prod_temp;
                prod_temp = ps1_data_hold[31] ? (~product + 64'd1) : product;
                mul_cdb_out.mul_output_data = prod_temp[63:32]; 
            end
            mulhu: begin
                mul_cdb_out.mul_output_data = product[63:32]; 
            end
            default: ;
        endcase
    end
end

always_comb begin
    a = 'x;
    b = 'x;
    ps1_s = 'x;
    ps2_s = 'x;
    prf_rd_en  = 1'b0;
    tc_in = 1'b0;
    if (exec_mul_rs.mul_output_valid) begin
        ps1_s       = exec_mul_rs.pr1_s;
        ps2_s       = exec_mul_rs.pr2_s;
        prf_rd_en   = 1'b1;
        unique case (exec_mul_rs.funct3)
            mul: begin
                b = ps2_data;
                a = ps1_data;
                tc_in = 1'b0;
            end
            mulh: begin
                b = ps2_data;
                a = ps1_data;
                tc_in = 1'b1;
                
            end
            mulhsu: begin
                b = ps2_data;
                a = ps1_data[31] ? (~ps1_data + 32'd1) : ps1_data;
                // a = ps1_data;
                tc_in = 1'b0;
            end
            mulhu: begin
                b = ps2_data[31:0];
                a = ps1_data[31:0];
                tc_in = 1'b0;     
            end
            default: ;
        endcase
    end
end

endmodule: multiply_wrapper

module DW_mult_pipe_inst(inst_clk, inst_rst_n, inst_en, inst_tc, inst_a, inst_b, product_inst );  
    parameter inst_a_width = 32;  
    parameter inst_b_width = 32;
    parameter inst_num_stages = 2;  
    parameter inst_stall_mode = 1;  
    parameter inst_rst_mode = 1;  
    parameter inst_op_iso_mode = 0;  
    input [inst_a_width-1 : 0] inst_a;  
    input [inst_b_width-1 : 0] inst_b;  
    input inst_tc;  
    input inst_clk;  
    input inst_en;  
    input inst_rst_n;  
    output [inst_a_width+inst_b_width-1 : 0] product_inst;
    // Instance of DW_mult_pipe  
    
    DW_mult_pipe #(
        inst_a_width, 
        inst_b_width, 
        inst_num_stages,
        inst_stall_mode, 
        inst_rst_mode, 
        inst_op_iso_mode
    ) U1 (
        .clk(inst_clk),   
        .rst_n(inst_rst_n),   
        .en(inst_en),        
        .tc(inst_tc),   
        .a(inst_a),   
        .b(inst_b),         
        .product(product_inst) 
    );
endmodule 



