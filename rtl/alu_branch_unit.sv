`timescale 1ns/1ps

module alu_branch_unit (
  input  logic                    valid_i,
  input  mycore_pkg::ren_uop_t    uop_i,
  input  logic [31:0]             src1_i,
  input  logic [31:0]             src2_i,
  output mycore_pkg::exec_wb_t    wb_o,
  output mycore_pkg::br_res_t     br_o
);
  import mycore_pkg::*;

  logic [31:0] rhs, result, sequential_pc, branch_target;
  logic branch_taken;

  always_comb begin
    rhs = uop_i.d.use2 ? src2_i : uop_i.d.imm;
    result = '0;
    sequential_pc = uop_i.d.pc + (uop_i.d.rvc ? 32'd2 : 32'd4);
    branch_target = uop_i.d.pc + uop_i.d.imm;
    branch_taken = 1'b0;

    if (uop_i.d.fu == FU_ALU) begin
      case (uop_i.d.op)
        ALU_ADD:   result = src1_i + rhs;
        ALU_SUB:   result = src1_i - src2_i;
        ALU_SLL:   result = src1_i << rhs[4:0];
        ALU_SLT:   result = {31'd0, $signed(src1_i) < $signed(rhs)};
        ALU_SLTU:  result = {31'd0, src1_i < rhs};
        ALU_XOR:   result = src1_i ^ rhs;
        ALU_SRL:   result = src1_i >> rhs[4:0];
        ALU_SRA:   result = $signed(src1_i) >>> rhs[4:0];
        ALU_OR:    result = src1_i | rhs;
        ALU_AND:   result = src1_i & rhs;
        ALU_LUI:   result = uop_i.d.imm;
        ALU_AUIPC: result = uop_i.d.pc + uop_i.d.imm;
        default:   result = '0;
      endcase
    end else if (uop_i.d.fu == FU_BR) begin
      result = sequential_pc;
      case (uop_i.d.op)
        BR_BEQ:  branch_taken = (src1_i == src2_i);
        BR_BNE:  branch_taken = (src1_i != src2_i);
        BR_BLT:  branch_taken = ($signed(src1_i) < $signed(src2_i));
        BR_BGE:  branch_taken = ($signed(src1_i) >= $signed(src2_i));
        BR_BLTU: branch_taken = (src1_i < src2_i);
        BR_BGEU: branch_taken = (src1_i >= src2_i);
        BR_JAL:  branch_taken = 1'b1;
        BR_JALR: begin
          branch_taken = 1'b1;
          branch_target = (src1_i + uop_i.d.imm) & 32'hffff_fffe;
        end
        default: branch_taken = 1'b0;
      endcase
    end

    wb_o = '0;
    wb_o.rob.valid = valid_i && ((uop_i.d.fu == FU_ALU) || (uop_i.d.fu == FU_BR));
    wb_o.rob.rob_idx = uop_i.rob_idx;
    wb_o.rob.epoch = uop_i.epoch;
    wb_o.write_pdst = wb_o.rob.valid && uop_i.d.rd_valid && (uop_i.d.rd != 0);
    wb_o.pdst = uop_i.pdst;
    wb_o.data = result;

    br_o = '0;
    br_o.valid = valid_i && (uop_i.d.fu == FU_BR);
    br_o.pc = uop_i.d.pc;
    br_o.rvc = uop_i.d.rvc;
    br_o.taken = branch_taken;
    br_o.target = branch_target;
    br_o.next_pc = branch_taken ? branch_target : sequential_pc;
    br_o.is_cond = (uop_i.d.op != BR_JAL) && (uop_i.d.op != BR_JALR);
    br_o.is_call = uop_i.d.is_call;
    br_o.is_ret = uop_i.d.is_ret;
    br_o.btype = BT_COND;
    if (uop_i.d.is_ret)
      br_o.btype = BT_RET;
    else if (uop_i.d.is_call)
      br_o.btype = BT_CALL;
    else if (!br_o.is_cond)
      br_o.btype = BT_JUMP;
    br_o.mispredict = br_o.valid &&
                      ((uop_i.d.pred_taken != branch_taken) ||
                       (branch_taken && (uop_i.d.pred_target != branch_target)));
    br_o.ghr = uop_i.d.ghr;
    br_o.ras_sp = uop_i.d.ras_sp;
    br_o.ras_top = uop_i.d.ras_top;
    br_o.rob_idx = uop_i.rob_idx;
    br_o.epoch = uop_i.epoch;
    br_o.sq_idx = uop_i.sq_idx;
    br_o.ckpt_id = uop_i.ckpt_id;
  end
endmodule
