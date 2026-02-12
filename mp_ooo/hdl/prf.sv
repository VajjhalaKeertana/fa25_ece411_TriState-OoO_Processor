module prf_table
import rv32i_types::*;
#(
    parameter DATA_WIDTH = 32,
    parameter PRF_ENTRY = 64,
    parameter integer CHANNELS = FU_IDX_COUNT - 1,
    parameter PRF_WIDTH = $clog2(PRF_ENTRY)
    //parameter ROB_DEPTH = 32
)(
    input logic clk,
    input logic rst,

    input logic [WAY-1:0] free_en,
    input logic [$clog2(PRF_ENTRY)-1:0] free_tag[WAY],

    input logic read_en[CHANNELS-WAY:0],
    input logic [$clog2(PRF_ENTRY)-1:0] pr1_s[CHANNELS-WAY:0],
    input logic [$clog2(PRF_ENTRY)-1:0] pr2_s[CHANNELS-WAY:0],
    output logic [DATA_WIDTH-1:0] pr1_data[CHANNELS-WAY:0],
    output logic [DATA_WIDTH-1:0] pr2_data[CHANNELS-WAY:0],

    output logic [PRF_ENTRY-1:0] valid_array,

    input logic  write_en[CHANNELS:0],
    input logic  [$clog2(PRF_ENTRY)-1:0] write_tag[CHANNELS:0] ,
    input logic  [DATA_WIDTH-1:0] write_data [CHANNELS:0],

    //input logic [PRF_WIDTH-1:0] prf_phy1[WAY],
    //input logic [PRF_WIDTH-1:0] prf_phy2[WAY],
   // output logic [DATA_WIDTH-1:0] prf_phy1_data[WAY],
    //output logic [DATA_WIDTH-1:0] prf_phy2_data[WAY],

    //input  logic br_mispredict_flush,
    input  logic [ROB_DEPTH-1:0] prf_free_v_flush,
    input  logic [PRF_WIDTH-1:0] prf_free_tag_flush [ROB_DEPTH-1:0]
);

localparam TAG_WIDTH = $clog2(PRF_ENTRY);
typedef logic [$clog2(PRF_ENTRY)-1:0] tag_t;
// size PRF_ENTRY-1 into tag width (avoids wrap)
localparam tag_t PRF_MAX_TAG = tag_t'(PRF_ENTRY-1);

// typedef struct packed {
//     logic valid;
//     logic [DATA_WIDTH-1:0] data;
// }prf;

//prf [PRF_ENTRY-1:0] row;
logic [DATA_WIDTH-1:0] row [PRF_ENTRY-1:0];
logic [PRF_ENTRY-1:0] row_valid;
logic [PRF_ENTRY-1:0] flush_mask;

always_comb begin
    flush_mask = '0; 
    
    for (integer unsigned f = 0; f < ROB_DEPTH; f++) begin
        if (prf_free_v_flush[f]) begin
            flush_mask[prf_free_tag_flush[f]] = 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if(rst) begin
        row_valid <= '0;

    end else begin
        if((write_en[ALU])) begin
            row[write_tag[ALU]] <= write_data[ALU];
            row_valid[write_tag[ALU]] <= 1'b1;
            //valid_array[write_tag[0]] <= 1'b1;
        end
        if((write_en[ALU1])) begin
            row[write_tag[ALU1]] <= write_data[ALU1];
            row_valid[write_tag[ALU1]] <= 1'b1;
            //valid_array[write_tag[0]] <= 1'b1;
        end
        if((write_en[ALU2])) begin
            row[write_tag[ALU2]] <= write_data[ALU2];
            row_valid[write_tag[ALU2]] <= 1'b1;
            //valid_array[write_tag[0]] <= 1'b1;
        end
        if((write_en[BRANCH])) begin
            row[write_tag[BRANCH]] <= write_data[BRANCH];
            row_valid[write_tag[BRANCH]] <= 1'b1;
           // valid_array[write_tag[1]] <= 1'b1;
        end
        if((write_en[MUL])) begin
            row[write_tag[MUL]] <= write_data[MUL];
            row_valid[write_tag[MUL]] <= 1'b1;
            //valid_array[write_tag[2]] <= 1'b1;
        end
        if((write_en[DIV])) begin
            row[write_tag[DIV]] <= write_data[DIV];
            row_valid[write_tag[DIV]] <= 1'b1;
            //valid_array[write_tag[3]] <= 1'b1;
        end
        if((write_en[MEM_LD])) begin
            row[write_tag[MEM_LD]] <= write_data[MEM_LD];
            row_valid[write_tag[MEM_LD]] <= 1'b1;
            //valid_array[write_tag[4]] <= 1'b1;
        end
        for(integer unsigned sc_prf=0; sc_prf < WAY; ++sc_prf) begin
            if((write_en[LUI_B + sc_prf])) begin
                row[write_tag[LUI_B + sc_prf]] <= write_data[LUI_B + sc_prf];
                row_valid[write_tag[LUI_B + sc_prf]] <= 1'b1;
                //valid_array[write_tag[5]] <= 1'b1;
            end
        end
        for(integer unsigned sc_prf=0; sc_prf<WAY; ++sc_prf) begin
            if(free_en[sc_prf]) begin
                row_valid[free_tag[sc_prf]] <= 1'b0;
                //valid_array[free_tag] <= 1'b0;
            end
        end

        if (|prf_free_v_flush) begin
            for (integer unsigned i = 0; i < PRF_ENTRY; i++) begin
                if (flush_mask[i]) begin
                    row_valid[i] <= 1'b0;
                end
            end
            
        end
    end
end

always_comb begin
    valid_array[0] = 1'b1;
    for(integer unsigned i =1; i < PRF_ENTRY; ++i ) begin
        valid_array[i] = row_valid[i];
    end

end

always_comb begin
    for(integer unsigned i = 0; i < CHANNELS-WAY+1; ++i) begin
        pr1_data[i] = '0;
        pr2_data[i] = '0;
        if(read_en[i]) begin
            pr1_data[i] = pr1_s[i] == 0 ? '0 : row[pr1_s[i]];
            pr2_data[i] = pr2_s[i] == 0 ? '0 : row[pr2_s[i]];
        end
    end
end

endmodule