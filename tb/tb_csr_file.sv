`timescale 1ns/1ps

module tb_csr_file;
  import mycore_pkg::*;
  import csr_pkg::*;
  import soc_pkg::ITIM_BASE;

  logic clk_i;
  logic rst_ni;
  logic csr_valid_i;
  logic [5:0] csr_op_i;
  logic [11:0] csr_addr_i;
  logic [31:0] csr_wdata_i, csr_rdata_o;
  logic csr_src_zero_i;
  logic csr_ready_o, csr_illegal_o;
  logic trap_valid_i, trap_is_interrupt_i;
  logic [30:0] trap_cause_i;
  logic [31:0] trap_pc_i, trap_tval_i;
  logic mret_commit_i, wfi_commit_i;
  logic [31:0] trap_vector_o, mret_pc_o;
  logic sleeping_o;
  logic irq_software_i, irq_timer_i, irq_external_i;
  logic interrupt_pending_o;
  logic [4:0] interrupt_cause_o;
  logic wake_pending_o;
  logic [$clog2(FW+1)-1:0] retire_count_i;
  logic [63:0] time_i;
  logic [31:0] perf_event_i;
  logic fp_flags_valid_i;
  logic [4:0] fp_flags_i;
  logic fp_write_commit_i, fp_enabled_o;
  logic [2:0] frm_o;
  logic [4:0] fflags_o;
  logic [7:0] pmpcfg_o [NPMP];
  logic [31:0] pmpaddr_o [NPMP];

  csr_file dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      csr_valid_i = 1'b0;
      csr_op_i = CSR_OP_RS;
      csr_addr_i = '0;
      csr_wdata_i = '0;
      csr_src_zero_i = 1'b1;
      trap_valid_i = 1'b0;
      trap_is_interrupt_i = 1'b0;
      trap_cause_i = '0;
      trap_pc_i = '0;
      trap_tval_i = '0;
      mret_commit_i = 1'b0;
      wfi_commit_i = 1'b0;
      irq_software_i = 1'b0;
      irq_timer_i = 1'b0;
      irq_external_i = 1'b0;
      retire_count_i = '0;
      perf_event_i = '0;
      fp_flags_valid_i = 1'b0;
      fp_flags_i = '0;
      fp_write_commit_i = 1'b0;
      #1;
    end
  endtask

  task automatic csr_access(
    input logic [5:0] op,
    input logic [11:0] addr,
    input logic [31:0] wdata,
    input logic expect_illegal,
    output logic [31:0] old_value
  );
    begin
      csr_valid_i = 1'b1;
      csr_op_i = op;
      csr_addr_i = addr;
      csr_wdata_i = wdata;
      csr_src_zero_i = (wdata == 0);
      #1;
      assert (csr_ready_o && (csr_illegal_o == expect_illegal));
      old_value = csr_rdata_o;
      @(posedge clk_i); #1;
      csr_valid_i = 1'b0;
      #1;
    end
  endtask

  task automatic csr_write(input logic [11:0] addr, input logic [31:0] value);
    logic [31:0] unused;
    begin
      csr_access(CSR_OP_RW, addr, value, 1'b0, unused);
    end
  endtask

  task automatic csr_read_expect(input logic [11:0] addr, input logic [31:0] expected);
    logic [31:0] value;
    begin
      csr_access(CSR_OP_RS, addr, 32'd0, 1'b0, value);
      assert (value == expected)
        else $fatal(1, "CSR %03x: got %08x expected %08x", addr, value, expected);
    end
  endtask

  logic [31:0] value;

  initial begin
    time_i = 64'h0123_4567_89ab_cdef;
    clear_inputs();
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i); #1;

    csr_read_expect(CSR_MISA, MISA_RV32IMFC);
    csr_write(CSR_MISA, 0);
    csr_read_expect(CSR_MISA, MISA_RV32IMFC);
    csr_read_expect(CSR_MSTATUS, 32'h0000_1800);
    csr_read_expect(CSR_MHARTID, 0);
    csr_read_expect(CSR_MCONFIGPTR, 0);
    csr_access(CSR_OP_RS, CSR_FCSR, 0, 1'b1, value);

    // Enable F state and exercise coherent fflags/frm/fcsr aliases.
    csr_write(CSR_MSTATUS, 32'h0000_2088);
    assert (fp_enabled_o);
    csr_read_expect(CSR_MSTATUS, 32'h0000_3888);
    fp_write_commit_i = 1'b1;
    csr_valid_i = 1'b1;
    csr_op_i = CSR_OP_RS;
    csr_addr_i = CSR_MSTATUS;
    csr_wdata_i = 0;
    csr_src_zero_i = 1'b0;
    #1;
    assert (csr_rdata_o == 32'h8000_7888);
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MSTATUS, 32'h8000_7888);
    csr_write(CSR_FCSR, 0);
    fp_flags_valid_i = 1'b1;
    fp_flags_i = 5'h01;
    csr_valid_i = 1'b1;
    csr_op_i = CSR_OP_RS;
    csr_addr_i = CSR_FFLAGS;
    csr_wdata_i = 32'h2;
    csr_src_zero_i = 1'b0;
    #1;
    assert (csr_rdata_o == 1);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (fflags_o == 3);
    csr_write(CSR_FCSR, 32'h0000_0065);
    csr_read_expect(CSR_FCSR, 32'h0000_0065);
    csr_read_expect(CSR_MSTATUS, 32'h8000_7888);
    fp_flags_valid_i = 1'b1;
    fp_flags_i = 5'h12;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (fflags_o == 5'h17 && frm_o == 3'd3);
    csr_write(CSR_FRM, 32'd7);
    assert (frm_o == 7 && fflags_o == 5'h17);
    csr_write(CSR_MSTATUS, 0);
    assert (!fp_enabled_o);
    csr_access(CSR_OP_RS, CSR_FFLAGS, 0, 1'b1, value);

    // WARL mtvec modes and machine interrupt priority/vectoring.
    csr_write(CSR_MTVEC, ITIM_BASE | 32'd3);
    csr_read_expect(CSR_MTVEC, ITIM_BASE);
    csr_write(CSR_MTVEC, ITIM_BASE | 32'd1);
    csr_valid_i = 1'b1;
    csr_op_i = CSR_OP_RW;
    csr_addr_i = CSR_MTVEC;
    csr_wdata_i = (ITIM_BASE + 32'h100) | 32'd1;
    csr_src_zero_i = 1'b0;
    trap_is_interrupt_i = 1'b1;
    trap_cause_i = 31'(IRQ_M_SOFTWARE);
    #1;
    assert (trap_vector_o == ITIM_BASE + 32'h10c);
    @(posedge clk_i); #1;
    clear_inputs();
    csr_write(CSR_MTVEC, ITIM_BASE | 32'd1);
    csr_write(CSR_MSTATUS, 32'h0000_2008);
    csr_write(CSR_MIE, MIP_MACHINE_MASK);
    irq_timer_i = 1'b1;
    irq_software_i = 1'b1;
    irq_external_i = 1'b1;
    trap_is_interrupt_i = 1'b1;
    trap_cause_i = 31'(IRQ_M_EXTERNAL);
    #1;
    assert (wake_pending_o && interrupt_pending_o);
    assert (interrupt_cause_o == IRQ_M_EXTERNAL);
    assert (trap_vector_o == ITIM_BASE + 32'd44);

    // Trap entry captures precise state and MRET restores global MIE.
    trap_valid_i = 1'b1;
    trap_cause_i = 31'(IRQ_M_SOFTWARE);
    trap_pc_i = 32'h0000_101c;
    trap_tval_i = 32'hfeed_face;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MEPC, 32'h0000_101c);
    csr_read_expect(CSR_MCAUSE, 32'h8000_0003);
    csr_read_expect(CSR_MTVAL, 0);
    csr_read_expect(CSR_MSTATUS, 32'h0000_3880);
    assert (mret_pc_o == 32'h0000_101c);
    mret_commit_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MSTATUS, 32'h0000_3888);

    // Synchronous traps retain mtval; trap coincident with MRET stacks MPIE.
    trap_valid_i = 1'b1;
    trap_is_interrupt_i = 1'b0;
    trap_cause_i = 31'(EXC_ILLEGAL);
    trap_pc_i = 32'h8000_0042;
    trap_tval_i = 32'hfeed_face;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MCAUSE, 32'(EXC_ILLEGAL));
    csr_read_expect(CSR_MTVAL, 32'hfeed_face);
    mret_commit_i = 1'b1;
    trap_valid_i = 1'b1;
    trap_is_interrupt_i = 1'b1;
    trap_cause_i = 31'(IRQ_M_SOFTWARE);
    trap_pc_i = 32'h8000_0050;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MSTATUS, 32'h0000_3880);
    mret_commit_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();

    // WFI wakes on a locally enabled interrupt even with global MIE clear.
    csr_write(CSR_MSTATUS, 32'h0000_2000);
    wfi_commit_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (sleeping_o);
    irq_software_i = 1'b1;
    #1;
    assert (wake_pending_o && !interrupt_pending_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (!sleeping_o);

    // Freeze counters, program both RV32 halves, and verify RO aliases.
    csr_write(CSR_MCOUNTINHIBIT, 32'hffff_ffff);
    csr_write(CSR_MCYCLEH, 32'h1234_5678);
    csr_write(CSR_MCYCLE, 32'h9abc_def0);
    csr_read_expect(CSR_MCYCLEH, 32'h1234_5678);
    csr_read_expect(CSR_MCYCLE, 32'h9abc_def0);
    csr_read_expect(CSR_CYCLEH, 32'h1234_5678);
    csr_read_expect(CSR_CYCLE, 32'h9abc_def0);
    csr_read_expect(CSR_TIMEH, 32'h0123_4567);
    csr_read_expect(CSR_TIME, 32'h89ab_cdef);
    csr_access(CSR_OP_RW, CSR_CYCLE, 32'd0, 1'b1, value);
    csr_read_expect(CSR_MCYCLE, 32'h9abc_def0);

    // A non-x0 source containing zero still attempts CSRRS and must fault on RO.
    csr_valid_i = 1'b1;
    csr_op_i = CSR_OP_RS;
    csr_addr_i = CSR_CYCLE;
    csr_wdata_i = 0;
    csr_src_zero_i = 1'b0;
    #1;
    assert (csr_illegal_o);
    @(posedge clk_i); #1;
    clear_inputs();

    // Instret counts retired uops; HPM event selectors and inhibit bits work.
    csr_write(CSR_MINSTRETH, 0);
    csr_write(CSR_MINSTRET, 0);
    csr_write(CSR_MCOUNTINHIBIT, 32'h0000_0001);
    retire_count_i = 3;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_INSTRET, 3);
    csr_write(CSR_MHPMEVENT3, 32'(PERF_ICACHE_MISS));
    perf_event_i[PERF_ICACHE_MISS] = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_MHPMCOUNTER3, 1);
    csr_write(CSR_MCOUNTINHIBIT, 32'h0000_0009);
    perf_event_i[PERF_ICACHE_MISS] = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    csr_read_expect(CSR_HPMCOUNTER3, 1);

    // PMP WARL fields and both forms of lock are sticky until reset.
    csr_write(CSR_PMPADDR0, 32'h0000_0100);
    csr_write(CSR_PMPCFG0, 32'h0000_0009);
    assert (pmpaddr_o[0] == 32'h100 && pmpcfg_o[0] == 8'h09);
    csr_write(CSR_PMPCFG0, 32'h0000_0209);
    csr_read_expect(CSR_PMPCFG0, 32'h0000_0009);
    csr_write(CSR_PMPCFG0, 32'h0000_0089);
    csr_write(CSR_PMPADDR0, 32'h0000_0200);
    csr_write(CSR_PMPCFG0, 32'h0000_0000);
    assert (pmpaddr_o[0] == 32'h100 && pmpcfg_o[0] == 8'h89);
    csr_write(CSR_PMPADDR0 + 12'd1, 32'h0000_0333);
    csr_write(CSR_PMPCFG0, 32'h0089_0089);
    csr_write(CSR_PMPADDR0 + 12'd1, 32'h0000_0444);
    assert (pmpaddr_o[1] == 32'h333 && pmpcfg_o[2] == 8'h89);

    // Remaining mandatory M CSRs and illegal unimplemented address behavior.
    csr_write(CSR_MSCRATCH, 32'h1357_9bdf);
    csr_read_expect(CSR_MSCRATCH, 32'h1357_9bdf);
    csr_write(CSR_MEPC, 32'h8000_0003);
    csr_read_expect(CSR_MEPC, 32'h8000_0002);
    csr_write(CSR_MIP, 32'hffff_ffff);
    csr_read_expect(CSR_MIP, 0);
    csr_write(CSR_MSTATUSH, 32'hffff_ffff);
    csr_read_expect(CSR_MSTATUSH, 0);
    csr_access(CSR_OP_RS, 12'h306, 0, 1'b1, value);

    $display("PASS: tb_csr_file");
    $finish;
  end
endmodule
