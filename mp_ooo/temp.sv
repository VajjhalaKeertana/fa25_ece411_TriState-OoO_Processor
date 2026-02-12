module cache_arbiter
#(
    parameter FIFO_DEPTH = 4
)
(
    input  logic          clk,
    input  logic          rst,

    // I-cache side
    input  logic  [31:0]  imem_addr,
    output logic  [255:0] imem_rdata,
    output logic          imem_resp,
    input  logic          iq_empty,
    input  logic          imem_req,

    // D-cache side
    input  logic  [31:0]  dmem_addr,
    output logic  [255:0] dmem_rdata,
    output logic          dmem_resp,
    input  logic          dmem_req,
    input  logic  [255:0] dmem_wdata,
    input  logic          dmem_write_req,

    // Unified memory
    output logic  [31:0]  umem_addr,
    input  logic  [255:0] umem_rdata,
    output logic  [255:0] umem_wdata,
    input  logic          umem_resp,
    output logic          umem_read,
    output logic          umem_write,

    // Existing input (unused here, keep for compatibility)
    input  logic          lsq_access_complete,

    // NEW: branch mispredict flush
    input  logic          br_mis_predict_flush,

    // Who currently holds the memory lock
    output logic  [1:0]   grant_lock
);

    typedef enum logic [1:0] {
        GNT_NONE = 2'd0,
        GNT_IC   = 2'd1,
        GNT_DC   = 2'd2
    } grant_t;

    // ---------------------------
    // FIFO of pending requests
    // ---------------------------
    typedef struct packed {
        grant_t       src;       // GNT_IC or GNT_DC
        logic         is_write;  // 1 = write, 0 = read
        logic [31:0]  addr;
        logic [255:0] wdata;
    } req_t;

    localparam int FIFO_IDX_W = (FIFO_DEPTH < 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam int COUNT_W    = $clog2(FIFO_DEPTH + 1);

    req_t                   fifo [FIFO_DEPTH];
    logic [FIFO_IDX_W-1:0]  head;
    logic [FIFO_IDX_W-1:0]  tail;
    logic [COUNT_W-1:0]     count;

    // Current in-flight transaction to umem
    grant_t                 grant_sel;      // which side is being served
    logic                   active_valid;   // 1 = umem has an outstanding req

    // When a branch mispredict happens while a req is in flight:
    //  - we keep that req running to memory
    //  - but when umem_resp comes, we DROP the result instead of sending it up
    logic                   flush_pending;  // drop current head when resp comes

    // ---------------------------
    // Main sequential logic
    // ---------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            head          <= '0;
            tail          <= '0;
            count         <= '0;

            grant_sel     <= GNT_NONE;
            grant_lock    <= 2'b00;
            active_valid  <= 1'b0;
            flush_pending <= 1'b0;

            umem_addr     <= '0;
            umem_wdata    <= '0;
            umem_read     <= 1'b0;
            umem_write    <= 1'b0;
        end else begin
            // -------------------------------
            // Highest priority: branch flush
            // -------------------------------
            if (br_mis_predict_flush) begin
                // Flush everything behind the current head
                head  <= '0;
                tail  <= '0;
                count <= '0;

                // If a request is already in-flight, mark it so that
                // its response will be ignored when it comes back.
                if (active_valid)
                    flush_pending <= 1'b1;
            end else begin
                // ---------------------------------
                // 1) Enqueue new requests (FIFO)
                // ---------------------------------
                req_t tmp_req;
                logic tmp_valid;

                tmp_valid = 1'b0;

                // Only enqueue if we are not in the middle of dropping stuff
                // and FIFO has space.
                if (!flush_pending && (count < FIFO_DEPTH)) begin
                    // Same priority as your original arb:
                    //  - If IQ empty and I-cache wants something, give I$
                    //  - Else if both request, give D$
                    //  - Else D$
                    //  - Else I$
                    if (iq_empty && imem_req) begin
                        tmp_valid        = 1'b1;
                        tmp_req.src      = GNT_IC;
                        tmp_req.is_write = 1'b0;
                        tmp_req.addr     = imem_addr;
                        tmp_req.wdata    = '0;
                    end else if (dmem_req && imem_req) begin
                        tmp_valid        = 1'b1;
                        tmp_req.src      = GNT_DC;
                        tmp_req.is_write = dmem_write_req;
                        tmp_req.addr     = dmem_addr;
                        tmp_req.wdata    = dmem_wdata;
                    end else if (dmem_req) begin
                        tmp_valid        = 1'b1;
                        tmp_req.src      = GNT_DC;
                        tmp_req.is_write = dmem_write_req;
                        tmp_req.addr     = dmem_addr;
                        tmp_req.wdata    = dmem_wdata;
                    end else if (imem_req) begin
                        tmp_valid        = 1'b1;
                        tmp_req.src      = GNT_IC;
                        tmp_req.is_write = 1'b0;
                        tmp_req.addr     = imem_addr;
                        tmp_req.wdata    = '0;
                    end
                end

                if (tmp_valid) begin
                    fifo[tail] <= tmp_req;
                    tail       <= (tail == FIFO_DEPTH-1) ? '0 : tail + 1;
                    count      <= count + 1;
                end

                // ---------------------------------
                // 2) Complete current transaction
                // ---------------------------------
                if (active_valid && umem_resp) begin
                    active_valid <= 1'b0;
                    grant_sel    <= GNT_NONE;
                    grant_lock   <= 2'b00;
                    umem_read    <= 1'b0;
                    umem_write   <= 1'b0;

                    // If this response was for a mispred path, just drop it
                    // (flush_pending prevents resp from going to I/D cache).
                    if (flush_pending)
                        flush_pending <= 1'b0;
                end

                // ---------------------------------
                // 3) Start next transaction from FIFO
                // ---------------------------------
                // Note: we deliberately introduce a 1-cycle bubble between
                // finishing one line and starting the next; that keeps logic simple.
                if (!active_valid && (count != 0)) begin
                    req_t q = fifo[head];

                    active_valid <= 1'b1;
                    grant_sel    <= q.src;
                    grant_lock   <= (q.src == GNT_IC) ? 2'b01 : 2'b10;

                    umem_addr    <= q.addr;
                    umem_wdata   <= q.wdata;
                    umem_read    <= !q.is_write;
                    umem_write   <=  q.is_write;

                    head  <= (head == FIFO_DEPTH-1) ? '0 : head + 1;
                    count <= count - 1;
                end
            end
        end
    end

    // ---------------------------------
    // Combinational: route data back up
    // ---------------------------------
    always_comb begin
        imem_rdata = '0;
        imem_resp  = 1'b0;
        dmem_rdata = '0;
        dmem_resp  = 1'b0;

        // Only forward response if:
        //  - we have an active request,
        //  - AND it's not marked for flush (wrong-path)
        if (active_valid && !flush_pending) begin
            unique case (grant_sel)
                GNT_IC: begin
                    imem_rdata = umem_rdata;
                    imem_resp  = umem_resp;
                end
                GNT_DC: begin
                    dmem_rdata = umem_rdata;
                    dmem_resp  = umem_resp;
                end
                default: ; // no-op
            endcase
        end
    end

endmodule : cache_arbiter
