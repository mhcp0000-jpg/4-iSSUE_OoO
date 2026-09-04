`timescale 1ns/1ps

// Functional bring-up frontend. It supplies one instruction per cycle to the
// four-wide backend; the fetch bandwidth is widened in a later implementation.
module frontend_single (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     consume_i,
  input  logic                     sleeping_i,
  input  logic                     redirect_valid_i,
  input  logic [31:0]              redirect_pc_i,

  output logic                     imem_valid_o,
  output logic [31:0]              imem_addr_o,
  output logic [1:0]               imem_size_o,
  input  logic                     imem_ready_i,
  input  logic [31:0]              imem_rdata_i,
  input  logic                     imem_error_i,

  output mycore_pkg::fetch_inst_t  fetch_o,
  output logic                     rvc_illegal_o,
  output logic                     fetch_fault_o,
  output logic                     cross_word_o,
  output logic [31:0]              pc_o
);
  import mycore_pkg::*;

  logic [31:0] pc_q;
  logic [15:0] halfword;
  logic [31:0] expanded;
  logic expanded_illegal, is_rvc;
  logic predicted_taken;
  logic [31:0] predicted_target;
  logic [31:0] branch_imm, jump_imm;

  rvc_expand u_expand (.c(halfword), .o(expanded), .illegal(expanded_illegal));

  always_comb begin
    halfword = pc_q[1] ? imem_rdata_i[31:16] : imem_rdata_i[15:0];
    is_rvc = (halfword[1:0] != 2'b11);
    cross_word_o = pc_q[1] && !is_rvc;
    branch_imm = {{19{imem_rdata_i[31]}}, imem_rdata_i[31],
                  imem_rdata_i[7], imem_rdata_i[30:25],
                  imem_rdata_i[11:8], 1'b0};
    jump_imm = {{11{imem_rdata_i[31]}}, imem_rdata_i[31],
                imem_rdata_i[19:12], imem_rdata_i[20],
                imem_rdata_i[30:21], 1'b0};
    predicted_taken = 1'b0;
    predicted_target = pc_q + (is_rvc ? 32'd2 : 32'd4);
    if (!is_rvc && (imem_rdata_i[6:0] == 7'b1101111)) begin
      predicted_taken = 1'b1;
      predicted_target = pc_q + jump_imm;
    end else if (!is_rvc && (imem_rdata_i[6:0] == 7'b1100011) && branch_imm[31]) begin
      predicted_taken = 1'b1;
      predicted_target = pc_q + branch_imm;
    end

    imem_valid_o = !sleeping_i;
    imem_addr_o = pc_q;
    imem_size_o = 2'd2;
    pc_o = pc_q;

    fetch_o = '0;
    fetch_o.valid = imem_valid_o && imem_ready_i && !redirect_valid_i;
    fetch_o.pc = pc_q;
    fetch_o.rvc = is_rvc;
    fetch_o.inst = is_rvc ? expanded : imem_rdata_i;
    fetch_o.raw16 = halfword;
    fetch_o.pred_taken = predicted_taken;
    fetch_o.pred_target = predicted_target;
    rvc_illegal_o = expanded_illegal;
    fetch_fault_o = fetch_o.valid && imem_error_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      pc_q <= RESET_PC;
    else if (redirect_valid_i)
      pc_q <= redirect_pc_i;
    else if (consume_i)
      pc_q <= predicted_taken ? predicted_target :
              pc_q + (is_rvc ? 32'd2 : 32'd4);
  end
endmodule
