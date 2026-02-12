module rat_ff #(
    parameter DATA_WIDTH = 32,
    parameter ARCH_ENTRY = 32,
    parameter ARCH_WIDTH = $clog2(ARCH_ENTRY),
    parameter PRF_ENTRY = 128,
    parameter PRF_WIDTH = $clog2(PRF_ENTRY)
)(
    input logic clk,
    input logic rst,

    input logic [ARCH_WIDTH-1:0] row_idx,

    input logic rename_en,
    input logic [ARCH_WIDTH-1:0] arch_reg,
    input logic [PRF_WIDTH-1:0] new_phy_reg,

    output logic [ARCH_WIDTH-1:0] arch_q,
    output logic [PRF_WIDTH-1:0] phy_q
);

always_ff @(posedge clk) begin
    if(rst) begin
        arch_q <= row_idx;
        phy_q <= '0;
    end else begin
        if(rename_en && (row_idx == arch_reg)) begin
            phy_q <= new_phy_reg;
        end
    end
end

endmodule