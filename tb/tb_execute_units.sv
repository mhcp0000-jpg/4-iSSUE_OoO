`timescale 1ns/1ps

module tb_execute_units;
  import mycore_pkg::*;

  logic valid_i;
  ren_uop_t uop_i;
  logic [31:0] src1_i, src2_i;
  exec_wb_t alu_wb, muldiv_wb;
  br_res_t br_o;

  alu_branch_unit u_alu (valid_i, uop_i, src1_i, src2_i, alu_wb, br_o);
  muldiv_unit u_muldiv (valid_i, uop_i, src1_i, src2_i, muldiv_wb);

  task automatic check_alu(
    input logic [5:0] op,
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    input logic use2,
    input logic [31:0] imm,
    input logic [31:0] expected
  );
    begin
      uop_i = '0;
      uop_i.d.valid = 1'b1;
      uop_i.d.fu = FU_ALU;
      uop_i.d.op = op;
      uop_i.d.use2 = use2;
      uop_i.d.imm = imm;
      uop_i.d.rd = 1;
      uop_i.d.rd_valid = 1'b1;
      uop_i.pdst = 64;
      src1_i = lhs;
      src2_i = rhs;
      valid_i = 1'b1;
      #1;
      assert (alu_wb.rob.valid && alu_wb.write_pdst && alu_wb.data == expected)
        else $fatal(1, "ALU op %0d got %08x expected %08x", op, alu_wb.data, expected);
    end
  endtask

  task automatic check_md(
    input fu_e fu,
    input logic [5:0] op,
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    input logic [31:0] expected
  );
    begin
      uop_i = '0;
      uop_i.d.valid = 1'b1;
      uop_i.d.fu = fu;
      uop_i.d.op = op;
      uop_i.d.rd = 1;
      uop_i.d.rd_valid = 1'b1;
      uop_i.pdst = 64;
      src1_i = lhs;
      src2_i = rhs;
      valid_i = 1'b1;
      #1;
      assert (muldiv_wb.rob.valid && muldiv_wb.data == expected)
        else $fatal(1, "MD op %0d got %08x expected %08x", op, muldiv_wb.data, expected);
    end
  endtask

  initial begin
    valid_i = 0;
    uop_i = '0;
    src1_i = 0;
    src2_i = 0;

    check_alu(ALU_ADD, 32'd5, 32'd7, 1, 0, 32'd12);
    check_alu(ALU_ADD, 32'd5, 0, 0, -32'sd2, 32'd3);
    check_alu(ALU_SUB, 32'd5, 32'd7, 1, 0, 32'hffff_fffe);
    check_alu(ALU_SLL, 32'h1, 32'd31, 1, 0, 32'h8000_0000);
    check_alu(ALU_SLT, 32'hffff_ffff, 1, 1, 0, 1);
    check_alu(ALU_SLTU, 32'hffff_ffff, 1, 1, 0, 0);
    check_alu(ALU_XOR, 32'haa55_aa55, 32'hffff_0000, 1, 0, 32'h55aa_aa55);
    check_alu(ALU_SRL, 32'h8000_0000, 4, 1, 0, 32'h0800_0000);
    check_alu(ALU_SRA, 32'h8000_0000, 4, 1, 0, 32'hf800_0000);
    check_alu(ALU_OR, 32'h00ff_0000, 32'h0000_00ff, 1, 0, 32'h00ff_00ff);
    check_alu(ALU_AND, 32'hffff_00ff, 32'h0f0f_0f0f, 1, 0, 32'h0f0f_000f);
    check_alu(ALU_LUI, 0, 0, 0, 32'h1234_5000, 32'h1234_5000);
    uop_i.d.pc = 32'h8000_0100;
    uop_i.d.op = ALU_AUIPC;
    uop_i.d.imm = 32'h2000;
    #1;
    assert (alu_wb.data == 32'h8000_2100);

    // Conditional and indirect branches report exact redirect metadata.
    uop_i = '0;
    uop_i.d.valid = 1;
    uop_i.d.fu = FU_BR;
    uop_i.d.op = BR_BEQ;
    uop_i.d.pc = 32'h1000;
    uop_i.d.imm = 32'h20;
    uop_i.d.pred_taken = 0;
    uop_i.rob_idx = 7;
    uop_i.epoch = 3;
    src1_i = 9;
    src2_i = 9;
    #1;
    assert (br_o.valid && br_o.taken && br_o.target == 32'h1020 && br_o.mispredict);
    assert (br_o.rob_idx == 7 && br_o.epoch == 3 && alu_wb.data == 32'h1004);

    uop_i.d.op = BR_JALR;
    uop_i.d.rd = 1;
    uop_i.d.rd_valid = 1;
    uop_i.d.rvc = 1;
    uop_i.d.imm = 3;
    uop_i.d.pred_taken = 1;
    uop_i.d.pred_target = 32'h2002;
    uop_i.d.is_call = 1;
    uop_i.d.is_ret = 1;
    src1_i = 32'h1fff;
    #1;
    assert (br_o.target == 32'h2002 && !br_o.mispredict && alu_wb.data == 32'h1002);
    assert (br_o.is_call && br_o.is_ret);

    uop_i.d.op = BR_BNE;
    uop_i.d.rvc = 0;
    uop_i.d.is_call = 0;
    uop_i.d.is_ret = 0;
    uop_i.d.pred_taken = 0;
    src1_i = 7;
    src2_i = 7;
    #1;
    assert (!br_o.taken && !br_o.mispredict && br_o.next_pc == 32'h1004);

    uop_i.d.op = BR_JAL;
    uop_i.d.imm = -32'sd8;
    #1;
    assert (br_o.taken && br_o.target == 32'h0ff8 && br_o.mispredict);

    check_md(FU_MUL, MD_MUL, 32'hffff_ffff, 2, 32'hffff_fffe);
    check_md(FU_MUL, MD_MULH, 32'hffff_ffff, 2, 32'hffff_ffff);
    check_md(FU_MUL, MD_MULHSU, 32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff);
    check_md(FU_MUL, MD_MULHU, 32'hffff_ffff, 32'hffff_ffff, 32'hffff_fffe);
    check_md(FU_DIV, MD_DIV, -32'sd7, 3, -32'sd2);
    check_md(FU_DIV, MD_DIVU, 32'hffff_ffff, 2, 32'h7fff_ffff);
    check_md(FU_DIV, MD_REM, -32'sd7, 3, -32'sd1);
    check_md(FU_DIV, MD_REMU, 32'hffff_ffff, 2, 1);
    check_md(FU_DIV, MD_DIV, 123, 0, 32'hffff_ffff);
    check_md(FU_DIV, MD_REMU, 32'h1234_5678, 0, 32'h1234_5678);
    check_md(FU_DIV, MD_DIV, 32'h8000_0000, 32'hffff_ffff, 32'h8000_0000);
    check_md(FU_DIV, MD_REM, 32'h8000_0000, 32'hffff_ffff, 0);

    $display("PASS: tb_execute_units");
    $finish;
  end
endmodule
