`timescale 1ns/1ps

// 64-entry reorder buffer with four-wide allocation and in-order retirement.
module rob (
  input  logic                              clk_i,
  input  logic                              rst_ni,

  input  mycore_pkg::ren_uop_t              alloc_i [mycore_pkg::FW],
  input  logic [mycore_pkg::FW-1:0]         alloc_valid_i,
  output logic                              alloc_ready_o,
  input  logic                              alloc_fire_i,

  input  mycore_pkg::rob_wb_t               wb_i [mycore_pkg::NWB],

  output logic [mycore_pkg::FW-1:0]         commit_valid_o,
  output mycore_pkg::ren_uop_t              commit_uop_o [mycore_pkg::FW],
  input  logic                              commit_ready_i,
  input  logic                              serial_ready_i,
  output logic                              serial_valid_o,
  output mycore_pkg::ren_uop_t              serial_uop_o,

  output logic                              trap_valid_o,
  output mycore_pkg::ren_uop_t              trap_uop_o,
  output logic [3:0]                        trap_cause_o,
  output logic [31:0]                       trap_tval_o,

  input  logic                              flush_i,
  input  logic                              br_recover_valid_i,
  input  logic [mycore_pkg::RW:0]           br_rob_idx_i,
  input  logic [mycore_pkg::EW-1:0]         br_epoch_i,
  output logic                              br_recover_fire_o,

  output logic [mycore_pkg::RW:0]           rob_head_o,
  output logic [mycore_pkg::RW:0]           rob_tail_o,
  output logic [mycore_pkg::RW:0]           occupancy_o,
  output logic [mycore_pkg::EW-1:0]         rob_epoch_o
);
  import mycore_pkg::*;

  typedef struct packed {
    logic       valid;
    logic       complete;
    logic       excp;
    logic [3:0] cause;
    logic [31:0] tval;
    ren_uop_t   uop;
  } rob_entry_t;

  rob_entry_t entry_q [NROB];
  rob_entry_t entry_wb [NROB];
  rob_entry_t entry_n [NROB];
  logic [RW:0] head_q, head_n, tail_q, tail_n;
  logic [EW-1:0] epoch_q, epoch_n;

  logic [RW:0] scan_ptr, alloc_ptr;
  logic commit_stop, br_recover_match, head_serial;
  integer alloc_count, commit_count, retire_count, available_slots;

  assign rob_head_o = head_q;
  assign rob_tail_o = tail_q;
  assign occupancy_o = tail_q - head_q;
  assign rob_epoch_o = epoch_q;
  assign br_recover_match = br_recover_valid_i && !flush_i &&
                            entry_q[br_rob_idx_i[RW-1:0]].valid &&
                            (entry_q[br_rob_idx_i[RW-1:0]].uop.rob_idx == br_rob_idx_i) &&
                            (entry_q[br_rob_idx_i[RW-1:0]].uop.epoch == br_epoch_i);
  assign br_recover_fire_o = br_recover_match;

  always_comb begin
    alloc_count = 0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (alloc_valid_i[lane_idx])
        alloc_count++;
    end
    head_serial = entry_q[head_q[RW-1:0]].valid &&
                  entry_q[head_q[RW-1:0]].complete &&
                  ((entry_q[head_q[RW-1:0]].uop.d.fu == FU_CSR) ||
                   (entry_q[head_q[RW-1:0]].uop.d.fu == FU_NONE) ||
                   (entry_q[head_q[RW-1:0]].uop.d.fu == FU_ST));
    available_slots = NROB - int'(occupancy_o);
    alloc_ready_o = !flush_i && !br_recover_valid_i && !head_serial &&
                    (available_slots >= alloc_count);
  end

  // Completion bypass permits a result arriving this cycle to retire at the
  // same edge, while the epoch rejects stale wrong-path traffic.
  always_comb begin
    for (int entry_idx = 0; entry_idx < NROB; entry_idx++)
      entry_wb[entry_idx] = entry_q[entry_idx];
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
      if (wb_i[wb_idx].valid &&
          entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].valid &&
          (entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].uop.rob_idx == wb_i[wb_idx].rob_idx) &&
          (entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].uop.epoch == wb_i[wb_idx].epoch)) begin
        entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].complete = 1'b1;
        if (wb_i[wb_idx].excp) begin
          entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].excp = 1'b1;
          entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].cause = wb_i[wb_idx].cause;
          entry_wb[wb_i[wb_idx].rob_idx[RW-1:0]].tval = wb_i[wb_idx].tval;
        end
      end
    end
  end

  // Side-effecting operations are offered only when already complete at the
  // registered ROB head. This keeps memory/CSR responses out of the candidate
  // path and guarantees they execute alone at the architectural boundary.
  always_comb begin
    serial_valid_o = 1'b0;
    serial_uop_o = '0;
    if (!flush_i && !br_recover_valid_i &&
        entry_q[head_q[RW-1:0]].valid &&
        (entry_q[head_q[RW-1:0]].uop.rob_idx == head_q) &&
        entry_q[head_q[RW-1:0]].complete &&
        !entry_q[head_q[RW-1:0]].excp &&
        ((entry_q[head_q[RW-1:0]].uop.d.fu == FU_CSR) ||
         (entry_q[head_q[RW-1:0]].uop.d.fu == FU_NONE) ||
         (entry_q[head_q[RW-1:0]].uop.d.fu == FU_ST))) begin
      serial_valid_o = 1'b1;
      serial_uop_o = entry_q[head_q[RW-1:0]].uop;
    end
  end

  always_comb begin
    trap_valid_o = 1'b0;
    trap_uop_o = '0;
    trap_cause_o = '0;
    trap_tval_o = '0;
    if (!flush_i && !br_recover_match &&
        entry_wb[head_q[RW-1:0]].valid &&
        (entry_wb[head_q[RW-1:0]].uop.rob_idx == head_q) &&
        entry_wb[head_q[RW-1:0]].complete &&
        entry_wb[head_q[RW-1:0]].excp) begin
      trap_valid_o = 1'b1;
      trap_uop_o = entry_wb[head_q[RW-1:0]].uop;
      trap_cause_o = entry_wb[head_q[RW-1:0]].cause;
      trap_tval_o = entry_wb[head_q[RW-1:0]].tval;
    end
  end

  // Commit and capacity outputs do not depend on alloc_fire_i. This avoids a
  // ready/fire combinational loop when the ROB is connected to rename.
  always_comb begin
    commit_valid_o = '0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++)
      commit_uop_o[lane_idx] = '0;
    commit_count = 0;
    commit_stop = 1'b0;
    scan_ptr = head_q;
    if (!flush_i && !br_recover_match) begin
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
        if (!commit_stop) begin
          if (entry_wb[scan_ptr[RW-1:0]].valid &&
              (entry_wb[scan_ptr[RW-1:0]].uop.rob_idx == scan_ptr) &&
              entry_wb[scan_ptr[RW-1:0]].complete) begin
            if (entry_wb[scan_ptr[RW-1:0]].excp) begin
              commit_stop = 1'b1;
            end else if ((entry_wb[scan_ptr[RW-1:0]].uop.d.fu == FU_CSR) ||
                         (entry_wb[scan_ptr[RW-1:0]].uop.d.fu == FU_NONE) ||
                         (entry_wb[scan_ptr[RW-1:0]].uop.d.fu == FU_ST)) begin
              if (serial_valid_o &&
                  (serial_uop_o.rob_idx == scan_ptr) && serial_ready_i) begin
                commit_valid_o[lane_idx] = 1'b1;
                commit_uop_o[lane_idx] = entry_wb[scan_ptr[RW-1:0]].uop;
                commit_count++;
                scan_ptr++;
              end
              commit_stop = 1'b1;
            end else begin
              commit_valid_o[lane_idx] = 1'b1;
              commit_uop_o[lane_idx] = entry_wb[scan_ptr[RW-1:0]].uop;
              commit_count++;
              scan_ptr++;
            end
          end else begin
            commit_stop = 1'b1;
          end
        end
      end
    end

    retire_count = commit_ready_i ? commit_count : 0;
  end

  always_comb begin
    for (int entry_idx = 0; entry_idx < NROB; entry_idx++)
      entry_n[entry_idx] = entry_wb[entry_idx];
    head_n = head_q;
    tail_n = tail_q;
    epoch_n = epoch_q;
    alloc_ptr = tail_q;

    if (flush_i) begin
      for (int entry_idx = 0; entry_idx < NROB; entry_idx++)
        entry_n[entry_idx].valid = 1'b0;
      head_n = tail_q;
      tail_n = tail_q;
      epoch_n = epoch_q + 1'b1;
    end else if (br_recover_match) begin
      for (int entry_idx = 0; entry_idx < NROB; entry_idx++) begin
        if (entry_q[entry_idx].valid &&
            rob_younger(entry_q[entry_idx].uop.rob_idx, br_rob_idx_i, head_q))
          entry_n[entry_idx].valid = 1'b0;
      end
      tail_n = br_rob_idx_i + 1'b1;
      epoch_n = epoch_q + 1'b1;
    end else begin
      if (retire_count != 0) begin
        for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
          if (commit_valid_o[lane_idx])
            entry_n[commit_uop_o[lane_idx].rob_idx[RW-1:0]].valid = 1'b0;
        end
        head_n = head_q + (RW+1)'(retire_count);
      end

      if (alloc_fire_i && alloc_ready_o && (alloc_count != 0)) begin
        for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
          if (alloc_valid_i[lane_idx]) begin
            entry_n[alloc_ptr[RW-1:0]] = '0;
            entry_n[alloc_ptr[RW-1:0]].valid = 1'b1;
            entry_n[alloc_ptr[RW-1:0]].complete = alloc_i[lane_idx].d.excp ||
                                                  (alloc_i[lane_idx].d.fu == FU_NONE) ||
                                                  (alloc_i[lane_idx].d.fu == FU_CSR);
            entry_n[alloc_ptr[RW-1:0]].excp = alloc_i[lane_idx].d.excp;
            entry_n[alloc_ptr[RW-1:0]].cause = alloc_i[lane_idx].d.cause;
            entry_n[alloc_ptr[RW-1:0]].tval = alloc_i[lane_idx].d.tval;
            entry_n[alloc_ptr[RW-1:0]].uop = alloc_i[lane_idx];
            alloc_ptr++;
          end
        end
        tail_n = alloc_ptr;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      head_q <= '0;
      tail_q <= '0;
      epoch_q <= '0;
      for (int entry_idx = 0; entry_idx < NROB; entry_idx++)
        entry_q[entry_idx] <= '0;
    end else begin
      head_q <= head_n;
      tail_q <= tail_n;
      epoch_q <= epoch_n;
      for (int entry_idx = 0; entry_idx < NROB; entry_idx++)
        entry_q[entry_idx] <= entry_n[entry_idx];
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert ((tail_q - head_q) <= (RW+1)'(NROB))
        else $error("ROB occupancy exceeded its capacity");
      if (br_recover_match)
        assert (entry_q[br_rob_idx_i[RW-1:0]].valid &&
                (entry_q[br_rob_idx_i[RW-1:0]].uop.rob_idx == br_rob_idx_i) &&
                (entry_q[br_rob_idx_i[RW-1:0]].uop.epoch == br_epoch_i))
          else $error("ROB recovery targeted an inactive entry");
      if (alloc_fire_i) begin
        logic [RW:0] expected_idx;
        assert (alloc_ready_o)
          else $error("ROB allocation fired without capacity");
        expected_idx = tail_q;
        for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
          if (alloc_valid_i[lane_idx]) begin
            assert (alloc_i[lane_idx].rob_idx == expected_idx)
              else $error("ROB allocation tag mismatch");
            assert (alloc_i[lane_idx].epoch == epoch_q)
              else $error("ROB allocation epoch mismatch");
            expected_idx++;
          end
        end
      end
    end
  end
`endif
endmodule
