`timescale 1ns/1ps

module tb_coremark_system;
  import soc_pkg::*;

  import "DPI-C" function int elf_open(input string path);
  import "DPI-C" function int unsigned elf_entry();
  import "DPI-C" function int elf_next(
    output int unsigned address,
    output int unsigned data,
    output byte unsigned strobe
  );
  import "DPI-C" function void elf_close();

  logic clk_i, rst_ni, irq_external_i;
  logic host_valid_i, host_write_i, host_ready_o, host_error_o;
  logic [31:0] host_addr_i, host_wdata_i, host_rdata_o;
  logic [3:0] host_wstrb_i;
  logic [63:0] tohost_o, fromhost_o;
  logic [31:0] debug_pc_o;
  logic [mycore_pkg::RW:0] debug_rob_occupancy_o;

  mycore_system dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic host_write(
    input logic [31:0] address,
    input logic [31:0] data,
    input logic [3:0] strobe
  );
    begin
      host_valid_i = 1;
      host_write_i = 1;
      host_addr_i = address;
      host_wdata_i = data;
      host_wstrb_i = strobe;
      #1;
      while (!host_ready_o) begin
        @(posedge clk_i); #1;
      end
      assert (!host_error_o);
      @(posedge clk_i); #1;
      host_valid_i = 0;
      host_write_i = 0;
    end
  endtask

  string elf_file;
  int write_count, next_result, cycles;
  int unsigned write_address, write_data;
  byte unsigned write_strobe;
  real coremark_per_mhz;
  real measured_ipc;
  longint unsigned retired_instructions, branch_count, branch_mispred_count;
  longint unsigned load_count, store_count, backend_stall_cycles;
  longint unsigned imem_req_wait_cycles, imem_rsp_wait_cycles;
  longint unsigned dispatch_instructions, dispatch_cycles, full_dispatch_cycles;
  logic profile_active;
  longint unsigned frontend_empty_cycles, frontend_head_miss_cycles;
  longint unsigned txn_full_cycles, line_full_cycles;
  longint unsigned stall_rob, stall_int_iq, stall_mem_iq, stall_sq;
  longint unsigned stall_control, commit_idle_cycles, serial_store_wait_cycles;
  longint unsigned dispatch_width [5], issue_width [7], commit_width [5];
  longint unsigned commit_origin [4][4];
  longint unsigned rob_occupancy_sum, int_iq_occupancy_sum;
  longint unsigned mem_iq_occupancy_sum, sq_occupancy_sum;
  longint unsigned rob_occupancy_max, int_iq_occupancy_max;
  longint unsigned mem_iq_occupancy_max, sq_occupancy_max;
  longint unsigned lsu_both_busy_cycles, lsu_one_busy_cycles;
  longint unsigned load_unknown_cycles, mem_head_blocked_cycles;
  integer dispatch_width_now, issue_width_now, commit_width_now;

  always_comb begin
    dispatch_width_now = $countones(dut.u_core.dispatch_valid);
    issue_width_now = $countones(dut.u_core.int_issue_accept) +
                      $countones(dut.u_core.mem_issue_accept);
    commit_width_now = int'(dut.u_core.retire_count);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      retired_instructions <= 0;
      branch_count <= 0;
      branch_mispred_count <= 0;
      load_count <= 0;
      store_count <= 0;
      backend_stall_cycles <= 0;
      imem_req_wait_cycles <= 0;
      imem_rsp_wait_cycles <= 0;
      dispatch_instructions <= 0;
      dispatch_cycles <= 0;
      full_dispatch_cycles <= 0;
      frontend_empty_cycles <= 0;
      frontend_head_miss_cycles <= 0;
      txn_full_cycles <= 0;
      line_full_cycles <= 0;
      stall_rob <= 0;
      stall_int_iq <= 0;
      stall_mem_iq <= 0;
      stall_sq <= 0;
      stall_control <= 0;
      commit_idle_cycles <= 0;
      serial_store_wait_cycles <= 0;
      rob_occupancy_sum <= 0;
      int_iq_occupancy_sum <= 0;
      mem_iq_occupancy_sum <= 0;
      sq_occupancy_sum <= 0;
      rob_occupancy_max <= 0;
      int_iq_occupancy_max <= 0;
      mem_iq_occupancy_max <= 0;
      sq_occupancy_max <= 0;
      lsu_both_busy_cycles <= 0;
      lsu_one_busy_cycles <= 0;
      load_unknown_cycles <= 0;
      mem_head_blocked_cycles <= 0;
      for (int width = 0; width <= 4; width++) begin
        dispatch_width[width] <= 0;
        commit_width[width] <= 0;
      end
      for (int commit_lane = 0; commit_lane < 4; commit_lane++) begin
        for (int origin_lane = 0; origin_lane < 4; origin_lane++)
          commit_origin[commit_lane][origin_lane] <= 0;
      end
      for (int width = 0; width <= 6; width++)
        issue_width[width] <= 0;
    end else if (profile_active) begin
      retired_instructions <= retired_instructions + 64'(dut.u_core.retire_count);
      branch_count <= branch_count + dut.u_core.perf_events[csr_pkg::PERF_BRANCH];
      branch_mispred_count <= branch_mispred_count +
                              dut.u_core.perf_events[csr_pkg::PERF_BRANCH_MISPRED];
      load_count <= load_count + dut.u_core.perf_events[csr_pkg::PERF_LOAD];
      store_count <= store_count + dut.u_core.perf_events[csr_pkg::PERF_STORE];
      backend_stall_cycles <= backend_stall_cycles +
                              (dut.u_core.fetch_inst[0].valid && !dut.u_core.fetch_consume);
      imem_req_wait_cycles <= imem_req_wait_cycles +
        (dut.u_core.imem_req_valid_o && !dut.u_core.imem_req_ready_i);
      imem_rsp_wait_cycles <= imem_rsp_wait_cycles +
        (dut.u_core.imem_rsp_valid_i && !dut.u_core.imem_rsp_ready_o);
      if (dut.u_core.dispatch_fire) begin
        dispatch_instructions <= dispatch_instructions +
                                 64'($countones(dut.u_core.dispatch_valid));
        dispatch_cycles <= dispatch_cycles + 1;
        if (&dut.u_core.dispatch_valid)
          full_dispatch_cycles <= full_dispatch_cycles + 1;
        dispatch_width[dispatch_width_now] <=
          dispatch_width[dispatch_width_now] + 1;
      end
      issue_width[issue_width_now] <= issue_width[issue_width_now] + 1;
      commit_width[commit_width_now] <= commit_width[commit_width_now] + 1;
      for (int commit_lane = 0; commit_lane < 4; commit_lane++) begin
        if (dut.u_core.rob_commit_valid[commit_lane]) begin
          commit_origin[commit_lane]
                       [dut.u_core.rob_commit_uop[commit_lane].d.origin_lane] <=
            commit_origin[commit_lane]
                         [dut.u_core.rob_commit_uop[commit_lane].d.origin_lane] + 1;
        end
      end

      frontend_empty_cycles <= frontend_empty_cycles +
        !dut.u_core.fetch_inst[0].valid;
      frontend_head_miss_cycles <= frontend_head_miss_cycles +
        ((dut.u_core.u_frontend.line_count_q != 0) &&
         !dut.u_core.u_frontend.source_valid);
      txn_full_cycles <= txn_full_cycles +
        (dut.u_core.u_frontend.txn_count_q == 4);
      line_full_cycles <= line_full_cycles +
        (dut.u_core.u_frontend.line_count_q == 4);

      if (dut.u_core.fetch_inst[0].valid && !dut.u_core.fetch_consume) begin
        stall_rob <= stall_rob + !dut.u_core.rob_ready;
        stall_int_iq <= stall_int_iq + !dut.u_core.int_iq_ready;
        stall_mem_iq <= stall_mem_iq + !dut.u_core.mem_iq_ready;
        stall_sq <= stall_sq + !dut.u_core.sq_dispatch_ready;
        stall_control <= stall_control +
          (dut.u_core.global_flush || dut.u_core.trap_take ||
           dut.u_core.csr_interrupt_pending);
      end

      commit_idle_cycles <= commit_idle_cycles +
        ((dut.u_core.rob_occupancy != 0) && (dut.u_core.retire_count == 0));
      serial_store_wait_cycles <= serial_store_wait_cycles +
        (dut.u_core.rob_serial_valid &&
         (dut.u_core.rob_serial_uop.d.fu == mycore_pkg::FU_ST) &&
         !dut.u_core.rob_serial_ready);
      rob_occupancy_sum <= rob_occupancy_sum + 64'(dut.u_core.rob_occupancy);
      int_iq_occupancy_sum <= int_iq_occupancy_sum +
                              64'(dut.u_core.int_iq_occupancy);
      mem_iq_occupancy_sum <= mem_iq_occupancy_sum +
                              64'(dut.u_core.mem_iq_occupancy);
      sq_occupancy_sum <= sq_occupancy_sum + 64'(dut.u_core.sq_occupancy);
      if (64'(dut.u_core.rob_occupancy) > rob_occupancy_max)
        rob_occupancy_max <= 64'(dut.u_core.rob_occupancy);
      if (64'(dut.u_core.int_iq_occupancy) > int_iq_occupancy_max)
        int_iq_occupancy_max <= 64'(dut.u_core.int_iq_occupancy);
      if (64'(dut.u_core.mem_iq_occupancy) > mem_iq_occupancy_max)
        mem_iq_occupancy_max <= 64'(dut.u_core.mem_iq_occupancy);
      if (64'(dut.u_core.sq_occupancy) > sq_occupancy_max)
        sq_occupancy_max <= 64'(dut.u_core.sq_occupancy);
      lsu_both_busy_cycles <= lsu_both_busy_cycles + (&dut.u_core.lsu_busy);
      lsu_one_busy_cycles <= lsu_one_busy_cycles +
        64'(dut.u_core.lsu_busy[0] ^ dut.u_core.lsu_busy[1]);
      load_unknown_cycles <= load_unknown_cycles +
        (|dut.u_core.load_older_unknown);
      mem_head_blocked_cycles <= mem_head_blocked_cycles +
        (dut.u_core.mem_issue_valid[0] && !dut.u_core.mem_issue_accept[0]);
    end
  end

  initial begin
    host_valid_i = 0;
    host_write_i = 0;
    host_addr_i = 0;
    host_wdata_i = 0;
    host_wstrb_i = 0;
    irq_external_i = 0;
    profile_active = 0;
    if (!$value$plusargs("ELF_FILE=%s", elf_file))
      $fatal(1, "missing +ELF_FILE=<path>");

    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    write_count = elf_open(elf_file);
    assert (write_count > 0 && elf_entry() == PAYLOAD_ENTRY);
    next_result = elf_next(write_address, write_data, write_strobe);
    while (next_result != 0) begin
      host_write(write_address, write_data, write_strobe[3:0]);
      next_result = elf_next(write_address, write_data, write_strobe);
    end
    elf_close();

    profile_active = 1;
    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf);
    cycles = 0;
    while ((tohost_o == 0) && (cycles < 2000000)) begin
      @(posedge clk_i);
      cycles++;
    end
    if (tohost_o != 64'd1) begin
      for (int iq_idx = 0; iq_idx < mycore_pkg::NIQ_INT; iq_idx++) begin
        if (dut.u_core.u_int_iq.entry_q[iq_idx].valid &&
            (dut.u_core.u_int_iq.entry_q[iq_idx].uop.rob_idx ==
             dut.u_core.rob_head))
          $display("Head IQ slot=%0d ready=%0b/%0b/%0b",
                   iq_idx, dut.u_core.u_int_iq.entry_q[iq_idx].src1_ready,
                   dut.u_core.u_int_iq.entry_q[iq_idx].src2_ready,
                   dut.u_core.u_int_iq.entry_q[iq_idx].src3_ready);
      end
      $fatal(1, "CoreMark failed: tohost=%x pc=%08x rob=%0d head=%0d head_pc=%08x head_fu=%0d head_done=%0b ps1=%0d/%0b ps2=%0d/%0b intiq=%0d memiq=%0d lsu=%b block=%0b txn=%0d line=%0d hold=%0b next=%08x source=%0b req=%0b/%0b rsp=%0b/%0b soc_if=%0d",
                  tohost_o, debug_pc_o, debug_rob_occupancy_o,
                  dut.u_core.rob_head,
                  dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.d.pc,
                  dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.d.fu,
                  dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].complete,
                  dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.ps1,
                  dut.u_core.u_prf.ready_q[dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.ps1],
                  dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.ps2,
                  dut.u_core.u_prf.ready_q[dut.u_core.u_rob.entry_q[dut.u_core.rob_head[mycore_pkg::RW-1:0]].uop.ps2],
                  dut.u_core.int_iq_occupancy, dut.u_core.mem_iq_occupancy,
                  dut.u_core.lsu_busy, dut.u_core.pipeline_issue_block,
                  dut.u_core.u_frontend.txn_count_q,
                  dut.u_core.u_frontend.line_count_q,
                  dut.u_core.u_frontend.req_hold_valid_q,
                  dut.u_core.u_frontend.next_req_pc_q,
                  dut.u_core.u_frontend.source_valid,
                  dut.u_core.imem_req_valid_o, dut.u_core.imem_req_ready_i,
                  dut.u_core.imem_rsp_valid_i, dut.u_core.imem_rsp_ready_o,
                   dut.u_soc.if_count_q);
    end
    assert (fromhost_o[31:0] != 0 && fromhost_o[63:32] != 0);
    coremark_per_mhz = (fromhost_o[63:32] * 1000000.0) / fromhost_o[31:0];
    measured_ipc = (retired_instructions * 1.0) / cycles;
    $display("PASS: CoreMark validation");
    $display("CoreMark iterations=%0d timed_cycles=%0d system_cycles=%0d",
             fromhost_o[63:32], fromhost_o[31:0], cycles);
    $display("Engineering estimate CoreMark/MHz=%0f", coremark_per_mhz);
    $display("Perf retired=%0d branches=%0d mispredicts=%0d loads=%0d stores=%0d",
             retired_instructions, branch_count, branch_mispred_count,
             load_count, store_count);
    $display("Perf backend_stall_cycles=%0d imem_req_wait_cycles=%0d imem_rsp_wait_cycles=%0d",
             backend_stall_cycles, imem_req_wait_cycles, imem_rsp_wait_cycles);
    $display("Perf IPC=%0f dispatched=%0d dispatch_cycles=%0d full_width=%0d",
             measured_ipc, dispatch_instructions, dispatch_cycles,
             full_dispatch_cycles);
    $display("Profile frontend_empty=%0d head_miss=%0d txn_full=%0d line_full=%0d",
             frontend_empty_cycles, frontend_head_miss_cycles,
             txn_full_cycles, line_full_cycles);
    $display("Profile stalls rob=%0d int_iq=%0d mem_iq=%0d sq=%0d control=%0d",
             stall_rob, stall_int_iq, stall_mem_iq, stall_sq, stall_control);
    $display("Profile commit_idle=%0d serial_store_wait=%0d mem_head_blocked=%0d",
             commit_idle_cycles, serial_store_wait_cycles,
             mem_head_blocked_cycles);
    $display("Profile LSU both_busy=%0d one_busy=%0d older_store_unknown=%0d",
             lsu_both_busy_cycles, lsu_one_busy_cycles, load_unknown_cycles);
    $display("Profile dispatch_width 1=%0d 2=%0d 3=%0d 4=%0d",
             dispatch_width[1], dispatch_width[2], dispatch_width[3],
             dispatch_width[4]);
    $display("Profile issue_width 0=%0d 1=%0d 2=%0d 3=%0d 4=%0d 5=%0d 6=%0d",
             issue_width[0], issue_width[1], issue_width[2], issue_width[3],
             issue_width[4], issue_width[5], issue_width[6]);
    $display("Profile commit_width 0=%0d 1=%0d 2=%0d 3=%0d 4=%0d",
             commit_width[0], commit_width[1], commit_width[2],
             commit_width[3], commit_width[4]);
    for (int commit_lane = 0; commit_lane < 4; commit_lane++) begin
      $display("Profile commit_lane%0d origins 0=%0d 1=%0d 2=%0d 3=%0d",
               commit_lane, commit_origin[commit_lane][0],
               commit_origin[commit_lane][1], commit_origin[commit_lane][2],
               commit_origin[commit_lane][3]);
    end
    $display("Profile occupancy avg/max ROB=%0f/%0d INTIQ=%0f/%0d MEMIQ=%0f/%0d SQ=%0f/%0d",
             rob_occupancy_sum * 1.0 / cycles, rob_occupancy_max,
             int_iq_occupancy_sum * 1.0 / cycles, int_iq_occupancy_max,
             mem_iq_occupancy_sum * 1.0 / cycles, mem_iq_occupancy_max,
             sq_occupancy_sum * 1.0 / cycles, sq_occupancy_max);
    $finish;
  end
endmodule
