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
    end else begin
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
      end
    end
  end

  initial begin
    host_valid_i = 0;
    host_write_i = 0;
    host_addr_i = 0;
    host_wdata_i = 0;
    host_wstrb_i = 0;
    irq_external_i = 0;
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

    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf);
    cycles = 0;
    while ((tohost_o == 0) && (cycles < 20000000)) begin
      @(posedge clk_i);
      cycles++;
    end
    assert (tohost_o == 64'd1)
      else $fatal(1, "CoreMark failed: tohost=%x pc=%08x rob=%0d",
                  tohost_o, debug_pc_o, debug_rob_occupancy_o);
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
    $finish;
  end
endmodule
