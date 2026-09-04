`timescale 1ns/1ps

module lsu_unit (
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

  output logic                    ready_o,
  output mycore_pkg::exec_wb_t    wb_o
);
  import mycore_pkg::*;

  logic [31:0] effective_addr, merged_word, shifted_word, load_result;
  logic [3:0] required_mask;
  logic [4:0] byte_shift;
  logic misaligned, fully_forwarded, memory_complete;

  always_comb begin
    effective_addr = base_i + uop_i.d.imm;
    dmem_addr_o = effective_addr;
    dmem_size_o = uop_i.d.op[1:0];
    byte_shift = {effective_addr[1:0], 3'b000};

    required_mask = '0;
    misaligned = 1'b0;
    case (uop_i.d.op[1:0])
      2'd0: required_mask = 4'b0001 << effective_addr[1:0];
      2'd1: begin
        required_mask = 4'b0011 << {effective_addr[1], 1'b0};
        misaligned = effective_addr[0];
      end
      2'd2: begin
        required_mask = 4'b1111;
        misaligned = |effective_addr[1:0];
      end
      default: misaligned = 1'b1;
    endcase

    merged_word = dmem_rdata_i;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (forward_mask_i[byte_idx])
        merged_word[byte_idx*8 +: 8] = forward_data_i[byte_idx*8 +: 8];
    end
    shifted_word = merged_word >> byte_shift;
    case (uop_i.d.op[1:0])
      2'd0: load_result = uop_i.d.op[2] ? {24'd0, shifted_word[7:0]} :
                                          {{24{shifted_word[7]}}, shifted_word[7:0]};
      2'd1: load_result = uop_i.d.op[2] ? {16'd0, shifted_word[15:0]} :
                                          {{16{shifted_word[15]}}, shifted_word[15:0]};
      default: load_result = shifted_word;
    endcase

    fully_forwarded = ((forward_mask_i & required_mask) == required_mask);
    dmem_valid_o = valid_i && (uop_i.d.fu == FU_LD) && !misaligned &&
                   !older_store_unknown_i && !fully_forwarded;
    memory_complete = fully_forwarded || (dmem_valid_o && dmem_ready_i);

    store_execute_valid_o = valid_i && (uop_i.d.fu == FU_ST) && !misaligned;
    store_execute_uop_o = uop_i;
    store_execute_addr_o = effective_addr;
    store_execute_data_o = store_data_i << byte_shift;
    store_execute_strb_o = required_mask;

    ready_o = 1'b0;
    wb_o = '0;
    wb_o.rob.rob_idx = uop_i.rob_idx;
    wb_o.rob.epoch = uop_i.epoch;
    wb_o.pdst = uop_i.pdst;

    if (valid_i && ((uop_i.d.fu == FU_LD) || (uop_i.d.fu == FU_ST))) begin
      if (misaligned) begin
        ready_o = 1'b1;
        wb_o.rob.valid = 1'b1;
        wb_o.rob.excp = 1'b1;
        wb_o.rob.cause = (uop_i.d.fu == FU_LD) ? EXC_LADDR_MISALIGNED :
                                                EXC_SADDR_MISALIGNED;
        wb_o.rob.tval = effective_addr;
      end else if (uop_i.d.fu == FU_ST) begin
        ready_o = 1'b1;
      end else if (!older_store_unknown_i && memory_complete) begin
        ready_o = 1'b1;
        wb_o.rob.valid = 1'b1;
        wb_o.rob.excp = !fully_forwarded && dmem_error_i;
        wb_o.rob.cause = EXC_LACCESS;
        wb_o.rob.tval = effective_addr;
        wb_o.write_pdst = !wb_o.rob.excp && uop_i.d.rd_valid && (uop_i.d.rd != 0);
        wb_o.data = load_result;
      end
    end
  end
endmodule
