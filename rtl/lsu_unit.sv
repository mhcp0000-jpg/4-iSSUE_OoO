`timescale 1ns/1ps

module lsu_unit (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    valid_i,
  input  mycore_pkg::ren_uop_t    uop_i,
  input  logic [31:0]             base_i,
  input  logic [31:0]             store_data_i,

  input  logic                    older_store_unknown_i,
  input  logic [3:0]              forward_mask_i,
  input  logic [31:0]             forward_data_i,

  output logic                    dmem_valid_o,
  output logic [31:0]             dmem_addr_o,
  output logic [1:0]              dmem_size_o,
  input  logic                    dmem_ready_i,
  input  logic [31:0]             dmem_rdata_i,
  input  logic                    dmem_error_i,

  output logic                    store_execute_valid_o,
  output mycore_pkg::ren_uop_t    store_execute_uop_o,
  output logic [31:0]             store_execute_addr_o,
  output logic [31:0]             store_execute_data_o,
  output logic [3:0]              store_execute_strb_o,

  input  logic                    flush_i,
  input  logic                    br_recover_fire_i,
  input  logic [mycore_pkg::RW:0] br_rob_idx_i,
  input  logic [mycore_pkg::RW:0] rob_head_i,

  output logic                    ready_o,
  output logic                    busy_o,
  output mycore_pkg::exec_wb_t    wb_o
);
  import mycore_pkg::*;

  logic busy_q, busy_n, killed_q, killed_n;
  ren_uop_t uop_q, uop_n;
  logic [31:0] addr_q, addr_n;
  logic [3:0] required_mask_q, required_mask_n;
  logic [3:0] forward_mask_q, forward_mask_n;
  logic [31:0] forward_data_q, forward_data_n;
  logic misaligned_q, misaligned_n;

  logic [31:0] input_addr, input_store_data;
  logic [3:0] input_required_mask;
  logic [4:0] input_byte_shift;
  logic input_misaligned, capture;
  logic [31:0] merged_word, shifted_word, load_result;
  logic fully_forwarded, memory_complete, complete, kill_active;

  always_comb begin
    input_addr = base_i + uop_i.d.imm;
    input_byte_shift = {input_addr[1:0], 3'b000};
    input_required_mask = '0;
    input_misaligned = 1'b0;
    case (uop_i.d.op[1:0])
      2'd0: input_required_mask = 4'b0001 << input_addr[1:0];
      2'd1: begin
        input_required_mask = 4'b0011 << {input_addr[1], 1'b0};
        input_misaligned = input_addr[0];
      end
      2'd2: begin
        input_required_mask = 4'b1111;
        input_misaligned = |input_addr[1:0];
      end
      default: input_misaligned = 1'b1;
    endcase
    input_store_data = store_data_i << input_byte_shift;

    ready_o = !busy_q && (!valid_i || (uop_i.d.fu == FU_ST) ||
                          input_misaligned || !older_store_unknown_i);
    capture = valid_i && ready_o && !flush_i && !br_recover_fire_i;
    busy_o = busy_q;

    store_execute_valid_o = capture && (uop_i.d.fu == FU_ST) &&
                            !input_misaligned;
    store_execute_uop_o = uop_i;
    store_execute_addr_o = input_addr;
    store_execute_data_o = input_store_data;
    store_execute_strb_o = input_required_mask;

    fully_forwarded = ((forward_mask_q & required_mask_q) == required_mask_q);
    dmem_valid_o = busy_q && !misaligned_q && !fully_forwarded;
    dmem_addr_o = addr_q;
    dmem_size_o = uop_q.d.op[1:0];
    memory_complete = dmem_valid_o && dmem_ready_i;
    complete = busy_q && (misaligned_q || fully_forwarded || memory_complete);
    kill_active = flush_i ||
                  (br_recover_fire_i &&
                   rob_younger(uop_q.rob_idx, br_rob_idx_i, rob_head_i));

    merged_word = dmem_rdata_i;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (forward_mask_q[byte_idx])
        merged_word[byte_idx*8 +: 8] = forward_data_q[byte_idx*8 +: 8];
    end
    shifted_word = merged_word >> {addr_q[1:0], 3'b000};
    case (uop_q.d.op[1:0])
      2'd0: load_result = uop_q.d.op[2] ? {24'd0, shifted_word[7:0]} :
                                         {{24{shifted_word[7]}}, shifted_word[7:0]};
      2'd1: load_result = uop_q.d.op[2] ? {16'd0, shifted_word[15:0]} :
                                         {{16{shifted_word[15]}}, shifted_word[15:0]};
      default: load_result = shifted_word;
    endcase

    wb_o = '0;
    wb_o.rob.rob_idx = busy_q ? uop_q.rob_idx : uop_i.rob_idx;
    wb_o.rob.epoch = busy_q ? uop_q.epoch : uop_i.epoch;
    wb_o.pdst = busy_q ? uop_q.pdst : uop_i.pdst;
    if (complete && !killed_q && !kill_active) begin
      wb_o.rob.valid = 1'b1;
      if (misaligned_q) begin
        wb_o.rob.excp = 1'b1;
        wb_o.rob.cause = EXC_LADDR_MISALIGNED;
        wb_o.rob.tval = addr_q;
      end else begin
        wb_o.rob.excp = !fully_forwarded && dmem_error_i;
        wb_o.rob.cause = EXC_LACCESS;
        wb_o.rob.tval = addr_q;
        wb_o.write_pdst = !wb_o.rob.excp && uop_q.d.rd_valid &&
                          (uop_q.d.rd != 0);
        wb_o.data = load_result;
      end
    end else if (capture && (uop_i.d.fu == FU_ST) && input_misaligned) begin
      wb_o.rob.valid = 1'b1;
      wb_o.rob.rob_idx = uop_i.rob_idx;
      wb_o.rob.epoch = uop_i.epoch;
      wb_o.rob.excp = 1'b1;
      wb_o.rob.cause = EXC_SADDR_MISALIGNED;
      wb_o.rob.tval = input_addr;
    end

    busy_n = busy_q;
    killed_n = killed_q || (busy_q && kill_active);
    uop_n = uop_q;
    addr_n = addr_q;
    required_mask_n = required_mask_q;
    forward_mask_n = forward_mask_q;
    forward_data_n = forward_data_q;
    misaligned_n = misaligned_q;
    if (complete) begin
      busy_n = 1'b0;
      killed_n = 1'b0;
    end
    if (capture && (uop_i.d.fu == FU_LD)) begin
      busy_n = 1'b1;
      killed_n = 1'b0;
      uop_n = uop_i;
      addr_n = input_addr;
      required_mask_n = input_required_mask;
      forward_mask_n = forward_mask_i;
      forward_data_n = forward_data_i;
      misaligned_n = input_misaligned;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      killed_q <= 1'b0;
      uop_q <= '0;
      addr_q <= '0;
      required_mask_q <= '0;
      forward_mask_q <= '0;
      forward_data_q <= '0;
      misaligned_q <= 1'b0;
    end else begin
      busy_q <= busy_n;
      killed_q <= killed_n;
      uop_q <= uop_n;
      addr_q <= addr_n;
      required_mask_q <= required_mask_n;
      forward_mask_q <= forward_mask_n;
      forward_data_q <= forward_data_n;
      misaligned_q <= misaligned_n;
    end
  end
endmodule
