`timescale 1ns/1ps

// ============================================================================
// MYCORE - RV32IMFC 4-issue out-of-order core : common package
// ============================================================================
package mycore_pkg;
  import soc_pkg::*;

  // ---------------- Parameters ----------------
  localparam int FW      = 4;              // front-end / rename / commit width
  localparam int NPRF    = 128;            // unified physical register file (int + fp)
  localparam int PW      = $clog2(NPRF);   // 7
  localparam int NROB    = 64;
  localparam int RW      = $clog2(NROB);   // 6  (rob index) ; pointers use RW+1 bits
  localparam int NSQ     = 16;             // store queue
  localparam int SW      = $clog2(NSQ);    // 4
  localparam int NCKPT   = 8;              // rename checkpoints (in-flight branches)
  localparam int CW      = $clog2(NCKPT);  // 3
  localparam int EW      = 4;              // recovery epoch width
  localparam int NIQ_INT = 24;
  localparam int NIQ_MEM = 16;
  localparam int NIQ_FP  = 12;
  localparam int NHWQ    = 32;             // fetch halfword queue depth
  localparam int GHRW    = 10;
  localparam int RASN    = 16;
  localparam int RASW    = $clog2(RASN);
  localparam int NWB     = 10;             // PRF write ports (ALU0-3, MUL, DIV, LD0, LD1, FPU, CSR)

  localparam logic [31:0] RESET_PC = BOOTROM_BASE;

  // ---------------- Functional units ----------------
  typedef enum logic [3:0] {
    FU_NONE = 4'd0,   // no execution needed (fence, nop-like) : done at dispatch
    FU_ALU  = 4'd1,
    FU_BR   = 4'd2,
    FU_MUL  = 4'd3,
    FU_DIV  = 4'd4,
    FU_LD   = 4'd5,
    FU_ST   = 4'd6,
    FU_FPU  = 4'd7,
    FU_CSR  = 4'd8    // serialized at commit
  } fu_e;

  // ---------------- op codes (per FU) ----------------
  // ALU
  localparam logic [5:0] ALU_ADD=0, ALU_SUB=1, ALU_SLL=2, ALU_SLT=3, ALU_SLTU=4, ALU_XOR=5,
                         ALU_SRL=6, ALU_SRA=7, ALU_OR=8, ALU_AND=9, ALU_LUI=10, ALU_AUIPC=11;
  // BR
  localparam logic [5:0] BR_BEQ=0, BR_BNE=1, BR_BLT=4, BR_BGE=5, BR_BLTU=6, BR_BGEU=7, BR_JAL=8, BR_JALR=9;
  // MUL/DIV
  localparam logic [5:0] MD_MUL=0, MD_MULH=1, MD_MULHSU=2, MD_MULHU=3, MD_DIV=4, MD_DIVU=5, MD_REM=6, MD_REMU=7;
  // MEM  : op[1:0]=size (0=B,1=H,2=W), op[2]=unsigned load
  localparam logic [5:0] MEM_LB=0, MEM_LH=1, MEM_LW=2, MEM_LBU=4, MEM_LHU=5, MEM_SB=0, MEM_SH=1, MEM_SW=2;
  // FPU
  localparam logic [5:0] FP_FADD=0, FP_FSUB=1, FP_FMUL=2, FP_FDIV=3, FP_FSQRT=4,
                         FP_FMADD=5, FP_FMSUB=6, FP_FNMSUB=7, FP_FNMADD=8,
                         FP_FSGNJ=9, FP_FSGNJN=10, FP_FSGNJX=11, FP_FMIN=12, FP_FMAX=13,
                         FP_FCVT_W_S=14, FP_FCVT_WU_S=15, FP_FCVT_S_W=16, FP_FCVT_S_WU=17,
                         FP_FMV_X_W=18, FP_FMV_W_X=19, FP_FEQ=20, FP_FLT=21, FP_FLE=22, FP_FCLASS=23;
  // CSR / SYS
  localparam logic [5:0] SYS_CSRRW=0, SYS_CSRRS=1, SYS_CSRRC=2, SYS_CSRRWI=3, SYS_CSRRSI=4, SYS_CSRRCI=5,
                         SYS_ECALL=6, SYS_EBREAK=7, SYS_MRET=8, SYS_WFI=9, SYS_FENCEI=10, SYS_FENCE=11;

  // exception causes
  localparam logic [3:0] EXC_IADDR_MISALIGNED=0, EXC_IACCESS=1, EXC_ILLEGAL=2, EXC_BREAKPOINT=3,
                         EXC_LADDR_MISALIGNED=4, EXC_LACCESS=5, EXC_SADDR_MISALIGNED=6, EXC_SACCESS=7,
                         EXC_ECALL_M=11;

  // branch types for BTB
  localparam logic [1:0] BT_COND=0, BT_JUMP=1, BT_CALL=2, BT_RET=3;

  // ---------------- Front-end records ----------------
  typedef struct packed {
    logic [15:0] hw;
    logic [31:1] pc;
    logic        taken;        // this halfword ends a predicted-taken branch
    logic [31:1] target;
    logic [GHRW-1:0] ghr;
    logic [RASW:0]   ras_sp;
    logic [31:1] ras_top;
  } hwq_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic        rvc;
    logic [31:0] inst;        // 32-bit (expanded if rvc)
    logic [15:0] raw16;
    logic        pred_taken;
    logic [31:0] pred_target;
    logic [GHRW-1:0] ghr;
    logic [RASW:0]   ras_sp;
    logic [31:0] ras_top;
  } fetch_inst_t;

  // ---------------- Decoded uop ----------------
  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic        rvc;
    logic [31:0] inst;
    fu_e         fu;
    logic [5:0]  op;
    logic [5:0]  rs1, rs2, rs3;      // arch regs: 0-31 int, 32-63 fp
    logic        use1, use2, use3;
    logic [5:0]  rd;
    logic        rd_valid;
    logic [31:0] imm;
    logic [2:0]  rm;                 // fp rounding mode
    logic [11:0] csr_addr;
    logic        is_branch;          // needs checkpoint (BR fu)
    logic        is_call, is_ret;    // ras hints
    logic        pred_taken;
    logic [31:0] pred_target;
    logic [GHRW-1:0] ghr;
    logic [RASW:0]   ras_sp;
    logic [31:0] ras_top;
    logic        excp;
    logic [3:0]  cause;
  } dec_uop_t;

  // ---------------- Renamed uop ----------------
  typedef struct packed {
    dec_uop_t    d;
    logic [PW-1:0] ps1, ps2, ps3, pdst, prev_pdst;
    logic [RW:0]   rob_idx;   // with wrap bit
    logic [EW-1:0] epoch;
    logic [SW:0]   sq_idx;    // store queue tail at dispatch (with wrap bit)
    logic [CW-1:0] ckpt_id;
  } ren_uop_t;

  // ---------------- ROB completion ----------------
  typedef struct packed {
    logic        valid;
    logic [RW:0] rob_idx;
    logic [EW-1:0] epoch;
    logic        excp;
    logic [3:0]  cause;
  } rob_wb_t;

  // ---------------- Branch resolution / redirect ----------------
  typedef struct packed {
    logic        valid;        // branch resolved this cycle (for BTB/BHT train)
    logic        mispredict;
    logic [31:0] pc;
    logic        rvc;
    logic        taken;
    logic [31:0] target;       // actual target (if taken)
    logic [31:0] next_pc;      // actual next pc
    logic [1:0]  btype;
    logic        is_cond;
    logic [GHRW-1:0] ghr;
    logic [RASW:0]   ras_sp;
    logic [31:0] ras_top;
    logic [RW:0]   rob_idx;
    logic [EW-1:0] epoch;
    logic [SW:0]   sq_idx;
    logic [CW-1:0] ckpt_id;
  } br_res_t;

  // age helpers (pointers carry wrap bit)
  function automatic logic rob_younger(input logic [RW:0] a, input logic [RW:0] ref_idx, input logic [RW:0] head);
    logic [RW:0] da, dr;
    da = a - head; dr = ref_idx - head;
    return da > dr;
  endfunction
  function automatic logic rob_older_eq(input logic [RW:0] a, input logic [RW:0] ref_idx, input logic [RW:0] head);
    return !rob_younger(a, ref_idx, head);
  endfunction

  function automatic logic [31:0] sext(input logic [31:0] v, input int bits);
    if (bits <= 0)
      return '0;
    if (bits >= 32)
      return v;
    return $signed(v << (32 - bits)) >>> (32 - bits);
  endfunction

endpackage
