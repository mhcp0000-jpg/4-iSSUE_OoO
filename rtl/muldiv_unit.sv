`timescale 1ns/1ps

module muldiv_unit (
  input  logic                 valid_i,
  input  mycore_pkg::ren_uop_t uop_i,
  input  logic [31:0]          src1_i,
  input  logic [31:0]          src2_i,
  output mycore_pkg::exec_wb_t wb_o
);
  import mycore_pkg::*;

  logic [31:0] result;
  logic signed [32:0] mul_a_signed, mul_b_signed, mul_b_unsigned;
  logic signed [65:0] product_ss, product_su;
  logic [63:0] product_uu;

  always_comb begin
    mul_a_signed = {src1_i[31], src1_i};
    mul_b_signed = {src2_i[31], src2_i};
    mul_b_unsigned = {1'b0, src2_i};
    product_ss = mul_a_signed * mul_b_signed;
    product_su = mul_a_signed * mul_b_unsigned;
    product_uu = src1_i * src2_i;
    result = '0;

    case (uop_i.d.op)
      MD_MUL:    result = product_uu[31:0];
      MD_MULH:   result = product_ss[63:32];
      MD_MULHSU: result = product_su[63:32];
      MD_MULHU:  result = product_uu[63:32];
      MD_DIV: begin
        if (src2_i == 0)
          result = 32'hffff_ffff;
        else if ((src1_i == 32'h8000_0000) && (src2_i == 32'hffff_ffff))
          result = 32'h8000_0000;
        else
          result = $signed(src1_i) / $signed(src2_i);
      end
      MD_DIVU: result = (src2_i == 0) ? 32'hffff_ffff : (src1_i / src2_i);
      MD_REM: begin
        if (src2_i == 0)
          result = src1_i;
        else if ((src1_i == 32'h8000_0000) && (src2_i == 32'hffff_ffff))
          result = 32'd0;
        else
          result = $signed(src1_i) % $signed(src2_i);
      end
      MD_REMU: result = (src2_i == 0) ? src1_i : (src1_i % src2_i);
      default: result = '0;
    endcase

    wb_o = '0;
    wb_o.rob.valid = valid_i && ((uop_i.d.fu == FU_MUL) || (uop_i.d.fu == FU_DIV));
    wb_o.rob.rob_idx = uop_i.rob_idx;
    wb_o.rob.epoch = uop_i.epoch;
    wb_o.write_pdst = wb_o.rob.valid && uop_i.d.rd_valid && (uop_i.d.rd != 0);
    wb_o.pdst = uop_i.pdst;
    wb_o.data = result;
  end
endmodule
