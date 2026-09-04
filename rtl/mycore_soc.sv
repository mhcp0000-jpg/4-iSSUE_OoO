`timescale 1ns/1ps

module mycore_soc (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic         imem_req_valid_i,
  input  logic [31:0]  imem_req_addr_i,
  input  logic [1:0]   imem_req_size_i,
  output logic         imem_req_ready_o,
  output logic         imem_rsp_valid_o,
  input  logic         imem_rsp_ready_i,
  output logic [127:0] imem_rsp_rdata_o,
  output logic [3:0]   imem_rsp_error_o,

  input  logic [mycore_pkg::NLSU-1:0] dmem_valid_i,
  input  logic [mycore_pkg::NLSU-1:0] dmem_write_i,
  input  logic [31:0] dmem_addr_i [mycore_pkg::NLSU],
  input  logic [1:0]  dmem_size_i [mycore_pkg::NLSU],
  input  logic [31:0] dmem_wdata_i [mycore_pkg::NLSU],
  input  logic [3:0]  dmem_wstrb_i [mycore_pkg::NLSU],
  output logic [mycore_pkg::NLSU-1:0] dmem_ready_o,
  output logic [31:0] dmem_rdata_o [mycore_pkg::NLSU],
  output logic [mycore_pkg::NLSU-1:0] dmem_error_o,

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
  import mycore_pkg::*;
  import soc_pkg::*;

  localparam int IF_SLOTS = 2;
  localparam logic [1:0] IF_COUNT_MAX = 2'd2;

  logic imem_boot, imem_itim;
  logic [NLSU-1:0] dmem_boot, dmem_itim, dmem_dtim, dmem_clint;
  logic host_boot, host_itim, host_dtim, host_clint;
  logic [TIM_BANKS-1:0] imem_pmp_matched, imem_pmp_allow;
  logic imem_access_pmp_matched, imem_access_pmp_allow;
  logic [NLSU-1:0] dmem_pmp_matched, dmem_pmp_allow;
  logic imem_pre_error, host_pre_error;
  logic [NLSU-1:0] dmem_pre_error, dmem_misaligned, dmem_bad_wstrb;
  logic [3:0] dmem_expected_wstrb [NLSU];

  logic [31:0] boot_imem_rdata [TIM_BANKS];
  logic [31:0] boot_dmem_rdata [NLSU], boot_host_rdata;
  logic [31:0] clint_cpu_rdata, clint_host_rdata;
  logic clint_cpu_error, clint_host_error, clint_cpu_valid;
  logic clint_cpu_write;
  logic [31:0] clint_cpu_addr, clint_cpu_wdata;
  logic [3:0] clint_cpu_wstrb;
  logic [NLSU-1:0] clint_grant;
  logic clint_selected;

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

  logic [IF_SLOTS-1:0] if_valid_q, if_complete_q, if_route_itim_q;
  logic [3:0] if_pending_q [IF_SLOTS];
  logic [31:0] if_addr_q [IF_SLOTS];
  logic [127:0] if_data_q [IF_SLOTS];
  logic [3:0] if_error_q [IF_SLOTS];
  logic [IF_SLOTS-1:0] if_ready_complete;
  logic [127:0] if_response_data [IF_SLOTS];
  logic if_head_q, if_tail_q;
  logic [1:0] if_count_q;
  logic imem_req_fire, imem_rsp_fire;

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

  for (genvar fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++) begin : g_imem_pmp
    pmp_checker u_imem_pmp (
      .addr_i({imem_req_addr_i[31:4], 4'b0000} + 32'(fetch_word * 4)),
      .size_i(2'd2), .access_r_i(1'b0), .access_w_i(1'b0),
      .access_x_i(1'b1), .priv_m_i(pmp_priv_m_i), .pmpcfg_i, .pmpaddr_i,
      .matched_o(imem_pmp_matched[fetch_word]), .allow_o(imem_pmp_allow[fetch_word])
    );
  end

  pmp_checker u_imem_access_pmp (
    .addr_i(imem_req_addr_i), .size_i(imem_req_size_i), .access_r_i(1'b0),
    .access_w_i(1'b0), .access_x_i(1'b1), .priv_m_i(pmp_priv_m_i),
    .pmpcfg_i, .pmpaddr_i, .matched_o(imem_access_pmp_matched),
    .allow_o(imem_access_pmp_allow)
  );

  for (genvar lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin : g_dmem_pmp
    pmp_checker u_dmem_pmp (
      .addr_i(dmem_addr_i[lsu_idx]), .size_i(dmem_size_i[lsu_idx]),
      .access_r_i(!dmem_write_i[lsu_idx]), .access_w_i(dmem_write_i[lsu_idx]),
      .access_x_i(1'b0), .priv_m_i(pmp_priv_m_i), .pmpcfg_i, .pmpaddr_i,
      .matched_o(dmem_pmp_matched[lsu_idx]), .allow_o(dmem_pmp_allow[lsu_idx])
    );
  end

  for (genvar fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++) begin : g_bootrom_imem
    bootrom u_bootrom_imem (
      .addr_i({imem_req_addr_i[31:4], 4'b0000} + 32'(fetch_word * 4)),
      .rdata_o(boot_imem_rdata[fetch_word])
    );
  end
  for (genvar lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin : g_bootrom_dmem
    bootrom u_bootrom_dmem (
      .addr_i(dmem_addr_i[lsu_idx]), .rdata_o(boot_dmem_rdata[lsu_idx])
    );
  end
  bootrom u_bootrom_host (.addr_i(host_addr_i), .rdata_o(boot_host_rdata));

  banked_sram_1r1w #(
    .BYTES(ITIM_BYTES), .BANKS(TIM_BANKS), .PORTS(TIM_PORTS),
    .PRIORITY_READ_PORTS(2 * TIM_BANKS)
  ) u_itim (
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
    imem_boot = addr_is_bootrom(imem_req_addr_i);
    imem_itim = addr_is_itim(imem_req_addr_i);
    host_boot = addr_is_bootrom(host_addr_i);
    host_itim = addr_is_itim(host_addr_i);
    host_dtim = addr_is_dtim(host_addr_i);
    host_clint = addr_is_clint(host_addr_i);
    imem_pre_error = (!imem_boot && !imem_itim) || imem_req_addr_i[0];
    host_pre_error = (!host_boot && !host_itim && !host_dtim && !host_clint) ||
                     (host_boot && host_write_i) || (host_addr_i[1:0] != 2'b00);

    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      dmem_boot[lsu_idx] = addr_is_bootrom(dmem_addr_i[lsu_idx]);
      dmem_itim[lsu_idx] = addr_is_itim(dmem_addr_i[lsu_idx]);
      dmem_dtim[lsu_idx] = addr_is_dtim(dmem_addr_i[lsu_idx]);
      dmem_clint[lsu_idx] = addr_is_clint(dmem_addr_i[lsu_idx]);
      case (dmem_size_i[lsu_idx])
        2'd0: begin
          dmem_misaligned[lsu_idx] = 1'b0;
          dmem_expected_wstrb[lsu_idx] = 4'b0001 << dmem_addr_i[lsu_idx][1:0];
        end
        2'd1: begin
          dmem_misaligned[lsu_idx] = dmem_addr_i[lsu_idx][0];
          dmem_expected_wstrb[lsu_idx] = 4'b0011 <<
                                                   {dmem_addr_i[lsu_idx][1], 1'b0};
        end
        2'd2: begin
          dmem_misaligned[lsu_idx] = |dmem_addr_i[lsu_idx][1:0];
          dmem_expected_wstrb[lsu_idx] = 4'b1111;
        end
        default: begin
          dmem_misaligned[lsu_idx] = 1'b1;
          dmem_expected_wstrb[lsu_idx] = '0;
        end
      endcase
      dmem_bad_wstrb[lsu_idx] = dmem_write_i[lsu_idx] &&
                                 (dmem_wstrb_i[lsu_idx] !=
                                  dmem_expected_wstrb[lsu_idx]);
      dmem_pre_error[lsu_idx] =
        (!dmem_boot[lsu_idx] && !dmem_itim[lsu_idx] &&
         !dmem_dtim[lsu_idx] && !dmem_clint[lsu_idx]) ||
        (dmem_boot[lsu_idx] && dmem_write_i[lsu_idx]) ||
        dmem_misaligned[lsu_idx] || dmem_bad_wstrb[lsu_idx] ||
        !dmem_pmp_allow[lsu_idx];
    end

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
    for (int fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++) begin
      itim_read_valid[TIM_PORT_IF_A0 + fetch_word] = if_valid_q[0] &&
        if_route_itim_q[0] && !if_complete_q[0] && if_pending_q[0][fetch_word];
      itim_read_offset[TIM_PORT_IF_A0 + fetch_word] =
        {if_addr_q[0][31:4], 4'b0000} - ITIM_BASE + 32'(fetch_word * 4);
      itim_read_valid[TIM_PORT_IF_B0 + fetch_word] = if_valid_q[1] &&
        if_route_itim_q[1] && !if_complete_q[1] && if_pending_q[1][fetch_word];
      itim_read_offset[TIM_PORT_IF_B0 + fetch_word] =
        {if_addr_q[1][31:4], 4'b0000} - ITIM_BASE + 32'(fetch_word * 4);
    end
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      itim_read_valid[TIM_PORT_LSU0 + lsu_idx] = dmem_valid_i[lsu_idx] &&
        !dmem_write_i[lsu_idx] && dmem_itim[lsu_idx] && !dmem_pre_error[lsu_idx];
      itim_read_offset[TIM_PORT_LSU0 + lsu_idx] = dmem_addr_i[lsu_idx] - ITIM_BASE;
      itim_write_valid[TIM_PORT_LSU0 + lsu_idx] = dmem_valid_i[lsu_idx] &&
        dmem_write_i[lsu_idx] && dmem_itim[lsu_idx] && !dmem_pre_error[lsu_idx];
      itim_write_offset[TIM_PORT_LSU0 + lsu_idx] = dmem_addr_i[lsu_idx] - ITIM_BASE;
      itim_write_data[TIM_PORT_LSU0 + lsu_idx] = dmem_wdata_i[lsu_idx];
      itim_write_strb[TIM_PORT_LSU0 + lsu_idx] = dmem_wstrb_i[lsu_idx];

      dtim_read_valid[TIM_PORT_LSU0 + lsu_idx] = dmem_valid_i[lsu_idx] &&
        !dmem_write_i[lsu_idx] && dmem_dtim[lsu_idx] && !dmem_pre_error[lsu_idx];
      dtim_read_offset[TIM_PORT_LSU0 + lsu_idx] = dmem_addr_i[lsu_idx] - DTIM_BASE;
      dtim_write_valid[TIM_PORT_LSU0 + lsu_idx] = dmem_valid_i[lsu_idx] &&
        dmem_write_i[lsu_idx] && dmem_dtim[lsu_idx] && !dmem_pre_error[lsu_idx];
      dtim_write_offset[TIM_PORT_LSU0 + lsu_idx] = dmem_addr_i[lsu_idx] - DTIM_BASE;
      dtim_write_data[TIM_PORT_LSU0 + lsu_idx] = dmem_wdata_i[lsu_idx];
      dtim_write_strb[TIM_PORT_LSU0 + lsu_idx] = dmem_wstrb_i[lsu_idx];
    end
    itim_read_valid[TIM_PORT_HOST] = host_valid_i && !host_write_i &&
                                     host_itim && !host_pre_error;
    itim_read_offset[TIM_PORT_HOST] = host_addr_i - ITIM_BASE;
    itim_write_valid[TIM_PORT_HOST] = host_valid_i && host_write_i &&
                                      host_itim && !host_pre_error;
    itim_write_offset[TIM_PORT_HOST] = host_addr_i - ITIM_BASE;
    itim_write_data[TIM_PORT_HOST] = host_wdata_i;
    itim_write_strb[TIM_PORT_HOST] = host_wstrb_i;
    dtim_read_valid[TIM_PORT_HOST] = host_valid_i && !host_write_i &&
                                     host_dtim && !host_pre_error;
    dtim_read_offset[TIM_PORT_HOST] = host_addr_i - DTIM_BASE;
    dtim_write_valid[TIM_PORT_HOST] = host_valid_i && host_write_i &&
                                      host_dtim && !host_pre_error;
    dtim_write_offset[TIM_PORT_HOST] = host_addr_i - DTIM_BASE;
    dtim_write_data[TIM_PORT_HOST] = host_wdata_i;
    dtim_write_strb[TIM_PORT_HOST] = host_wstrb_i;
  end

  always_comb begin
    if_ready_complete = '0;
    for (int slot_idx = 0; slot_idx < IF_SLOTS; slot_idx++) begin
      if_response_data[slot_idx] = if_data_q[slot_idx];
      if (if_valid_q[slot_idx] && if_route_itim_q[slot_idx] &&
          !if_complete_q[slot_idx]) begin
        if_ready_complete[slot_idx] =
          ((if_pending_q[slot_idx] &
            ~itim_read_ready[slot_idx*TIM_BANKS +: TIM_BANKS]) == 0);
        for (int fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++) begin
          if (itim_read_ready[(slot_idx * TIM_BANKS) + fetch_word])
            if_response_data[slot_idx][fetch_word*32 +: 32] =
              itim_read_data[(slot_idx * TIM_BANKS) + fetch_word];
        end
      end
    end
  end

  assign imem_rsp_valid_o = (if_count_q != 0) && if_valid_q[if_head_q] &&
                            (if_complete_q[if_head_q] ||
                             if_ready_complete[if_head_q]);
  assign imem_rsp_rdata_o = if_response_data[if_head_q];
  assign imem_rsp_error_o = if_error_q[if_head_q];
  assign imem_rsp_fire = imem_rsp_valid_o && imem_rsp_ready_i;
  assign imem_req_ready_o = rst_ni &&
                            ((if_count_q != IF_COUNT_MAX) || imem_rsp_fire);
  assign imem_req_fire = imem_req_valid_i && imem_req_ready_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      if_valid_q <= '0;
      if_complete_q <= '0;
      if_route_itim_q <= '0;
      if_head_q <= 1'b0;
      if_tail_q <= 1'b0;
      if_count_q <= '0;
      for (int slot_idx = 0; slot_idx < IF_SLOTS; slot_idx++) begin
        if_pending_q[slot_idx] <= '0;
        if_addr_q[slot_idx] <= '0;
        if_data_q[slot_idx] <= '0;
        if_error_q[slot_idx] <= '0;
      end
    end else begin
      for (int slot_idx = 0; slot_idx < IF_SLOTS; slot_idx++) begin
        if (if_valid_q[slot_idx] && if_route_itim_q[slot_idx] &&
            !if_complete_q[slot_idx]) begin
          for (int fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++) begin
            if (itim_read_ready[(slot_idx * TIM_BANKS) + fetch_word]) begin
              if_pending_q[slot_idx][fetch_word] <= 1'b0;
              if_data_q[slot_idx][fetch_word*32 +: 32] <=
                itim_read_data[(slot_idx * TIM_BANKS) + fetch_word];
            end
          end
          if ((if_pending_q[slot_idx] &
               ~itim_read_ready[slot_idx*TIM_BANKS +: TIM_BANKS]) == 0)
            if_complete_q[slot_idx] <= 1'b1;
        end
      end

      if (imem_rsp_fire) begin
        if_valid_q[if_head_q] <= 1'b0;
        if_complete_q[if_head_q] <= 1'b0;
        if_head_q <= ~if_head_q;
      end

      if (imem_req_fire) begin
        if_valid_q[if_tail_q] <= 1'b1;
        if_complete_q[if_tail_q] <= imem_pre_error || imem_boot;
        if_route_itim_q[if_tail_q] <= imem_itim && !imem_pre_error;
        if_pending_q[if_tail_q] <= (imem_itim && !imem_pre_error) ? 4'hf : 4'h0;
        if_addr_q[if_tail_q] <= imem_req_addr_i;
        if_data_q[if_tail_q] <= '0;
        if_error_q[if_tail_q] <= imem_pre_error ? 4'hf :
          ((~imem_pmp_allow) |
           ((4'b0001 << imem_req_addr_i[3:2]) &
            {4{!imem_access_pmp_allow}}));
        if (imem_boot) begin
          for (int fetch_word = 0; fetch_word < TIM_BANKS; fetch_word++)
            if_data_q[if_tail_q][fetch_word*32 +: 32] <=
              boot_imem_rdata[fetch_word];
        end
        if_tail_q <= ~if_tail_q;
      end

      case ({imem_req_fire, imem_rsp_fire})
        2'b10: if_count_q <= if_count_q + 1'b1;
        2'b01: if_count_q <= if_count_q - 1'b1;
        default: if_count_q <= if_count_q;
      endcase
    end
  end

  always_comb begin
    clint_grant = '0;
    clint_selected = 1'b0;
    clint_cpu_valid = 1'b0;
    clint_cpu_write = 1'b0;
    clint_cpu_addr = '0;
    clint_cpu_wdata = '0;
    clint_cpu_wstrb = '0;
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      if (!clint_selected && rst_ni && dmem_valid_i[lsu_idx] &&
          dmem_clint[lsu_idx] && !dmem_pre_error[lsu_idx]) begin
        clint_selected = 1'b1;
        clint_grant[lsu_idx] = 1'b1;
        clint_cpu_valid = 1'b1;
        clint_cpu_write = dmem_write_i[lsu_idx];
        clint_cpu_addr = dmem_addr_i[lsu_idx];
        clint_cpu_wdata = dmem_wdata_i[lsu_idx];
        clint_cpu_wstrb = dmem_wstrb_i[lsu_idx];
      end
    end
  end

  always_comb begin
    dmem_ready_o = '0;
    dmem_error_o = '0;
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      dmem_rdata_o[lsu_idx] = '0;
      if (dmem_valid_i[lsu_idx]) begin
        if (dmem_pre_error[lsu_idx]) begin
          dmem_ready_o[lsu_idx] = 1'b1;
          dmem_error_o[lsu_idx] = 1'b1;
        end else if (dmem_boot[lsu_idx]) begin
          dmem_ready_o[lsu_idx] = 1'b1;
          dmem_rdata_o[lsu_idx] = boot_dmem_rdata[lsu_idx];
        end else if (dmem_clint[lsu_idx] && clint_grant[lsu_idx]) begin
          dmem_ready_o[lsu_idx] = 1'b1;
          dmem_rdata_o[lsu_idx] = clint_cpu_rdata;
          dmem_error_o[lsu_idx] = clint_cpu_error;
        end else if (dmem_itim[lsu_idx]) begin
          dmem_ready_o[lsu_idx] = dmem_write_i[lsu_idx] ?
            itim_write_ready[TIM_PORT_LSU0 + lsu_idx] :
            itim_read_ready[TIM_PORT_LSU0 + lsu_idx];
          dmem_rdata_o[lsu_idx] = itim_read_data[TIM_PORT_LSU0 + lsu_idx];
        end else if (dmem_dtim[lsu_idx]) begin
          dmem_ready_o[lsu_idx] = dmem_write_i[lsu_idx] ?
            dtim_write_ready[TIM_PORT_LSU0 + lsu_idx] :
            dtim_read_ready[TIM_PORT_LSU0 + lsu_idx];
          dmem_rdata_o[lsu_idx] = dtim_read_data[TIM_PORT_LSU0 + lsu_idx];
        end
      end
    end
  end

  always_comb begin
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
    .clk_i, .rst_ni, .cpu_valid_i(clint_cpu_valid), .cpu_write_i(clint_cpu_write),
    .cpu_addr_i(clint_cpu_addr), .cpu_wdata_i(clint_cpu_wdata),
    .cpu_wstrb_i(clint_cpu_wstrb), .cpu_rdata_o(clint_cpu_rdata),
    .cpu_error_o(clint_cpu_error),
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
      for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
        if (dtim_write_valid[TIM_PORT_LSU0 + lsu_idx] &&
            dtim_write_ready[TIM_PORT_LSU0 + lsu_idx] &&
            (dtim_write_offset[TIM_PORT_LSU0 + lsu_idx] < 32'd16)) begin
          case (dtim_write_offset[TIM_PORT_LSU0 + lsu_idx][3:2])
            2'd0: tohost_q[31:0] <= merge_bytes(tohost_q[31:0],
              dtim_write_data[TIM_PORT_LSU0 + lsu_idx],
              dtim_write_strb[TIM_PORT_LSU0 + lsu_idx]);
            2'd1: tohost_q[63:32] <= merge_bytes(tohost_q[63:32],
              dtim_write_data[TIM_PORT_LSU0 + lsu_idx],
              dtim_write_strb[TIM_PORT_LSU0 + lsu_idx]);
            2'd2: fromhost_q[31:0] <= merge_bytes(fromhost_q[31:0],
              dtim_write_data[TIM_PORT_LSU0 + lsu_idx],
              dtim_write_strb[TIM_PORT_LSU0 + lsu_idx]);
            2'd3: fromhost_q[63:32] <= merge_bytes(fromhost_q[63:32],
              dtim_write_data[TIM_PORT_LSU0 + lsu_idx],
              dtim_write_strb[TIM_PORT_LSU0 + lsu_idx]);
          endcase
        end
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

`ifndef SYNTHESIS
  logic imem_rsp_stalled_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      imem_rsp_stalled_q <= 1'b0;
    end else begin
      if (imem_rsp_stalled_q) begin
        assert (imem_rsp_valid_o);
        assert ($stable(imem_rsp_rdata_o));
        assert ($stable(imem_rsp_error_o));
      end
      assert (if_count_q <= IF_COUNT_MAX);
      assert ($countones(if_valid_q) == if_count_q);
      imem_rsp_stalled_q <= imem_rsp_valid_o && !imem_rsp_ready_i;
    end
  end
`endif
endmodule
