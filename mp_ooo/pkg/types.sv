package rv32i_types;
  localparam PHY_REG_COUNT =  64;
  localparam ROB_DEPTH = 32;
  localparam integer unsigned ROB_ID_WIDTH = $clog2(ROB_DEPTH);
  localparam ARCH_ENTRY = 32;
  localparam ARCH_WIDTH = $clog2(ARCH_ENTRY);
  localparam PRF_ENTRY = 64;
  localparam PRF_WIDTH = $clog2(PRF_ENTRY);
  localparam integer unsigned WAY = 2;
  localparam HISTORY_BITS = 8;

localparam integer IDX_PC_N_LO   = 0;
localparam integer IDX_PC_N_HI   = IDX_PC_N_LO + 31;

localparam integer IDX_PC_LO     = IDX_PC_N_HI + 1;
localparam integer IDX_PC_HI     = IDX_PC_LO + 31; 

localparam integer IDX_INST_LO   = IDX_PC_HI + 1;
localparam integer IDX_INST_HI   = IDX_INST_LO + 31;

localparam integer IDX_INDEX_LO  = IDX_INST_HI + 1;
localparam integer IDX_INDEX_HI  = IDX_INDEX_LO + HISTORY_BITS - 1;

localparam integer IDX_TARGET_LO = IDX_INDEX_HI + 1; 
localparam integer IDX_TARGET_HI = IDX_TARGET_LO + 31;

localparam integer IDX_PRED_T    = IDX_TARGET_HI + 1;
localparam integer IDX_PRED_V    = IDX_PRED_T + 1;



  typedef enum logic [6:0] {
    op_invalid   = 7'b0000000,
    op_lui       = 7'b0110111, // load upper imemediate (U type)
    op_auipc     = 7'b0010111, // add upper imemediate PC (U type)
    op_jal       = 7'b1101111, // jump and link (J type)
    op_jalr      = 7'b1100111, // jump and link register (I type)
    op_br        = 7'b1100011, // branch (B type)
    op_load      = 7'b0000011, // load (I type)
    op_store     = 7'b0100011, // store (S type)
    op_imm       = 7'b0010011, // arith ops with register/imemediate operands (I type)
    op_reg       = 7'b0110011  // arith ops with register operands (R type)
  } rv32i_opcode;

  typedef enum logic [2:0] {
    beq  = 3'b000,
    bne  = 3'b001,
    blt  = 3'b100,
    bge  = 3'b101,
    bltu = 3'b110,
    bgeu = 3'b111
  } branch_funct3_t;

  typedef enum logic [2:0] {
    lb  = 3'b000,
    lh  = 3'b001,
    lw  = 3'b010,
    lbu = 3'b100,
    lhu = 3'b101
  } load_funct3_t;

  typedef enum logic [2:0] {
    sb = 3'b000,
    sh = 3'b001,
    sw = 3'b010
  } store_funct3_t;

  typedef enum logic [2:0] {
    add  = 3'b000, //check logic 30 for sub if op_reg opcode
    sll  = 3'b001,
    slt  = 3'b010,
    sltu = 3'b011,
    axor = 3'b100,
    sr   = 3'b101, //check logic 30 for logical/arithmetic
    aor  = 3'b110,
    aand = 3'b111
  } arith_funct3_t;

  typedef enum logic [2:0] {
    alu_add = 3'b000,
    alu_sll = 3'b001,
    alu_sra = 3'b010,
    alu_sub = 3'b011,
    alu_xor = 3'b100,
    alu_srl = 3'b101,
    alu_or  = 3'b110,
    alu_and = 3'b111
  } alu_ops;

  typedef enum logic [2:0] {
    mul     = 3'b000,
    mulh    = 3'b001,
    mulhsu  = 3'b010,
    mulhu   = 3'b011,
    div     = 3'b100,
    divu    = 3'b101,
    rem     = 3'b110,
    remu    = 3'b111
  } mul_div_ops;

  typedef enum logic {
    rs1_out = 1'b0,
    pc_out  = 1'b1
  } alu_m1_sel_t;

  typedef enum integer unsigned{
    ALU = 0,
    ALU1,
    ALU2,
    BRANCH,
    MUL,
    DIV,
    MEM_LD,
    MEM_ST,
    LUI_B,
    LUI_L = LUI_B + WAY - 1,
    FU_IDX_COUNT
} fu_idx_e;

  typedef struct packed {
    logic   [63:0] order;
    logic monitor_valid;
    logic   [31:0]      pc;
    logic   [31:0]      pc_next;
    logic   [31:0]      inst;
   } if_id_t;

  typedef struct packed {
    
    //asr logic [63:0] order;
    //asr logic monitor_valid;
    //asr logic valid;
    //logic [31:0] rd_v_data;
    logic [4:0] rd_s;
    logic rd_valid;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic   [31:0] inst;
    logic [4:0] rs1_s;
    logic [4:0] rs2_s;
    logic rs1_s_valid;
    logic rs2_s_valid;
    logic no_rs1;
    //logic wb_regf_we;
    logic op_lui;
    logic mem_stage_valid;
    logic  [31:0]   dmem_addr;
    logic br_valid;
    logic jump_valid;
    //asr logic [31:0] jump_branch_pc;
    logic [31:0] imms;
    logic [31:0] pc;
    logic [31:0] pc_next;    
    logic imm_flag;
    fu_idx_e fu_idx;
    logic id_valid;
    rv32i_opcode opcode;
    logic br_pred_valid;
    logic br_pred_taken;
    logic [31:0] br_pred_target;
    logic [HISTORY_BITS-1:0] br_pred_index;
    logic load_or_store;
    // Add more signals
  } id_rename_nd_dispatch_t;

