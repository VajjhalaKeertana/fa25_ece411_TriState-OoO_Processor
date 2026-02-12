module btb_ff_array #(
    parameter S_INDEX = 4,
    parameter WIDTH   = 60
)(
    input logic clk,
    input logic rst,

    input  logic csb0,
    input  logic web0,
    input  logic [S_INDEX-1:0] addr0,
    input  logic [WIDTH-1:0] din0,
    output logic [WIDTH-1:0] dout0,

    input logic csb1,
    input logic web1,
    input logic [S_INDEX-1:0] addr1,
    input logic [WIDTH-1:0] din1,
    output logic [WIDTH-1:0] dout1
);

localparam integer NUM_SETS = 2 ** S_INDEX;
logic [WIDTH-1:0] mem [NUM_SETS-1:0];

logic web0_r, web1_r;
logic [S_INDEX-1:0] addr0_r, addr1_r;
logic [WIDTH-1:0] din0_r, din1_r;

always_comb begin
    web0_r  = 1'b1;
    web1_r  = 1'b1;
    addr0_r = '0;
    addr1_r = '0;
    din0_r  = '0;
    din1_r  = '0;
    if (!csb0) begin
        web0_r  = web0;
        addr0_r = addr0;
        din0_r  = din0;
    end
    if (!csb1) begin
        web1_r  = web1;
        addr1_r = addr1;
        din1_r  = din1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        for (integer i = 0; i < NUM_SETS; i++)
            mem[i] <= '0;
    end else begin
        unique case ({~web1_r, ~web0_r})
            2'b01: mem[addr0_r] <= din0_r;
            2'b10: mem[addr1_r] <= din1_r;
            2'b11: begin
                if (addr0_r != addr1_r) begin
                    mem[addr0_r] <= din0_r;
                    mem[addr1_r] <= din1_r;
                end else begin
                    mem[addr0_r] <= 'x;
                end
            end
            default: ;
        endcase
    end
end

always_comb begin
    dout0 = mem[addr0_r];
    dout1 = mem[addr1_r];
end

endmodule
