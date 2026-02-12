module arf_rat_table 
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

    input logic [WAY-1:0] en,
    input logic rs1_arch_read[WAY-1:0],
    input logic rs2_arch_read[WAY-1:0],
    input logic [ARCH_WIDTH-1:0]rs_arch1[WAY-1:0],
    input logic [ARCH_WIDTH-1:0]rs_arch2[WAY-1:0],
    input logic [ARCH_WIDTH-1:0] rd_arch[WAY-1:0],
    input logic [PRF_WIDTH-1:0] new_phy_reg[WAY-1:0],

    //input logic rd_en,
    //output logic rd_valid,
    output logic [PRF_WIDTH-1:0] rs_phy1[WAY-1:0],
    output logic [PRF_WIDTH-1:0] rs_phy2[WAY-1:0],

    input logic br_mispredict_flush,
    input logic [ARCH_ENTRY-1:0][PRF_WIDTH-1:0] rrat,
    input logic [WAY-1:0]commit_valid,
    input logic [ARCH_WIDTH-1:0] commit_arch[WAY],
    input logic [PRF_WIDTH-1:0] commit_phy[WAY]
);

logic [ARCH_ENTRY-1:0][PRF_WIDTH-1:0] phy_q;

always_ff @(posedge clk) begin
    if(rst) begin
        phy_q <= '0;
    end else begin
        if(br_mispredict_flush) begin
            phy_q <= rrat;
            for(integer unsigned sc_arf=0; sc_arf < WAY; ++sc_arf) begin
                if(commit_valid[sc_arf]) begin
                    phy_q[commit_arch[sc_arf]] <= commit_phy[sc_arf];
                end else begin
                    phy_q[commit_arch[sc_arf]] <= rrat[commit_arch[sc_arf]];
                end
            end
        end else if(|en) begin
            for(integer unsigned sc_arf=0; sc_arf < WAY; sc_arf++) begin
                if(en[sc_arf]) begin
                    phy_q[rd_arch[sc_arf]] <= new_phy_reg[sc_arf];
                end
            end
        end
    end
end

always_comb begin
    for(integer unsigned sc_arf=0; sc_arf < WAY; sc_arf++) begin
        rs_phy1[sc_arf] = 'x;
        rs_phy2[sc_arf] = 'x;
    end

    for(integer unsigned sc_arf=0; sc_arf < WAY; sc_arf++) begin
        if(rs1_arch_read[sc_arf]) begin
            if(sc_arf == 0) begin
                rs_phy1[sc_arf] = phy_q[rs_arch1[sc_arf]];
            end else begin
                for(integer unsigned sc_arf_1=0; sc_arf_1 < WAY; sc_arf_1++) begin
                    if(sc_arf_1 < sc_arf) begin
                        if(rs_arch1[sc_arf] == rd_arch[sc_arf_1]) begin
                            rs_phy1[sc_arf] = new_phy_reg[sc_arf_1];
                        end else begin
                            rs_phy1[sc_arf] = phy_q[rs_arch1[sc_arf]];
                        end
                    end
                end
            end
        end
        if(rs2_arch_read[sc_arf]) begin
            if(sc_arf == 0) begin
                rs_phy2[sc_arf] = phy_q[rs_arch2[sc_arf]];  
            end else begin
                for(integer unsigned sc_arf_2=0; sc_arf_2 < WAY; sc_arf_2++) begin
                    if(sc_arf_2  < sc_arf) begin
                        if(rs_arch2[sc_arf] == rd_arch[sc_arf_2]) begin
                            rs_phy2[sc_arf] = new_phy_reg[sc_arf_2];
                        end else begin
                            rs_phy2[sc_arf] = phy_q[rs_arch2[sc_arf]];
                        end
                    end 
                end
            end
        end
    end


end

endmodule