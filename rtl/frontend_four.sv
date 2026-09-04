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

  output logic                              imem_valid_o,
  output logic [31:0]                       imem_addr_o,
  output logic [1:0]                        imem_size_o,
  input  logic                              imem_ready_i,
  input  logic [127:0]                      imem_rdata_i,
  input  logic [3:0]                        imem_error_i,

  output mycore_pkg::fetch_inst_t           fetch_o [mycore_pkg::FW],
  output logic [mycore_pkg::FW-1:0]         rvc_illegal_o,
  output logic [mycore_pkg::FW-1:0]         fetch_fault_o,
  output logic [mycore_pkg::FW-1:0]         cross_word_o,
  output logic [31:0]                       pc_o
);
  import mycore_pkg::*;

  logic [31:0] pc_q;
  logic line_valid_q;
  logic [27:0] line_tag_q;
  logic [127:0] line_data_q;
  logic [3:0] line_error_q;
  logic [31:0] ras_q [RASN];
  logic [RASW-1:0] ras_sp_q;
  logic [RASW:0] ras_count_q;

  logic line_hit, source_valid, stop_bundle;
  logic [127:0] selected_line;
  logic [3:0] selected_errors;
  logic [31:0] lane_word [FW];
  logic [31:0] branch_imm [FW], jump_imm [FW];
  logic [31:0] bundle_next_pc;
  logic [31:0] ras_work [RASN];
  logic [RASW-1:0] ras_sp_work;
  logic [RASW:0] ras_count_work;
  logic lane_call, lane_return;
  integer word_index;

  assign line_hit = line_valid_q && (line_tag_q == pc_q[31:4]);
  assign source_valid = line_hit || imem_ready_i;
  assign selected_line = line_hit ? line_data_q : imem_rdata_i;
  assign selected_errors = line_hit ? line_error_q : imem_error_i;
  assign imem_valid_o = !sleeping_i && !line_hit;
  assign imem_addr_o = pc_q;
  assign imem_size_o = 2'd2;
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
      line_valid_q <= 1'b0;
      line_tag_q <= '0;
      line_data_q <= '0;
      line_error_q <= '0;
      ras_sp_q <= '0;
      ras_count_q <= '0;
      for (int ras_idx = 0; ras_idx < RASN; ras_idx++)
        ras_q[ras_idx] <= '0;
    end else begin
      if (invalidate_i)
        line_valid_q <= 1'b0;
      if (imem_ready_i && !line_hit && !redirect_valid_i && !invalidate_i) begin
        line_valid_q <= 1'b1;
        line_tag_q <= pc_q[31:4];
        line_data_q <= imem_rdata_i;
        line_error_q <= imem_error_i;
      end

      if (redirect_valid_i) begin
        pc_q <= redirect_pc_i;
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
        pc_q <= bundle_next_pc;
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
