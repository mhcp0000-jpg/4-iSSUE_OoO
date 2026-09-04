`timescale 1ns/1ps

// Memory subsystem and host loader shell. The CPU core connects through the
// instruction and data ports; the host uses the same address map to load ELF.
module mycore_soc (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        imem_valid_i,
  input  logic [31:0] imem_addr_i,
  input  logic [1:0]  imem_size_i,
  output logic        imem_ready_o,
  output logic [31:0] imem_rdata_o,
  output logic        imem_error_o,

  input  logic        dmem_valid_i,
  input  logic        dmem_write_i,
  input  logic [31:0] dmem_addr_i,
  input  logic [1:0]  dmem_size_i,
  input  logic [31:0] dmem_wdata_i,
  input  logic [3:0]  dmem_wstrb_i,
  output logic        dmem_ready_o,
  output logic [31:0] dmem_rdata_o,
  output logic        dmem_error_o,

  input  logic        host_valid_i,
  input  logic        host_write_i,
  input  logic [31:0] host_addr_i,
  input  logic [31:0] host_wdata_i,
  input  logic [3:0]  host_wstrb_i,
  output logic        host_ready_o,
  output logic [31:0] host_rdata_o,
  output logic        host_error_o,

  input  logic        pmp_priv_m_i,
  input  logic [7:0]  pmpcfg_i [csr_pkg::NPMP],
  input  logic [31:0] pmpaddr_i [csr_pkg::NPMP],

  output logic        irq_software_o,
  output logic        irq_timer_o,
  output logic [63:0] time_o,
  output logic [63:0] tohost_o,
  output logic [63:0] fromhost_o
);
  import soc_pkg::*;

  logic imem_boot, imem_itim;
  logic dmem_boot, dmem_itim, dmem_dtim, dmem_clint;
  logic host_boot, host_itim, host_dtim, host_clint;
  logic [31:0] boot_imem_rdata, boot_dmem_rdata, boot_host_rdata;
  logic [31:0] itim_if_rdata, itim_cpu_rdata, itim_host_rdata;
  logic [31:0] dtim_cpu_rdata, dtim_host_rdata;
  logic [31:0] clint_cpu_rdata, clint_host_rdata;
  logic clint_cpu_error, clint_host_error;
  logic [63:0] unused_itim_probe0, unused_itim_probe1;
  logic [31:0] zero_if_rdata;
  logic imem_pmp_matched, imem_pmp_allow;
  logic dmem_pmp_matched, dmem_pmp_allow;
  logic dmem_misaligned;
  logic [3:0] dmem_expected_wstrb;
  logic dmem_bad_wstrb;

  always_comb begin
    imem_boot = imem_valid_i && addr_is_bootrom(imem_addr_i);
    imem_itim = imem_valid_i && addr_is_itim(imem_addr_i);
    dmem_boot = dmem_valid_i && addr_is_bootrom(dmem_addr_i);
    dmem_itim = dmem_valid_i && addr_is_itim(dmem_addr_i);
    dmem_dtim = dmem_valid_i && addr_is_dtim(dmem_addr_i);
    dmem_clint = dmem_valid_i && addr_is_clint(dmem_addr_i);
    host_boot = host_valid_i && addr_is_bootrom(host_addr_i);
    host_itim = host_valid_i && addr_is_itim(host_addr_i);
    host_dtim = host_valid_i && addr_is_dtim(host_addr_i);
    host_clint = host_valid_i && addr_is_clint(host_addr_i);

    case (dmem_size_i)
      2'd0: begin
        dmem_misaligned = 1'b0;
        dmem_expected_wstrb = 4'b0001 << dmem_addr_i[1:0];
      end
      2'd1: begin
        dmem_misaligned = dmem_addr_i[0];
        dmem_expected_wstrb = 4'b0011 << {dmem_addr_i[1], 1'b0};
      end
      2'd2: begin
        dmem_misaligned = |dmem_addr_i[1:0];
        dmem_expected_wstrb = 4'b1111;
      end
      default: begin
        dmem_misaligned = 1'b1;
        dmem_expected_wstrb = '0;
      end
    endcase
    dmem_bad_wstrb = dmem_write_i && (dmem_wstrb_i != dmem_expected_wstrb);

    imem_ready_o = imem_valid_i;
    imem_rdata_o = (imem_pmp_allow && imem_boot) ? boot_imem_rdata :
                   (imem_pmp_allow && imem_itim) ? itim_if_rdata : '0;
    imem_error_o = imem_valid_i &&
                   ((!imem_boot && !imem_itim) || imem_addr_i[0] ||
                    !imem_pmp_allow);

    dmem_ready_o = dmem_valid_i;
    dmem_rdata_o = (dmem_pmp_allow && dmem_boot) ? boot_dmem_rdata :
                   (dmem_pmp_allow && dmem_itim) ? itim_cpu_rdata :
                   (dmem_pmp_allow && dmem_dtim) ? dtim_cpu_rdata :
                   (dmem_pmp_allow && dmem_clint) ? clint_cpu_rdata : '0;
    dmem_error_o = dmem_valid_i &&
                   ((!dmem_boot && !dmem_itim && !dmem_dtim && !dmem_clint) ||
                     (dmem_boot && dmem_write_i) || dmem_misaligned || dmem_bad_wstrb ||
                     !dmem_pmp_allow || clint_cpu_error);

    host_ready_o = host_valid_i;
    host_rdata_o = host_boot ? boot_host_rdata :
                   host_itim ? itim_host_rdata :
                   host_dtim ? dtim_host_rdata :
                   host_clint ? clint_host_rdata : '0;
    host_error_o = host_valid_i &&
                   ((!host_boot && !host_itim && !host_dtim && !host_clint) ||
                    (host_boot && host_write_i) || host_addr_i[1:0] != 2'b00 ||
                    clint_host_error);
  end

  bootrom u_bootrom_imem (.addr_i(imem_addr_i), .rdata_o(boot_imem_rdata));
  bootrom u_bootrom_dmem (.addr_i(dmem_addr_i), .rdata_o(boot_dmem_rdata));
  bootrom u_bootrom_host (.addr_i(host_addr_i), .rdata_o(boot_host_rdata));

  pmp_checker u_imem_pmp (
    .addr_i       (imem_addr_i),
    .size_i       (imem_size_i),
    .access_r_i   (1'b0),
    .access_w_i   (1'b0),
    .access_x_i   (1'b1),
    .priv_m_i     (pmp_priv_m_i),
    .pmpcfg_i,
    .pmpaddr_i,
    .matched_o    (imem_pmp_matched),
    .allow_o      (imem_pmp_allow)
  );

  pmp_checker u_dmem_pmp (
    .addr_i       (dmem_addr_i),
    .size_i       (dmem_size_i),
    .access_r_i   (!dmem_write_i),
    .access_w_i   (dmem_write_i),
    .access_x_i   (1'b0),
    .priv_m_i     (pmp_priv_m_i),
    .pmpcfg_i,
    .pmpaddr_i,
    .matched_o    (dmem_pmp_matched),
    .allow_o      (dmem_pmp_allow)
  );

  tim_ram #(.BYTES(ITIM_BYTES)) u_itim (
    .clk_i,
    .if_valid_i   (imem_itim && imem_pmp_allow),
    .if_offset_i  (imem_addr_i - ITIM_BASE),
    .if_rdata_o   (itim_if_rdata),
    .cpu_valid_i  (dmem_itim && dmem_pmp_allow && !dmem_misaligned && !dmem_bad_wstrb),
    .cpu_write_i  (dmem_write_i),
    .cpu_offset_i (dmem_addr_i - ITIM_BASE),
    .cpu_wdata_i  (dmem_wdata_i),
    .cpu_wstrb_i  (dmem_wstrb_i),
    .cpu_rdata_o  (itim_cpu_rdata),
    .host_valid_i (host_itim && (host_addr_i[1:0] == 2'b00)),
    .host_write_i (host_write_i),
    .host_offset_i(host_addr_i - ITIM_BASE),
    .host_wdata_i (host_wdata_i),
    .host_wstrb_i (host_wstrb_i),
    .host_rdata_o (itim_host_rdata),
    .probe0_o     (unused_itim_probe0),
    .probe1_o     (unused_itim_probe1)
  );

  tim_ram #(.BYTES(DTIM_BYTES), .ENABLE_PROBES(1'b1)) u_dtim (
    .clk_i,
    .if_valid_i   (1'b0),
    .if_offset_i  ('0),
    .if_rdata_o   (zero_if_rdata),
    .cpu_valid_i  (dmem_dtim && dmem_pmp_allow && !dmem_misaligned && !dmem_bad_wstrb),
    .cpu_write_i  (dmem_write_i),
    .cpu_offset_i (dmem_addr_i - DTIM_BASE),
    .cpu_wdata_i  (dmem_wdata_i),
    .cpu_wstrb_i  (dmem_wstrb_i),
    .cpu_rdata_o  (dtim_cpu_rdata),
    .host_valid_i (host_dtim && (host_addr_i[1:0] == 2'b00)),
    .host_write_i (host_write_i),
    .host_offset_i(host_addr_i - DTIM_BASE),
    .host_wdata_i (host_wdata_i),
    .host_wstrb_i (host_wstrb_i),
    .host_rdata_o (dtim_host_rdata),
    .probe0_o     (tohost_o),
    .probe1_o     (fromhost_o)
  );

  clint u_clint (
    .clk_i,
    .rst_ni,
    .cpu_valid_i  (dmem_clint && dmem_pmp_allow && !dmem_misaligned && !dmem_bad_wstrb),
    .cpu_write_i  (dmem_write_i),
    .cpu_addr_i   (dmem_addr_i),
    .cpu_wdata_i  (dmem_wdata_i),
    .cpu_wstrb_i  (dmem_wstrb_i),
    .cpu_rdata_o  (clint_cpu_rdata),
    .cpu_error_o  (clint_cpu_error),
    .host_valid_i (host_clint && (host_addr_i[1:0] == 2'b00)),
    .host_write_i (host_write_i),
    .host_addr_i  (host_addr_i),
    .host_wdata_i (host_wdata_i),
    .host_wstrb_i (host_wstrb_i),
    .host_rdata_o (clint_host_rdata),
    .host_error_o (clint_host_error),
    .irq_software_o,
    .irq_timer_o,
    .time_o
  );
endmodule
