`timescale 1ns/1ps

// Four-wide speculative register rename and physical-register allocation.
module rename_stage (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  mycore_pkg::dec_uop_t         dec_i [mycore_pkg::FW],
  output logic                         dec_ready_o,
  output mycore_pkg::ren_uop_t         ren_o [mycore_pkg::FW],
  output logic [mycore_pkg::FW-1:0]    dispatch_valid_o,
  input  logic                         dispatch_ready_i,
  output logic                         dispatch_fire_o,
  input  logic [mycore_pkg::RW:0]      rob_tail_i,
  input  logic [mycore_pkg::SW:0]      sq_tail_i,
  input  logic [mycore_pkg::RW:0]      rob_head_i,
  input  logic [mycore_pkg::EW-1:0]    epoch_i,

  // A full flush restores the committed map. A branch mispredict restores
  // the map and free set captured immediately after the branch was renamed.
  input  logic                         flush_i,
  input  logic                         br_resolve_valid_i,
  input  logic                         br_mispredict_i,
  input  logic [mycore_pkg::CW-1:0]    br_ckpt_id_i,
  input  logic [mycore_pkg::RW:0]      br_rob_idx_i,
  input  logic [mycore_pkg::EW-1:0]    br_epoch_i,

  // One entry for each retiring destination. Commit is in lane age order.
  input  logic [mycore_pkg::FW-1:0]    commit_valid_i,
  input  logic [5:0]                   commit_rd_i [mycore_pkg::FW],
  input  logic [mycore_pkg::PW-1:0]    commit_pdst_i [mycore_pkg::FW],
  input  logic [mycore_pkg::PW-1:0]    commit_prev_pdst_i [mycore_pkg::FW],

  output logic [$clog2(mycore_pkg::NPRF+1)-1:0] free_count_o,
  output logic [$clog2(mycore_pkg::NCKPT+1)-1:0] ckpt_free_count_o
);
  import mycore_pkg::*;

  localparam int NARCH = 64;
  localparam int PCOUNT_W = $clog2(NPRF + 1);
  localparam int CCOUNT_W = $clog2(NCKPT + 1);

  logic [PW-1:0] rat_q [NARCH];
  logic [PW-1:0] rat_n [NARCH];
  logic [PW-1:0] committed_rat_q [NARCH];
  logic [PW-1:0] committed_rat_n [NARCH];
  logic [NPRF-1:0] free_q, free_n;

  logic [NCKPT-1:0] ckpt_valid_q, ckpt_valid_n;
  logic [PW-1:0] ckpt_rat_q [NCKPT][NARCH];
  logic [PW-1:0] ckpt_rat_n [NCKPT][NARCH];
  logic [NPRF-1:0] ckpt_free_q [NCKPT];
  logic [NPRF-1:0] ckpt_free_n [NCKPT];
  logic [RW:0] ckpt_rob_q [NCKPT];
  logic [RW:0] ckpt_rob_n [NCKPT];
  logic [EW-1:0] ckpt_epoch_q [NCKPT];
  logic [EW-1:0] ckpt_epoch_n [NCKPT];

  logic [PW-1:0] work_rat [NARCH];
  logic [NPRF-1:0] work_free;
  logic [NCKPT-1:0] work_ckpt_valid;
  logic [NPRF-1:0] commit_free_mask;
  logic resources_available, rename_fire, ckpt_found, br_resolve_match;
  integer valid_uops, need_pregs, need_ckpts, avail_pregs, avail_ckpts;
  integer rob_offset, sq_offset;

  for (genvar lane_idx = 0; lane_idx < FW; lane_idx++) begin : g_dispatch_valid
    assign dispatch_valid_o[lane_idx] = dec_i[lane_idx].valid;
  end

  always_comb begin
    for (int arch_idx = 0; arch_idx < NARCH; arch_idx++) begin
      rat_n[arch_idx] = rat_q[arch_idx];
      committed_rat_n[arch_idx] = committed_rat_q[arch_idx];
      work_rat[arch_idx] = rat_q[arch_idx];
    end
    free_n = free_q;
    ckpt_valid_n = ckpt_valid_q;
    for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
      ckpt_free_n[ckpt_idx] = ckpt_free_q[ckpt_idx];
      ckpt_rob_n[ckpt_idx] = ckpt_rob_q[ckpt_idx];
      ckpt_epoch_n[ckpt_idx] = ckpt_epoch_q[ckpt_idx];
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
        ckpt_rat_n[ckpt_idx][arch_idx] = ckpt_rat_q[ckpt_idx][arch_idx];
    end

    commit_free_mask = '0;
    ckpt_found = 1'b0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (commit_valid_i[lane_idx]) begin
        committed_rat_n[commit_rd_i[lane_idx]] = commit_pdst_i[lane_idx];
        if (commit_prev_pdst_i[lane_idx] != '0)
          commit_free_mask[commit_prev_pdst_i[lane_idx]] = 1'b1;
      end
    end
    free_n |= commit_free_mask;
    for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
      if (ckpt_valid_q[ckpt_idx])
        ckpt_free_n[ckpt_idx] |= commit_free_mask;
    end

    work_free = free_n;
    br_resolve_match = br_resolve_valid_i && ckpt_valid_q[br_ckpt_id_i] &&
                       (ckpt_rob_q[br_ckpt_id_i] == br_rob_idx_i) &&
                       (ckpt_epoch_q[br_ckpt_id_i] == br_epoch_i);
    if (br_resolve_match && !br_mispredict_i)
      ckpt_valid_n[br_ckpt_id_i] = 1'b0;
    work_ckpt_valid = ckpt_valid_n;

    valid_uops = 0;
    need_pregs = 0;
    need_ckpts = 0;
    avail_pregs = 0;
    avail_ckpts = 0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (dec_i[lane_idx].valid)
        valid_uops++;
      if (dec_i[lane_idx].valid && dec_i[lane_idx].rd_valid && (dec_i[lane_idx].rd != 6'd0))
        need_pregs++;
      if (dec_i[lane_idx].valid && dec_i[lane_idx].is_branch)
        need_ckpts++;
    end
    for (int phys_idx = 0; phys_idx < NPRF; phys_idx++) begin
      if (work_free[phys_idx])
        avail_pregs++;
    end
    for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
      if (!work_ckpt_valid[ckpt_idx])
        avail_ckpts++;
    end

    free_count_o = PCOUNT_W'(avail_pregs);
    ckpt_free_count_o = CCOUNT_W'(avail_ckpts);
    resources_available = (avail_pregs >= need_pregs) &&
                          (avail_ckpts >= need_ckpts) &&
                          !flush_i && !(br_resolve_match && br_mispredict_i);
    dec_ready_o = resources_available && dispatch_ready_i;
    rename_fire = dec_ready_o && (valid_uops != 0);
    dispatch_fire_o = rename_fire;

    rob_offset = 0;
    sq_offset = 0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      ren_o[lane_idx] = '0;
      ren_o[lane_idx].d = dec_i[lane_idx];
      // Candidate validity is independent of backpressure; state changes only
      // when dispatch_fire_o is asserted.
      ren_o[lane_idx].d.valid = dec_i[lane_idx].valid;
      ren_o[lane_idx].rob_idx = rob_tail_i + (RW+1)'(rob_offset);
      ren_o[lane_idx].epoch = epoch_i;
      ren_o[lane_idx].sq_idx = sq_tail_i + (SW+1)'(sq_offset);

      if (dec_i[lane_idx].valid) begin
        if (dec_i[lane_idx].use1)
          ren_o[lane_idx].ps1 = work_rat[dec_i[lane_idx].rs1];
        if (dec_i[lane_idx].use2)
          ren_o[lane_idx].ps2 = work_rat[dec_i[lane_idx].rs2];
        if (dec_i[lane_idx].use3)
          ren_o[lane_idx].ps3 = work_rat[dec_i[lane_idx].rs3];

        if (dec_i[lane_idx].rd_valid && (dec_i[lane_idx].rd != 6'd0)) begin
          ren_o[lane_idx].prev_pdst = work_rat[dec_i[lane_idx].rd];
          for (int phys_idx = 0; phys_idx < NPRF; phys_idx++) begin
            if (work_free[phys_idx] && (ren_o[lane_idx].pdst == '0)) begin
              ren_o[lane_idx].pdst = PW'(phys_idx);
              work_free[phys_idx] = 1'b0;
            end
          end
          work_rat[dec_i[lane_idx].rd] = ren_o[lane_idx].pdst;
        end

        if (dec_i[lane_idx].is_branch) begin
          ckpt_found = 1'b0;
          for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
            if (!work_ckpt_valid[ckpt_idx] && !ckpt_found) begin
              ren_o[lane_idx].ckpt_id = CW'(ckpt_idx);
              work_ckpt_valid[ckpt_idx] = 1'b1;
              ckpt_found = 1'b1;
              if (rename_fire) begin
                ckpt_free_n[ckpt_idx] = work_free;
                ckpt_rob_n[ckpt_idx] = ren_o[lane_idx].rob_idx;
                ckpt_epoch_n[ckpt_idx] = epoch_i;
                for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
                  ckpt_rat_n[ckpt_idx][arch_idx] = work_rat[arch_idx];
              end
            end
          end
        end

        rob_offset++;
        if (dec_i[lane_idx].fu == FU_ST)
          sq_offset++;
      end
    end

    if (flush_i) begin
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
        rat_n[arch_idx] = committed_rat_n[arch_idx];
      free_n = '1;
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
        free_n[committed_rat_n[arch_idx]] = 1'b0;
      ckpt_valid_n = '0;
    end else if (br_resolve_match && br_mispredict_i) begin
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
        rat_n[arch_idx] = ckpt_rat_q[br_ckpt_id_i][arch_idx];
      free_n = ckpt_free_n[br_ckpt_id_i];
      for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
        if (ckpt_valid_q[ckpt_idx] &&
            ((CW'(ckpt_idx) == br_ckpt_id_i) ||
             rob_younger(ckpt_rob_q[ckpt_idx], br_rob_idx_i, rob_head_i)))
          ckpt_valid_n[ckpt_idx] = 1'b0;
      end
    end else begin
      if (rename_fire) begin
        ckpt_valid_n = work_ckpt_valid;
        for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
          rat_n[arch_idx] = work_rat[arch_idx];
        free_n = work_free;
      end
    end

    // Physical zero is permanently reserved for architectural x0.
    rat_n[0] = '0;
    committed_rat_n[0] = '0;
    free_n[0] = 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++) begin
        rat_q[arch_idx] <= PW'(arch_idx);
        committed_rat_q[arch_idx] <= PW'(arch_idx);
      end
      free_q <= {{(NPRF-NARCH){1'b1}}, {NARCH{1'b0}}};
      ckpt_valid_q <= '0;
      for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
        ckpt_free_q[ckpt_idx] <= '0;
        ckpt_rob_q[ckpt_idx] <= '0;
        ckpt_epoch_q[ckpt_idx] <= '0;
        for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
          ckpt_rat_q[ckpt_idx][arch_idx] <= '0;
      end
    end else begin
      for (int arch_idx = 0; arch_idx < NARCH; arch_idx++) begin
        rat_q[arch_idx] <= rat_n[arch_idx];
        committed_rat_q[arch_idx] <= committed_rat_n[arch_idx];
      end
      free_q <= free_n;
      ckpt_valid_q <= ckpt_valid_n;
      for (int ckpt_idx = 0; ckpt_idx < NCKPT; ckpt_idx++) begin
        ckpt_free_q[ckpt_idx] <= ckpt_free_n[ckpt_idx];
        ckpt_rob_q[ckpt_idx] <= ckpt_rob_n[ckpt_idx];
        ckpt_epoch_q[ckpt_idx] <= ckpt_epoch_n[ckpt_idx];
        for (int arch_idx = 0; arch_idx < NARCH; arch_idx++)
          ckpt_rat_q[ckpt_idx][arch_idx] <= ckpt_rat_n[ckpt_idx][arch_idx];
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (rat_n[0] == '0);
      assert (!free_n[0]);
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
        if (commit_valid_i[lane_idx]) begin
          assert (commit_rd_i[lane_idx] != 6'd0);
          assert (commit_pdst_i[lane_idx] != '0);
        end
      end
    end
  end
`endif
endmodule
