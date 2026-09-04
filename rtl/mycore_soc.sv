`timescale 1ns/1ps

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
  logic imem_pmp_matched, imem_pmp_allow;
  logic dmem_pmp_matched, dmem_pmp_allow;
  logic imem_pre_error, dmem_pre_error, host_pre_error;
  logic dmem_misaligned, dmem_bad_wstrb;
  logic [3:0] dmem_expected_wstrb;

  logic [31:0] boot_imem_rdata, boot_dmem_rdata, boot_host_rdata;
  logic [31:0] clint_cpu_rdata, clint_host_rdata;
  logic clint_cpu_error, clint_host_error;

  logic [TIM_PORTS-1:0] itim_read_valid, itim_read_ready;
  logic [31:0] itim_read_offset [TIM_PORTS], itim_read_data [TIM_PORTS];
  logic [TIM_PORTS-1:0] itim_write_valid, itim_write_ready;
  logic [31:0] itim_write_offset [TIM_PORTS], itim_write_data [TIM_PORTS];
  logic [3:0] itim_write_strb [TIM_PORTS];

  logic [TIM_PORTS-1:0] dtim_read_valid, dtim_read_ready;
  logic [31:0] dtim_read_offset [TIM_PORTS], dtim_read_data [TIM_PORTS];
  logic [TIM_PORTS-1:0] dtim_write_valid, dtim_write_ready;
  logic [31:0] dtim_write_offset [TIM_PORTS], dtim_write_data [TIM_PORTS];
  logic [3:0] dtim_write_strb [TIM_PORTS];

  logic [63:0] tohost_q, fromhost_q;

  function automatic logic [31:0] merge_bytes(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] strb
  );
    logic [31:0] result;
    result = old_value;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
      if (strb[byte_idx])
        result[byte_idx*8 +: 8] = new_value[byte_idx*8 +: 8];
    end
    return result;
  endfunction

  pmp_checker u_imem_pmp (
    .addr_i(imem_addr_i), .size_i(imem_size_i), .access_r_i(1'b0),
    .access_w_i(1'b0), .access_x_i(1'b1), .priv_m_i(pmp_priv_m_i),
    .pmpcfg_i, .pmpaddr_i, .matched_o(imem_pmp_matched), .allow_o(imem_pmp_allow)
  );

  pmp_checker u_dmem_pmp (
    .addr_i(dmem_addr_i), .size_i(dmem_size_i), .access_r_i(!dmem_write_i),
    .access_w_i(dmem_write_i), .access_x_i(1'b0), .priv_m_i(pmp_priv_m_i),
    .pmpcfg_i, .pmpaddr_i, .matched_o(dmem_pmp_matched), .allow_o(dmem_pmp_allow)
  );

  bootrom u_bootrom_imem (.addr_i(imem_addr_i), .rdata_o(boot_imem_rdata));
  bootrom u_bootrom_dmem (.addr_i(dmem_addr_i), .rdata_o(boot_dmem_rdata));
  bootrom u_bootrom_host (.addr_i(host_addr_i), .rdata_o(boot_host_rdata));

  banked_sram_1r1w #(.BYTES(ITIM_BYTES), .BANKS(TIM_BANKS), .PORTS(TIM_PORTS)) u_itim (
    .clk_i, .rst_ni, .read_valid_i(itim_read_valid),
    .read_offset_i(itim_read_offset), .read_ready_o(itim_read_ready),
    .read_data_o(itim_read_data), .write_valid_i(itim_write_valid),
    .write_offset_i(itim_write_offset), .write_data_i(itim_write_data),
    .write_strb_i(itim_write_strb), .write_ready_o(itim_write_ready)
  );

  banked_sram_1r1w #(.BYTES(DTIM_BYTES), .BANKS(TIM_BANKS), .PORTS(TIM_PORTS)) u_dtim (
    .clk_i, .rst_ni, .read_valid_i(dtim_read_valid),
    .read_offset_i(dtim_read_offset), .read_ready_o(dtim_read_ready),
    .read_data_o(dtim_read_data), .write_valid_i(dtim_write_valid),
    .write_offset_i(dtim_write_offset), .write_data_i(dtim_write_data),
    .write_strb_i(dtim_write_strb), .write_ready_o(dtim_write_ready)
  );

  always_comb begin
    imem_boot = addr_is_bootrom(imem_addr_i);
    imem_itim = addr_is_itim(imem_addr_i);
    dmem_boot = addr_is_bootrom(dmem_addr_i);
    dmem_itim = addr_is_itim(dmem_addr_i);
    dmem_dtim = addr_is_dtim(dmem_addr_i);
    dmem_clint = addr_is_clint(dmem_addr_i);
    host_boot = addr_is_bootrom(host_addr_i);
    host_itim = addr_is_itim(host_addr_i);
    host_dtim = addr_is_dtim(host_addr_i);
    host_clint = addr_is_clint(host_addr_i);

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
    imem_pre_error = (!imem_boot && !imem_itim) || imem_addr_i[0] || !imem_pmp_allow;
    dmem_pre_error = (!dmem_boot && !dmem_itim && !dmem_dtim && !dmem_clint) ||
                     (dmem_boot && dmem_write_i) || dmem_misaligned ||
                     dmem_bad_wstrb || !dmem_pmp_allow;
    host_pre_error = (!host_boot && !host_itim && !host_dtim && !host_clint) ||
                     (host_boot && host_write_i) || (host_addr_i[1:0] != 2'b00);

    itim_read_valid = '0;
    itim_write_valid = '0;
    dtim_read_valid = '0;
    dtim_write_valid = '0;
    for (int port_idx = 0; port_idx < TIM_PORTS; port_idx++) begin
      itim_read_offset[port_idx] = '0;
      itim_write_offset[port_idx] = '0;
      itim_write_data[port_idx] = '0;
      itim_write_strb[port_idx] = '0;
      dtim_read_offset[port_idx] = '0;
      dtim_write_offset[port_idx] = '0;
      dtim_write_data[port_idx] = '0;
      dtim_write_strb[port_idx] = '0;
    end

    itim_read_valid[TIM_PORT_IF] = imem_valid_i && imem_itim && !imem_pre_error;
    itim_read_offset[TIM_PORT_IF] = imem_addr_i - ITIM_BASE;
    itim_read_valid[TIM_PORT_LSU0] = dmem_valid_i && !dmem_write_i &&
                                      dmem_itim && !dmem_pre_error;
    itim_read_offset[TIM_PORT_LSU0] = dmem_addr_i - ITIM_BASE;
    itim_write_valid[TIM_PORT_LSU0] = dmem_valid_i && dmem_write_i &&
                                       dmem_itim && !dmem_pre_error;
    itim_write_offset[TIM_PORT_LSU0] = dmem_addr_i - ITIM_BASE;
    itim_write_data[TIM_PORT_LSU0] = dmem_wdata_i;
    itim_write_strb[TIM_PORT_LSU0] = dmem_wstrb_i;
    itim_read_valid[TIM_PORT_HOST] = host_valid_i && !host_write_i &&
                                     host_itim && !host_pre_error;
    itim_read_offset[TIM_PORT_HOST] = host_addr_i - ITIM_BASE;
    itim_write_valid[TIM_PORT_HOST] = host_valid_i && host_write_i &&
                                      host_itim && !host_pre_error;
    itim_write_offset[TIM_PORT_HOST] = host_addr_i - ITIM_BASE;
    itim_write_data[TIM_PORT_HOST] = host_wdata_i;
    itim_write_strb[TIM_PORT_HOST] = host_wstrb_i;

    dtim_read_valid[TIM_PORT_LSU0] = dmem_valid_i && !dmem_write_i &&
                                     dmem_dtim && !dmem_pre_error;
    dtim_read_offset[TIM_PORT_LSU0] = dmem_addr_i - DTIM_BASE;
    dtim_write_valid[TIM_PORT_LSU0] = dmem_valid_i && dmem_write_i &&
                                      dmem_dtim && !dmem_pre_error;
    dtim_write_offset[TIM_PORT_LSU0] = dmem_addr_i - DTIM_BASE;
    dtim_write_data[TIM_PORT_LSU0] = dmem_wdata_i;
    dtim_write_strb[TIM_PORT_LSU0] = dmem_wstrb_i;
    dtim_read_valid[TIM_PORT_HOST] = host_valid_i && !host_write_i &&
                                     host_dtim && !host_pre_error;
    dtim_read_offset[TIM_PORT_HOST] = host_addr_i - DTIM_BASE;
    dtim_write_valid[TIM_PORT_HOST] = host_valid_i && host_write_i &&
                                      host_dtim && !host_pre_error;
    dtim_write_offset[TIM_PORT_HOST] = host_addr_i - DTIM_BASE;
    dtim_write_data[TIM_PORT_HOST] = host_wdata_i;
    dtim_write_strb[TIM_PORT_HOST] = host_wstrb_i;

    imem_ready_o = 1'b0;
    imem_rdata_o = '0;
    imem_error_o = 1'b0;
    if (imem_valid_i) begin
      if (imem_pre_error) begin
        imem_ready_o = 1'b1;
        imem_error_o = 1'b1;
      end else if (imem_boot) begin
        imem_ready_o = 1'b1;
        imem_rdata_o = boot_imem_rdata;
      end else if (imem_itim) begin
        imem_ready_o = itim_read_ready[TIM_PORT_IF];
        imem_rdata_o = itim_read_data[TIM_PORT_IF];
      end
    end

    dmem_ready_o = 1'b0;
    dmem_rdata_o = '0;
    dmem_error_o = 1'b0;
    if (dmem_valid_i) begin
      if (dmem_pre_error) begin
        dmem_ready_o = 1'b1;
        dmem_error_o = 1'b1;
      end else if (dmem_boot) begin
        dmem_ready_o = 1'b1;
        dmem_rdata_o = boot_dmem_rdata;
      end else if (dmem_clint) begin
        dmem_ready_o = 1'b1;
        dmem_rdata_o = clint_cpu_rdata;
        dmem_error_o = clint_cpu_error;
      end else if (dmem_itim) begin
        dmem_ready_o = dmem_write_i ? itim_write_ready[TIM_PORT_LSU0] :
                                     itim_read_ready[TIM_PORT_LSU0];
        dmem_rdata_o = itim_read_data[TIM_PORT_LSU0];
      end else if (dmem_dtim) begin
        dmem_ready_o = dmem_write_i ? dtim_write_ready[TIM_PORT_LSU0] :
                                     dtim_read_ready[TIM_PORT_LSU0];
        dmem_rdata_o = dtim_read_data[TIM_PORT_LSU0];
      end
    end

    host_ready_o = 1'b0;
    host_rdata_o = '0;
    host_error_o = 1'b0;
    if (host_valid_i) begin
      if (!rst_ni) begin
        host_ready_o = 1'b0;
      end else if (host_pre_error) begin
        host_ready_o = 1'b1;
        host_error_o = 1'b1;
      end else if (host_boot) begin
        host_ready_o = 1'b1;
        host_rdata_o = boot_host_rdata;
      end else if (host_clint) begin
        host_ready_o = 1'b1;
        host_rdata_o = clint_host_rdata;
        host_error_o = clint_host_error;
      end else if (host_itim) begin
        host_ready_o = host_write_i ? itim_write_ready[TIM_PORT_HOST] :
                                     itim_read_ready[TIM_PORT_HOST];
        host_rdata_o = itim_read_data[TIM_PORT_HOST];
      end else if (host_dtim) begin
        host_ready_o = host_write_i ? dtim_write_ready[TIM_PORT_HOST] :
                                     dtim_read_ready[TIM_PORT_HOST];
        host_rdata_o = dtim_read_data[TIM_PORT_HOST];
      end
    end
  end

  clint u_clint (
    .clk_i, .rst_ni,
    .cpu_valid_i(rst_ni && dmem_valid_i && dmem_clint && !dmem_pre_error),
    .cpu_write_i(dmem_write_i), .cpu_addr_i(dmem_addr_i),
    .cpu_wdata_i(dmem_wdata_i), .cpu_wstrb_i(dmem_wstrb_i),
    .cpu_rdata_o(clint_cpu_rdata), .cpu_error_o(clint_cpu_error),
    .host_valid_i(rst_ni && host_valid_i && host_clint && !host_pre_error),
    .host_write_i(host_write_i), .host_addr_i(host_addr_i),
    .host_wdata_i(host_wdata_i), .host_wstrb_i(host_wstrb_i),
    .host_rdata_o(clint_host_rdata), .host_error_o(clint_host_error),
    .irq_software_o, .irq_timer_o, .time_o
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tohost_q <= '0;
      fromhost_q <= '0;
    end else begin
      if (dtim_write_valid[TIM_PORT_LSU0] && dtim_write_ready[TIM_PORT_LSU0] &&
          (dtim_write_offset[TIM_PORT_LSU0] < 32'd16)) begin
        case (dtim_write_offset[TIM_PORT_LSU0][3:2])
          2'd0: tohost_q[31:0] <= merge_bytes(tohost_q[31:0],
                                              dtim_write_data[TIM_PORT_LSU0],
                                              dtim_write_strb[TIM_PORT_LSU0]);
          2'd1: tohost_q[63:32] <= merge_bytes(tohost_q[63:32],
                                               dtim_write_data[TIM_PORT_LSU0],
                                               dtim_write_strb[TIM_PORT_LSU0]);
          2'd2: fromhost_q[31:0] <= merge_bytes(fromhost_q[31:0],
                                                dtim_write_data[TIM_PORT_LSU0],
                                                dtim_write_strb[TIM_PORT_LSU0]);
          2'd3: fromhost_q[63:32] <= merge_bytes(fromhost_q[63:32],
                                                 dtim_write_data[TIM_PORT_LSU0],
                                                 dtim_write_strb[TIM_PORT_LSU0]);
        endcase
      end
      if (dtim_write_valid[TIM_PORT_HOST] && dtim_write_ready[TIM_PORT_HOST] &&
          (dtim_write_offset[TIM_PORT_HOST] < 32'd16)) begin
        case (dtim_write_offset[TIM_PORT_HOST][3:2])
          2'd0: tohost_q[31:0] <= merge_bytes(tohost_q[31:0],
                                              dtim_write_data[TIM_PORT_HOST],
                                              dtim_write_strb[TIM_PORT_HOST]);
          2'd1: tohost_q[63:32] <= merge_bytes(tohost_q[63:32],
                                               dtim_write_data[TIM_PORT_HOST],
                                               dtim_write_strb[TIM_PORT_HOST]);
          2'd2: fromhost_q[31:0] <= merge_bytes(fromhost_q[31:0],
                                                dtim_write_data[TIM_PORT_HOST],
                                                dtim_write_strb[TIM_PORT_HOST]);
          2'd3: fromhost_q[63:32] <= merge_bytes(fromhost_q[63:32],
                                                 dtim_write_data[TIM_PORT_HOST],
                                                 dtim_write_strb[TIM_PORT_HOST]);
        endcase
      end
    end
  end

  assign tohost_o = tohost_q;
  assign fromhost_o = fromhost_q;
endmodule