/*
  typedef struct packed {
    //logic valid;
    logic [31:0] rd_v_data;
    logic [6: 0] phy_rd;
    logic [6: 0] phy_r1;
    logic [6: 0] phy_r2;
    logic [31:0] inst;
    fu_idx_e fu_idx;
    logic monitor_valid;
    logic   [31:0]      pc;
    logic   [31:0]      pc_next;
    logic wb_regf_we;
    logic [4:0] rs1_s;
    logic [4:0] rs2_s;
    logic [31:0] rs1_v;
    logic [31:0] rs2_v;
    logic mem_stage_valid;
    logic  [31:0]   dmem_addr;
    logic [2:0] funct3;
    logic   [3:0] dmem_rmask;
    logic   [3:0] dmem_wmask;
    logic [31:0]  dmem_wdata;
    logic [31:0]  dmem_rdata;
    //logic rd_v_valid;
    // Add more signals
  } issue_t;*/

typedef struct packed {
    logic dispatch_to_res_valid;
    logic [$clog2(PHY_REG_COUNT)-1:0] ps1_s;
    logic ps1_v;
    logic [$clog2(PHY_REG_COUNT)-1:0] ps2_s;
    logic ps2_v; 
    logic [$clog2(PHY_REG_COUNT)-1:0] pd_s;
    logic [31:0] imm_val;
    logic imm_flag;
    fu_idx_e fu_idx;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [ROB_ID_WIDTH -1: 0] rob_id;
    logic   [31:0]      pc;
    logic   [31:0]      pc_next;
    rv32i_opcode opcode;
    logic rs1_s_valid;
    logic rs2_s_valid;
} res_station_cols_s;

typedef struct packed {
    logic [PHY_REG_COUNT-1:0] cdb_valid;
    logic [$clog2(PHY_REG_COUNT)-1:0] cdb_phy_reg;
    logic [ROB_ID_WIDTH-1:0] cdb_rob_id;
    logic branch_taken;
} cdb_out_signal_s;

typedef struct packed {
    logic mem_valid;
    logic [$clog2(PHY_REG_COUNT)-1:0] pd_s;
    logic [ROB_ID_WIDTH-1:0] rob_id;
    logic [31:0] mem_rd_data;
    logic store_or_load;
    //monitor
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [3:0] rmask;
    logic [3:0] wmask;
    logic [31:0] ld_addr;
    logic [31:0] st_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_load_data;
} mem_ld_cdb_t;

typedef struct packed {
    logic [ROB_ID_WIDTH-1:0]  rob_id;
    logic [2:0]   funct3;
    logic [6:0]   funct7;
    logic [PRF_WIDTH - 1:0]  pr1_s, pr2_s, prd_s;
    logic [31+1:0] imm_val;
    logic [31:0] alu_output_data;
    logic [31:0] alu_rs1_data;
    logic [31:0] alu_rs2_data;
    logic alu_output_valid;
    rv32i_opcode opcode;
    logic [31:0] pc;
} res_station_alu_out_s;

