module circular_queue 
import rv32i_types::*;
#(
    parameter DEPTH = 32,
    parameter WIDTH = $clog2(DEPTH),
    parameter DATA_WIDTH = 32,
    parameter FULL_AT_RESET = 0
)
(
    input   logic               clk,
    input   logic               rst,

    input   logic   [DATA_WIDTH - 1:0]      iq_wrdata[WAY-1:0],
    input   logic               iq_push,
    input   logic               iq_pop,
    output  logic   [DATA_WIDTH - 1:0]      iq_rdata[WAY-1:0],
    output  logic               iq_resp,
    output  logic [1:0]         iq_status,
    input logic               branch_at_odd_word,
    input integer index_pc
);

//localparam DEPTH = 32;
//localparam WIDTH = $clog2(DEPTH);
localparam logic [WIDTH-1:0] LAST_PTR = DEPTH - 1;

logic [DATA_WIDTH-1:0] circular_buffer[0:DEPTH-1];
logic [WIDTH:0] head_ptr;
logic [WIDTH:0] tail_ptr;

logic [WIDTH:0] head_ptr_seq;
logic [WIDTH:0] tail_ptr_seq;

logic iq_full, iq_empty, enqueue, dequeue;
logic [WIDTH:0] num_occupied;
logic [WIDTH:0] free_slots;

always_comb begin
    num_occupied = tail_ptr - head_ptr;
    free_slots = (WIDTH+1)'(DEPTH - num_occupied); 
    iq_empty = (num_occupied < (WIDTH+1)'(WAY));
    iq_full = (free_slots < (WIDTH+1)'('d2 * WAY));
end

// always_comb begin
//     iq_full = '0;
//     iq_empty = '0;
//     if(head_ptr[WIDTH] != tail_ptr[WIDTH]) begin
//         if((head_ptr[WIDTH-1:0] == tail_ptr[WIDTH-1:0] + 'd1) || head_ptr[WIDTH-1:0] == tail_ptr[WIDTH-1:0]) begin
//             iq_full = 1'b1;
//         end
//     end else begin
//         if((tail_ptr[WIDTH-1:0] == LAST_PTR) && (head_ptr[WIDTH-1:0] == '0)) begin
//             iq_full = 1'b1;
//         end
//     end

//     if(head_ptr == tail_ptr) begin
//         iq_empty = 1'b1;
//     end else if (head_ptr[WIDTH] == tail_ptr[WIDTH]) begin
//         if(tail_ptr[WIDTH-1:0] == head_ptr[WIDTH-1:0] + (WAY - 'd1)) begin
//             iq_empty = 1'b1;
//         end
//     end else if ((head_ptr[WIDTH-1:0] == LAST_PTR) && (tail_ptr[WIDTH-1:0] < WAY - 'd1)) begin
//         iq_empty = 1'b1;
//     end

// end

//assign iq_full = (head_ptr[WIDTH] != tail_ptr[WIDTH]) && (head_ptr[WIDTH-1:0] == tail_ptr[WIDTH-1:0]);
//assign iq_empty = head_ptr == tail_ptr;

// always_ff @(posedge clk) begin
//     if(rst) begin
//         if(FULL_AT_RESET) begin
//             iq_status <= 2'b10; // full
//         end else begin
//             iq_status <= 2'b01; // empty
//         end
//     end else begin
//         if (iq_full) begin
//             iq_status <= 2'b10; // full
//         end else if (iq_empty) begin
//             iq_status <= 2'b01; // empty
//         end else begin
//             iq_status <= 2'b00; // normal   
//         end
//     end
// end

always_comb begin
    if (iq_full) begin
        iq_status = 2'b10; // full
    end else if (iq_empty) begin
        iq_status = 2'b01; // empty
    end else begin
        iq_status = 2'b00; // normal   
    end
end

