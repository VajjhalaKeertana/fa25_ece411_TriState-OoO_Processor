module cache_arbiter
(
    input       logic          clk,
    input       logic          rst,

    input       logic   [31:0]  imem_addr,
    output      logic   [255:0] imem_rdata,
    output      logic           imem_resp,
    input       logic           iq_empty,
    input       logic           imem_req,

    input       logic   [31:0]  dmem_addr,
    output      logic   [255:0] dmem_rdata,
    output      logic           dmem_resp,
    input       logic           dmem_req,
    input       logic   [255:0] dmem_wdata,
    input       logic           dmem_write_req,
    
    output      logic   [31:0]  umem_addr,
    input       logic   [255:0] umem_rdata,
    output      logic   [255:0] umem_wdata,
    input       logic           umem_resp,
    output      logic           umem_read,
    output      logic           umem_write,

    output      logic   [1:0]   grant_lock
);

typedef enum logic [1:0] { GNT_NONE=2'd0, GNT_IC=2'd1, GNT_DC=2'd2 } grant_t;
logic [1:0] grant_sel;

always_ff @(posedge clk) begin
    if (rst) begin
        grant_sel   <= GNT_NONE;
        umem_addr   <= 'x;
        umem_wdata  <= '0;
        umem_read   <= 1'b0;
        umem_write  <= 1'b0;
        //imem_rdata  <= '0;
        //dmem_rdata  <= '0;
        //imem_resp   <= 1'b0;
        //dmem_resp   <= 1'b0;
        grant_lock  <= 2'b00;
    end else begin
        //imem_resp <= 1'b0;
        //dmem_resp <= 1'b0;
        case (grant_sel)
            GNT_NONE: begin
                grant_lock <= 2'b00;
                // umem_read  <= 1'b0;
                // umem_write <= 1'b0;
                umem_addr  <= '0;
                if (iq_empty && imem_req && !imem_resp) begin
                    grant_sel  <= GNT_IC;
                    grant_lock <= 2'b01;
                    umem_addr  <= imem_addr;
                    umem_wdata <= '0;
                    // umem_read  <= 1'b1;
                    // umem_write <= 1'b0;
                end else if (dmem_req && imem_req && !dmem_resp) begin
                    grant_sel  <= GNT_DC;
                    grant_lock <= 2'b10;
                    umem_addr  <= dmem_addr;
                    umem_wdata <= dmem_wdata;
                    // umem_read  <= !dmem_write_req;
                    // umem_write <=  dmem_write_req;
                end else if (dmem_req && !dmem_resp) begin
                    grant_sel  <= GNT_DC;
                    grant_lock <= 2'b10;
                    umem_addr  <= dmem_addr;
                    umem_wdata <= dmem_wdata;
                    //umem_read  <= !dmem_write_req;
                    //umem_write <=  dmem_write_req;
                end else if (imem_req && !imem_resp) begin
                    grant_sel  <= GNT_IC;
                    grant_lock <= 2'b01;
                    umem_addr  <= imem_addr;
                    umem_wdata <= '0;
                    // umem_read  <= 1'b1;
                    // umem_write <= 1'b0;
                end
            end
            GNT_IC: begin
                grant_lock <= 2'b01;
                umem_read  <= 1'b1;
                umem_write <= 1'b0;
                if (umem_resp) begin
                    //imem_rdata <= umem_rdata;
                    //imem_resp  <= 1'b1;
                    grant_sel  <= GNT_NONE;
                    grant_lock <= 2'b00;
                    umem_read  <= 1'b0;
                    umem_read  <= '0;
                    umem_write <=  '0;
                end
        
            end
            GNT_DC: begin
                grant_lock <= 2'b10;
                /*if (dmem_write_req) begin
                    umem_write <= 1'b1;
                    umem_read  <= 1'b0;
                    grant_sel  <= GNT_NONE;
                    grant_lock <= 2'b0;
                end else begin*/
                if (dmem_write_req) begin
                    umem_write <= 1'b1;
                    umem_read <= 1'b0;
                end else if(dmem_req) begin
                    umem_read  <= 1'b1;
                    umem_write <= 1'b0;
                end
                    if (umem_resp) begin
                        //dmem_rdata <= umem_rdata;
                        //dmem_resp  <= 1'b1;
                        umem_read  <= 1'b0;
                        grant_sel   <= GNT_NONE;
                        grant_lock  <= 2'b00;
                        umem_read  <= '0;
                        umem_write <=  '0;

                    end
        
                    // if(lsq_access_complete) begin
                    //     grant_sel   <= GNT_NONE;
                    //     grant_lock  <= 2'b00;
                    // end
                //end
            end
            default: begin
                grant_sel  <= GNT_NONE;
                grant_lock <= 2'b00;
            end
        endcase
    end
end

always_comb begin
    imem_rdata = '0;
    imem_resp = '0;
    dmem_rdata = '0;
    dmem_resp = '0;
    if (grant_sel == GNT_IC) begin
        imem_rdata = umem_rdata;
        imem_resp = umem_resp;
    end else if (grant_sel == GNT_DC) begin
        dmem_rdata = umem_rdata;
        dmem_resp = umem_resp;
    end
end

endmodule : cache_arbiter
