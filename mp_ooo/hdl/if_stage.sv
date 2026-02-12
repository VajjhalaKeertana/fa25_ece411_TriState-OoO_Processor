module if_stage
(
  input   logic   [31:0]  pc,
  input   logic   [31:0]  pc_next,
  input   logic   [1:0]   iq_status,
  input   logic           icache_resp,
  output  logic   [31:0]  imem_addr,
  output  logic   [3:0]   imem_mask,
  input logic stall
);
  // What to set imem_mask to?
  // What is imem_stall?
  always_comb begin
      imem_addr = pc;
      imem_mask = (iq_status != 2'b10 && !stall) ? 4'b1111 : 4'b0000;
      if(icache_resp) begin
        imem_addr = pc_next;
      end
  end
endmodule : if_stage