always_comb begin
    for(integer unsigned sc_cq=0; sc_cq < WAY; ++sc_cq) begin
        iq_rdata[sc_cq] = '0;
    end
    iq_resp = 1'b0;
    if ((iq_pop && !iq_empty) ) begin
        if(WIDTH'(head_ptr[WIDTH-1:0] + WAY - 1'b1) <= LAST_PTR) begin
            for(integer unsigned sc_cq=0; sc_cq < WAY; ++sc_cq) begin
                iq_rdata[sc_cq] = circular_buffer[head_ptr[WIDTH-1:0] + sc_cq];
            end
        end else if (WIDTH'(head_ptr[WIDTH-1:0] + WAY - 1'b1) > LAST_PTR) begin
            for(integer unsigned sc_cq=0; sc_cq < WAY; ++sc_cq) begin
                if(head_ptr[WIDTH-1:0] + WIDTH'(sc_cq) <= LAST_PTR) begin
                    iq_rdata[sc_cq] = circular_buffer[head_ptr[WIDTH-1:0] + sc_cq];
                end else begin
                     iq_rdata[sc_cq] = circular_buffer[sc_cq - (LAST_PTR - head_ptr[WIDTH-1:0] + 'd1)];
                end
            end
        end
        iq_resp = 1'b1;
    end

end

always_ff @(posedge clk) begin
    if (rst) begin
        if(FULL_AT_RESET) begin
            head_ptr <= '0;
            tail_ptr <= {1'b1, {(WIDTH){1'b0}} };
            for (integer unsigned i = 1; i <= DEPTH; i++) begin
                circular_buffer[i-1] <= ({(DATA_WIDTH){1'b0}} | WIDTH'(i));
            end
        end else begin
            head_ptr <= '0;
            tail_ptr <= '0;
            for (integer i = 0; i < DEPTH; i++) begin
                circular_buffer[i] <= 'x;
            end
        end
    end else begin
        if (iq_push && ((free_slots != '0) || (iq_pop && !iq_empty))&& !branch_at_odd_word) begin
            if(tail_ptr[WIDTH-1:0] + WAY - 1'b1 < {{(32-WIDTH){1'b0}}, LAST_PTR}) begin
                for(integer unsigned sc_cq=0; sc_cq < WAY; ++ sc_cq) begin
                    circular_buffer[tail_ptr[WIDTH-1:0] + sc_cq] <= iq_wrdata[sc_cq];
                end
                tail_ptr <= tail_ptr + 2'd2;
            end else if (tail_ptr[WIDTH-1:0] + WAY - 1'b1 == {{(32-WIDTH){1'b0}}, LAST_PTR}) begin
                for(integer unsigned sc_cq=0; sc_cq < WAY; ++ sc_cq) begin
                    circular_buffer[tail_ptr[WIDTH-1:0] + sc_cq] <= iq_wrdata[sc_cq];
                end
                tail_ptr[WIDTH-1:0] <= '0;
                tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
            end else begin
                for(integer unsigned sc_cq=0; sc_cq < WAY; ++ sc_cq) begin
                    if(tail_ptr[WIDTH-1:0] + sc_cq <= {{(32-WIDTH){1'b0}}, LAST_PTR}) begin
                        circular_buffer[tail_ptr[WIDTH-1:0] + sc_cq] <= iq_wrdata[sc_cq];
                    end else begin
                        circular_buffer[sc_cq - (LAST_PTR - tail_ptr[WIDTH-1:0] + 'd1)] <= iq_wrdata[sc_cq];
                    end
                end
                tail_ptr[WIDTH-1:0] <= WIDTH'(WAY) - (LAST_PTR - tail_ptr[WIDTH-1:0] + 1'b1);
                tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
            end
        end else if (iq_push && ((free_slots != '0) || (iq_pop && !iq_empty)) && branch_at_odd_word) begin
                 if(tail_ptr[WIDTH-1:0] == LAST_PTR) begin
                    circular_buffer[tail_ptr[WIDTH-1:0]] <= iq_wrdata[index_pc];
                    tail_ptr[WIDTH-1:0] <= '0;
                    tail_ptr[WIDTH] <= ~tail_ptr[WIDTH];
                 end else begin
                    circular_buffer[tail_ptr[WIDTH-1:0]] <= iq_wrdata[index_pc];
                    tail_ptr[WIDTH-1:0] <= tail_ptr[WIDTH-1:0] + 1'b1;
                 end
        end
        if ((iq_pop && !iq_empty) ) begin
            
            if(head_ptr[WIDTH-1:0] + WAY - 'd1 < {{(32-WIDTH){1'b0}}, LAST_PTR}) begin
                head_ptr[WIDTH-1:0] <= head_ptr[WIDTH-1:0] + WIDTH'(WAY);
            end else if (head_ptr[WIDTH-1:0] + WAY - 'd1 == {{(32-WIDTH){1'b0}}, LAST_PTR}) begin
                head_ptr[WIDTH-1:0] <= '0;
                head_ptr[WIDTH] <= ~head_ptr[WIDTH];
            end else begin
                head_ptr[WIDTH-1:0] <= WIDTH'((WAY - (LAST_PTR - head_ptr[WIDTH-1:0] + 'd1)) & {WIDTH{1'b1}});
                head_ptr[WIDTH] <= ~head_ptr[WIDTH];
            end
        end
    end
end

endmodule : circular_queue