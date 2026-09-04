`timescale 1ns/1ps

module mycore_core (
  input  logic        clk_i,
  input  logic        rst_ni,

  output logic         imem_req_valid_o,
  output logic [31:0]  imem_req_addr_o,
  output logic [1:0]   imem_req_size_o,
  input  logic         imem_req_ready_i,
  input  logic         imem_rsp_valid_i,
  output logic         imem_rsp_ready_o,
  input  logic [127:0] imem_rsp_rdata_i,
  input  logic [3:0]   imem_rsp_error_i,

  output logic [mycore_pkg::NLSU-1:0] dmem_valid_o,
  output logic [mycore_pkg::NLSU-1:0] dmem_write_o,
  output logic [31:0] dmem_addr_o [mycore_pkg::NLSU],
  output logic [1:0]  dmem_size_o [mycore_pkg::NLSU],
  output logic [31:0] dmem_wdata_o [mycore_pkg::NLSU],
  output logic [3:0]  dmem_wstrb_o [mycore_pkg::NLSU],
  input  logic [mycore_pkg::NLSU-1:0] dmem_ready_i,
  input  logic [31:0] dmem_rdata_i [mycore_pkg::NLSU],
  input  logic [mycore_pkg::NLSU-1:0] dmem_error_i,

  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  input  logic [63:0] time_i,

  output logic [7:0]  pmpcfg_o [csr_pkg::NPMP],
  output logic [31:0] pmpaddr_o [csr_pkg::NPMP],
  output logic [31:0] debug_pc_o,
  output logic [mycore_pkg::RW:0] debug_rob_occupancy_o
);
  import mycore_pkg::*;
  import csr_pkg::*;

  localparam int INT_RBASE = NREAD_DISPATCH;
  localparam int MEM_RBASE = NREAD_DISPATCH + NREAD_INT;

  fetch_inst_t fetch_inst [FW];
  dec_uop_t decoded_uop [FW], dec_bundle [FW];
  logic [FW-1:0] rvc_illegal, fetch_fault, fetch_cross_word;
  logic fetch_consume, frontend_redirect, frontend_invalidate;
  logic [31:0] frontend_redirect_pc, fetch_pc;

  ren_uop_t ren_uop [FW];
  logic rename_ready, dispatch_fire;
  logic [FW-1:0] dispatch_valid;
  logic [FW-1:0] int_dispatch_valid, mem_dispatch_valid, fp_dispatch_valid;
  logic [FW-1:0] store_dispatch_valid;
  logic int_iq_ready, mem_iq_ready, fp_iq_ready, sq_dispatch_ready;
  logic backend_ready;

  logic [RW:0] rob_head, rob_tail, rob_occupancy;
  logic [EW-1:0] rob_epoch;
  logic rob_ready, rob_recover_fire;
  logic [FW-1:0] rob_commit_valid;
  ren_uop_t rob_commit_uop [FW];
  logic rob_serial_valid, rob_serial_ready;
  ren_uop_t rob_serial_uop;
  logic rob_trap_valid;
  ren_uop_t rob_trap_uop;
  logic [3:0] rob_trap_cause;
  logic [31:0] rob_trap_tval;
  rob_wb_t rob_wb [NWB];

  logic [FW-1:0] rename_commit_valid;
  logic [5:0] rename_commit_rd [FW];
  logic [PW-1:0] rename_commit_pdst [FW], rename_commit_prev [FW];
  logic [$clog2(NPRF+1)-1:0] free_count;
  logic [$clog2(NCKPT+1)-1:0] ckpt_free_count;

  logic [PW-1:0] prf_raddr [NREAD];
  logic [31:0] prf_rdata [NREAD];
  logic [NREAD-1:0] prf_rready;
  logic [31:0] serial_prf_rdata;
  logic serial_prf_rready;
  logic [31:0] mem_base_rdata [NLSU], mem_data_rdata [NLSU];
  logic [FW-1:0] dispatch_src1_ready, dispatch_src2_ready, dispatch_src3_ready;
  logic [NWB-1:0] wb_accepted;
  exec_wb_t exec_wb_q [NWB], exec_wb_n [NWB];

  logic [FW-1:0] int_issue_valid, int_issue_accept;
  ren_uop_t int_issue_uop [FW];
  logic [4:0] int_iq_occupancy;
  logic [NLSU-1:0] mem_issue_valid, mem_issue_accept;
  ren_uop_t mem_issue_uop [NLSU];
  logic [4:0] mem_iq_occupancy;
  logic fp_issue_valid;
  ren_uop_t fp_issue_uop [1];
  logic [3:0] fp_iq_occupancy;

  exec_wb_t alu_wb [FW], muldiv_wb, lsu_wb [NLSU], sq_execute_wb [NLSU];
  exec_wb_t store_fault_wb, system_wb, csr_wb;
  br_res_t alu_br [FW], branch_q, branch_n;
  logic branch_slot_used, muldiv_slot_used;
  ren_uop_t muldiv_uop;
  logic [31:0] muldiv_src1, muldiv_src2;
  logic muldiv_valid;

  logic [NLSU-1:0] lsu_input_valid, lsu_ready, lsu_busy, lsu_dmem_valid;
  ren_uop_t lsu_input_uop [NLSU];
  logic [31:0] lsu_input_base [NLSU], lsu_input_data [NLSU];
  logic [NLSU-1:0] lsu_input_unknown;
  logic [3:0] lsu_input_forward_mask [NLSU];
  logic [31:0] lsu_input_forward_data [NLSU];
  logic [31:0] lsu_dmem_addr [NLSU];
  logic [1:0] lsu_dmem_size [NLSU];
  logic [NLSU-1:0] load_dmem_ready, load_dmem_error;
  logic [NLSU-1:0] store_execute_valid;
  ren_uop_t store_execute_uop [NLSU];
  logic [31:0] store_execute_addr [NLSU], store_execute_data [NLSU];
  logic [3:0] store_execute_strb [NLSU];
  logic [NLSU-1:0] load_query_valid, load_older_unknown;
  logic [31:0] load_query_addr [NLSU];
  logic [SW:0] load_query_sq [NLSU];
  logic [3:0] load_forward_mask [NLSU];
  logic [31:0] load_forward_data [NLSU];
  integer oldest_lsu_slot, younger_lsu_slot;

  logic [SW:0] sq_head, sq_tail;
  logic sq_commit_ready, sq_commit_fire;
  ren_uop_t sq_commit_uop;
  logic [31:0] sq_commit_addr, sq_commit_data;
  logic [3:0] sq_commit_strb;
  logic [4:0] sq_occupancy;
  logic store_dmem_valid, store_dmem_write;
  logic [31:0] store_dmem_addr, store_dmem_wdata;
  logic [1:0] store_dmem_size;
  logic [3:0] store_dmem_wstrb;
  logic store_dmem_ready, store_dmem_error;

  logic csr_valid, csr_ready, csr_illegal, csr_src_zero;
  logic [5:0] csr_op;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata, csr_rdata;
  logic csr_interrupt_pending, csr_wake_pending, csr_sleeping, fp_enabled;
  logic [4:0] csr_interrupt_cause, fp_flags;
  logic [2:0] frm;
  logic [31:0] trap_vector, mret_pc;
  logic [31:0] perf_events;
  logic [$clog2(FW+1)-1:0] retire_count;
  logic mret_commit, wfi_commit;
  logic other_serial_ready;
  logic serial_csr_access, serial_source_ready;

  logic interrupt_take, trap_take, global_flush;
  logic pipeline_issue_block, control_serial_commit;
  logic control_flush_q;
  logic [31:0] control_target_q;

  frontend_four u_frontend (
    .clk_i, .rst_ni, .consume_i(fetch_consume), .sleeping_i(csr_sleeping),
    .invalidate_i(frontend_invalidate),
    .redirect_valid_i(frontend_redirect), .redirect_pc_i(frontend_redirect_pc),
    .recover_valid_i(rob_recover_fire), .recover_ras_sp_i(branch_q.ras_sp),
    .recover_ras_top_i(branch_q.ras_top),
    .imem_req_valid_o, .imem_req_addr_o, .imem_req_size_o, .imem_req_ready_i,
    .imem_rsp_valid_i, .imem_rsp_ready_o, .imem_rsp_rdata_i, .imem_rsp_error_i,
    .fetch_o(fetch_inst), .rvc_illegal_o(rvc_illegal),
    .fetch_fault_o(fetch_fault), .cross_word_o(fetch_cross_word), .pc_o(fetch_pc)
  );

  for (genvar lane_idx = 0; lane_idx < FW; lane_idx++) begin : g_decoder
    decoder u_decoder (
      .fi(fetch_inst[lane_idx]), .rvc_illegal(rvc_illegal[lane_idx]),
      .u(decoded_uop[lane_idx])
    );
  end

  always_comb begin
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      dec_bundle[lane_idx] = decoded_uop[lane_idx];
      if (fetch_fault[lane_idx]) begin
        dec_bundle[lane_idx] = '0;
        dec_bundle[lane_idx].valid = 1'b1;
        dec_bundle[lane_idx].pc = fetch_inst[lane_idx].pc;
        dec_bundle[lane_idx].inst = fetch_inst[lane_idx].inst;
        dec_bundle[lane_idx].fu = FU_CSR;
        dec_bundle[lane_idx].excp = 1'b1;
        dec_bundle[lane_idx].cause = EXC_IACCESS;
        dec_bundle[lane_idx].tval = fetch_inst[lane_idx].pc;
      end else if (fetch_cross_word[lane_idx]) begin
        dec_bundle[lane_idx].fu = FU_CSR;
        dec_bundle[lane_idx].use1 = 1'b0;
        dec_bundle[lane_idx].use2 = 1'b0;
        dec_bundle[lane_idx].use3 = 1'b0;
        dec_bundle[lane_idx].rd_valid = 1'b0;
        dec_bundle[lane_idx].is_branch = 1'b0;
        dec_bundle[lane_idx].excp = 1'b1;
        dec_bundle[lane_idx].cause = EXC_ILLEGAL;
        dec_bundle[lane_idx].tval = fetch_inst[lane_idx].inst;
      end
      if (dec_bundle[lane_idx].valid && !fetch_fault[lane_idx] &&
          ((dec_bundle[lane_idx].fu == FU_FPU) || dec_bundle[lane_idx].rd[5] ||
           (dec_bundle[lane_idx].use1 && dec_bundle[lane_idx].rs1[5]) ||
           (dec_bundle[lane_idx].use2 && dec_bundle[lane_idx].rs2[5]) ||
           (dec_bundle[lane_idx].use3 && dec_bundle[lane_idx].rs3[5]))) begin
        dec_bundle[lane_idx].fu = FU_CSR;
        dec_bundle[lane_idx].use1 = 1'b0;
        dec_bundle[lane_idx].use2 = 1'b0;
        dec_bundle[lane_idx].use3 = 1'b0;
        dec_bundle[lane_idx].rd_valid = 1'b0;
        dec_bundle[lane_idx].is_branch = 1'b0;
        dec_bundle[lane_idx].excp = 1'b1;
        dec_bundle[lane_idx].cause = EXC_ILLEGAL;
        dec_bundle[lane_idx].tval = fetch_inst[lane_idx].inst;
      end
      if (dec_bundle[lane_idx].valid && !fetch_fault[lane_idx] &&
          fetch_inst[lane_idx].rvc) begin
        dec_bundle[lane_idx].fu = FU_CSR;
        dec_bundle[lane_idx].use1 = 1'b0;
        dec_bundle[lane_idx].use2 = 1'b0;
        dec_bundle[lane_idx].use3 = 1'b0;
        dec_bundle[lane_idx].rd_valid = 1'b0;
        dec_bundle[lane_idx].is_branch = 1'b0;
        dec_bundle[lane_idx].excp = 1'b1;
        dec_bundle[lane_idx].cause = EXC_ILLEGAL;
        dec_bundle[lane_idx].tval = {16'd0, fetch_inst[lane_idx].raw16};
      end
    end
  end

  always_comb begin
    int_dispatch_valid = '0;
    mem_dispatch_valid = '0;
    fp_dispatch_valid = '0;
    store_dispatch_valid = '0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (dispatch_valid[lane_idx]) begin
        int_dispatch_valid[lane_idx] = (dec_bundle[lane_idx].fu == FU_ALU) ||
                                       (dec_bundle[lane_idx].fu == FU_BR) ||
                                       (dec_bundle[lane_idx].fu == FU_MUL) ||
                                       (dec_bundle[lane_idx].fu == FU_DIV);
        mem_dispatch_valid[lane_idx] = (dec_bundle[lane_idx].fu == FU_LD) ||
                                       (dec_bundle[lane_idx].fu == FU_ST);
        fp_dispatch_valid[lane_idx] = (dec_bundle[lane_idx].fu == FU_FPU);
        store_dispatch_valid[lane_idx] = (dec_bundle[lane_idx].fu == FU_ST);
      end
    end
    backend_ready = rob_ready && int_iq_ready && mem_iq_ready && fp_iq_ready &&
                     sq_dispatch_ready && !global_flush && !trap_take &&
                     !csr_interrupt_pending;
    fetch_consume = dispatch_fire && (|dispatch_valid);
  end

  rename_stage u_rename (
    .clk_i, .rst_ni, .dec_i(dec_bundle), .dec_ready_o(rename_ready), .ren_o(ren_uop),
    .dispatch_valid_o(dispatch_valid), .dispatch_ready_i(backend_ready),
    .dispatch_fire_o(dispatch_fire), .rob_tail_i(rob_tail), .sq_tail_i(sq_tail),
    .rob_head_i(rob_head), .epoch_i(rob_epoch), .flush_i(global_flush),
    .br_resolve_valid_i(branch_q.valid), .br_mispredict_i(branch_q.mispredict),
    .br_ckpt_id_i(branch_q.ckpt_id), .br_rob_idx_i(branch_q.rob_idx),
    .br_epoch_i(branch_q.epoch), .commit_valid_i(rename_commit_valid),
    .commit_rd_i(rename_commit_rd), .commit_pdst_i(rename_commit_pdst),
    .commit_prev_pdst_i(rename_commit_prev), .free_count_o(free_count),
    .ckpt_free_count_o(ckpt_free_count)
  );

  rob u_rob (
    .clk_i, .rst_ni, .alloc_i(ren_uop), .alloc_valid_i(dispatch_valid),
    .alloc_ready_o(rob_ready), .alloc_fire_i(dispatch_fire), .wb_i(rob_wb),
    .commit_valid_o(rob_commit_valid), .commit_uop_o(rob_commit_uop),
    .commit_ready_i(1'b1), .serial_ready_i(rob_serial_ready),
    .serial_valid_o(rob_serial_valid), .serial_uop_o(rob_serial_uop),
    .trap_valid_o(rob_trap_valid), .trap_uop_o(rob_trap_uop),
    .trap_cause_o(rob_trap_cause), .trap_tval_o(rob_trap_tval),
    .flush_i(global_flush), .br_recover_valid_i(branch_q.valid && branch_q.mispredict),
    .br_rob_idx_i(branch_q.rob_idx), .br_epoch_i(branch_q.epoch),
    .br_recover_fire_o(rob_recover_fire), .rob_head_o(rob_head),
    .rob_tail_o(rob_tail), .occupancy_o(rob_occupancy), .rob_epoch_o(rob_epoch)
  );

  always_comb begin
    for (int read_idx = 0; read_idx < NREAD; read_idx++)
      prf_raddr[read_idx] = '0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      prf_raddr[lane_idx*3] = ren_uop[lane_idx].ps1;
      prf_raddr[lane_idx*3+1] = ren_uop[lane_idx].ps2;
      prf_raddr[lane_idx*3+2] = ren_uop[lane_idx].ps3;
      dispatch_src1_ready[lane_idx] = prf_rready[lane_idx*3];
      dispatch_src2_ready[lane_idx] = prf_rready[lane_idx*3+1];
      dispatch_src3_ready[lane_idx] = prf_rready[lane_idx*3+2];
      for (int older_lane = 0; older_lane < lane_idx; older_lane++) begin
        if (dispatch_valid[older_lane] && ren_uop[older_lane].d.rd_valid) begin
          if (ren_uop[lane_idx].d.use1 &&
              (ren_uop[lane_idx].ps1 == ren_uop[older_lane].pdst))
            dispatch_src1_ready[lane_idx] = 1'b0;
          if (ren_uop[lane_idx].d.use2 &&
              (ren_uop[lane_idx].ps2 == ren_uop[older_lane].pdst))
            dispatch_src2_ready[lane_idx] = 1'b0;
          if (ren_uop[lane_idx].d.use3 &&
              (ren_uop[lane_idx].ps3 == ren_uop[older_lane].pdst))
            dispatch_src3_ready[lane_idx] = 1'b0;
        end
      end
      prf_raddr[INT_RBASE+lane_idx*2] = int_issue_uop[lane_idx].ps1;
      prf_raddr[INT_RBASE+lane_idx*2+1] = int_issue_uop[lane_idx].ps2;
    end
    for (int mem_idx = 0; mem_idx < NLSU; mem_idx++) begin
      prf_raddr[MEM_RBASE+mem_idx*2] = mem_issue_uop[mem_idx].ps1;
      prf_raddr[MEM_RBASE+mem_idx*2+1] = mem_issue_uop[mem_idx].ps2;
      mem_base_rdata[mem_idx] = prf_rdata[MEM_RBASE+mem_idx*2];
      mem_data_rdata[mem_idx] = prf_rdata[MEM_RBASE+mem_idx*2+1];
    end
  end

  physical_regfile u_prf (
    .clk_i, .rst_ni, .alloc_fire_i(dispatch_fire), .alloc_valid_i(dispatch_valid),
    .alloc_uop_i(ren_uop), .wb_i(exec_wb_q), .wb_accepted_o(wb_accepted),
    .raddr_i(prf_raddr), .rdata_o(prf_rdata), .rready_o(prf_rready),
    .serial_raddr_i(rob_serial_uop.ps1), .serial_rdata_o(serial_prf_rdata),
    .serial_rready_o(serial_prf_rready)
  );

  issue_queue #(.DEPTH(NIQ_INT), .ISSUE_WIDTH(FW)) u_int_iq (
    .clk_i, .rst_ni, .dispatch_valid_i(int_dispatch_valid), .dispatch_uop_i(ren_uop),
    .dispatch_src1_ready_i(dispatch_src1_ready),
    .dispatch_src2_ready_i(dispatch_src2_ready),
    .dispatch_src3_ready_i(dispatch_src3_ready), .dispatch_ready_o(int_iq_ready),
    .dispatch_fire_i(dispatch_fire), .wb_i(exec_wb_q), .wb_accepted_i(wb_accepted),
    .issue_valid_o(int_issue_valid), .issue_uop_o(int_issue_uop),
    .issue_accept_i(int_issue_accept), .flush_i(global_flush),
    .br_recover_fire_i(rob_recover_fire), .br_rob_idx_i(branch_q.rob_idx),
    .rob_head_i(rob_head), .occupancy_o(int_iq_occupancy)
  );

  issue_queue #(.DEPTH(NIQ_MEM), .ISSUE_WIDTH(NLSU), .STRICT_ORDER(1'b1)) u_mem_iq (
    .clk_i, .rst_ni, .dispatch_valid_i(mem_dispatch_valid), .dispatch_uop_i(ren_uop),
    .dispatch_src1_ready_i(dispatch_src1_ready),
    .dispatch_src2_ready_i(dispatch_src2_ready),
    .dispatch_src3_ready_i(dispatch_src3_ready), .dispatch_ready_o(mem_iq_ready),
    .dispatch_fire_i(dispatch_fire), .wb_i(exec_wb_q), .wb_accepted_i(wb_accepted),
    .issue_valid_o(mem_issue_valid), .issue_uop_o(mem_issue_uop),
    .issue_accept_i(mem_issue_accept), .flush_i(global_flush),
    .br_recover_fire_i(rob_recover_fire), .br_rob_idx_i(branch_q.rob_idx),
    .rob_head_i(rob_head), .occupancy_o(mem_iq_occupancy)
  );

  issue_queue #(.DEPTH(NIQ_FP), .ISSUE_WIDTH(1), .STRICT_ORDER(1'b1)) u_fp_iq (
    .clk_i, .rst_ni, .dispatch_valid_i(fp_dispatch_valid), .dispatch_uop_i(ren_uop),
    .dispatch_src1_ready_i(dispatch_src1_ready),
    .dispatch_src2_ready_i(dispatch_src2_ready),
    .dispatch_src3_ready_i(dispatch_src3_ready), .dispatch_ready_o(fp_iq_ready),
    .dispatch_fire_i(dispatch_fire), .wb_i(exec_wb_q), .wb_accepted_i(wb_accepted),
    .issue_valid_o(fp_issue_valid), .issue_uop_o(fp_issue_uop),
    .issue_accept_i(1'b0), .flush_i(global_flush),
    .br_recover_fire_i(rob_recover_fire), .br_rob_idx_i(branch_q.rob_idx),
    .rob_head_i(rob_head), .occupancy_o(fp_iq_occupancy)
  );

  always_comb begin
    int_issue_accept = '0;
    branch_slot_used = 1'b0;
    muldiv_slot_used = 1'b0;
    muldiv_valid = 1'b0;
    muldiv_uop = '0;
    muldiv_src1 = '0;
    muldiv_src2 = '0;
    for (int issue_idx = 0; issue_idx < FW; issue_idx++) begin
      if (!pipeline_issue_block && int_issue_valid[issue_idx]) begin
        case (int_issue_uop[issue_idx].d.fu)
          FU_ALU: int_issue_accept[issue_idx] = 1'b1;
          FU_BR: begin
            if (!branch_slot_used) begin
              int_issue_accept[issue_idx] = 1'b1;
              branch_slot_used = 1'b1;
            end
          end
          FU_MUL, FU_DIV: begin
            if (!muldiv_slot_used) begin
              int_issue_accept[issue_idx] = 1'b1;
              muldiv_slot_used = 1'b1;
              muldiv_valid = 1'b1;
              muldiv_uop = int_issue_uop[issue_idx];
              muldiv_src1 = prf_rdata[INT_RBASE+issue_idx*2];
              muldiv_src2 = prf_rdata[INT_RBASE+issue_idx*2+1];
            end
          end
          default: begin end
        endcase
      end
    end
  end

  for (genvar alu_idx = 0; alu_idx < FW; alu_idx++) begin : g_alu
    alu_branch_unit u_alu (
      .valid_i(int_issue_valid[alu_idx] && int_issue_accept[alu_idx] &&
               ((int_issue_uop[alu_idx].d.fu == FU_ALU) ||
                (int_issue_uop[alu_idx].d.fu == FU_BR))),
      .uop_i(int_issue_uop[alu_idx]),
      .src1_i(prf_rdata[INT_RBASE+alu_idx*2]),
      .src2_i(prf_rdata[INT_RBASE+alu_idx*2+1]),
      .wb_o(alu_wb[alu_idx]), .br_o(alu_br[alu_idx])
    );
  end

  muldiv_unit u_muldiv (
    .valid_i(muldiv_valid), .uop_i(muldiv_uop), .src1_i(muldiv_src1),
    .src2_i(muldiv_src2), .wb_o(muldiv_wb)
  );

  always_comb begin
    branch_n = '0;
    for (int alu_idx = 0; alu_idx < FW; alu_idx++) begin
      if (alu_br[alu_idx].valid)
        branch_n = alu_br[alu_idx];
    end
  end

  always_comb begin
    mem_issue_accept = '0;
    lsu_input_valid = '0;
    oldest_lsu_slot = -1;
    younger_lsu_slot = -1;
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      lsu_input_uop[lsu_idx] = '0;
      lsu_input_base[lsu_idx] = '0;
      lsu_input_data[lsu_idx] = '0;
      lsu_input_unknown[lsu_idx] = 1'b0;
      lsu_input_forward_mask[lsu_idx] = '0;
      lsu_input_forward_data[lsu_idx] = '0;
    end

    if (!pipeline_issue_block && mem_issue_valid[0]) begin
      if (!lsu_busy[0])
        oldest_lsu_slot = 0;
      else if (!lsu_busy[1])
        oldest_lsu_slot = 1;
      if (oldest_lsu_slot >= 0) begin
        lsu_input_valid[oldest_lsu_slot] = 1'b1;
        lsu_input_uop[oldest_lsu_slot] = mem_issue_uop[0];
        lsu_input_base[oldest_lsu_slot] = mem_base_rdata[0];
        lsu_input_data[oldest_lsu_slot] = mem_data_rdata[0];
        lsu_input_unknown[oldest_lsu_slot] = load_older_unknown[0];
        lsu_input_forward_mask[oldest_lsu_slot] = load_forward_mask[0];
        lsu_input_forward_data[oldest_lsu_slot] = load_forward_data[0];
        mem_issue_accept[0] = (mem_issue_uop[0].d.fu == FU_ST) ||
                              !load_older_unknown[0];
      end
    end

    if (mem_issue_accept[0] && mem_issue_valid[1]) begin
      younger_lsu_slot = (oldest_lsu_slot == 0) ? 1 : 0;
      if (!lsu_busy[younger_lsu_slot]) begin
        lsu_input_valid[younger_lsu_slot] = 1'b1;
        lsu_input_uop[younger_lsu_slot] = mem_issue_uop[1];
        lsu_input_base[younger_lsu_slot] = mem_base_rdata[1];
        lsu_input_data[younger_lsu_slot] = mem_data_rdata[1];
        lsu_input_unknown[younger_lsu_slot] = load_older_unknown[1];
        lsu_input_forward_mask[younger_lsu_slot] = load_forward_mask[1];
        lsu_input_forward_data[younger_lsu_slot] = load_forward_data[1];
        mem_issue_accept[1] = (mem_issue_uop[1].d.fu == FU_ST) ||
                              !load_older_unknown[1];
      end
    end
  end

  for (genvar lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin : g_lsu
    lsu_unit u_lsu (
      .clk_i, .rst_ni, .valid_i(lsu_input_valid[lsu_idx]),
      .uop_i(lsu_input_uop[lsu_idx]), .base_i(lsu_input_base[lsu_idx]),
      .store_data_i(lsu_input_data[lsu_idx]),
      .older_store_unknown_i(lsu_input_unknown[lsu_idx]),
      .forward_mask_i(lsu_input_forward_mask[lsu_idx]),
      .forward_data_i(lsu_input_forward_data[lsu_idx]),
      .dmem_valid_o(lsu_dmem_valid[lsu_idx]), .dmem_addr_o(lsu_dmem_addr[lsu_idx]),
      .dmem_size_o(lsu_dmem_size[lsu_idx]), .dmem_ready_i(load_dmem_ready[lsu_idx]),
      .dmem_rdata_i(dmem_rdata_i[lsu_idx]), .dmem_error_i(load_dmem_error[lsu_idx]),
      .store_execute_valid_o(store_execute_valid[lsu_idx]),
      .store_execute_uop_o(store_execute_uop[lsu_idx]),
      .store_execute_addr_o(store_execute_addr[lsu_idx]),
      .store_execute_data_o(store_execute_data[lsu_idx]),
      .store_execute_strb_o(store_execute_strb[lsu_idx]),
      .flush_i(global_flush || trap_take), .br_recover_fire_i(rob_recover_fire),
      .br_rob_idx_i(branch_q.rob_idx), .rob_head_i(rob_head),
      .ready_o(lsu_ready[lsu_idx]), .busy_o(lsu_busy[lsu_idx]), .wb_o(lsu_wb[lsu_idx])
    );
  end

  always_comb begin
    for (int load_idx = 0; load_idx < NLSU; load_idx++) begin
      load_query_valid[load_idx] = mem_issue_valid[load_idx] &&
                                   (mem_issue_uop[load_idx].d.fu == FU_LD);
      load_query_addr[load_idx] = mem_base_rdata[load_idx] +
                                  mem_issue_uop[load_idx].d.imm;
      load_query_sq[load_idx] = mem_issue_uop[load_idx].sq_idx;
    end
  end

  store_queue u_sq (
    .clk_i, .rst_ni, .dispatch_valid_i(store_dispatch_valid),
    .dispatch_uop_i(ren_uop), .dispatch_ready_o(sq_dispatch_ready),
    .dispatch_fire_i(dispatch_fire), .sq_head_o(sq_head), .sq_tail_o(sq_tail),
    .execute_valid_i(store_execute_valid), .execute_uop_i(store_execute_uop),
    .execute_addr_i(store_execute_addr), .execute_data_i(store_execute_data),
    .execute_strb_i(store_execute_strb), .execute_wb_o(sq_execute_wb),
    .commit_ready_o(sq_commit_ready), .commit_uop_o(sq_commit_uop),
    .commit_addr_o(sq_commit_addr), .commit_data_o(sq_commit_data),
    .commit_strb_o(sq_commit_strb), .commit_fire_i(sq_commit_fire),
    .load_query_valid_i(load_query_valid), .load_query_addr_i(load_query_addr),
    .load_query_sq_i(load_query_sq), .load_older_unknown_o(load_older_unknown),
    .load_forward_mask_o(load_forward_mask), .load_forward_data_o(load_forward_data),
    .flush_i(global_flush), .br_recover_fire_i(rob_recover_fire),
    .br_sq_tail_i(branch_q.sq_idx), .occupancy_o(sq_occupancy)
  );

  always_comb begin
    sq_commit_fire = 1'b0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (rob_commit_valid[lane_idx] && (rob_commit_uop[lane_idx].d.fu == FU_ST))
        sq_commit_fire = 1'b1;
    end
  end

  store_commit_unit u_store_commit (
    .clk_i, .rst_ni, .cancel_i(global_flush), .serial_valid_i(rob_serial_valid),
    .serial_uop_i(rob_serial_uop), .commit_ready_i(1'b1),
    .commit_fire_i(sq_commit_fire), .other_serial_ready_i(other_serial_ready),
    .sq_ready_i(sq_commit_ready), .sq_uop_i(sq_commit_uop),
    .sq_addr_i(sq_commit_addr), .sq_data_i(sq_commit_data),
    .sq_strb_i(sq_commit_strb), .dmem_valid_o(store_dmem_valid),
    .dmem_write_o(store_dmem_write), .dmem_addr_o(store_dmem_addr),
    .dmem_size_o(store_dmem_size), .dmem_wdata_o(store_dmem_wdata),
    .dmem_wstrb_o(store_dmem_wstrb), .dmem_ready_i(store_dmem_ready),
    .dmem_error_i(store_dmem_error), .serial_ready_o(rob_serial_ready),
    .fault_wb_o(store_fault_wb)
  );

  always_comb begin
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      dmem_valid_o[lsu_idx] = lsu_dmem_valid[lsu_idx];
      dmem_write_o[lsu_idx] = 1'b0;
      dmem_addr_o[lsu_idx] = lsu_dmem_addr[lsu_idx];
      dmem_size_o[lsu_idx] = lsu_dmem_size[lsu_idx];
      dmem_wdata_o[lsu_idx] = '0;
      dmem_wstrb_o[lsu_idx] = '0;
      load_dmem_ready[lsu_idx] = dmem_ready_i[lsu_idx];
      load_dmem_error[lsu_idx] = dmem_error_i[lsu_idx];
    end
    if (store_dmem_valid && !lsu_busy[0]) begin
      dmem_valid_o[0] = 1'b1;
      dmem_write_o[0] = store_dmem_write;
      dmem_addr_o[0] = store_dmem_addr;
      dmem_size_o[0] = store_dmem_size;
      dmem_wdata_o[0] = store_dmem_wdata;
      dmem_wstrb_o[0] = store_dmem_wstrb;
    end
    store_dmem_ready = store_dmem_valid && !lsu_busy[0] && dmem_ready_i[0];
    store_dmem_error = store_dmem_valid && !lsu_busy[0] && dmem_error_i[0];
  end

  always_comb begin
    serial_source_ready = !rob_serial_uop.d.use1 || serial_prf_rready;
    serial_csr_access = rob_serial_valid && (rob_serial_uop.d.fu == FU_CSR) &&
                        (rob_serial_uop.d.op <= SYS_CSRRCI);
    csr_valid = serial_csr_access && serial_source_ready && !global_flush;
    csr_op = rob_serial_uop.d.op;
    csr_addr = rob_serial_uop.d.csr_addr;
    csr_wdata = (rob_serial_uop.d.op >= SYS_CSRRWI) ? rob_serial_uop.d.imm :
                                                     serial_prf_rdata;
    csr_src_zero = (rob_serial_uop.d.op >= SYS_CSRRWI) ?
                   (rob_serial_uop.d.imm[4:0] == 0) : !rob_serial_uop.d.use1;

    other_serial_ready = 1'b1;
    if (rob_serial_valid && (rob_serial_uop.d.fu == FU_CSR)) begin
      if (rob_serial_uop.d.op <= SYS_CSRRCI)
        other_serial_ready = serial_source_ready && !csr_illegal;
      else if ((rob_serial_uop.d.op == SYS_ECALL) ||
               (rob_serial_uop.d.op == SYS_EBREAK))
        other_serial_ready = 1'b0;
    end

    system_wb = '0;
    system_wb.rob.rob_idx = rob_serial_uop.rob_idx;
    system_wb.rob.epoch = rob_serial_uop.epoch;
    system_wb.rob.tval = rob_serial_uop.d.inst;
    if (rob_serial_valid && (rob_serial_uop.d.fu == FU_CSR)) begin
      if (serial_csr_access && serial_source_ready && csr_illegal) begin
        system_wb.rob.valid = 1'b1;
        system_wb.rob.excp = 1'b1;
        system_wb.rob.cause = EXC_ILLEGAL;
      end else if (rob_serial_uop.d.op == SYS_ECALL) begin
        system_wb.rob.valid = 1'b1;
        system_wb.rob.excp = 1'b1;
        system_wb.rob.cause = EXC_ECALL_M;
        system_wb.rob.tval = 32'd0;
      end else if (rob_serial_uop.d.op == SYS_EBREAK) begin
        system_wb.rob.valid = 1'b1;
        system_wb.rob.excp = 1'b1;
        system_wb.rob.cause = EXC_BREAKPOINT;
        system_wb.rob.tval = 32'd0;
      end
    end

    csr_wb = '0;
    if (rob_commit_valid[0] && (rob_commit_uop[0].d.fu == FU_CSR) &&
        (rob_commit_uop[0].d.op <= SYS_CSRRCI)) begin
      csr_wb.rob.valid = 1'b1;
      csr_wb.rob.rob_idx = rob_commit_uop[0].rob_idx;
      csr_wb.rob.epoch = rob_commit_uop[0].epoch;
      csr_wb.write_pdst = rob_commit_uop[0].d.rd_valid;
      csr_wb.pdst = rob_commit_uop[0].pdst;
      csr_wb.data = csr_rdata;
    end
  end

  always_comb begin
    retire_count = '0;
    rename_commit_valid = '0;
    mret_commit = 1'b0;
    wfi_commit = 1'b0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (rob_commit_valid[lane_idx])
        retire_count++;
      rename_commit_valid[lane_idx] = rob_commit_valid[lane_idx] &&
                                       rob_commit_uop[lane_idx].d.rd_valid &&
                                       (rob_commit_uop[lane_idx].d.rd != 0);
      rename_commit_rd[lane_idx] = rob_commit_uop[lane_idx].d.rd;
      rename_commit_pdst[lane_idx] = rob_commit_uop[lane_idx].pdst;
      rename_commit_prev[lane_idx] = rob_commit_uop[lane_idx].prev_pdst;
    end
    if (rob_commit_valid[0] && (rob_commit_uop[0].d.fu == FU_CSR)) begin
      mret_commit = (rob_commit_uop[0].d.op == SYS_MRET);
      wfi_commit = (rob_commit_uop[0].d.op == SYS_WFI);
    end
  end

  assign interrupt_take = csr_interrupt_pending && (rob_occupancy == 0) &&
                          !control_flush_q;
  assign trap_take = rob_trap_valid || interrupt_take;
  assign global_flush = control_flush_q;
  assign control_serial_commit = rob_commit_valid[0] &&
                                  ((rob_commit_uop[0].d.fu == FU_CSR) ||
                                   (rob_commit_uop[0].d.fu == FU_NONE));
  assign frontend_invalidate = control_serial_commit &&
                               (rob_commit_uop[0].d.fu == FU_CSR) &&
                               ((rob_commit_uop[0].d.op == SYS_FENCEI) ||
                                ((rob_commit_uop[0].d.csr_addr >= CSR_PMPCFG0) &&
                                 (rob_commit_uop[0].d.csr_addr <= CSR_PMPCFG3)) ||
                                ((rob_commit_uop[0].d.csr_addr >= CSR_PMPADDR0) &&
                                 (rob_commit_uop[0].d.csr_addr <= CSR_PMPADDR15)));
  assign pipeline_issue_block = trap_take || control_flush_q ||
                                (rob_serial_valid &&
                                 ((rob_serial_uop.d.fu == FU_CSR) ||
                                  (rob_serial_uop.d.fu == FU_NONE) ||
                                  (rob_serial_uop.d.fu == FU_ST)));

  csr_file u_csr (
    .clk_i, .rst_ni, .csr_valid_i(csr_valid), .csr_op_i(csr_op),
    .csr_addr_i(csr_addr), .csr_wdata_i(csr_wdata), .csr_src_zero_i(csr_src_zero),
    .csr_rdata_o(csr_rdata), .csr_ready_o(csr_ready), .csr_illegal_o(csr_illegal),
    .trap_valid_i(trap_take), .trap_is_interrupt_i(interrupt_take),
    .trap_cause_i(interrupt_take ? 31'(csr_interrupt_cause) : 31'(rob_trap_cause)),
    .trap_pc_i(interrupt_take ? fetch_pc : rob_trap_uop.d.pc),
    .trap_tval_i(interrupt_take ? 32'd0 : rob_trap_tval),
    .mret_commit_i(mret_commit), .wfi_commit_i(wfi_commit),
    .trap_vector_o(trap_vector), .mret_pc_o(mret_pc), .sleeping_o(csr_sleeping),
    .irq_software_i, .irq_timer_i, .irq_external_i,
    .interrupt_pending_o(csr_interrupt_pending),
    .interrupt_cause_o(csr_interrupt_cause), .wake_pending_o(csr_wake_pending),
    .retire_count_i(retire_count), .time_i, .perf_event_i(perf_events),
    .fp_flags_valid_i(1'b0), .fp_flags_i('0), .fp_write_commit_i(1'b0),
    .fp_enabled_o(fp_enabled), .frm_o(frm), .fflags_o(fp_flags),
    .pmpcfg_o, .pmpaddr_o
  );

  always_comb begin
    frontend_redirect = control_flush_q || trap_take || rob_recover_fire;
    frontend_redirect_pc = control_target_q;
    if (trap_take)
      frontend_redirect_pc = trap_vector;
    else if (control_flush_q)
      frontend_redirect_pc = control_target_q;
    else if (rob_recover_fire)
      frontend_redirect_pc = branch_q.next_pc;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      control_flush_q <= 1'b0;
      control_target_q <= RESET_PC;
    end else begin
      control_flush_q <= 1'b0;
      if (trap_take) begin
        control_flush_q <= 1'b1;
        control_target_q <= trap_vector;
      end else if (control_serial_commit) begin
        control_flush_q <= 1'b1;
        if ((rob_commit_uop[0].d.fu == FU_CSR) &&
            (rob_commit_uop[0].d.op == SYS_MRET))
          control_target_q <= mret_pc;
        else
          control_target_q <= rob_commit_uop[0].d.pc +
                              (rob_commit_uop[0].d.rvc ? 32'd2 : 32'd4);
      end
    end
  end

  always_comb begin
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
      exec_wb_n[wb_idx] = '0;
    for (int alu_idx = 0; alu_idx < FW; alu_idx++)
      exec_wb_n[alu_idx] = alu_wb[alu_idx];
    exec_wb_n[4] = sq_execute_wb[0];
    exec_wb_n[5] = sq_execute_wb[1];
    exec_wb_n[6] = lsu_wb[0];
    exec_wb_n[7] = lsu_wb[1];
    exec_wb_n[8] = muldiv_wb;
    exec_wb_n[9] = store_fault_wb.rob.valid ? store_fault_wb :
                   (system_wb.rob.valid ? system_wb : csr_wb);
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
      rob_wb[wb_idx] = exec_wb_q[wb_idx].rob;

    perf_events = '0;
    for (int alu_idx = 0; alu_idx < FW; alu_idx++) begin
      if (alu_br[alu_idx].valid)
        perf_events[PERF_BRANCH] = 1'b1;
      if (alu_br[alu_idx].valid && alu_br[alu_idx].mispredict)
        perf_events[PERF_BRANCH_MISPRED] = 1'b1;
    end
    for (int mem_idx = 0; mem_idx < NLSU; mem_idx++) begin
      if (mem_issue_valid[mem_idx] && mem_issue_accept[mem_idx] &&
          (mem_issue_uop[mem_idx].d.fu == FU_LD))
        perf_events[PERF_LOAD] = 1'b1;
      if (mem_issue_valid[mem_idx] && mem_issue_accept[mem_idx] &&
          (mem_issue_uop[mem_idx].d.fu == FU_ST))
        perf_events[PERF_STORE] = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        exec_wb_q[wb_idx] <= '0;
      branch_q <= '0;
    end else if (global_flush || trap_take) begin
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        exec_wb_q[wb_idx] <= '0;
      branch_q <= '0;
    end else if (rob_recover_fire) begin
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
        if (exec_wb_n[wb_idx].rob.valid &&
            !rob_younger(exec_wb_n[wb_idx].rob.rob_idx, branch_q.rob_idx, rob_head))
          exec_wb_q[wb_idx] <= exec_wb_n[wb_idx];
        else
          exec_wb_q[wb_idx] <= '0;
      end
      branch_q <= '0;
    end else begin
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        exec_wb_q[wb_idx] <= exec_wb_n[wb_idx];
      branch_q <= branch_n;
    end
  end

  assign debug_pc_o = fetch_pc;
  assign debug_rob_occupancy_o = rob_occupancy;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      for (int lane_idx = 1; lane_idx < FW; lane_idx++) begin
        assert (!dec_bundle[lane_idx].valid || dec_bundle[lane_idx-1].valid);
        assert (!dispatch_valid[lane_idx] || dispatch_valid[lane_idx-1]);
        if (dec_bundle[lane_idx].valid)
          assert (dec_bundle[lane_idx].pc == dec_bundle[lane_idx-1].pc + 32'd4);
      end
      if (dispatch_fire)
        assert (fetch_consume && (|dispatch_valid));
      assert (!mem_issue_accept[1] || mem_issue_accept[0]);
      assert (!store_dmem_ready || !lsu_busy[0]);
    end
  end
`endif
endmodule