typedef struct packed {
    logic [ROB_ID_WIDTH-1:0]  rob_id;
    logic [2:0]   funct3;
    logic [6:0]   funct7;
    logic [PRF_WIDTH - 1:0]  pr1_s, pr2_s, prd_s;
    logic [31+1:0] imm_val;
    logic [31:0] br_output_data;
    logic br_taken;
    logic [31:0] br_rs1_data;
    logic br_rs1_s_valid;
    logic [31:0] br_rs2_data;
    logic br_rs2_s_valid;
    logic br_output_valid;
    rv32i_opcode opcode;
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic br_jal_flush;
} res_station_br_out_s;

typedef struct packed {
    logic [ROB_ID_WIDTH-1:0]  rob_id;
    logic [2:0]   funct3;
    logic [6:0]   funct7;
    logic [PRF_WIDTH - 1:0]  pr1_s, pr2_s, prd_s;
    logic [31+1:0] imm_val;
    logic mul_output_valid;
    logic [31:0] mul_rs1_data;
    logic [31:0] mul_rs2_data;
    logic [31:0] mul_output_data;
} res_station_mul_out_s;

typedef struct packed {
    logic [ROB_ID_WIDTH-1:0]  rob_id;
    logic [2:0]   funct3;
    logic [6:0]   funct7;
    logic [PRF_WIDTH - 1:0]  pr1_s, pr2_s, prd_s;
    logic [31+1:0] imm_val;
    logic div_output_valid;
    logic [31:0] div_rs1_data;
    logic [31:0] div_rs2_data;
    logic [31:0] div_output_data;
} res_station_div_out_s;


  typedef struct packed {
    //logic valid;
     //logic dispatch_to_res_valid;
     logic [$clog2(PHY_REG_COUNT)-1:0] ps1_s;
     logic [$clog2(PHY_REG_COUNT)-1:0] ps2_s;
     logic [$clog2(PHY_REG_COUNT)-1:0] pd_s;
     logic [31:0] imms;
     logic [2:0] funct3;
     logic [ROB_ID_WIDTH -1: 0] rob_id;
     logic load_or_store;
     logic mem_inst_valid;
     logic [31:0] pc;

  } mem_ld_st_unit;

  // For forwarding register data
  typedef struct packed {
    // replace this with actual fields for CP3!
    logic dummy;
  } fwd_t;

  typedef union packed {
    logic [31:0] word;

    struct packed {
      logic [11:0] i_imm;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } i_type;

    struct packed {
      logic [6:0]  funct7;
      logic [4:0]  rs2;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } r_type;

    struct packed {
      logic [11:5] imm_s_top;
      logic [4:0]  rs2;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  imm_s_bot;
      rv32i_opcode opcode;
    } s_type;

    struct packed {
      logic [31:12] imm;
      logic [4:0]   rd;
      rv32i_opcode  opcode;
    } j_type;
  } instr_t;
  


typedef struct packed {
logic [4:0] rd_s;
logic [$clog2(PHY_REG_COUNT)-1:0] pd_s;
logic status;
logic br_pred_valid;
logic br_pred_taken;
logic [HISTORY_BITS-1:0] pht_index;
logic [31:0] pc;
logic [31:0] lui_wdata;
logic [ROB_ID_WIDTH-1:0]rob_id;
} rob_input;

typedef struct packed {
  logic valid;
  logic ready;
  logic [ARCH_WIDTH-1:0] arch;
  logic [PRF_WIDTH-1:0] phy;
  logic br_pred_valid; //TBD
  logic br_pred; //TBD
  logic br_result;
  logic [HISTORY_BITS-1:0] pht_index;
  logic [31:0] pc;
  logic [31:0] pc_next;
  logic br_jal_flush;
} rob_entry_t;

typedef struct packed {
  logic           valid;
  //logic   [63:0]  order;
  logic   [31:0]  inst;
  logic   [4:0]   rs1_addr;
  logic   [4:0]   rs2_addr;
  logic   [31:0]  rs1_rdata;
  logic   [31:0]  rs2_rdata;
  logic   [4:0]   rd_addr;
  logic   [31:0]  rd_wdata;
  logic   [31:0]  pc_rdata;
  logic   [31:0]  pc_wdata;
  logic   [31:0]  mem_addr;
  logic   [3:0]   mem_rmask;
  logic   [3:0]   mem_wmask;
  logic   [31:0]  mem_rdata;
  logic   [31:0]  mem_wdata; 
  logic           lui;
} monitor_t;


endpackage
