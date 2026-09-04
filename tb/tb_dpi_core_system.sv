`timescale 1ns/1ps

module tb_dpi_core_system;
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
    while ((tohost_o == 0) && (cycles < 30000)) begin
      @(posedge clk_i);
      cycles++;
    end
    assert (tohost_o == 64'd1)
      else $fatal(1, "DPI ELF failed: tohost=%x pc=%08x rob=%0d",
                  tohost_o, debug_pc_o, debug_rob_occupancy_o);
    $display("PASS: tb_dpi_core_system writes=%0d cycles=%0d", write_count, cycles);
    $finish;
  end
endmodule
