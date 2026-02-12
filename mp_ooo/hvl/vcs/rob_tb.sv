module rob_tb;

    timeunit 1ps;
    timeprecision 1ps;

    localparam int ARCH_ENTRY = 32;
    localparam int ARCH_WIDTH = $clog2(ARCH_ENTRY);
    localparam int PRF_ENTRY = 64;
    localparam int PRF_WIDTH = $clog2(PRF_ENTRY);
    localparam int ROB_ENTRY = 4;
    localparam int ROB_WIDTH = $clog2(ROB_ENTRY);
    localparam int NUM_CDB = 2;

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    logic clk=1'b0;
    logic rst=1'b1;
    always #5 clk=~clk;

    typedef struct packed {
        logic [ARCH_WIDTH-1:0] arch;
        logic [PRF_WIDTH-1:0] phy;
        logic br_pred_valid;
        logic br_pred_taken;
    } ren_item_t;

    // rename
    logic ren_en;
    ren_item_t ren_item;
    logic [ROB_WIDTH-1:0] ren_rob_id;
    logic ren_resp;
    logic ren_full;
    logic [1:0] ren_status;

    // exec + CDB
    logic [NUM_CDB-1:0] cdb_valid;
    logic [ROB_WIDTH-1:0] cdb_rob_id [NUM_CDB-1:0];

    // commit
    logic commit_valid;
    logic [ROB_WIDTH-1:0] commit_rob_id;
    struct packed {
        logic [ARCH_WIDTH-1:0] arch;
        logic [PRF_WIDTH-1:0]  phy;
    } commit_item;

    rob #(
        .ARCH_ENTRY (ARCH_ENTRY),
        .ARCH_WIDTH (ARCH_WIDTH),
        .PRF_ENTRY  (PRF_ENTRY),
        .PRF_WIDTH  (PRF_WIDTH),
        .ROB_ENTRY  (ROB_ENTRY),
        .ROB_WIDTH  (ROB_WIDTH),
        .CHANNELS    (NUM_CDB)
    ) dut (

    .clk          (clk),
  .rst          (rst),

  // rename -> enqueue at tail
  .ren_en       (ren_en),
  .ren_input    (ren_item),
  .ren_resp     (ren_resp),
  .ren_full     (ren_full),
  .ren_status   (ren_status),

  // CDB lanes
  .cdb_valid    (cdb_valid), 
  .cdb_rob_id   (cdb_rob_id),

  // auto-commit outputs
  .commit_valid (commit_valid),
  .commit_arch  (commit_item.arch),
  .commit_phy   (commit_item.phy),

  // tail ROB index (exposed)
  .rob_id_tail  (ren_rob_id)
    );

    initial begin
        ren_en =  '0;
        ren_item = '0;
        cdb_valid = '0;
        cdb_rob_id = '{default: '0};

        repeat (3) @(posedge clk);
        rst = 0; @(posedge clk);

        //enqueue T1
        ren_item = '{arch: 5, phy: 11, br_pred_valid:0, br_pred_taken:0};
        ren_en = 1'b1;
        @(posedge clk);
        ren_en = 1'b0;
        if(!ren_resp) begin
            $display("T1: enqueue not accepted");
        end else begin
            $display("T1: enqueue completed");
        end
        if (ren_rob_id !== '0) begin
            $display("T1: expected first ROB id 0, got %0d", ren_rob_id);
        end
        if (commit_valid) begin
            $display("T1: should not commit until ready");
        end
        $display("Testing is done");
        $finish;
    end

endmodule