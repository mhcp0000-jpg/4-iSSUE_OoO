`timescale 1ns/1ps

// Single-instruction decoder : fetch_inst_t -> dec_uop_t
module decoder (
  input  mycore_pkg::fetch_inst_t fi,
  input  logic                    rvc_illegal,
  output mycore_pkg::dec_uop_t    u
);
  import mycore_pkg::*;
  logic [31:0] i;
  logic [6:0] opc, f7;
  logic [2:0] f3;
  logic [4:0] rd, rs1, rs2, rs3;
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  logic ill;

  always_comb begin
    i   = fi.inst;
    opc = i[6:0]; f7 = i[31:25]; f3 = i[14:12];
    rd = i[11:7]; rs1 = i[19:15]; rs2 = i[24:20]; rs3 = i[31:27];
    imm_i = {{20{i[31]}}, i[31:20]};
    imm_s = {{20{i[31]}}, i[31:25], i[11:7]};
    imm_b = {{19{i[31]}}, i[31], i[7], i[30:25], i[11:8], 1'b0};
    imm_u = {i[31:12], 12'b0};
    imm_j = {{11{i[31]}}, i[31], i[19:12], i[20], i[30:21], 1'b0};

    u = '0;
    u.valid = fi.valid;
    u.pc = fi.pc; u.rvc = fi.rvc; u.inst = fi.inst;
    u.fu = FU_NONE; u.op = 0;
    u.rs1 = {1'b0, rs1}; u.rs2 = {1'b0, rs2}; u.rs3 = {1'b1, rs3};
    u.rd = {1'b0, rd};
    u.rm = f3;
    u.csr_addr = i[31:20];
    u.pred_taken = fi.pred_taken; u.pred_target = fi.pred_target;
    u.ghr = fi.ghr; u.ras_sp = fi.ras_sp; u.ras_top = fi.ras_top;
    ill = 1'b0;

    case (opc)
      7'b0000011: begin // LOAD
        u.fu = FU_LD; u.use1 = 1; u.rd_valid = (rd != 0); u.imm = imm_i;
        case (f3)
          3'b000: u.op = MEM_LB; 3'b001: u.op = MEM_LH; 3'b010: u.op = MEM_LW;
          3'b100: u.op = MEM_LBU; 3'b101: u.op = MEM_LHU;
          default: ill = 1;
        endcase
      end
      7'b0000111: begin // FLW
        u.fu = FU_LD; u.use1 = 1; u.rd = {1'b1, rd}; u.rd_valid = 1; u.imm = imm_i; u.op = MEM_LW;
        if (f3 != 3'b010) ill = 1;
      end
      7'b0100011: begin // STORE
        u.fu = FU_ST; u.use1 = 1; u.use2 = 1; u.imm = imm_s;
        case (f3)
          3'b000: u.op = MEM_SB; 3'b001: u.op = MEM_SH; 3'b010: u.op = MEM_SW;
          default: ill = 1;
        endcase
      end
      7'b0100111: begin // FSW
        u.fu = FU_ST; u.use1 = 1; u.use2 = 1; u.rs2 = {1'b1, rs2}; u.imm = imm_s; u.op = MEM_SW;
        if (f3 != 3'b010) ill = 1;
      end
      7'b0010011: begin // OP-IMM
        u.fu = FU_ALU; u.use1 = 1; u.rd_valid = (rd != 0); u.imm = imm_i;
        case (f3)
          3'b000: u.op = ALU_ADD; 3'b010: u.op = ALU_SLT; 3'b011: u.op = ALU_SLTU;
          3'b100: u.op = ALU_XOR; 3'b110: u.op = ALU_OR; 3'b111: u.op = ALU_AND;
          3'b001: begin u.op = ALU_SLL; u.imm = {27'b0, rs2}; if (f7 != 0) ill = 1; end
          3'b101: begin u.imm = {27'b0, rs2};
                        if (f7 == 7'b0000000) u.op = ALU_SRL; else if (f7 == 7'b0100000) u.op = ALU_SRA; else ill = 1; end
        endcase
      end
      7'b0110011: begin // OP
        u.use1 = 1; u.use2 = 1; u.rd_valid = (rd != 0);
        if (f7 == 7'b0000001) begin
          u.fu = (f3[2]) ? FU_DIV : FU_MUL;
          u.op = {3'b0, f3};
        end else begin
          u.fu = FU_ALU;
          case (f3)
            3'b000: begin if (f7 == 0) u.op = ALU_ADD; else if (f7 == 7'b0100000) u.op = ALU_SUB; else ill = 1; end
            3'b001: begin u.op = ALU_SLL; if (f7 != 0) ill = 1; end
            3'b010: begin u.op = ALU_SLT; if (f7 != 0) ill = 1; end
            3'b011: begin u.op = ALU_SLTU; if (f7 != 0) ill = 1; end
            3'b100: begin u.op = ALU_XOR; if (f7 != 0) ill = 1; end
            3'b101: begin if (f7 == 0) u.op = ALU_SRL; else if (f7 == 7'b0100000) u.op = ALU_SRA; else ill = 1; end
            3'b110: begin u.op = ALU_OR; if (f7 != 0) ill = 1; end
            3'b111: begin u.op = ALU_AND; if (f7 != 0) ill = 1; end
          endcase
        end
      end
      7'b0110111: begin u.fu = FU_ALU; u.op = ALU_LUI; u.rd_valid = (rd != 0); u.imm = imm_u; end
      7'b0010111: begin u.fu = FU_ALU; u.op = ALU_AUIPC; u.rd_valid = (rd != 0); u.imm = imm_u; end
      7'b1100011: begin // BRANCH
        u.fu = FU_BR; u.is_branch = 1; u.use1 = 1; u.use2 = 1; u.imm = imm_b;
        case (f3)
          3'b000: u.op = BR_BEQ; 3'b001: u.op = BR_BNE; 3'b100: u.op = BR_BLT;
          3'b101: u.op = BR_BGE; 3'b110: u.op = BR_BLTU; 3'b111: u.op = BR_BGEU;
          default: ill = 1;
        endcase
      end
      7'b1101111: begin // JAL
        u.fu = FU_BR; u.is_branch = 1; u.op = BR_JAL; u.rd_valid = (rd != 0); u.imm = imm_j;
        u.is_call = (rd == 1 || rd == 5);
      end
      7'b1100111: begin // JALR
        u.fu = FU_BR; u.is_branch = 1; u.op = BR_JALR; u.use1 = 1; u.rd_valid = (rd != 0); u.imm = imm_i;
        u.is_call = (rd == 1 || rd == 5);
        u.is_ret  = (rd == 0) && (rs1 == 1 || rs1 == 5);
        if (f3 != 0) ill = 1;
      end
      7'b0001111: begin // MISC-MEM
        if (f3 == 3'b000) begin u.fu = FU_NONE; u.op = SYS_FENCE; end
        else if (f3 == 3'b001) begin u.fu = FU_CSR; u.op = SYS_FENCEI; end
        else ill = 1;
      end
      7'b1110011: begin // SYSTEM
        u.fu = FU_CSR;
        case (f3)
          3'b000: begin
            case (i[31:20])
              12'h000: u.op = SYS_ECALL;
              12'h001: u.op = SYS_EBREAK;
              12'h302: u.op = SYS_MRET;
              12'h105: u.op = SYS_WFI;
              default: ill = 1;
            endcase
            if (rd != 0 || rs1 != 0) ill = 1;
          end
          3'b001: begin u.op = SYS_CSRRW; u.use1 = 1; u.rd_valid = (rd != 0); end
          3'b010: begin u.op = SYS_CSRRS; u.use1 = 1; u.rd_valid = (rd != 0); end
          3'b011: begin u.op = SYS_CSRRC; u.use1 = 1; u.rd_valid = (rd != 0); end
          3'b101: begin u.op = SYS_CSRRWI; u.rd_valid = (rd != 0); u.imm = {27'b0, rs1}; end
          3'b110: begin u.op = SYS_CSRRSI; u.rd_valid = (rd != 0); u.imm = {27'b0, rs1}; end
          3'b111: begin u.op = SYS_CSRRCI; u.rd_valid = (rd != 0); u.imm = {27'b0, rs1}; end
          default: ill = 1;
        endcase
      end
      7'b1010011: begin // OP-FP
        u.fu = FU_FPU; u.rs1 = {1'b1, rs1}; u.rs2 = {1'b1, rs2}; u.rd = {1'b1, rd}; u.rd_valid = 1;
        u.use1 = 1; u.use2 = 1;
        if (i[26:25] != 2'b00) ill = 1;
        case (f7[6:2])
          5'b00000: u.op = FP_FADD;
          5'b00001: u.op = FP_FSUB;
          5'b00010: u.op = FP_FMUL;
          5'b00011: u.op = FP_FDIV;
          5'b01011: begin u.op = FP_FSQRT; u.use2 = 0; if (rs2 != 0) ill = 1; end
          5'b00100: begin case (f3) 3'b000: u.op = FP_FSGNJ; 3'b001: u.op = FP_FSGNJN; 3'b010: u.op = FP_FSGNJX; default: ill = 1; endcase end
          5'b00101: begin case (f3) 3'b000: u.op = FP_FMIN; 3'b001: u.op = FP_FMAX; default: ill = 1; endcase end
          5'b11000: begin u.use2 = 0; u.rd = {1'b0, rd}; u.rd_valid = (rd != 0);
                          if (rs2 == 0) u.op = FP_FCVT_W_S; else if (rs2 == 1) u.op = FP_FCVT_WU_S; else ill = 1; end
          5'b11100: begin u.use2 = 0; u.rd = {1'b0, rd}; u.rd_valid = (rd != 0);
                          if (f3 == 0 && rs2 == 0) u.op = FP_FMV_X_W; else if (f3 == 1 && rs2 == 0) u.op = FP_FCLASS; else ill = 1; end
          5'b10100: begin u.rd = {1'b0, rd}; u.rd_valid = (rd != 0);
                          case (f3) 3'b010: u.op = FP_FEQ; 3'b001: u.op = FP_FLT; 3'b000: u.op = FP_FLE; default: ill = 1; endcase end
          5'b11010: begin u.use2 = 0; u.rs1 = {1'b0, rs1};
                          if (rs2 == 0) u.op = FP_FCVT_S_W; else if (rs2 == 1) u.op = FP_FCVT_S_WU; else ill = 1; end
          5'b11110: begin u.use2 = 0; u.rs1 = {1'b0, rs1};
                          if (f3 == 0 && rs2 == 0) u.op = FP_FMV_W_X; else ill = 1; end
          default: ill = 1;
        endcase
      end
      7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin // FMADD/FMSUB/FNMSUB/FNMADD
        u.fu = FU_FPU; u.rs1 = {1'b1, rs1}; u.rs2 = {1'b1, rs2}; u.rs3 = {1'b1, rs3}; u.rd = {1'b1, rd}; u.rd_valid = 1;
        u.use1 = 1; u.use2 = 1; u.use3 = 1;
        if (i[26:25] != 2'b00) ill = 1;
        case (opc[3:2])
          2'b00: u.op = FP_FMADD; 2'b01: u.op = FP_FMSUB; 2'b10: u.op = FP_FNMSUB; 2'b11: u.op = FP_FNMADD;
        endcase
      end
      default: ill = 1;
    endcase

    if (ill || (fi.rvc && rvc_illegal)) begin
      u.fu = FU_CSR;      // route to commit for exception
      u.op = 0;
      u.use1 = 0; u.use2 = 0; u.use3 = 0; u.rd_valid = 0; u.is_branch = 0; u.is_call = 0; u.is_ret = 0;
      u.excp = 1; u.cause = EXC_ILLEGAL;
    end
    // register x0 as a source is never "used" (maps to phys 0 anyway)
    if (u.rs1 == 6'd0) u.use1 = 0;
    if (u.rs2 == 6'd0) u.use2 = 0;
  end
endmodule
