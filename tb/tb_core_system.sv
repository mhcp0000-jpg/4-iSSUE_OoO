`timescale 1ns/1ps

module tb_core_system;
  import soc_pkg::*;

  logic clk_i, rst_ni, irq_external_i;
  logic host_valid_i, host_write_i, host_ready_o, host_error_o;
  logic [31:0] host_addr_i, host_wdata_i, host_rdata_o;
  logic [3:0] host_wstrb_i;
  logic [63:0] tohost_o, fromhost_o;
  logic [31:0] debug_pc_o;
  logic [mycore_pkg::RW:0] debug_rob_occupancy_o;

  mycore_system dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic host_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0] strb
  );
    begin
      @(negedge clk_i);
      host_valid_i = 1'b1;
      host_write_i = 1'b1;
      host_addr_i = addr;
      host_wdata_i = data;
      host_wstrb_i = strb;
      #1;
      assert (host_ready_o && !host_error_o);
      @(posedge clk_i); #1;
      host_valid_i = 1'b0;
      host_write_i = 1'b0;
    end
  endtask

  string host_file, opcode;
  integer fd, scan_result, cycles;
  logic [31:0] file_addr, file_data, entry;
  logic [3:0] file_strb;

  initial begin
    host_valid_i = 0;
    host_write_i = 0;
    host_addr_i = 0;
    host_wdata_i = 0;
    host_wstrb_i = 0;
    irq_external_i = 0;
    if (!$value$plusargs("HOST_FILE=%s", host_file))
      $fatal(1, "missing +HOST_FILE=<path>");

    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;

    fd = $fopen(host_file, "r");
    if (fd == 0)
      $fatal(1, "cannot open %s", host_file);
    entry = 0;
    while (!$feof(fd)) begin
      scan_result = $fscanf(fd, "%s %h %h %h\n", opcode, file_addr, file_data, file_strb);
      if (scan_result == 4) begin
        if (opcode == "E")
          entry = file_addr;
        else if (opcode == "W")
          host_write(file_addr, file_data, file_strb);
      end
    end
    $fclose(fd);
    assert (entry == PAYLOAD_ENTRY);

    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf);
    cycles = 0;
    while ((tohost_o == 0) && (cycles < 20000)) begin
      @(posedge clk_i);
      cycles++;
    end
    if (tohost_o == 0)
      $fatal(1, "timeout pc=%08x rob=%0d", debug_pc_o, debug_rob_occupancy_o);
    assert (tohost_o == 64'd1)
      else $fatal(1, "program failed: tohost=%016x pc=%08x", tohost_o, debug_pc_o);

    $display("PASS: tb_core_system cycles=%0d", cycles);
    $finish;
  end
endmodule
