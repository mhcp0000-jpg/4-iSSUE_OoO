`timescale 1ns/1ps

module tb_soc;
  import soc_pkg::*;
  import csr_pkg::NPMP;
  import mycore_pkg::RESET_PC;

  logic clk_i;
  logic rst_ni;
  logic imem_valid_i;
  logic [31:0] imem_addr_i;
  logic [1:0] imem_size_i;
  logic imem_ready_o;
  logic [127:0] imem_rdata_o;
  logic [3:0] imem_error_o;
  logic dmem_valid_i, dmem_write_i;
  logic [31:0] dmem_addr_i, dmem_wdata_i;
  logic [1:0] dmem_size_i;
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
  logic irq_timer_o;
  logic [63:0] time_o;
  logic [63:0] tohost_o, fromhost_o;
  logic pmp_priv_m_i;
  logic [7:0] pmpcfg_i [NPMP];
  logic [31:0] pmpaddr_i [NPMP];

  mycore_soc dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      imem_valid_i = 1'b0;
      imem_addr_i = '0;
      imem_size_i = 2'd2;
      dmem_valid_i = 1'b0;
      dmem_write_i = 1'b0;
      dmem_addr_i = '0;
      dmem_wdata_i = '0;
      dmem_wstrb_i = '0;
      dmem_size_i = 2'd2;
      pmp_priv_m_i = 1'b1;
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
      while (!host_ready_o) begin
        @(posedge clk_i); #1;
      end
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
      while (!imem_ready_o) begin
        @(posedge clk_i); #1;
      end
      assert (imem_ready_o &&
              (imem_error_o[addr[3:2]] == expect_error));
      imem_line_data = imem_rdata_o;
      imem_line_error = imem_error_o;
      data = imem_rdata_o[addr[3:2]*32 +: 32];
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
      while (!dmem_ready_o) begin
        @(posedge clk_i); #1;
      end
      assert (dmem_ready_o && (dmem_error_o == expect_error));
      data = dmem_rdata_o;
      dmem_valid_i = 1'b0;
      #1;
    end
  endtask

  logic [31:0] data;
  logic [127:0] imem_line_data;
  logic [3:0] imem_line_error;

  initial begin
    for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
      pmpcfg_i[pmp_idx] = '0;
      pmpaddr_i[pmp_idx] = '0;
    end
    clear_inputs();
    rst_ni = 1'b0;
    host_valid_i = 1'b1;
    host_write_i = 1'b1;
    host_addr_i = CLINT_MSIP_ADDR;
    host_wdata_i = 1;
    host_wstrb_i = 4'hf;
    #1;
    assert (!host_ready_o);
    host_valid_i = 1'b0;
    host_write_i = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i); #1;

    assert (RESET_PC == BOOTROM_BASE);
    assert (ITIM_BASE + ITIM_BYTES == DTIM_BASE);
    assert (TOHOST_ADDR == DTIM_BASE && FROMHOST_ADDR == DTIM_BASE + 8);
    assert (!irq_software_o && !irq_timer_o && tohost_o == 0 && fromhost_o == 0);

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
    host_write(ITIM_BASE + 4, 32'h5566_7788, 4'hf, 0);
    host_write(ITIM_BASE + 8, 32'h99aa_bbcc, 4'hf, 0);
    host_write(ITIM_BASE + 12, 32'hddee_ff00, 4'hf, 0);
    imem_read(ITIM_BASE + 8, data, 0);
    assert (data == 32'h99aa_bbcc);
    assert (imem_line_data == 128'hddee_ff00_99aa_bbcc_5566_7788_1122_3344);
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
    dmem_size_i = 2'd0;
    dmem_write(DTIM_BASE + 19, 32'haa00_0000, 4'b1000, 0);
    dmem_write(DTIM_BASE + 18, 32'hffff_ffff, 4'b1111, 1);
    dmem_size_i = 2'd2;
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'haaad_beef);

    // Host raises MSIP after loading; payload code clears it through dmem.
    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf, 0);
    assert (irq_software_o);
    dmem_read(CLINT_MSIP_ADDR, data, 0); assert (data == 1);
    dmem_write(CLINT_MSIP_ADDR, 32'd0, 4'hf, 0);
    assert (!irq_software_o);

    // Standard CLINT mtime/mtimecmp registers drive MTIP.
    host_write(CLINT_MTIMECMP_ADDR, 32'd0, 4'hf, 0);
    host_write(CLINT_MTIMECMP_ADDR + 4, 32'd0, 4'hf, 0);
    assert (irq_timer_o);
    host_write(CLINT_MTIMECMP_ADDR, 32'hffff_ffff, 4'hf, 0);
    host_write(CLINT_MTIMECMP_ADDR + 4, 32'hffff_ffff, 4'hf, 0);
    assert (!irq_timer_o && time_o != 0);

    // ROM writes and unmapped accesses report errors without modifying state.
    host_write(BOOTROM_BASE, 32'hffff_ffff, 4'hf, 1);
    imem_read(BOOTROM_BASE, data, 0); assert (data == 32'h8000_02b7);
    host_read(32'h4000_0000, data, 1);
    dmem_read(32'h4000_0000, data, 1);
    imem_read(ITIM_BASE + 1, data, 1);

    // Locked PMP permissions apply to CPU ports while the host still loads.
    pmpaddr_i[0] = DTIM_BASE >> 2;
    pmpaddr_i[1] = (DTIM_BASE + 32'h100) >> 2;
    pmpcfg_i[1] = 8'h89; // locked TOR, read-only
    dmem_read(DTIM_BASE + 16, data, 0);
    dmem_write(DTIM_BASE + 16, 32'h1111_2222, 4'hf, 1);
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'haaad_beef);
    host_write(DTIM_BASE + 16, 32'h3333_4444, 4'hf, 0);
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'h3333_4444);

    pmpaddr_i[0] = ITIM_BASE >> 2;
    pmpaddr_i[1] = (ITIM_BASE + 32'h100) >> 2;
    pmpcfg_i[1] = 8'h89;
    imem_read(ITIM_BASE, data, 1);
    pmpcfg_i[1] = 8'h8d; // locked TOR, read and execute
    imem_read(ITIM_BASE, data, 0);
    pmpaddr_i[1] = (ITIM_BASE + 32'hf4) >> 2;
    pmpaddr_i[2] = (ITIM_BASE + 32'h100) >> 2;
    pmpcfg_i[2] = 8'h89;
    imem_read(ITIM_BASE + 32'hf0, data, 0);
    assert (imem_line_error[3:1] == 3'b111);
    imem_read(ITIM_BASE + 32'hf4, data, 1);
    pmpcfg_i[2] = '0;
    pmpaddr_i[1] = (ITIM_BASE + 32'h100) >> 2;
    imem_size_i = 2'd1;
    imem_read(ITIM_BASE + 32'hfe, data, 0);
    imem_size_i = 2'd2;
    imem_read(ITIM_BASE + 32'hfe, data, 1);

    $display("PASS: tb_soc");
    $finish;
  end
endmodule
