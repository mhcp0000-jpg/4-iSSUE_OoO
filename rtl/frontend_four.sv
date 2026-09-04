`timescale 1ns/1ps

module frontend_four (
  input  logic                              clk_i,
  input  logic                              rst_ni,
  input  logic                              consume_i,
  input  logic                              sleeping_i,
  input  logic                              invalidate_i,
  input  logic                              redirect_valid_i,
  input  logic [31:0]                       redirect_pc_i,
  input  logic                              recover_valid_i,
  input  logic [mycore_pkg::RASW:0]         recover_ras_sp_i,
  input  logic [31:0]                       recover_ras_top_i,

  output logic                              imem_req_valid_o,
  output logic [31:0]                       imem_req_addr_o,
  output logic [1:0]                        imem_req_size_o,
  input  logic                              imem_req_ready_i,
  input  logic                              imem_rsp_valid_i,
  output logic                              imem_rsp_ready_o,
  input  logic [127:0]                      imem_rsp_rdata_i,
  input  logic [3:0]                        imem_rsp_error_i,

  output mycore_pkg::fetch_inst_t           fetch_o [mycore_pkg::FW],
  output logic [mycore_pkg::FW-1:0]         rvc_illegal_o,
  output logic [mycore_pkg::FW-1:0]         fetch_fault_o,
  output logic [mycore_pkg::FW-1:0]         cross_word_o,
  output logic [31:0]                       pc_o
);
  import mycore_pkg::*;

  localparam int TXN = 4;
  localparam int LINEQ = 4;
  localparam int TXW = $clog2(TXN);
  localparam int LQW = $clog2(LINEQ);
  localparam int ECW = 8;
  localparam logic [$clog2(TXN+1)-1:0] TXN_COUNT_MAX = 3'd4;
  localparam logic [$clog2(LINEQ+1)-1:0] LINE_COUNT_MAX = 3'd4;

  logic [31:0] pc_q, next_req_pc_q;
  logic sleeping_q;
  logic [ECW-1:0] epoch_q;
  logic req_hold_valid_q, req_hold_canceled_q;
  logic [31:0] req_hold_addr_q;
  logic [ECW-1:0] req_hold_epoch_q;

  logic [TXW-1:0] txn_head_q, txn_tail_q;
  logic [$clog2(TXN+1)-1:0] txn_count_q;
  logic [31:0] txn_pc_q [TXN];
  logic [ECW-1:0] txn_epoch_q [TXN];
  logic [TXN-1:0] txn_canceled_q;

  logic [LQW-1:0] line_head_q, line_tail_q;
  logic [$clog2(LINEQ+1)-1:0] line_count_q;
  logic [31:0] line_pc_q [LINEQ];
  logic [127:0] line_data_q [LINEQ];
  logic [3:0] line_error_q [LINEQ];

  logic [31:0] ras_q [RASN];
  logic [RASW-1:0] ras_sp_q;
  logic [RASW:0] ras_count_q;

  logic source_valid, stop_bundle, predicted_redirect;
  logic flush_requests, req_fire, rsp_fire, line_pop, line_push;
  logic txn_stale, line_space;
  logic req_candidate_valid, req_using_hold, req_accepted_canceled;
  logic req_hold_matches_restart;
  logic req_live_fire;
  logic [31:0] req_candidate_addr;
  logic [ECW-1:0] req_candidate_epoch;
  logic [127:0] selected_line;
  logic [3:0] selected_errors;
  logic [31:0] lane_word [FW];
  logic [31:0] branch_imm [FW], jump_imm [FW];
  logic [31:0] bundle_next_pc;
  logic [31:0] restart_pc;
  logic [31:0] ras_work [RASN];
  logic [RASW-1:0] ras_sp_work;
  logic [RASW:0] ras_count_work;
  logic lane_call, lane_return;
  integer word_index;

  assign source_valid = (line_count_q != 0) &&
                        (line_pc_q[line_head_q][31:4] == pc_q[31:4]);
  assign selected_line = line_data_q[line_head_q];
  assign selected_errors = line_error_q[line_head_q];
  assign predicted_redirect = consume_i && source_valid &&
                              (fetch_o[0].pred_taken || fetch_o[1].pred_taken ||
                               fetch_o[2].pred_taken || fetch_o[3].pred_taken);
  assign flush_requests = redirect_valid_i || invalidate_i ||
                          (sleeping_i && !sleeping_q) || predicted_redirect;
  assign line_pop = consume_i && source_valid;
  assign line_space = (line_count_q != LINE_COUNT_MAX) || line_pop;
  assign txn_stale = txn_canceled_q[txn_head_q] ||
                     (txn_epoch_q[txn_head_q] != epoch_q);
  assign imem_rsp_ready_o = (txn_count_q != 0) &&
                            (flush_requests || txn_stale || line_space);
  assign rsp_fire = imem_rsp_valid_i && imem_rsp_ready_o;
  assign line_push = rsp_fire && !flush_requests && !txn_stale;

  assign restart_pc = redirect_valid_i ? redirect_pc_i :
                      (predicted_redirect ? bundle_next_pc : pc_q);
  assign req_candidate_valid = !sleeping_i &&
                               (txn_count_q != TXN_COUNT_MAX);
  assign req_candidate_addr = flush_requests ? restart_pc : next_req_pc_q;
  assign req_candidate_epoch = flush_requests ? epoch_q + 1'b1 : epoch_q;
  assign req_using_hold = req_hold_valid_q;
  assign req_hold_matches_restart = req_hold_valid_q && flush_requests &&
                                    (req_hold_addr_q[31:4] == restart_pc[31:4]);
  assign imem_req_valid_o = req_hold_valid_q || req_candidate_valid;
  assign imem_req_addr_o = req_hold_valid_q ? req_hold_addr_q :
                                              req_candidate_addr;
  assign imem_req_size_o = 2'd2;
  assign req_fire = imem_req_valid_o && imem_req_ready_i;
  assign req_accepted_canceled = req_using_hold &&
                                 !req_hold_matches_restart &&
                                 (req_hold_canceled_q || flush_requests);
  assign req_live_fire = req_fire && !req_accepted_canceled;
  assign pc_o = pc_q;

  always_comb begin
    rvc_illegal_o = '0;
    fetch_fault_o = '0;
    cross_word_o = '0;
    stop_bundle = 1'b0;
    bundle_next_pc = pc_q;
    ras_sp_work = ras_sp_q;
    ras_count_work = ras_count_q;
    lane_call = 1'b0;
    lane_return = 1'b0;
    word_index = 0;
    for (int ras_idx = 0; ras_idx < RASN; ras_idx++)
      ras_work[ras_idx] = ras_q[ras_idx];

    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      fetch_o[lane_idx] = '0;
      lane_word[lane_idx] = '0;
      branch_imm[lane_idx] = '0;
      jump_imm[lane_idx] = '0;
      word_index = int'(pc_q[3:2]) + lane_idx;
      if (word_index < FW)
        lane_word[lane_idx] = selected_line[word_index*32 +: 32];

      if (source_valid && !sleeping_i && !redirect_valid_i &&
          !stop_bundle && (word_index < FW)) begin
        fetch_o[lane_idx].valid = 1'b1;
        fetch_o[lane_idx].pc = pc_q + 32'(lane_idx * 4);
        fetch_o[lane_idx].rvc = (lane_word[lane_idx][1:0] != 2'b11);
        fetch_o[lane_idx].inst = lane_word[lane_idx];
        fetch_o[lane_idx].raw16 = lane_word[lane_idx][15:0];
        fetch_o[lane_idx].pred_target = fetch_o[lane_idx].pc + 32'd4;
        fetch_o[lane_idx].ghr = '0;
        rvc_illegal_o[lane_idx] = fetch_o[lane_idx].rvc;
        fetch_fault_o[lane_idx] = selected_errors[word_index];

        branch_imm[lane_idx] =
          {{19{lane_word[lane_idx][31]}}, lane_word[lane_idx][31],
           lane_word[lane_idx][7], lane_word[lane_idx][30:25],
           lane_word[lane_idx][11:8], 1'b0};
        jump_imm[lane_idx] =
          {{11{lane_word[lane_idx][31]}}, lane_word[lane_idx][31],
           lane_word[lane_idx][19:12], lane_word[lane_idx][20],
           lane_word[lane_idx][30:21], 1'b0};
        lane_call = !fetch_o[lane_idx].rvc &&
                    ((lane_word[lane_idx][6:0] == 7'b1101111) ||
                     (lane_word[lane_idx][6:0] == 7'b1100111)) &&
                    ((lane_word[lane_idx][11:7] == 5'd1) ||
                     (lane_word[lane_idx][11:7] == 5'd5));
        lane_return = !fetch_o[lane_idx].rvc &&
                      (lane_word[lane_idx][6:0] == 7'b1100111) &&
                      (lane_word[lane_idx][14:12] == 3'b000) &&
                      (lane_word[lane_idx][11:7] == 5'd0) &&
                      ((lane_word[lane_idx][19:15] == 5'd1) ||
                       (lane_word[lane_idx][19:15] == 5'd5)) &&
                      (lane_word[lane_idx][31:20] == 12'd0);

        if (!fetch_o[lane_idx].rvc && !fetch_fault_o[lane_idx]) begin
          if (lane_word[lane_idx][6:0] == 7'b1101111) begin
            fetch_o[lane_idx].pred_taken = 1'b1;
            fetch_o[lane_idx].pred_target = fetch_o[lane_idx].pc +
                                             jump_imm[lane_idx];
          end else if ((lane_word[lane_idx][6:0] == 7'b1100011) &&
                       branch_imm[lane_idx][31]) begin
            fetch_o[lane_idx].pred_taken = 1'b1;
            fetch_o[lane_idx].pred_target = fetch_o[lane_idx].pc +
                                             branch_imm[lane_idx];
          end else if (lane_return && (ras_count_work != 0)) begin
            fetch_o[lane_idx].pred_taken = 1'b1;
            fetch_o[lane_idx].pred_target = ras_work[ras_sp_work - 1'b1];
          end
        end

        if (!fetch_fault_o[lane_idx]) begin
          if (lane_return && (ras_count_work != 0)) begin
            ras_sp_work = ras_sp_work - 1'b1;
            ras_count_work = ras_count_work - 1'b1;
          end else if (lane_call) begin
            ras_work[ras_sp_work] = fetch_o[lane_idx].pc + 32'd4;
            ras_sp_work = ras_sp_work + 1'b1;
            if (!ras_count_work[RASW])
              ras_count_work = ras_count_work + 1'b1;
          end
        end
        fetch_o[lane_idx].ras_sp = ras_count_work;
        fetch_o[lane_idx].ras_top = (ras_count_work != 0) ?
                                     ras_work[ras_sp_work - 1'b1] : 32'd0;

        bundle_next_pc = fetch_o[lane_idx].pred_taken ?
                         fetch_o[lane_idx].pred_target :
                         fetch_o[lane_idx].pc + 32'd4;
        if (fetch_o[lane_idx].pred_taken || fetch_fault_o[lane_idx])
          stop_bundle = 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= RESET_PC;
      next_req_pc_q <= RESET_PC;
      sleeping_q <= 1'b0;
      epoch_q <= '0;
      req_hold_valid_q <= 1'b0;
      req_hold_canceled_q <= 1'b0;
      req_hold_addr_q <= '0;
      req_hold_epoch_q <= '0;
      txn_head_q <= '0;
      txn_tail_q <= '0;
      txn_count_q <= '0;
      txn_canceled_q <= '0;
      line_head_q <= '0;
      line_tail_q <= '0;
      line_count_q <= '0;
      ras_sp_q <= '0;
      ras_count_q <= '0;
      for (int txn_idx = 0; txn_idx < TXN; txn_idx++) begin
        txn_pc_q[txn_idx] <= '0;
        txn_epoch_q[txn_idx] <= '0;
      end
      for (int line_idx = 0; line_idx < LINEQ; line_idx++) begin
        line_pc_q[line_idx] <= '0;
        line_data_q[line_idx] <= '0;
        line_error_q[line_idx] <= '0;
      end
      for (int ras_idx = 0; ras_idx < RASN; ras_idx++)
        ras_q[ras_idx] <= '0;
    end else begin
      sleeping_q <= sleeping_i;

      if (req_hold_valid_q) begin
        if (flush_requests) begin
          req_hold_canceled_q <= !req_hold_matches_restart;
          if (req_hold_matches_restart)
            req_hold_epoch_q <= epoch_q + 1'b1;
        end
        if (req_fire) begin
          req_hold_valid_q <= 1'b0;
          req_hold_canceled_q <= 1'b0;
        end
      end else if (req_candidate_valid && !imem_req_ready_i) begin
        req_hold_valid_q <= 1'b1;
        req_hold_canceled_q <= 1'b0;
        req_hold_addr_q <= req_candidate_addr;
        req_hold_epoch_q <= req_candidate_epoch;
      end

      if (rsp_fire) begin
        txn_canceled_q[txn_head_q] <= 1'b0;
        txn_head_q <= txn_head_q + 1'b1;
      end
      if (req_fire) begin
        txn_pc_q[txn_tail_q] <= imem_req_addr_o;
        txn_epoch_q[txn_tail_q] <= req_hold_matches_restart ? epoch_q + 1'b1 :
          (req_using_hold ? req_hold_epoch_q : req_candidate_epoch);
        txn_canceled_q[txn_tail_q] <= req_accepted_canceled;
        txn_tail_q <= txn_tail_q + 1'b1;
        if (req_live_fire)
          next_req_pc_q <= {imem_req_addr_o[31:4], 4'b0000} + 32'd16;
      end
      case ({req_fire, rsp_fire})
        2'b10: txn_count_q <= txn_count_q + 1'b1;
        2'b01: txn_count_q <= txn_count_q - 1'b1;
        default: txn_count_q <= txn_count_q;
      endcase

      if (line_pop)
        line_head_q <= line_head_q + 1'b1;
      if (line_push) begin
        line_pc_q[line_tail_q] <= txn_pc_q[txn_head_q];
        line_data_q[line_tail_q] <= imem_rsp_rdata_i;
        line_error_q[line_tail_q] <= imem_rsp_error_i;
        line_tail_q <= line_tail_q + 1'b1;
      end
      case ({line_push, line_pop})
        2'b10: line_count_q <= line_count_q + 1'b1;
        2'b01: line_count_q <= line_count_q - 1'b1;
        default: line_count_q <= line_count_q;
      endcase

      if (flush_requests) begin
        epoch_q <= epoch_q + 1'b1;
        txn_canceled_q <= {TXN{1'b1}};
        if (req_live_fire)
          txn_canceled_q[txn_tail_q] <= 1'b0;
        line_head_q <= '0;
        line_tail_q <= '0;
        line_count_q <= '0;
        if (redirect_valid_i) begin
          pc_q <= redirect_pc_i;
          next_req_pc_q <= (req_live_fire || req_hold_matches_restart) ?
                             {redirect_pc_i[31:4], 4'b0000} + 32'd16 :
                             redirect_pc_i;
        end else if (predicted_redirect) begin
          pc_q <= bundle_next_pc;
          next_req_pc_q <= (req_live_fire || req_hold_matches_restart) ?
                             {bundle_next_pc[31:4], 4'b0000} + 32'd16 :
                             bundle_next_pc;
        end else begin
          next_req_pc_q <= (req_live_fire || req_hold_matches_restart) ?
                             {pc_q[31:4], 4'b0000} + 32'd16 : pc_q;
        end
      end else if (consume_i) begin
        pc_q <= bundle_next_pc;
      end

      if (redirect_valid_i) begin
        if (recover_valid_i) begin
          ras_sp_q <= recover_ras_sp_i[RASW-1:0];
          ras_count_q <= recover_ras_sp_i;
          if (recover_ras_sp_i != 0)
            ras_q[recover_ras_sp_i[RASW-1:0] - 1'b1] <= recover_ras_top_i;
        end else begin
          ras_sp_q <= '0;
          ras_count_q <= '0;
        end
      end else if (consume_i) begin
        ras_sp_q <= ras_sp_work;
        ras_count_q <= ras_count_work;
        for (int ras_idx = 0; ras_idx < RASN; ras_idx++)
          ras_q[ras_idx] <= ras_work[ras_idx];
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      for (int lane_idx = 1; lane_idx < FW; lane_idx++)
        assert (!fetch_o[lane_idx].valid || fetch_o[lane_idx-1].valid);
      if (consume_i)
        assert (fetch_o[0].valid);
    end
  end
`endif
endmodule
