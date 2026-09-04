`timescale 1ns/1ps

module tb_elf_load;
  import soc_pkg::*;
  import csr_pkg::NPMP;

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
  logic pmp_priv_m_i;
  logic [7:0] pmpcfg_i [NPMP];
  logic [31:0] pmpaddr_i [NPMP];
  logic irq_software_o, irq_timer_o;
  logic [63:0] time_o, tohost_o, fromhost_o;

  mycore_soc dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  function automatic logic [31:0] strobe_mask(input logic [3:0] strb);
    logic [31:0] mask;
    mask = '0;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (strb[byte_idx])
        mask[byte_idx*8 +: 8] = 8'hff;
    end
    return mask;
  endfunction

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

  task automatic host_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      host_valid_i = 1'b1;
      host_write_i = 1'b0;
      host_addr_i = addr;
      #1;
      while (!host_ready_o) begin
        @(posedge clk_i); #1;
      end
      assert (host_ready_o && !host_error_o);
      data = host_rdata_o;
      host_valid_i = 1'b0;
    end
  endtask

  string host_file, opcode;
  integer fd, scan_result, write_count;
  logic [31:0] file_addr, file_data, read_data, entry;
  logic [3:0] file_strb;

  initial begin
    imem_valid_i = 1'b0;
    imem_addr_i = '0;
    imem_size_i = 2'd2;
    dmem_valid_i = 1'b0;
    dmem_write_i = 1'b0;
    dmem_addr_i = '0;
    dmem_size_i = 2'd2;
    dmem_wdata_i = '0;
    dmem_wstrb_i = '0;
    host_valid_i = 1'b0;
    host_write_i = 1'b0;
    host_addr_i = '0;
    host_wdata_i = '0;
    host_wstrb_i = '0;
    pmp_priv_m_i = 1'b1;
    for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
      pmpcfg_i[pmp_idx] = '0;
      pmpaddr_i[pmp_idx] = '0;
    end

    if (!$value$plusargs("HOST_FILE=%s", host_file))
      $fatal(1, "missing +HOST_FILE=<path>");

    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;

    fd = $fopen(host_file, "r");
    if (fd == 0)
      $fatal(1, "cannot open %s", host_file);
    write_count = 0;
    entry = '0;
    while (!$feof(fd)) begin
      scan_result = $fscanf(fd, "%s %h %h %h\n", opcode, file_addr, file_data, file_strb);
      if (scan_result == 4) begin
        if (opcode == "E")
          entry = file_addr;
        else if (opcode == "W") begin
          host_write(file_addr, file_data, file_strb);
          write_count++;
        end else
          $fatal(1, "unknown host operation %s", opcode);
      end
    end
    $fclose(fd);

    assert (entry == PAYLOAD_ENTRY);
    assert (write_count > 0 && tohost_o == 0 && fromhost_o == 0);

    // Re-read every loaded word through the same host aperture.
    fd = $fopen(host_file, "r");
    while (!$feof(fd)) begin
      scan_result = $fscanf(fd, "%s %h %h %h\n", opcode, file_addr, file_data, file_strb);
      if ((scan_result == 4) && (opcode == "W")) begin
        host_read(file_addr, read_data);
        assert ((read_data & strobe_mask(file_strb)) ==
                (file_data & strobe_mask(file_strb)))
          else $fatal(1, "ELF readback mismatch at %08x", file_addr);
      end
    end
    $fclose(fd);

    host_write(CLINT_MSIP_ADDR, 32'd1, 4'hf);
    assert (irq_software_o);
    $display("PASS: tb_elf_load (%0d writes)", write_count);
    $finish;
  end
endmodule
