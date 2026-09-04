`timescale 1ns/1ps

module mycore_system (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        irq_external_i,

  input  logic        host_valid_i,
  input  logic        host_write_i,
  input  logic [31:0] host_addr_i,
  input  logic [31:0] host_wdata_i,
  input  logic [3:0]  host_wstrb_i,
  output logic        host_ready_o,
  output logic [31:0] host_rdata_o,
  output logic        host_error_o,

  output logic [63:0] tohost_o,
  output logic [63:0] fromhost_o,
  output logic [31:0] debug_pc_o,
  output logic [mycore_pkg::RW:0] debug_rob_occupancy_o
);
  import csr_pkg::*;

  logic imem_valid, imem_ready;
  logic [3:0] imem_error;
  logic [31:0] imem_addr;
  logic [127:0] imem_rdata;
  logic [1:0] imem_size;
  logic dmem_valid, dmem_write, dmem_ready, dmem_error;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [1:0] dmem_size;
  logic [3:0] dmem_wstrb;
  logic irq_software, irq_timer;
  logic [63:0] time_value;
  logic [7:0] pmpcfg [NPMP];
  logic [31:0] pmpaddr [NPMP];

  mycore_core u_core (
    .clk_i, .rst_ni, .imem_valid_o(imem_valid), .imem_addr_o(imem_addr),
    .imem_size_o(imem_size), .imem_ready_i(imem_ready), .imem_rdata_i(imem_rdata),
    .imem_error_i(imem_error), .dmem_valid_o(dmem_valid),
    .dmem_write_o(dmem_write), .dmem_addr_o(dmem_addr), .dmem_size_o(dmem_size),
    .dmem_wdata_o(dmem_wdata), .dmem_wstrb_o(dmem_wstrb),
    .dmem_ready_i(dmem_ready), .dmem_rdata_i(dmem_rdata), .dmem_error_i(dmem_error),
    .irq_software_i(irq_software), .irq_timer_i(irq_timer), .irq_external_i,
    .time_i(time_value), .pmpcfg_o(pmpcfg), .pmpaddr_o(pmpaddr),
    .debug_pc_o, .debug_rob_occupancy_o
  );

  mycore_soc u_soc (
    .clk_i, .rst_ni, .imem_valid_i(imem_valid), .imem_addr_i(imem_addr),
    .imem_size_i(imem_size), .imem_ready_o(imem_ready), .imem_rdata_o(imem_rdata),
    .imem_error_o(imem_error), .dmem_valid_i(dmem_valid), .dmem_write_i(dmem_write),
    .dmem_addr_i(dmem_addr), .dmem_size_i(dmem_size), .dmem_wdata_i(dmem_wdata),
    .dmem_wstrb_i(dmem_wstrb), .dmem_ready_o(dmem_ready), .dmem_rdata_o(dmem_rdata),
    .dmem_error_o(dmem_error), .host_valid_i, .host_write_i, .host_addr_i,
    .host_wdata_i, .host_wstrb_i, .host_ready_o, .host_rdata_o, .host_error_o,
    .pmp_priv_m_i(1'b1), .pmpcfg_i(pmpcfg), .pmpaddr_i(pmpaddr),
    .irq_software_o(irq_software), .irq_timer_o(irq_timer), .time_o(time_value),
    .tohost_o, .fromhost_o
  );
endmodule
