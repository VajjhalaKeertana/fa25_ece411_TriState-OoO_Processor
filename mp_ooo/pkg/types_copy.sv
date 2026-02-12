package rv32i_types;
  localparam PHY_REG_COUNT =  128;
  typedef enum logic [6:0] {
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

  typedef enum logic {
    rs1_out = 1'b0,
    pc_out  = 1'b1
  } alu_m1_sel_t;

  typedef enum integer {
    LUI,
    ALU,
    BRANCH,
    MUL,
    DIV,
    LOAD,
    STORE,
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
    logic [31:0] rd_v_data;
    logic [4:0] rd_s;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic   [31:0] inst;
    logic [4:0] rs1_s;
    logic [4:0] rs2_s;
    logic wb_regf_we;
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
    logic [$clog2(PHY_REG_COUNT)-1:0] rob_idx;
    logic [31:0] imm_val;
    logic imm_flag;
    fu_idx_e fu_idx;
    logic [2:0] funct3;
    logic [6:0] funct7;
} res_station_cols_s;


  typedef struct packed {
    //logic valid;
    logic [31:0] rd_v_data;
    logic [4:0] rd_s;
    logic wb_regf_we;
    logic [63:0] order;
    logic   [31:0]      inst;
    logic monitor_valid;
    logic   [31:0]      pc;
    logic   [31:0]      pc_next;
    logic [4:0] rs1_s;
    logic [4:0] rs2_s;
    logic [31:0] rs1_v;
    logic [31:0] rs2_v;
    logic   [3:0] dmem_rmask;
    logic  [31:0]   dmem_addr;
    logic [31:0]  dmem_rdata;
    logic [31:0]  dmem_wdata;
    logic   [3:0] dmem_wmask;
    // Add more signals
  } mem_wb_t;

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
  


struct packed {
logic [4:0] rd_s;
logic [6:0] pd_s;
logic status;
logic branch_pred
} rob_input;

typedef struct packed {
  logic valid;
  logic ready;
  logic [ARCH_WIDTH-1:0] arch;
  logic [PRF_WIDTH-1:0] phys;
  logic br_pred_valid; //TBD
  logic br_pred_taken; //TBD
} rob_entry_t;




endpackage
