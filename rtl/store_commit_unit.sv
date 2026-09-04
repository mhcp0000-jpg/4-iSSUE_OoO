`timescale 1ns/1ps

module store_commit_unit (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    cancel_i,

  input  logic                    serial_valid_i,
  input  mycore_pkg::ren_uop_t    serial_uop_i,
  input  logic                    commit_ready_i,
  input  logic                    commit_fire_i,
  input  logic                    other_serial_ready_i,

  input  logic                    sq_ready_i,
  input  mycore_pkg::ren_uop_t    sq_uop_i,
  input  logic [31:0]             sq_addr_i,
  input  logic [31:0]             sq_data_i,
  input  logic [3:0]              sq_strb_i,

  output logic                    dmem_valid_o,
  output logic                    dmem_write_o,
  output logic [31:0]             dmem_addr_o,
  output logic [1:0]              dmem_size_o,
  output logic [31:0]             dmem_wdata_o,
  output logic [3:0]              dmem_wstrb_o,
  input  logic                    dmem_ready_i,
  input  logic                    dmem_error_i,

  output logic                    serial_ready_o,
  output mycore_pkg::exec_wb_t    fault_wb_o
);
  import mycore_pkg::*;

  logic store_serial, store_match, launch_request, active_request, response;
  logic active_matches_serial, completed_matches_serial;
  logic pending_q, pending_n, completed_q, completed_n;
  ren_uop_t request_uop_q, request_uop_n, active_uop;
  logic [31:0] request_addr_q, request_addr_n, active_addr;
  logic [31:0] request_data_q, request_data_n, active_data;
  logic [3:0] request_strb_q, request_strb_n, active_strb;

  always_comb begin
    store_serial = serial_valid_i && (serial_uop_i.d.fu == FU_ST);
    store_match = sq_ready_i &&
                  (sq_uop_i.rob_idx == serial_uop_i.rob_idx) &&
                  (sq_uop_i.epoch == serial_uop_i.epoch) &&
                  (sq_uop_i.sq_idx == serial_uop_i.sq_idx);
    launch_request = store_serial && commit_ready_i && store_match &&
                     !pending_q && !completed_q && !cancel_i;
    active_request = (pending_q || launch_request) && !cancel_i;
    active_uop = pending_q ? request_uop_q : serial_uop_i;
    active_addr = pending_q ? request_addr_q : sq_addr_i;
    active_data = pending_q ? request_data_q : sq_data_i;
    active_strb = pending_q ? request_strb_q : sq_strb_i;

    dmem_valid_o = active_request;
    dmem_write_o = active_request;
    dmem_addr_o = active_addr;
    dmem_size_o = active_uop.d.op[1:0];
    dmem_wdata_o = active_data;
    dmem_wstrb_o = active_strb;
    response = active_request && dmem_ready_i;
    active_matches_serial = (active_uop.rob_idx == serial_uop_i.rob_idx) &&
                            (active_uop.epoch == serial_uop_i.epoch);
    completed_matches_serial = completed_q &&
                               (request_uop_q.rob_idx == serial_uop_i.rob_idx) &&
                               (request_uop_q.epoch == serial_uop_i.epoch);

    serial_ready_o = other_serial_ready_i;
    if (store_serial)
      serial_ready_o = completed_matches_serial ||
                       (response && !dmem_error_i && active_matches_serial);

    fault_wb_o = '0;
    fault_wb_o.rob.valid = response && dmem_error_i;
    fault_wb_o.rob.rob_idx = active_uop.rob_idx;
    fault_wb_o.rob.epoch = active_uop.epoch;
    fault_wb_o.rob.excp = fault_wb_o.rob.valid;
    fault_wb_o.rob.cause = EXC_SACCESS;

    pending_n = pending_q;
    completed_n = completed_q;
    request_uop_n = request_uop_q;
    request_addr_n = request_addr_q;
    request_data_n = request_data_q;
    request_strb_n = request_strb_q;
    if (cancel_i) begin
      pending_n = 1'b0;
      completed_n = 1'b0;
    end else begin
      if (response)
        pending_n = 1'b0;
      else if (launch_request)
        pending_n = 1'b1;
      if (response && !dmem_error_i)
        completed_n = 1'b1;
      if (commit_fire_i)
        completed_n = 1'b0;
      if (launch_request) begin
      request_uop_n = serial_uop_i;
      request_addr_n = sq_addr_i;
      request_data_n = sq_data_i;
      request_strb_n = sq_strb_i;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q <= 1'b0;
      completed_q <= 1'b0;
      request_uop_q <= '0;
      request_addr_q <= '0;
      request_data_q <= '0;
      request_strb_q <= '0;
    end else begin
      pending_q <= pending_n;
      completed_q <= completed_n;
      request_uop_q <= request_uop_n;
      request_addr_q <= request_addr_n;
      request_data_q <= request_data_n;
      request_strb_q <= request_strb_n;
    end
  end
endmodule
