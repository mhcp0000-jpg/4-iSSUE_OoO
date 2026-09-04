`timescale 1ns/1ps

module tb_soc;
  import soc_pkg::*;
  import mycore_pkg::RESET_PC;

  logic clk_i;
  logic rst_ni;
  logic imem_valid_i;
  logic [31:0] imem_addr_i;
  logic imem_ready_o;
  logic [31:0] imem_rdata_o;
  logic imem_error_o;
  logic dmem_valid_i, dmem_write_i;
  logic [31:0] dmem_addr_i, dmem_wdata_i;
  logic [3:0] dmem_wstrb_i;
  logic dmem_ready_o;
  logic [31:0] dmem_rdata_o;
  logic dmem_error_o;
  logic host_valid_i, host_write_i;
  logic [31:0] host_addr_i, host_wdata_i;
  logic [3:0] host_wstrb_i;
  logic host_ready_o;
  logic [31:0] host_rdata_o;
  logic host_error_o;
  logic irq_software_o;
  logic [63:0] tohost_o, fromhost_o;

  mycore_soc dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      imem_valid_i = 1'b0;
      imem_addr_i = '0;
      dmem_valid_i = 1'b0;
      dmem_write_i = 1'b0;
      dmem_addr_i = '0;
      dmem_wdata_i = '0;
      dmem_wstrb_i = '0;
      host_valid_i = 1'b0;
      host_write_i = 1'b0;
      host_addr_i = '0;
      host_wdata_i = '0;
      host_wstrb_i = '0;
      #1;
    end
  endtask

  task automatic host_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0] strb,
    input logic expect_error
  );
    begin
      @(negedge clk_i);
      host_valid_i = 1'b1;
      host_write_i = 1'b1;
      host_addr_i = addr;
      host_wdata_i = data;
      host_wstrb_i = strb;
      #1;
      assert (host_ready_o && (host_error_o == expect_error));
      @(posedge clk_i); #1;
      host_valid_i = 1'b0;
      host_write_i = 1'b0;
      #1;
    end
  endtask

  task automatic host_read(
    input logic [31:0] addr,
    output logic [31:0] data,
    input logic expect_error
  );
    begin
      @(negedge clk_i);
      host_valid_i = 1'b1;
      host_write_i = 1'b0;
      host_addr_i = addr;
      #1;
      assert (host_ready_o && (host_error_o == expect_error));
      data = host_rdata_o;
      host_valid_i = 1'b0;
      #1;
    end
  endtask

  task automatic imem_read(
    input logic [31:0] addr,
    output logic [31:0] data,
    input logic expect_error
  );
    begin
      imem_valid_i = 1'b1;
      imem_addr_i = addr;
      #1;
      assert (imem_ready_o && (imem_error_o == expect_error));
      data = imem_rdata_o;
      imem_valid_i = 1'b0;
      #1;
    end
  endtask

  task automatic dmem_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0] strb,
    input logic expect_error
  );
    begin
      @(negedge clk_i);
      dmem_valid_i = 1'b1;
      dmem_write_i = 1'b1;
      dmem_addr_i = addr;
      dmem_wdata_i = data;
      dmem_wstrb_i = strb;
      #1;
      assert (dmem_ready_o && (dmem_error_o == expect_error));
      @(posedge clk_i); #1;
      dmem_valid_i = 1'b0;
      dmem_write_i = 1'b0;
      #1;
    end
  endtask

  task automatic dmem_read(
    input logic [31:0] addr,
    output logic [31:0] data,
    input logic expect_error
  );
    begin
      dmem_valid_i = 1'b1;
      dmem_write_i = 1'b0;
      dmem_addr_i = addr;
      #1;
      assert (dmem_ready_o && (dmem_error_o == expect_error));
      data = dmem_rdata_o;
      dmem_valid_i = 1'b0;
      #1;
    end
  endtask

  logic [31:0] data;

  initial begin
    clear_inputs();
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i); #1;

    assert (RESET_PC == BOOTROM_BASE);
    assert (ITIM_BASE + ITIM_BYTES == DTIM_BASE);
    assert (TOHOST_ADDR == DTIM_BASE && FROMHOST_ADDR == DTIM_BASE + 8);
    assert (!irq_software_o && tohost_o == 0 && fromhost_o == 0);

    // Boot ROM installs mtvec=ITIM_BASE, enables MSIE/MIE, then loops in WFI.
    imem_read(BOOTROM_BASE + 0, data, 0);  assert (data == 32'h8000_02b7);
    imem_read(BOOTROM_BASE + 4, data, 0);  assert (data == 32'h3052_9073);
    imem_read(BOOTROM_BASE + 8, data, 0);  assert (data == 32'h0080_0293);
    imem_read(BOOTROM_BASE + 12, data, 0); assert (data == 32'h3042_a073);
    imem_read(BOOTROM_BASE + 16, data, 0); assert (data == 32'h3002_a073);
    imem_read(BOOTROM_BASE + 20, data, 0); assert (data == 32'h1050_0073);
    imem_read(BOOTROM_BASE + 24, data, 0); assert (data == 32'hffdff06f);

    // Host ELF writes are immediately visible to instruction and data ports.
    host_write(ITIM_BASE, 32'h1122_3344, 4'b1111, 0);
    imem_read(ITIM_BASE, data, 0); assert (data == 32'h1122_3344);
    host_write(ITIM_BASE, 32'haabb_ccdd, 4'b0101, 0);
    dmem_read(ITIM_BASE, data, 0); assert (data == 32'h11bb_33dd);
    host_write(ITIM_BASE + ITIM_BYTES - 4, 32'hc001_c0de, 4'hf, 0);
    host_read(ITIM_BASE + ITIM_BYTES - 4, data, 0); assert (data == 32'hc001_c0de);

    // DTIM reserves two 64-bit host mailboxes at its first 16 bytes.
    host_write(TOHOST_ADDR, 32'h89ab_cdef, 4'hf, 0);
    host_write(TOHOST_ADDR + 4, 32'h0123_4567, 4'hf, 0);
    host_write(FROMHOST_ADDR, 32'h7654_3210, 4'hf, 0);
    host_write(FROMHOST_ADDR + 4, 32'hfedc_ba98, 4'hf, 0);
    assert (tohost_o == 64'h0123_4567_89ab_cdef);
    assert (fromhost_o == 64'hfedc_ba98_7654_3210);

    dmem_write(DTIM_BASE + 16, 32'hdead_beef, 4'hf, 0);
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'hdead_beef);
    dmem_write(DTIM_BASE + 17, 32'hffff_ffff, 4'hf, 1);
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'hdead_beef);

    // Host raises MSIP after loading; payload code clears it through dmem.
    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf, 0);
    assert (irq_software_o);
    dmem_read(CLINT_MSIP_ADDR, data, 0); assert (data == 1);
    dmem_write(CLINT_MSIP_ADDR, 32'd0, 4'hf, 0);
    assert (!irq_software_o);

    // ROM writes and unmapped accesses report errors without modifying state.
    host_write(BOOTROM_BASE, 32'hffff_ffff, 4'hf, 1);
    imem_read(BOOTROM_BASE, data, 0); assert (data == 32'h8000_02b7);
    host_read(32'h4000_0000, data, 1);
    dmem_read(32'h4000_0000, data, 1);
    imem_read(ITIM_BASE + 1, data, 1);

    $display("PASS: tb_soc");
    $finish;
  end
endmodule
