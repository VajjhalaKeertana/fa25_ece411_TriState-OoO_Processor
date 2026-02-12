module cacheline_adapter
(
    input   logic           clk,
    input   logic           rst,

    input  logic   [31:0]  umem_addr,
    input  logic           umem_read,
    input  logic           umem_write,
    input  logic   [255:0] umem_wdata,

    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid,

    output  logic   [31:0]  bmem_addr,
    output  logic           bmem_read,
    output   logic   [255:0] umem_rdata,
    output   logic           umem_resp,
    
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata
);

logic [2:0] burst_counter_read;
logic [2:0] burst_counter_write;
logic pulse_umem_read;
logic umem_resp_assign;
assign umem_resp_assign = umem_resp;

always_ff @(posedge clk) begin
    if (rst) begin
        umem_rdata <= '0;
         umem_resp <='0;
        burst_counter_read <= '0;
        burst_counter_write <= '0;
        pulse_umem_read <= 1'b1;
    end else begin
         umem_resp <= 1'b0;
        pulse_umem_read <= 1'b1;
        if(umem_read) begin
            pulse_umem_read <= 1'b0;
        end
        if (bmem_rvalid) begin
            umem_rdata[burst_counter_read*64 +: 64] <= bmem_rdata;
            burst_counter_read <= burst_counter_read + 3'd1;
            if (burst_counter_read == 3'd3) begin
                 umem_resp <= 1'b1;
                burst_counter_read <= '0;
            end
        end else if(umem_write && !umem_resp_assign) begin
            // bmem_wdata <= umem_wdata[burst_counter_write*64 +: 64];
            burst_counter_write <= burst_counter_write + 3'b1;
            if (burst_counter_write == 3'd3) begin
                 umem_resp <= 1'b1;
                burst_counter_write <= '0;
            end
        end
    end
end

always_comb begin
    bmem_addr = '0;
    bmem_read = '0;
    bmem_write = '0;
    bmem_wdata = '0;
   // umem_resp = 1'b0;

    if(umem_write && !umem_resp_assign) begin
        bmem_addr = umem_addr;
        bmem_write = umem_write;
        bmem_read = '0;
        bmem_wdata = umem_wdata[burst_counter_write*64 +: 64];
    end else if(umem_read & pulse_umem_read && !umem_resp_assign) begin
        bmem_addr = umem_addr;
        bmem_read = umem_read;
        bmem_write = '0;
    end
    // if (burst_counter_write + 'd1 == 'd4) begin
    //     umem_resp = 1'b1;
    // end
    // if (burst_counter_read + 'd1 == 'd4) begin
    //     umem_resp = 1'b1;
    //     //burst_counter_read <= '0;
    // end

end

endmodule : cacheline_adapter