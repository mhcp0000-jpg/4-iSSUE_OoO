`timescale 1ns/1ps

package soc_pkg;
  localparam int TIM_BANKS = 4;
  localparam int TIM_PORTS = 4;
  localparam int TIM_PORT_IF = 0;
  localparam int TIM_PORT_LSU0 = 1;
  localparam int TIM_PORT_LSU1 = 2;
  localparam int TIM_PORT_HOST = 3;

  localparam logic [31:0] BOOTROM_BASE = 32'h0000_1000;
  localparam int unsigned BOOTROM_BYTES = 4 * 1024;

  localparam logic [31:0] CLINT_BASE = 32'h0200_0000;
  localparam int unsigned CLINT_BYTES = 64 * 1024;
  localparam logic [31:0] CLINT_MSIP_ADDR = CLINT_BASE;
  localparam logic [31:0] CLINT_MTIMECMP_ADDR = CLINT_BASE + 32'h0000_4000;
  localparam logic [31:0] CLINT_MTIME_ADDR = CLINT_BASE + 32'h0000_bff8;

  localparam logic [31:0] ITIM_BASE = 32'h8000_0000;
  localparam int unsigned ITIM_BYTES = 128 * 1024;

  localparam logic [31:0] DTIM_BASE = 32'h8002_0000;
  localparam int unsigned DTIM_BYTES = 128 * 1024;

  localparam logic [31:0] TOHOST_ADDR = DTIM_BASE;
  localparam logic [31:0] FROMHOST_ADDR = DTIM_BASE + 32'd8;
  localparam logic [31:0] PAYLOAD_ENTRY = ITIM_BASE;

  function automatic logic addr_in_range(
    input logic [31:0] addr,
    input logic [31:0] base,
    input int unsigned size_bytes
  );
    return (addr >= base) && (addr < (base + size_bytes));
  endfunction

  function automatic logic addr_is_bootrom(input logic [31:0] addr);
    return addr_in_range(addr, BOOTROM_BASE, BOOTROM_BYTES);
  endfunction

  function automatic logic addr_is_clint(input logic [31:0] addr);
    return addr_in_range(addr, CLINT_BASE, CLINT_BYTES);
  endfunction

  function automatic logic addr_is_itim(input logic [31:0] addr);
    return addr_in_range(addr, ITIM_BASE, ITIM_BYTES);
  endfunction

  function automatic logic addr_is_dtim(input logic [31:0] addr);
    return addr_in_range(addr, DTIM_BASE, DTIM_BYTES);
  endfunction
endpackage
