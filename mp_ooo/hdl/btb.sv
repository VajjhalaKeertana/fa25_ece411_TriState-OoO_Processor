module btb #(
    parameter integer ENTRIES  = 8,
    parameter integer DATA_W   = 66
)(
    input logic clk,
    input logic rst,

    input logic [31:0] pc,
    input logic pc_valid,

    output logic btb_hit,
    output logic [31:0] btb_target,
    output logic  pc_valid_resp,

    //input logic c_valid,
    input logic c_is_branch,
    input logic c_taken,
    input logic [31:0] c_pc,
    input logic [31:0] c_target,

    input logic  br_mispredict_flush
);

localparam integer IDX_W = $clog2(ENTRIES);

logic [IDX_W-1:0] rd_idx;
logic [IDX_W-1:0] wr_idx;

assign rd_idx = pc[IDX_W+1:2];
assign wr_idx = c_pc[IDX_W+1:2];

logic upd_en;
assign upd_en = c_is_branch && c_taken && br_mispredict_flush;

logic csb0, web0;
logic [IDX_W-1:0] addr0;
logic [DATA_W-1:0] din0;
logic [DATA_W-1:0] dout0;

logic csb1, web1;
logic [IDX_W-1:0] addr1;
logic [DATA_W-1:0] din1;
logic [DATA_W-1:0] dout1;

assign csb0  = ~pc_valid;
assign web0  = 1'b1;
assign addr0 = rd_idx;
assign din0  = '0; 

assign csb1 = ~upd_en;
assign web1 = 1'b0;
assign addr1 = wr_idx;
assign din1 = {1'b1, c_pc, c_target, 1'b0};

logic v_csb0, v_web0;
logic [IDX_W-1:0] v_addr0;
logic v_din0;
logic v_dout0;

logic v_csb1, v_web1;
logic [IDX_W-1:0] v_addr1;
logic v_din1;
logic v_dout1;

assign v_csb0 = ~pc_valid;
assign v_web0 = 1'b1;
assign v_addr0 = rd_idx;
assign v_din0 = 1'b0;

assign v_csb1 = ~upd_en;
assign v_web1 = 1'b0;
assign v_addr1 = wr_idx;
assign v_din1 = 1'b1;

btb_ff_array #(
    .S_INDEX(IDX_W),
    .WIDTH(1)
) valid_array (
    .clk  (clk),
    .rst  (rst),

    .csb0 (v_csb0),
    .web0 (v_web0),
    .addr0(v_addr0),
    .din0 (v_din0),
    .dout0(v_dout0),

    .csb1 (v_csb1),
    .web1 (v_web1),
    .addr1(v_addr1),
    .din1 (v_din1),
    .dout1(v_dout1)
);

btb_ff_array #(
    .WIDTH(DATA_W),
    .S_INDEX(IDX_W)
) sram (
    .clk   (clk),
    .rst   (rst),

    .csb0  (csb0),
    .web0  (web0),
    .addr0 (addr0),
    .din0  (din0),
    .dout0 (dout0),

    .csb1  (csb1),
    .web1  (web1),
    .addr1 (addr1),
    .din1  (din1),
    .dout1 (dout1)
);


logic [31:0] pc_q;
logic rd_req_q;
logic valid_dout_q;

always_ff @(posedge clk) begin
    if (rst) begin
        pc_q <= '0;
        rd_req_q <= 1'b0;
        valid_dout_q <= 1'b0;
    end else begin
        if (pc_valid)
            pc_q <= pc;
        rd_req_q  <= pc_valid;
        valid_dout_q <= v_dout0;
    end
end

wire [31:0] mem_tag = dout0[64:33];
wire [31:0] mem_target = dout0[32:1];

always_comb begin
    btb_hit    = 1'b0;
    btb_target = 32'h0;

    if (pc_valid && v_dout0 && (mem_tag == pc) && (mem_tag != '0)) begin
        btb_hit = 1'b1;
        btb_target = mem_target;
    end
end

always_ff @(posedge clk) begin
    if (rst)
        pc_valid_resp <= 1'b0;
    else
        pc_valid_resp <= btb_hit;
end

endmodule
