`timescale 1ns/1ps

module issue_queue #(
  parameter int DEPTH = mycore_pkg::NIQ_INT,
  parameter int ISSUE_WIDTH = mycore_pkg::FW,
  parameter bit STRICT_ORDER = 1'b0
) (
  input  logic                              clk_i,
  input  logic                              rst_ni,

  input  logic [mycore_pkg::FW-1:0]         dispatch_valid_i,
  input  mycore_pkg::ren_uop_t              dispatch_uop_i [mycore_pkg::FW],
  input  logic [mycore_pkg::FW-1:0]         dispatch_src1_ready_i,
  input  logic [mycore_pkg::FW-1:0]         dispatch_src2_ready_i,
  input  logic [mycore_pkg::FW-1:0]         dispatch_src3_ready_i,
  output logic                              dispatch_ready_o,
  input  logic                              dispatch_fire_i,

  input  mycore_pkg::exec_wb_t              wb_i [mycore_pkg::NWB],
  input  logic [mycore_pkg::NWB-1:0]        wb_accepted_i,

  output logic [ISSUE_WIDTH-1:0]            issue_valid_o,
  output mycore_pkg::ren_uop_t              issue_uop_o [ISSUE_WIDTH],
  input  logic [ISSUE_WIDTH-1:0]            issue_accept_i,

  input  logic                              flush_i,
  // Must be the ROB-validated recovery fire, never a raw branch response.
  input  logic                              br_recover_fire_i,
  input  logic [mycore_pkg::RW:0]           br_rob_idx_i,
  input  logic [mycore_pkg::RW:0]           rob_head_i,

  output logic [$clog2(DEPTH+1)-1:0]        occupancy_o
);
  import mycore_pkg::*;

  localparam int IW = $clog2(DEPTH);
  localparam int OCW = $clog2(DEPTH + 1);

  typedef struct packed {
    logic     valid;
    logic     src1_ready;
    logic     src2_ready;
    logic     src3_ready;
    ren_uop_t uop;
  } iq_entry_t;

  iq_entry_t entry_q [DEPTH], entry_wakeup [DEPTH], entry_n [DEPTH];
  logic [DEPTH-1:0] selected;
  logic [IW-1:0] issue_slot [ISSUE_WIDTH];
  logic dispatch_slot_found;
  integer dispatch_count, available_slots;
  integer best_slot, best_distance, candidate_distance;
  logic strict_chain_ready;

  always_comb begin
    for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
      entry_wakeup[entry_idx] = entry_q[entry_idx];
      if (entry_q[entry_idx].valid) begin
        for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
          if (wb_accepted_i[wb_idx] && wb_i[wb_idx].write_pdst) begin
            if (entry_q[entry_idx].uop.d.use1 &&
                (entry_q[entry_idx].uop.ps1 == wb_i[wb_idx].pdst))
              entry_wakeup[entry_idx].src1_ready = 1'b1;
            if (entry_q[entry_idx].uop.d.use2 &&
                (entry_q[entry_idx].uop.ps2 == wb_i[wb_idx].pdst))
              entry_wakeup[entry_idx].src2_ready = 1'b1;
            if (entry_q[entry_idx].uop.d.use3 &&
                (entry_q[entry_idx].uop.ps3 == wb_i[wb_idx].pdst))
              entry_wakeup[entry_idx].src3_ready = 1'b1;
          end
        end
      end
    end
  end

  always_comb begin
    dispatch_count = 0;
    available_slots = 0;
    dispatch_ready_o = 1'b0;
    occupancy_o = '0;
    for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
      if (entry_q[entry_idx].valid)
        occupancy_o++;
    end
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (dispatch_valid_i[lane_idx])
        dispatch_count++;
    end
    available_slots = DEPTH - int'(occupancy_o);
    dispatch_ready_o = !flush_i && !br_recover_fire_i &&
                       (available_slots >= dispatch_count);
  end

  always_comb begin
    best_slot = -1;
    best_distance = 2 * NROB;
    candidate_distance = 0;
    selected = '0;
    issue_valid_o = '0;
    strict_chain_ready = 1'b1;
    for (int issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin
      issue_uop_o[issue_idx] = '0;
      issue_slot[issue_idx] = '0;
    end

    if (!flush_i && !br_recover_fire_i && STRICT_ORDER) begin
      for (int issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin
        best_slot = -1;
        best_distance = 2 * NROB;
        for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
          candidate_distance = int'(rob_distance(entry_wakeup[entry_idx].uop.rob_idx,
                                                  rob_head_i));
          if (entry_wakeup[entry_idx].valid && !selected[entry_idx] &&
              (candidate_distance < best_distance)) begin
            best_slot = entry_idx;
            best_distance = candidate_distance;
          end
        end
        if (best_slot >= 0) begin
          issue_uop_o[issue_idx] = entry_wakeup[best_slot].uop;
          issue_slot[issue_idx] = IW'(best_slot);
          selected[best_slot] = 1'b1;
          strict_chain_ready = strict_chain_ready &&
                               entry_wakeup[best_slot].src1_ready &&
                               entry_wakeup[best_slot].src2_ready &&
                               entry_wakeup[best_slot].src3_ready;
          issue_valid_o[issue_idx] = strict_chain_ready;
        end
      end
    end else if (!flush_i && !br_recover_fire_i) begin
      for (int issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin
        best_slot = -1;
        best_distance = 2 * NROB;
        for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
          candidate_distance = int'(rob_distance(entry_wakeup[entry_idx].uop.rob_idx,
                                                  rob_head_i));
          if (entry_wakeup[entry_idx].valid && !selected[entry_idx] &&
              entry_wakeup[entry_idx].src1_ready &&
              entry_wakeup[entry_idx].src2_ready &&
              entry_wakeup[entry_idx].src3_ready &&
              (candidate_distance < best_distance)) begin
            best_slot = entry_idx;
            best_distance = candidate_distance;
          end
        end
        if (best_slot >= 0) begin
          issue_valid_o[issue_idx] = 1'b1;
          issue_uop_o[issue_idx] = entry_wakeup[best_slot].uop;
          issue_slot[issue_idx] = IW'(best_slot);
          selected[best_slot] = 1'b1;
        end
      end
    end

  end

  always_comb begin
    for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++)
      entry_n[entry_idx] = entry_wakeup[entry_idx];
    dispatch_slot_found = 1'b0;

    if (flush_i) begin
      for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++)
        entry_n[entry_idx].valid = 1'b0;
    end else if (br_recover_fire_i) begin
      for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
        if (entry_q[entry_idx].valid &&
            rob_younger(entry_q[entry_idx].uop.rob_idx, br_rob_idx_i, rob_head_i))
          entry_n[entry_idx].valid = 1'b0;
      end
    end else begin
      for (int issue_idx = 0; issue_idx < ISSUE_WIDTH; issue_idx++) begin
        if (issue_valid_o[issue_idx] && issue_accept_i[issue_idx])
          entry_n[issue_slot[issue_idx]].valid = 1'b0;
      end

      if (dispatch_fire_i) begin
        for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
          if (dispatch_valid_i[lane_idx]) begin
            dispatch_slot_found = 1'b0;
            for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++) begin
              if (!entry_n[entry_idx].valid && !dispatch_slot_found) begin
                entry_n[entry_idx] = '0;
                entry_n[entry_idx].valid = 1'b1;
                entry_n[entry_idx].src1_ready = !dispatch_uop_i[lane_idx].d.use1 ||
                                                dispatch_src1_ready_i[lane_idx];
                entry_n[entry_idx].src2_ready = !dispatch_uop_i[lane_idx].d.use2 ||
                                                dispatch_src2_ready_i[lane_idx];
                entry_n[entry_idx].src3_ready = !dispatch_uop_i[lane_idx].d.use3 ||
                                                dispatch_src3_ready_i[lane_idx];
                entry_n[entry_idx].uop = dispatch_uop_i[lane_idx];
                dispatch_slot_found = 1'b1;
              end
            end
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++)
        entry_q[entry_idx] <= '0;
    end else begin
      for (int entry_idx = 0; entry_idx < DEPTH; entry_idx++)
        entry_q[entry_idx] <= entry_n[entry_idx];
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni && dispatch_fire_i)
      assert (dispatch_ready_o) else $error("issue queue dispatch without capacity");
    if (rst_ni && STRICT_ORDER) begin
      for (int issue_idx = 1; issue_idx < ISSUE_WIDTH; issue_idx++)
        assert (!issue_accept_i[issue_idx] || issue_accept_i[issue_idx-1])
          else $error("strict issue accepted a younger candidate alone");
    end
  end
`endif
endmodule
