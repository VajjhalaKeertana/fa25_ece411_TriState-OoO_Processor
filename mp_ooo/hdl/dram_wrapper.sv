module dram_wrapper
(
    input  logic         clk,
    input  logic         rst,

    input  logic  [31:0] imem_addr,
    output logic [255:0] imem_rdata,
    output logic         imem_resp,
    input  logic         iq_empty,
    input  logic         imem_req,

    input  logic  [31:0] dmem_addr,
    output logic [255:0] dmem_rdata,
    output logic         dmem_resp,
    input  logic         dmem_req,
    input  logic [255:0] dmem_wdata,
    input  logic         dmem_write_req,

    output logic  [31:0] bmem_addr,
    output logic         bmem_read,
    output logic         bmem_write,
    output logic  [63:0] bmem_wdata,
    input  logic         bmem_ready,

    input  logic  [31:0] bmem_raddr,
    input  logic  [63:0] bmem_rdata,
    input  logic         bmem_rvalid,

    output logic  [1:0]  grant_lock,
    input logic  [31:0]   incoming_prefetcher_addr,
    output logic [31:0]  prefetch_addr,
    output logic [255:0] prefetch_rdata,
    output logic         prefetch_resp
);

    logic imem_req_q, dcache_read_req_q, dcache_write_req_q;
    logic dcache_read_req, dcache_write_req;
    logic start_icache_read, start_dcache_read, start_dcache_write;
    logic icache_valid;
    logic [31:5] icache_line_tag;
    logic icache_sent;
    logic [1:0] icache_bursts_received;
    logic [255:0] icache_line_data;
    logic dcache_valid;
    logic dcache_is_write;
    logic [31:5] dcache_line_tag;
    logic [1:0] dcache_bursts_sent;
    logic dcache_read_sent;
    logic [1:0] dcache_bursts_received;
    logic [255:0] dcache_line_data;
    logic prefetch_valid;
    logic [31:5] prefetch_tag;
    logic prefetch_sent;
    logic [1:0] prefetch_bursts_received;
    logic [255:0] prefetch_data_buf;
    logic prefetch_done;
    logic prefetch_matches_imem;
    logic prefetch_busy; 

    assign dcache_read_req  = dmem_req && !dmem_write_req;
    assign dcache_write_req = dmem_req &&  dmem_write_req;
    assign prefetch_matches_imem = prefetch_valid && (prefetch_tag == imem_addr[31:5]);
    assign prefetch_busy = prefetch_valid && !prefetch_done;

    logic icache_read_done;
    logic dcache_read_done;
    logic dcache_write_done;

    assign grant_lock = { dcache_valid, icache_valid };
    assign start_icache_read  = imem_req && !imem_req_q && !icache_valid && !prefetch_matches_imem;
    assign start_dcache_read  = dcache_read_req  && !dcache_read_req_q  && !dcache_valid;
    assign start_dcache_write = dcache_write_req && !dcache_write_req_q && !dcache_valid;

    logic icache_needs_issue;
    logic dcache_needs_issue;
    logic dcache_write_ongoing;
    logic issue_ic;
    logic issue_dc;
    logic issue_pref;

    assign icache_needs_issue = icache_valid && !icache_sent;
    assign dcache_needs_issue = dcache_valid && (dcache_is_write?(dcache_bursts_sent <= 2'd3): !dcache_read_sent);
    assign dcache_write_ongoing = dcache_valid && dcache_is_write && (dcache_bursts_sent != 2'd0);
    always_comb begin
        bmem_addr = '0;
        bmem_read = 1'b0;
        bmem_write = 1'b0;
        bmem_wdata = '0;
        issue_ic = 1'b0;
        issue_dc = 1'b0;
        issue_pref = 1'b0;
        if (bmem_ready) begin
            if (dcache_write_ongoing) begin
                issue_dc = 1'b1;
            end
            else if (icache_needs_issue && iq_empty) begin
                issue_ic = 1'b1;
            end
            else if (dcache_needs_issue) begin
                issue_dc = 1'b1;
            end
            else if (icache_needs_issue) begin
                issue_ic = 1'b1;
            end
            else if (prefetch_valid && !prefetch_sent) begin
                issue_pref = 1'b1;
            end
        end
        if (issue_ic) begin
            bmem_addr = {icache_line_tag, 5'b0};
            bmem_read = 1'b1;
        end
        else if (issue_dc) begin
            bmem_addr = {dcache_line_tag, 5'b0};
            if (dcache_is_write) begin
                bmem_write = 1'b1;
                bmem_wdata = dcache_line_data[dcache_bursts_sent*64 +: 64];
            end
            else begin
                bmem_read = 1'b1;
            end
        end
        else if (issue_pref) begin
            bmem_addr = {prefetch_tag, 5'b0};
            bmem_read = 1'b1;
        end
    end

    always_comb begin
        imem_rdata = '0;
        imem_resp = 1'b0;
        icache_read_done = 1'b0;
        dmem_rdata = '0;
        dmem_resp = 1'b0;
        dcache_read_done = 1'b0;
        dcache_write_done = 1'b0;
        prefetch_rdata = '0;
        prefetch_resp = 1'b0;
        prefetch_done = 1'b0;
        prefetch_addr = '0;
        if (prefetch_valid && bmem_rvalid && (bmem_raddr[31:5] == prefetch_tag)) begin
            if (prefetch_bursts_received == 2'd3) begin
                prefetch_resp = 1'b1;
                prefetch_done = 1'b1;
                prefetch_rdata = prefetch_data_buf;
                prefetch_rdata[192 +: 64] = bmem_rdata;
                prefetch_addr = bmem_raddr;
            end
        end

        if (icache_valid && bmem_rvalid && (bmem_raddr[31:5] == icache_line_tag)) begin
            if (icache_bursts_received == 2'd3) begin
                imem_resp = 1'b1;
                icache_read_done = 1'b1;
                imem_rdata = icache_line_data;
                imem_rdata[192 +: 64] = bmem_rdata;
            end
        end
        else if (prefetch_matches_imem && prefetch_done && imem_req) begin
            imem_resp  = 1'b1;
            imem_rdata = prefetch_rdata;
        end
        if (dcache_valid && !dcache_is_write &&
            bmem_rvalid && (bmem_raddr[31:5] == dcache_line_tag)) begin
            if (dcache_bursts_received == 2'd3) begin
                dmem_resp = 1'b1;
                dcache_read_done = 1'b1;
                dmem_rdata = dcache_line_data;
                dmem_rdata[192 +: 64] = bmem_rdata;
            end
        end
        if (issue_dc && dcache_is_write && (dcache_bursts_sent == 2'd3)) begin
            dmem_resp = 1'b1;
            dcache_write_done = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            imem_req_q <= 1'b0;
            dcache_read_req_q <= 1'b0;
            dcache_write_req_q <= 1'b0;
            icache_valid <= 1'b0;
            icache_line_tag <= '0;
            icache_sent <= 1'b0;
            icache_bursts_received <= '0;
            icache_line_data <= '0;
            dcache_valid <= 1'b0;
            dcache_is_write <= 1'b0;
            dcache_line_tag <= '0;
            dcache_bursts_sent <= '0;
            dcache_read_sent <= 1'b0;
            dcache_bursts_received <= '0;
            dcache_line_data <= '0;

            prefetch_valid <= 1'b0;
            prefetch_tag <= '0;
            prefetch_sent <= 1'b0;
            prefetch_bursts_received <= '0;
            prefetch_data_buf <= '0;
        end
        else begin
            imem_req_q <= imem_req;
            dcache_read_req_q <= dcache_read_req;
            dcache_write_req_q <= dcache_write_req;
            if (start_icache_read) begin
                icache_valid <= 1'b1;
                icache_line_tag <= imem_addr[31:5];
                icache_sent <= 1'b0;
                icache_bursts_received <= 2'd0;
                if (!prefetch_busy) begin
                    prefetch_valid <= 1'b1;
                    prefetch_tag <= incoming_prefetcher_addr[31:5];
                    prefetch_sent <= 1'b0;
                    prefetch_bursts_received <= 2'd0;
                end
            end
            else if (prefetch_matches_imem && prefetch_done && imem_req) begin
                prefetch_valid <= 1'b1;
                prefetch_tag <= incoming_prefetcher_addr[31:5];
                prefetch_sent <= 1'b0;
                prefetch_bursts_received <= 2'd0;
            end
            else if (prefetch_done) begin
                prefetch_valid <= 1'b0;
            end
            if (start_dcache_read) begin
                dcache_valid           <= 1'b1;
                dcache_is_write        <= 1'b0;
                dcache_line_tag        <= dmem_addr[31:5];
                dcache_read_sent       <= 1'b0;
                dcache_bursts_received <= 2'd0;
            end
            if (start_dcache_write) begin
                dcache_valid       <= 1'b1;
                dcache_is_write    <= 1'b1;
                dcache_line_tag    <= dmem_addr[31:5];
                dcache_bursts_sent <= 2'd0;
                dcache_line_data   <= dmem_wdata;
            end
            if (issue_ic) begin
                icache_sent <= 1'b1;
            end
            if (issue_pref) begin
                prefetch_sent <= 1'b1;
            end
            if (issue_dc) begin
                if (dcache_is_write) begin
                    dcache_bursts_sent <= dcache_bursts_sent + 2'd1;
                end
                else begin
                    dcache_read_sent <= 1'b1;
                end
            end
            if (bmem_rvalid) begin
                if (icache_valid && (bmem_raddr[31:5] == icache_line_tag)) begin
                    icache_line_data[icache_bursts_received*64 +: 64] <= bmem_rdata;
                    icache_bursts_received <= icache_bursts_received + 2'd1;
                end
                if (dcache_valid && !dcache_is_write && (bmem_raddr[31:5] == dcache_line_tag)) begin
                    dcache_line_data[dcache_bursts_received*64 +: 64] <= bmem_rdata;
                    dcache_bursts_received <= dcache_bursts_received + 2'd1;
                end
                if (prefetch_valid && (bmem_raddr[31:5] == prefetch_tag)) begin
                    prefetch_data_buf[prefetch_bursts_received*64 +: 64] <= bmem_rdata;
                    prefetch_bursts_received <= prefetch_bursts_received + 2'd1;
                end
            end
            if (icache_read_done) begin
                icache_valid <= 1'b0;
            end
            if (dcache_read_done) begin
                dcache_valid <= 1'b0;
            end
            if (dcache_write_done) begin
                dcache_valid <= 1'b0;
            end
        end
    end

endmodule : dram_wrapper