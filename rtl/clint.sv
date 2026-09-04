`timescale 1ns/1ps

module clint (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        cpu_valid_i,
  input  logic        cpu_write_i,
  input  logic [31:0] cpu_addr_i,
  input  logic [31:0] cpu_wdata_i,
  input  logic [3:0]  cpu_wstrb_i,
  output logic [31:0] cpu_rdata_o,
  output logic        cpu_error_o,

  input  logic        host_valid_i,
  input  logic        host_write_i,
  input  logic [31:0] host_addr_i,
  input  logic [31:0] host_wdata_i,
  input  logic [3:0]  host_wstrb_i,
  output logic [31:0] host_rdata_o,
  output logic        host_error_o,

  output logic        irq_software_o
);
  import soc_pkg::*;

  logic msip_q;

  always_comb begin
    cpu_rdata_o = (cpu_valid_i && (cpu_addr_i == CLINT_MSIP_ADDR)) ?
                  {31'b0, msip_q} : '0;
    host_rdata_o = (host_valid_i && (host_addr_i == CLINT_MSIP_ADDR)) ?
                   {31'b0, msip_q} : '0;
    cpu_error_o = cpu_valid_i && (cpu_addr_i != CLINT_MSIP_ADDR);
    host_error_o = host_valid_i && (host_addr_i != CLINT_MSIP_ADDR);
    irq_software_o = msip_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      msip_q <= 1'b0;
    end else begin
      if (cpu_valid_i && cpu_write_i && (cpu_addr_i == CLINT_MSIP_ADDR) && cpu_wstrb_i[0])
        msip_q <= cpu_wdata_i[0];
      if (host_valid_i && host_write_i && (host_addr_i == CLINT_MSIP_ADDR) && host_wstrb_i[0])
        msip_q <= host_wdata_i[0];
    end
  end
endmodule
