module instruction_queue_tb;
    timeunit 1ps;
    timeprecision 1ps;

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    logic clk=1'b0;
    logic rst=1'b1;
    always #5 clk=~clk;

    logic [31:0] imem_rdata;
    logic imem_resp;
    logic iq_pop;
    logic [31:0] iq_rdata;
    logic iq_resp;

    localparam DEPTH=32;
    localparam WIDTH=$clog2(DEPTH);

    instruction_queue #(
      .DEPTH (DEPTH),
      .WIDTH (WIDTH)
    ) dut(
    .clk        (clk),
    .rst        (rst),
    .imem_rdata (imem_rdata),
    .imem_resp  (imem_resp),
    .iq_pop     (iq_pop),
    .iq_rdata   (iq_rdata),
    .iq_resp    (iq_resp)
  );

  initial begin
    imem_resp='0;
    iq_pop='0;
    imem_rdata='0;

    //Reset
    repeat (3) @(posedge clk);
    rst<=1'b0;
    $display("%0t Reset done", $time); 

    @(posedge clk);
    iq_pop<=1'b1;
    if (iq_resp) begin
      $display("%0t Cannot pop when queue is empty ", $time);
    end
    iq_pop<=1'b0;

    $display("\n Push 0xAAAA0001 then pop");
    @(posedge clk);
    imem_rdata<=32'hAAAA0001;
    imem_resp<=1'b1;
    @(posedge clk);
    imem_resp<=1'b0;
    @(posedge clk);
    iq_pop<=1'b1;
    @(posedge clk);
    iq_pop<=1'b0;
    repeat (3) @(posedge clk);

    $display("\n Pushing values into the queue");
    for(int i=0; i<DEPTH; i+=1) begin
      @(posedge clk);
      imem_rdata <= 32'ha0b0c0d0 + i;
      imem_resp <= 1'b1;
    end
    @(posedge clk);
    imem_resp <= 1'b0;

    @(posedge clk);
    for(int i=0; i<DEPTH; i+=1) begin
      @(posedge clk);
      iq_pop<=1'b1;
      $display("pop num: %0d", i);
      @(posedge clk);
      iq_pop<=1'b0;
    end
    @(posedge clk);
      iq_pop<=1'b1;
      @(posedge clk);
      iq_pop<=1'b0;
    
    $display("\n Pushing when it is full");
    @(posedge clk);
    imem_rdata<=32'hAAAA0001;
    imem_resp<=1'b1;
    @(posedge clk);
    imem_resp<=1'b0;
    @(posedge clk);
    iq_pop<=1'b1;
    @(posedge clk);
    iq_pop<=1'b0;
    @(posedge clk);
    @(posedge clk);

    repeat (2) @(posedge clk);
    @(posedge clk);
    iq_pop <= 1'b1;
    @(posedge clk);
    iq_pop <= 1'b0;
    @(posedge clk);
    iq_pop <= 1'b1;
    @(posedge clk);
    iq_pop <= 1'b0;

    repeat (4) begin
      @(posedge clk);
      iq_pop <= 1'b1;
      @(posedge clk);
      iq_pop <= 1'b0;
    end

    $display("\nAll directed tests complete");
    $finish;
  end


endmodule