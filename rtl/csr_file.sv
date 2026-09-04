`timescale 1ns/1ps

module csr_file #(
  parameter logic [31:0] MVENDORID = 32'd0,
  parameter logic [31:0] MARCHID   = 32'd0,
  parameter logic [31:0] MIMPID    = 32'h0001_0000,
  parameter logic [31:0] MHARTID   = 32'd0
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         csr_valid_i,
  input  logic [5:0]                   csr_op_i,
  input  logic [11:0]                  csr_addr_i,
  input  logic [31:0]                  csr_wdata_i,
  input  logic                         csr_src_zero_i,
  output logic [31:0]                  csr_rdata_o,
  output logic                         csr_ready_o,
  output logic                         csr_illegal_o,

  input  logic                         trap_valid_i,
  input  logic                         trap_is_interrupt_i,
  input  logic [30:0]                  trap_cause_i,
  input  logic [31:0]                  trap_pc_i,
  input  logic [31:0]                  trap_tval_i,
  input  logic                         mret_commit_i,
  input  logic                         wfi_commit_i,
  output logic [31:0]                  trap_vector_o,
  output logic [31:0]                  mret_pc_o,
  output logic                         sleeping_o,

  input  logic                         irq_software_i,
  input  logic                         irq_timer_i,
  input  logic                         irq_external_i,
  output logic                         interrupt_pending_o,
  output logic [4:0]                   interrupt_cause_o,
  output logic                         wake_pending_o,

  input  logic [$clog2(mycore_pkg::FW+1)-1:0] retire_count_i,
  input  logic [63:0]                  time_i,
  input  logic [31:0]                  perf_event_i,
  input  logic                         fp_flags_valid_i,
  input  logic [4:0]                   fp_flags_i,
  input  logic                         fp_write_commit_i,
  output logic                         fp_enabled_o,
  output logic [2:0]                   frm_o,
  output logic [4:0]                   fflags_o,

  output logic [7:0]                   pmpcfg_o [csr_pkg::NPMP],
  output logic [31:0]                  pmpaddr_o [csr_pkg::NPMP]
);
  import mycore_pkg::*;
  import csr_pkg::*;

  logic mstatus_mie_q, mstatus_mie_n, mstatus_mpie_q, mstatus_mpie_n;
  logic [1:0] mstatus_fs_q, mstatus_fs_n;
  logic [7:0] fcsr_q, fcsr_n;
  logic [31:0] mie_q, mie_n, mtvec_q, mtvec_n, mscratch_q, mscratch_n;
  logic [31:0] mepc_q, mepc_n, mcause_q, mcause_n, mtval_q, mtval_n;
  logic sleeping_q;

  logic [63:0] mcycle_q, mcycle_n, minstret_q, minstret_n;
  logic [63:0] mhpmcounter_q [29], mhpmcounter_n [29];
  logic [31:0] mhpmevent_q [29], mhpmevent_n [29];
  logic [31:0] mcountinhibit_q, mcountinhibit_n;

  logic [7:0] pmpcfg_q [NPMP];
  logic [31:0] pmpaddr_q [NPMP];

  logic [31:0] mstatus_value, mip_value, csr_new_value, mtvec_trap_value;
  logic [7:0] fcsr_read_value;
  logic [1:0] mstatus_read_fs;
  logic csr_implemented, csr_readonly, csr_write_request, csr_write_enable;
  logic csr_is_fp, trap_entry_mie;
  integer csr_index;

  function automatic logic [31:0] legal_mtvec(input logic [31:0] value);
    return {value[31:2], (value[1:0] == 2'b01) ? 2'b01 : 2'b00};
  endfunction

  function automatic logic [7:0] legal_pmpcfg(input logic [7:0] value);
    logic [7:0] result;
    result = {value[7], 2'b00, value[4:0]};
    if (result[1] && !result[0])
      result[1] = 1'b0;
    return result;
  endfunction

  always_comb begin
    mstatus_read_fs = (fp_flags_valid_i || fp_write_commit_i) ? 2'b11 : mstatus_fs_q;
    mstatus_value = '0;
    mstatus_value[31] = (mstatus_read_fs == 2'b11);
    mstatus_value[14:13] = mstatus_read_fs;
    mstatus_value[12:11] = 2'b11;
    mstatus_value[7] = mstatus_mpie_q;
    mstatus_value[3] = mstatus_mie_q;

    mip_value = '0;
    mip_value[3] = irq_software_i;
    mip_value[7] = irq_timer_i;
    mip_value[11] = irq_external_i;

    fcsr_read_value = fcsr_q;
    if (fp_flags_valid_i)
      fcsr_read_value[4:0] = fcsr_q[4:0] | fp_flags_i;

    wake_pending_o = |(mie_q & mip_value & MIP_MACHINE_MASK);
    interrupt_pending_o = mstatus_mie_q && wake_pending_o;
    interrupt_cause_o = IRQ_M_TIMER;
    if (mie_q[11] && irq_external_i)
      interrupt_cause_o = IRQ_M_EXTERNAL;
    else if (mie_q[3] && irq_software_i)
      interrupt_cause_o = IRQ_M_SOFTWARE;

    mret_pc_o = mepc_q;
    sleeping_o = sleeping_q;
    frm_o = fcsr_q[7:5];
    fflags_o = fcsr_q[4:0];
    fp_enabled_o = (mstatus_fs_q != 2'b00);
  end

  always_comb begin
    mtvec_trap_value = mtvec_q;
    if (csr_write_enable && (csr_addr_i == CSR_MTVEC))
      mtvec_trap_value = legal_mtvec(csr_new_value);
    trap_vector_o = {mtvec_trap_value[31:2], 2'b00};
    if (trap_is_interrupt_i && (mtvec_trap_value[1:0] == 2'b01))
      trap_vector_o = {mtvec_trap_value[31:2], 2'b00} + ({1'b0, trap_cause_i} << 2);
  end

  always_comb begin
    csr_rdata_o = '0;
    csr_implemented = 1'b1;
    csr_index = 0;

    if ((csr_addr_i >= CSR_MHPMEVENT3) && (csr_addr_i <= CSR_MHPMEVENT31)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_MHPMEVENT3);
      csr_rdata_o = mhpmevent_q[csr_index];
    end else if ((csr_addr_i >= CSR_PMPCFG0) && (csr_addr_i <= CSR_PMPCFG3)) begin
      csr_index = (int'(csr_addr_i) - int'(CSR_PMPCFG0)) * 4;
      csr_rdata_o = {pmpcfg_q[csr_index+3], pmpcfg_q[csr_index+2],
                     pmpcfg_q[csr_index+1], pmpcfg_q[csr_index]};
    end else if ((csr_addr_i >= CSR_PMPADDR0) && (csr_addr_i <= CSR_PMPADDR15)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_PMPADDR0);
      csr_rdata_o = pmpaddr_q[csr_index];
    end else if ((csr_addr_i >= CSR_MHPMCOUNTER3) && (csr_addr_i <= CSR_MHPMCOUNTER31)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_MHPMCOUNTER3);
      csr_rdata_o = mhpmcounter_q[csr_index][31:0];
    end else if ((csr_addr_i >= CSR_MHPMCOUNTER3H) && (csr_addr_i <= CSR_MHPMCOUNTER31H)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_MHPMCOUNTER3H);
      csr_rdata_o = mhpmcounter_q[csr_index][63:32];
    end else if ((csr_addr_i >= CSR_HPMCOUNTER3) && (csr_addr_i <= CSR_HPMCOUNTER31)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_HPMCOUNTER3);
      csr_rdata_o = mhpmcounter_q[csr_index][31:0];
    end else if ((csr_addr_i >= CSR_HPMCOUNTER3H) && (csr_addr_i <= CSR_HPMCOUNTER31H)) begin
      csr_index = int'(csr_addr_i) - int'(CSR_HPMCOUNTER3H);
      csr_rdata_o = mhpmcounter_q[csr_index][63:32];
    end else begin
      case (csr_addr_i)
        CSR_FFLAGS:        csr_rdata_o = {27'b0, fcsr_read_value[4:0]};
        CSR_FRM:           csr_rdata_o = {29'b0, fcsr_read_value[7:5]};
        CSR_FCSR:          csr_rdata_o = {24'b0, fcsr_read_value};
        CSR_MSTATUS:       csr_rdata_o = mstatus_value;
        CSR_MISA:          csr_rdata_o = MISA_RV32IMFC;
        CSR_MIE:           csr_rdata_o = mie_q;
        CSR_MTVEC:         csr_rdata_o = mtvec_q;
        CSR_MSTATUSH:      csr_rdata_o = 32'd0;
        CSR_MCOUNTINHIBIT: csr_rdata_o = mcountinhibit_q;
        CSR_MSCRATCH:      csr_rdata_o = mscratch_q;
        CSR_MEPC:          csr_rdata_o = mepc_q;
        CSR_MCAUSE:        csr_rdata_o = mcause_q;
        CSR_MTVAL:         csr_rdata_o = mtval_q;
        CSR_MIP:           csr_rdata_o = mip_value;
        CSR_MCYCLE:        csr_rdata_o = mcycle_q[31:0];
        CSR_MINSTRET:      csr_rdata_o = minstret_q[31:0];
        CSR_MCYCLEH:       csr_rdata_o = mcycle_q[63:32];
        CSR_MINSTRETH:     csr_rdata_o = minstret_q[63:32];
        CSR_CYCLE:         csr_rdata_o = mcycle_q[31:0];
        CSR_TIME:          csr_rdata_o = time_i[31:0];
        CSR_INSTRET:       csr_rdata_o = minstret_q[31:0];
        CSR_CYCLEH:        csr_rdata_o = mcycle_q[63:32];
        CSR_TIMEH:         csr_rdata_o = time_i[63:32];
        CSR_INSTRETH:      csr_rdata_o = minstret_q[63:32];
        CSR_MVENDORID:     csr_rdata_o = MVENDORID;
        CSR_MARCHID:       csr_rdata_o = MARCHID;
        CSR_MIMPID:        csr_rdata_o = MIMPID;
        CSR_MHARTID:       csr_rdata_o = MHARTID;
        CSR_MCONFIGPTR:    csr_rdata_o = 32'd0;
        default: begin
          csr_rdata_o = '0;
          csr_implemented = 1'b0;
        end
      endcase
    end

    csr_write_request = (csr_op_i == CSR_OP_RW) || (csr_op_i == CSR_OP_RWI) ||
                        (((csr_op_i == CSR_OP_RS) || (csr_op_i == CSR_OP_RC) ||
                          (csr_op_i == CSR_OP_RSI) || (csr_op_i == CSR_OP_RCI)) &&
                         !csr_src_zero_i);
    csr_readonly = (csr_addr_i[11:10] == 2'b11);
    csr_is_fp = (csr_addr_i == CSR_FFLAGS) || (csr_addr_i == CSR_FRM) ||
                (csr_addr_i == CSR_FCSR);
    csr_illegal_o = csr_valid_i &&
                    ((!csr_implemented) || (csr_op_i > CSR_OP_RCI) ||
                     (csr_write_request && csr_readonly) ||
                     (csr_is_fp && (mstatus_fs_q == 2'b00)));
    csr_ready_o = 1'b1;
    csr_write_enable = csr_valid_i && csr_write_request && !csr_illegal_o;

    case (csr_op_i)
      CSR_OP_RW, CSR_OP_RWI: csr_new_value = csr_wdata_i;
      CSR_OP_RS, CSR_OP_RSI: csr_new_value = csr_rdata_o | csr_wdata_i;
      CSR_OP_RC, CSR_OP_RCI: csr_new_value = csr_rdata_o & ~csr_wdata_i;
      default:                csr_new_value = csr_rdata_o;
    endcase
  end

  always_comb begin
    trap_entry_mie = mstatus_mie_q;
    if (csr_write_enable && (csr_addr_i == CSR_MSTATUS))
      trap_entry_mie = csr_new_value[3];
    if (mret_commit_i)
      trap_entry_mie = mstatus_mpie_q;
  end

  always_comb begin
    mstatus_mie_n = mstatus_mie_q;
    mstatus_mpie_n = mstatus_mpie_q;
    mstatus_fs_n = mstatus_fs_q;
    fcsr_n = fcsr_q;
    mie_n = mie_q;
    mtvec_n = mtvec_q;
    mscratch_n = mscratch_q;
    mepc_n = mepc_q;
    mcause_n = mcause_q;
    mtval_n = mtval_q;

    if (fp_flags_valid_i) begin
      fcsr_n[4:0] = fcsr_q[4:0] | fp_flags_i;
      mstatus_fs_n = 2'b11;
    end
    if (fp_write_commit_i)
      mstatus_fs_n = 2'b11;

    if (csr_write_enable) begin
      case (csr_addr_i)
        CSR_FFLAGS: begin
          fcsr_n[4:0] = csr_new_value[4:0];
          mstatus_fs_n = 2'b11;
        end
        CSR_FRM: begin
          fcsr_n[7:5] = csr_new_value[2:0];
          mstatus_fs_n = 2'b11;
        end
        CSR_FCSR: begin
          fcsr_n = csr_new_value[7:0];
          mstatus_fs_n = 2'b11;
        end
        CSR_MSTATUS: begin
          mstatus_mie_n = csr_new_value[3];
          mstatus_mpie_n = csr_new_value[7];
          mstatus_fs_n = csr_new_value[14:13];
        end
        CSR_MIE:      mie_n = csr_new_value & MIP_MACHINE_MASK;
        CSR_MTVEC:    mtvec_n = legal_mtvec(csr_new_value);
        CSR_MSCRATCH: mscratch_n = csr_new_value;
        CSR_MEPC:     mepc_n = {csr_new_value[31:1], 1'b0};
        CSR_MCAUSE:   mcause_n = csr_new_value;
        CSR_MTVAL:    mtval_n = csr_new_value;
        default: begin end
      endcase
    end

    if (mret_commit_i) begin
      mstatus_mie_n = mstatus_mpie_q;
      mstatus_mpie_n = 1'b1;
    end
    if (trap_valid_i) begin
      mepc_n = {trap_pc_i[31:1], 1'b0};
      mcause_n = {trap_is_interrupt_i, trap_cause_i};
      mtval_n = trap_is_interrupt_i ? 32'd0 : trap_tval_i;
      mstatus_mpie_n = trap_entry_mie;
      mstatus_mie_n = 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mstatus_mie_q <= 1'b0;
      mstatus_mpie_q <= 1'b0;
      mstatus_fs_q <= 2'b00;
      fcsr_q <= '0;
      mie_q <= '0;
      mtvec_q <= '0;
      mscratch_q <= '0;
      mepc_q <= '0;
      mcause_q <= '0;
      mtval_q <= '0;
    end else begin
      mstatus_mie_q <= mstatus_mie_n;
      mstatus_mpie_q <= mstatus_mpie_n;
      mstatus_fs_q <= mstatus_fs_n;
      fcsr_q <= fcsr_n;
      mie_q <= mie_n;
      mtvec_q <= mtvec_n;
      mscratch_q <= mscratch_n;
      mepc_q <= mepc_n;
      mcause_q <= mcause_n;
      mtval_q <= mtval_n;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sleeping_q <= 1'b0;
    end else begin
      if (wfi_commit_i && !wake_pending_o)
        sleeping_q <= 1'b1;
      if (wake_pending_o || trap_valid_i)
        sleeping_q <= 1'b0;
    end
  end

  always_comb begin
    mcycle_n = mcycle_q;
    minstret_n = minstret_q;
    mcountinhibit_n = mcountinhibit_q;
    for (int hpm_idx = 0; hpm_idx < 29; hpm_idx++) begin
      mhpmcounter_n[hpm_idx] = mhpmcounter_q[hpm_idx];
      mhpmevent_n[hpm_idx] = mhpmevent_q[hpm_idx];
    end

    if (!mcountinhibit_q[0])
      mcycle_n = mcycle_q + 1'b1;
    if (!mcountinhibit_q[2])
      minstret_n = minstret_q + 64'(retire_count_i);
    for (int hpm_idx = 0; hpm_idx < 29; hpm_idx++) begin
      if (!mcountinhibit_q[hpm_idx+3] &&
          (mhpmevent_q[hpm_idx][4:0] != PERF_NONE) &&
          perf_event_i[mhpmevent_q[hpm_idx][4:0]])
        mhpmcounter_n[hpm_idx] = mhpmcounter_q[hpm_idx] + 1'b1;
    end

    if (csr_write_enable) begin
      if (csr_addr_i == CSR_MCYCLE)
        mcycle_n[31:0] = csr_new_value;
      else if (csr_addr_i == CSR_MCYCLEH)
        mcycle_n[63:32] = csr_new_value;
      else if (csr_addr_i == CSR_MINSTRET)
        minstret_n[31:0] = csr_new_value;
      else if (csr_addr_i == CSR_MINSTRETH)
        minstret_n[63:32] = csr_new_value;
      else if (csr_addr_i == CSR_MCOUNTINHIBIT)
        mcountinhibit_n = csr_new_value & 32'hffff_fffd;
      else if ((csr_addr_i >= CSR_MHPMEVENT3) && (csr_addr_i <= CSR_MHPMEVENT31))
        mhpmevent_n[int'(csr_addr_i)-int'(CSR_MHPMEVENT3)] = csr_new_value;
      else if ((csr_addr_i >= CSR_MHPMCOUNTER3) && (csr_addr_i <= CSR_MHPMCOUNTER31))
        mhpmcounter_n[int'(csr_addr_i)-int'(CSR_MHPMCOUNTER3)][31:0] = csr_new_value;
      else if ((csr_addr_i >= CSR_MHPMCOUNTER3H) && (csr_addr_i <= CSR_MHPMCOUNTER31H))
        mhpmcounter_n[int'(csr_addr_i)-int'(CSR_MHPMCOUNTER3H)][63:32] = csr_new_value;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mcycle_q <= '0;
      minstret_q <= '0;
      mcountinhibit_q <= '0;
      for (int hpm_idx = 0; hpm_idx < 29; hpm_idx++) begin
        mhpmcounter_q[hpm_idx] <= '0;
        mhpmevent_q[hpm_idx] <= '0;
      end
    end else begin
      mcycle_q <= mcycle_n;
      minstret_q <= minstret_n;
      mcountinhibit_q <= mcountinhibit_n;
      for (int hpm_idx = 0; hpm_idx < 29; hpm_idx++) begin
        mhpmcounter_q[hpm_idx] <= mhpmcounter_n[hpm_idx];
        mhpmevent_q[hpm_idx] <= mhpmevent_n[hpm_idx];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
        pmpcfg_q[pmp_idx] <= '0;
        pmpaddr_q[pmp_idx] <= '0;
      end
    end else if (csr_write_enable) begin
      for (int cfg_word = 0; cfg_word < NPMP/4; cfg_word++) begin
        if (csr_addr_i == (CSR_PMPCFG0 + 12'(cfg_word))) begin
          for (int cfg_byte = 0; cfg_byte < 4; cfg_byte++) begin
            if (!pmpcfg_q[cfg_word*4+cfg_byte][7])
              pmpcfg_q[cfg_word*4+cfg_byte] <=
                legal_pmpcfg(csr_new_value[cfg_byte*8 +: 8]);
          end
        end
      end
      for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
        if ((csr_addr_i == (CSR_PMPADDR0 + 12'(pmp_idx))) && !pmpcfg_q[pmp_idx][7]) begin
          if (pmp_idx == NPMP-1)
            pmpaddr_q[pmp_idx] <= csr_new_value;
          else if (!(pmpcfg_q[pmp_idx+1][7] && (pmpcfg_q[pmp_idx+1][4:3] == 2'b01)))
            pmpaddr_q[pmp_idx] <= csr_new_value;
        end
      end
    end
  end

  for (genvar pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin : g_pmp_outputs
    assign pmpcfg_o[pmp_idx] = pmpcfg_q[pmp_idx];
    assign pmpaddr_o[pmp_idx] = pmpaddr_q[pmp_idx];
  end
endmodule
