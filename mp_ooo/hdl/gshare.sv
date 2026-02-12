module gshare_predictor #(
    parameter integer HISTORY_BITS = 8,
    parameter integer NUM_WAYS     = 2
) (
    input  logic clk,
    input  logic rst,
    
    input  logic [31:0] pc,
    input  logic pc_valid,
    output logic pred_valid,
    output logic pred_taken,

    output logic [HISTORY_BITS-1:0] pred_index,
    //input  logic c_resolve_valid,
    input  logic  c_is_branch,
    input  logic c_taken,
    input  logic [HISTORY_BITS-1:0] c_index
);

localparam integer PHT_ENTRIES = (1 << HISTORY_BITS);

logic [HISTORY_BITS-1:0] ghr;
logic [1:0] pht[PHT_ENTRIES-1:0];
logic [HISTORY_BITS-1:0] ghr_tmp;
logic [HISTORY_BITS-1:0] pc_idx;
logic [HISTORY_BITS-1:0] index;
logic [1:0] ctr;

always_comb begin
    pc_idx = pc[HISTORY_BITS+1 : 2];
    index = pc_idx ^ ghr;
    pred_index = index;
    pred_valid = pc_valid;
    if (pc_valid)
        pred_taken = pht[index][1];
    else
        pred_taken = 1'b0;
end

always_ff @(posedge clk) begin
    if (rst) begin
        ghr <= '0;
        for (integer i = 0; i < PHT_ENTRIES; i++)
            pht[i] <= 2'b01;
    end else begin
        ghr_tmp = ghr;
        if (c_is_branch) begin
            ctr = pht[c_index];
            if (c_taken) begin
                if (ctr != 2'b11) 
                    ctr = ctr + 2'b01;
            end else begin
                if (ctr != 2'b00) 
                    ctr = ctr - 2'b01;
            end
            pht[c_index] <= ctr;
            ghr_tmp = {ghr_tmp[HISTORY_BITS-2:0], c_taken};
        end
        ghr <= ghr_tmp;
    end
end

endmodule
