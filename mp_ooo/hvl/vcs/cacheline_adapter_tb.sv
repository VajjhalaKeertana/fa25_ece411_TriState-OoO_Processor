module cacheline_adapter_tb;
    timeunit 1ps;
    timeprecision 1ps;

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    logic clk=1'b0;
    logic rst=1'b1;
    always #5 clk=~clk;

    logic [31:0] dfp_addr;
    logic dfp_read;
    logic dfp_write;
    logic [255:0] dfp_wdata;
    logic [63:0]  bmem_rdata;
    logic bmem_rvalid;

    logic [31:0] bmem_addr;
    logic bmem_read;
    logic [255:0] dfp_rdata;
    logic dfp_resp;

    logic bmem_write;
    logic [63:0] bmem_wdata;

    cacheline_adapter dut (
        .clk(clk), .rst(rst),
        .dfp_addr(dfp_addr),
        .dfp_read(dfp_read),
        .dfp_write(dfp_write),
        .dfp_wdata(dfp_wdata),
        .bmem_rdata(bmem_rdata),
        .bmem_rvalid(bmem_rvalid),
        .bmem_addr(bmem_addr),
        .bmem_read(bmem_read),
        .dfp_rdata(dfp_rdata),
        .dfp_resp(dfp_resp),
        .bmem_write(bmem_write),
        .bmem_wdata(bmem_wdata)
    );

    initial begin
        dfp_addr   = 32'h00402000;
        dfp_read   = 1'b0;
        dfp_write  = 1'b0;
        dfp_wdata  = '0;
        bmem_rdata = '0;
        bmem_rvalid= 1'b0;

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        $display("%0t Reset deasserted", $time);

        $display("4-beat read burst");
        dfp_read<=1'b1;
        @(posedge clk);
        dfp_read<=1'b1;
        @(posedge clk);
        bmem_rdata<=64'h1111111111111111;
        bmem_rvalid<=1'b1;
        @(posedge clk); 
        bmem_rdata<=64'h2222222222222222; 
        bmem_rvalid<=1'b1;
        @(posedge clk);
        bmem_rdata<=64'h3333333333333333;
        bmem_rvalid<=1'b1;
        @(posedge clk);
        bmem_rdata<=64'h4444444444444444;
        bmem_rvalid<=1'b1;
        @(posedge clk);
        bmem_rvalid<=1'b0;
        dfp_read<=1'b0;

        @(posedge clk);
        if(!dfp_resp) begin
            $display("DFP Resp is missing");
        end
        if(dfp_rdata!={64'h4444444444444444, 64'h3333333333333333, 64'h2222222222222222, 64'h1111111111111111}) begin
            $display("Data mismatch");
        end else begin
            $display("Data is aligned");
        end

        $display("4-bead write burst");
        dfp_wdata<={64'h4444000044444444, 64'h3333300000033333, 64'h2222200000002222, 64'h1111111000011111};
        @(posedge clk);
        dfp_write<=1'b1;
        @(posedge clk);
        if(bmem_wdata!=64'h1111111000011111) begin
            $display("beat0 mismatch seen");
        end
        if(bmem_write || bmem_addr!=dfp_addr) begin
            $display("bmem_write/addr not asserted correctly on beat0");
        end
        if(bmem_wdata!=64'h2222200000002222) begin
            $display("beat1 mismatch seen");
        end
        if(bmem_wdata!=64'h3333300000033333) begin
            $display("beat2 mismatch seen");
        end
        if(bmem_wdata!=64'h4444000044444444) begin
            $display("beat3 mismatch seen");
        end
        @(posedge clk);
        if(!dfp_resp) begin
            $display("DFP Resp is missing");
        end
        @(posedge clk);
        dfp_write <= 1'b0;

        $finish;
    end

endmodule