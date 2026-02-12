module retired_rat_table 
import rv32i_types::*;
#(
    parameter DATA_WIDTH = 32,
    parameter ARCH_ENTRY = 32,
    parameter ARCH_WIDTH = $clog2(ARCH_ENTRY),
    parameter PRF_ENTRY = 64,
    parameter PRF_WIDTH = $clog2(PRF_ENTRY)
)(
    input logic clk,
    input logic rst,

    input logic [WAY-1:0]en,
    input logic [ARCH_WIDTH-1:0] rd_arch[WAY],
    input logic [PRF_WIDTH-1:0] new_phy_reg[WAY],

    output logic [PRF_WIDTH-1:0] rd_phy[WAY],
    output integer unsigned commit_count,
    output logic[31:0] commit_count_relative[WAY],
    output logic [WAY-1:0] commit_phy_reg_valid,

    //input logic [ARCH_WIDTH-1:0] rob_arch1,
    //input logic [ARCH_WIDTH-1:0] rob_arch2,
    //output logic [PRF_WIDTH-1:0] prf_phy1,
    //output logic [PRF_WIDTH-1:0] prf_phy2,

    output logic [ARCH_ENTRY-1:0][PRF_WIDTH-1:0] rrat
);

logic [ARCH_ENTRY-1:0][PRF_WIDTH-1:0] phy_q;
logic flag;
assign rrat = phy_q;

always_ff @(posedge clk) begin
    if(rst) begin
        phy_q <= '0;
    end else begin
        for(integer unsigned sc_rrat=0; sc_rrat < WAY; ++sc_rrat) begin
            if(en[sc_rrat]) begin
                phy_q[rd_arch[sc_rrat]] <= new_phy_reg[sc_rrat];
            end
        end
    end
end

//assign prf_phy1 = phy_q[rob_arch1];
//assign prf_phy2 = phy_q[rob_arch2];

always_comb begin
    commit_count = 0;
    flag = 1'b0;
    for(integer unsigned sc_rrat=0; sc_rrat<WAY; ++sc_rrat) begin
        commit_phy_reg_valid[sc_rrat] = 1'b0;
        commit_count_relative[sc_rrat] = '0;
        rd_phy[sc_rrat] = '0;
    end

    for(integer unsigned sc_rrat=0; sc_rrat<WAY; ++sc_rrat) begin
        if(en[sc_rrat]) begin
            for(integer unsigned sc_rrat_1=0; sc_rrat_1<WAY; ++sc_rrat_1) begin
                if(sc_rrat_1 < sc_rrat) begin
                    if((rd_arch[sc_rrat] == rd_arch[sc_rrat_1]) && (rd_arch[sc_rrat] != 0)) begin
                        rd_phy[sc_rrat] = new_phy_reg[sc_rrat_1];
                        flag = 1'b1;
                    end
                end
            end
            if(!flag) begin
                rd_phy[sc_rrat] = phy_q[rd_arch[sc_rrat]];
                commit_count_relative[sc_rrat] = commit_count;
                if(rd_phy[sc_rrat] != '0) begin
                    commit_count = commit_count + 1;
                    commit_phy_reg_valid[sc_rrat] = 1'b1;
                end
            end else begin
                commit_count_relative[sc_rrat] = commit_count;
                if(rd_phy[sc_rrat] != '0) begin
                    commit_count = commit_count + 1;
                    commit_phy_reg_valid[sc_rrat] = 1'b1;
                end
            end
        
        end
    end
end

endmodule