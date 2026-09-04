`timescale 1ns/1ps

module tb_soc;
  import soc_pkg::*;
  import csr_pkg::NPMP;
  import mycore_pkg::RESET_PC;

  logic clk_i;
  logic rst_ni;
  logic imem_req_valid_i, imem_req_ready_o;
  logic [31:0] imem_req_addr_i;
  logic [1:0] imem_req_size_i;
  logic imem_rsp_valid_o, imem_rsp_ready_i;
  logic [127:0] imem_rsp_rdata_o;
  logic [3:0] imem_rsp_error_o;
  logic [mycore_pkg::NLSU-1:0] dmem_valid_i, dmem_write_i;
  logic [31:0] dmem_addr_i [mycore_pkg::NLSU];
  logic [31:0] dmem_wdata_i [mycore_pkg::NLSU];
  logic [1:0] dmem_size_i [mycore_pkg::NLSU];
  logic [3:0] dmem_wstrb_i [mycore_pkg::NLSU];
  logic [mycore_pkg::NLSU-1:0] dmem_ready_o;
  logic [31:0] dmem_rdata_o [mycore_pkg::NLSU];
  logic [mycore_pkg::NLSU-1:0] dmem_error_o;
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
      imem_req_valid_i = 1'b0;
      imem_req_addr_i = '0;
      imem_req_size_i = 2'd2;
      imem_rsp_ready_i = 1'b1;
      dmem_valid_i = '0;
      dmem_write_i = '0;
      for (int lsu_idx = 0; lsu_idx < mycore_pkg::NLSU; lsu_idx++) begin
        dmem_addr_i[lsu_idx] = '0;
        dmem_wdata_i[lsu_idx] = '0;
        dmem_wstrb_i[lsu_idx] = '0;
        dmem_size_i[lsu_idx] = 2'd2;
      end
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
      imem_req_valid_i = 1'b1;
      imem_req_addr_i = addr;
      #1;
      while (!imem_req_ready_o) begin
        @(posedge clk_i); #1;
      end
      @(posedge clk_i); #1;
      imem_req_valid_i = 1'b0;
      while (!imem_rsp_valid_o) begin
        @(posedge clk_i); #1;
      end
      assert (imem_rsp_error_o[addr[3:2]] == expect_error);
      imem_line_data = imem_rsp_rdata_o;
      imem_line_error = imem_rsp_error_o;
      data = imem_rsp_rdata_o[addr[3:2]*32 +: 32];
      @(posedge clk_i); #1;
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
      dmem_valid_i[0] = 1'b1;
      dmem_write_i[0] = 1'b1;
      dmem_addr_i[0] = addr;
      dmem_wdata_i[0] = data;
      dmem_wstrb_i[0] = strb;
      #1;
      assert (dmem_ready_o[0] && (dmem_error_o[0] == expect_error));
      @(posedge clk_i); #1;
      dmem_valid_i[0] = 1'b0;
      dmem_write_i[0] = 1'b0;
      #1;
    end
  endtask

  task automatic dmem_read(
    input logic [31:0] addr,
    output logic [31:0] data,
    input logic expect_error
  );
    begin
      dmem_valid_i[0] = 1'b1;
      dmem_write_i[0] = 1'b0;
      dmem_addr_i[0] = addr;
      #1;
      while (!dmem_ready_o[0]) begin
        @(posedge clk_i); #1;
      end
      assert (dmem_ready_o[0] && (dmem_error_o[0] == expect_error));
      data = dmem_rdata_o[0];
      dmem_valid_i[0] = 1'b0;
      #1;
    end
  endtask

  task automatic dual_dmem_read(
    input logic [31:0] addr0,
    input logic [31:0] addr1,
    input logic [31:0] expected0,
    input logic [31:0] expected1,
    input logic expect_serialized
  );
    logic done0, done1, first_seen;
    logic [1:0] ready_now;
    logic [31:0] data0, data1;
    begin
      dmem_valid_i = '1;
      dmem_write_i = '0;
      dmem_addr_i[0] = addr0;
      dmem_addr_i[1] = addr1;
      done0 = 1'b0;
      done1 = 1'b0;
      first_seen = 1'b0;
      while (!done0 || !done1) begin
        @(posedge clk_i); #1;
        ready_now = dmem_ready_o & dmem_valid_i;
        if (!first_seen && (|ready_now)) begin
          if (expect_serialized)
            assert ($onehot(ready_now));
          else
            assert (ready_now == 2'b11);
          first_seen = 1'b1;
        end
        if (!done0 && dmem_ready_o[0]) begin
          data0 = dmem_rdata_o[0];
          done0 = 1'b1;
          dmem_valid_i[0] = 1'b0;
        end
        if (!done1 && dmem_ready_o[1]) begin
          data1 = dmem_rdata_o[1];
          done1 = 1'b1;
          dmem_valid_i[1] = 1'b0;
        end
      end
      assert (data0 == expected0 && data1 == expected1);
      #1;
    end
  endtask

  logic [31:0] data;
  logic [127:0] imem_line_data;
  logic [3:0] imem_line_error;
  logic [127:0] held_imem_data;
  logic [3:0] held_imem_error;
  integer stream_rsp_count;

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

    // Immediate ROM and unmapped results use the same ordered response slots.
    @(negedge clk_i);
    imem_rsp_ready_i = 1'b0;
    imem_req_valid_i = 1'b1;
    imem_req_addr_i = BOOTROM_BASE;
    #1;
    assert (imem_req_ready_o);
    @(posedge clk_i); #1;
    imem_req_addr_i = 32'h4000_0000;
    assert (imem_req_ready_o && imem_rsp_valid_o);
    @(posedge clk_i); #1;
    imem_req_valid_i = 1'b0;
    assert (imem_rsp_valid_o && imem_rsp_error_o == 4'h0 &&
            imem_rsp_rdata_o[31:0] == 32'h8000_02b7);
    imem_rsp_ready_i = 1'b1;
    @(posedge clk_i); #1;
    assert (imem_rsp_valid_o && imem_rsp_error_o == 4'hf &&
            imem_rsp_rdata_o == 128'd0);
    @(posedge clk_i); #1;

    // Host ELF writes are immediately visible to instruction and data ports.
    host_write(ITIM_BASE, 32'h1122_3344, 4'b1111, 0);
    imem_read(ITIM_BASE, data, 0); assert (data == 32'h1122_3344);
    host_write(ITIM_BASE + 4, 32'h5566_7788, 4'hf, 0);
    host_write(ITIM_BASE + 8, 32'h99aa_bbcc, 4'hf, 0);
    host_write(ITIM_BASE + 12, 32'hddee_ff00, 4'hf, 0);
    imem_read(ITIM_BASE + 8, data, 0);
    assert (data == 32'h99aa_bbcc);
    assert (imem_line_data == 128'hddee_ff00_99aa_bbcc_5566_7788_1122_3344);

    // Two ITIM line requests are accepted on consecutive cycles. The oldest
    // response remains stable while blocked and the second response stays ordered.
    host_write(ITIM_BASE + 16, 32'h0101_0101, 4'hf, 0);
    host_write(ITIM_BASE + 20, 32'h0202_0202, 4'hf, 0);
    host_write(ITIM_BASE + 24, 32'h0303_0303, 4'hf, 0);
    host_write(ITIM_BASE + 28, 32'h0404_0404, 4'hf, 0);
    @(negedge clk_i);
    imem_rsp_ready_i = 1'b0;
    imem_req_valid_i = 1'b1;
    imem_req_addr_i = ITIM_BASE;
    #1;
    assert (imem_req_ready_o);
    @(posedge clk_i); #1;
    imem_req_addr_i = ITIM_BASE + 16;
    assert (imem_req_ready_o);
    @(posedge clk_i); #1;
    imem_req_valid_i = 1'b0;
    while (!imem_rsp_valid_o) begin
      @(posedge clk_i); #1;
    end
    held_imem_data = imem_rsp_rdata_o;
    held_imem_error = imem_rsp_error_o;
    repeat (2) begin
      @(posedge clk_i); #1;
      assert (imem_rsp_valid_o && imem_rsp_rdata_o == held_imem_data &&
              imem_rsp_error_o == held_imem_error);
    end
    assert (held_imem_data ==
            128'hddee_ff00_99aa_bbcc_5566_7788_1122_3344);
    imem_rsp_ready_i = 1'b1;
    @(posedge clk_i); #1;
    assert (imem_rsp_valid_o && imem_rsp_rdata_o ==
            128'h0404_0404_0303_0303_0202_0202_0101_0101);
    @(posedge clk_i); #1;

    // After SRAM pipeline fill, a ping-pong slot accepts and retires every cycle.
    @(negedge clk_i);
    imem_req_valid_i = 1'b1;
    imem_req_addr_i = ITIM_BASE;
    stream_rsp_count = 0;
    for (int req_idx = 0; req_idx < 8; req_idx++) begin
      #1;
      assert (imem_req_ready_o);
      if (req_idx >= 2)
        assert (imem_rsp_valid_o);
      if (imem_rsp_valid_o) begin
        if (stream_rsp_count[0])
          assert (imem_rsp_rdata_o ==
                  128'h0404_0404_0303_0303_0202_0202_0101_0101);
        else
          assert (imem_rsp_rdata_o ==
                  128'hddee_ff00_99aa_bbcc_5566_7788_1122_3344);
        stream_rsp_count++;
      end
      @(posedge clk_i); #1;
      imem_req_addr_i = (req_idx[0] ? ITIM_BASE : ITIM_BASE + 16);
    end
    imem_req_valid_i = 1'b0;
    while (stream_rsp_count < 8) begin
      assert (imem_rsp_valid_o);
      if (stream_rsp_count[0])
        assert (imem_rsp_rdata_o ==
                128'h0404_0404_0303_0303_0202_0202_0101_0101);
      else
        assert (imem_rsp_rdata_o ==
                128'hddee_ff00_99aa_bbcc_5566_7788_1122_3344);
      stream_rsp_count++;
      @(posedge clk_i); #1;
    end

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

    // LSU lanes complete different banks together and arbitrate the same bank.
    host_write(DTIM_BASE + 32'h100, 32'h1111_2222, 4'hf, 0);
    host_write(DTIM_BASE + 32'h104, 32'h3333_4444, 4'hf, 0);
    dual_dmem_read(DTIM_BASE + 32'h100, DTIM_BASE + 32'h104,
                   32'h1111_2222, 32'h3333_4444, 1'b0);
    host_write(DTIM_BASE + 32'h110, 32'h5555_6666, 4'hf, 0);
    host_write(DTIM_BASE + 32'h120, 32'h7777_8888, 4'hf, 0);
    dual_dmem_read(DTIM_BASE + 32'h110, DTIM_BASE + 32'h120,
                   32'h5555_6666, 32'h7777_8888, 1'b1);
    dmem_write(DTIM_BASE + 17, 32'hffff_ffff, 4'hf, 1);
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'hdead_beef);
    dmem_size_i[0] = 2'd0;
    dmem_write(DTIM_BASE + 19, 32'haa00_0000, 4'b1000, 0);
    dmem_write(DTIM_BASE + 18, 32'hffff_ffff, 4'b1111, 1);
    dmem_size_i[0] = 2'd2;
    host_read(DTIM_BASE + 16, data, 0); assert (data == 32'haaad_beef);

    // Host raises MSIP after loading; payload code clears it through dmem.
    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf, 0);
    assert (irq_software_o);
    dmem_read(CLINT_MSIP_ADDR, data, 0); assert (data == 1);

    // The scalar CLINT CPU port deterministically grants lane 0 first.
    dmem_valid_i = '1;
    dmem_write_i = '0;
    dmem_addr_i[0] = CLINT_MSIP_ADDR;
    dmem_addr_i[1] = CLINT_MTIME_ADDR;
    #1;
    assert (dmem_ready_o == 2'b01 && dmem_rdata_o[0] == 1);
    dmem_valid_i[0] = 1'b0;
    #1;
    assert (dmem_ready_o == 2'b10);
    dmem_valid_i[1] = 1'b0;
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

    // Per-word PMP errors are captured with each accepted request, not sampled
    // later from the live PMP inputs.
    pmpaddr_i[0] = ITIM_BASE >> 2;
    pmpaddr_i[1] = (ITIM_BASE + 4) >> 2;
    pmpcfg_i[1] = 8'h89;
    @(negedge clk_i);
    imem_rsp_ready_i = 1'b0;
    imem_req_valid_i = 1'b1;
    imem_req_addr_i = ITIM_BASE;
    #1;
    assert (imem_req_ready_o);
    @(posedge clk_i); #1;
    pmpcfg_i[1] = 8'h8d;
    assert (imem_req_ready_o);
    @(posedge clk_i); #1;
    imem_req_valid_i = 1'b0;
    assert (imem_rsp_valid_o && imem_rsp_error_o == 4'b0001);
    @(posedge clk_i); #1;
    assert (imem_rsp_valid_o && imem_rsp_error_o == 4'b0001);
    imem_rsp_ready_i = 1'b1;
    @(posedge clk_i); #1;
    assert (imem_rsp_valid_o && imem_rsp_error_o == 4'b0000);
    @(posedge clk_i); #1;
    pmpcfg_i[1] = '0;
    pmpaddr_i[0] = '0;
    pmpaddr_i[1] = '0;

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
    imem_req_size_i = 2'd1;
    imem_read(ITIM_BASE + 32'hfe, data, 0);
    imem_req_size_i = 2'd2;
    imem_read(ITIM_BASE + 32'hfe, data, 1);

    $display("PASS: tb_soc");
    $finish;
  end
endmodule
