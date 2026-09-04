`timescale 1ns/1ps

// Reset code installs the ITIM trap vector, enables MSIP, and sleeps in WFI.
module bootrom (
  input  logic [31:0] addr_i,
  output logic [31:0] rdata_o
);
  import soc_pkg::*;

  always_comb begin
    rdata_o = 32'h0000_0013;
    case ((addr_i - BOOTROM_BASE) >> 2)
      0: rdata_o = 32'h8000_02b7; // lui   t0, 0x80000
      1: rdata_o = 32'h3052_9073; // csrw  mtvec, t0
      2: rdata_o = 32'h0080_0293; // li    t0, 8
      3: rdata_o = 32'h3042_a073; // csrs  mie, t0 (MSIE)
      4: rdata_o = 32'h3002_a073; // csrs  mstatus, t0 (MIE)
      5: rdata_o = 32'h1050_0073; // wfi
      6: rdata_o = 32'hffdff06f;  // j     -4
      default: rdata_o = 32'h0000_0013;
    endcase
  end
endmodule
