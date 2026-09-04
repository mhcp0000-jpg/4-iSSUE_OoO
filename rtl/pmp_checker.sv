`timescale 1ns/1ps

module pmp_checker (
  input  logic [31:0] addr_i,
  input  logic [1:0]  size_i,
  input  logic        access_r_i,
  input  logic        access_w_i,
  input  logic        access_x_i,
  input  logic        priv_m_i,
  input  logic [7:0]  pmpcfg_i [csr_pkg::NPMP],
  input  logic [31:0] pmpaddr_i [csr_pkg::NPMP],
  output logic        matched_o,
  output logic        allow_o
);
  import csr_pkg::*;

  logic search;
  logic [63:0] access_lo, access_hi;
  logic [63:0] region_lo, region_hi, napot_mask;
  logic region_active, region_overlap, region_full;
  integer trailing_ones;

  function automatic integer count_trailing_ones(input logic [31:0] value);
    integer count;
    logic stop;
    count = 0;
    stop = 1'b0;
    for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
      if (!stop && value[bit_idx])
        count++;
      else
        stop = 1'b1;
    end
    return count;
  endfunction

  always_comb begin
    access_lo = {32'd0, addr_i};
    access_hi = access_lo + (64'd1 << size_i) - 1'b1;
    matched_o = 1'b0;
    allow_o = priv_m_i;
    search = 1'b1;
    region_lo = '0;
    region_hi = '0;
    napot_mask = '0;
    region_active = 1'b0;
    region_overlap = 1'b0;
    region_full = 1'b0;
    trailing_ones = 0;

    for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
      region_active = (pmpcfg_i[pmp_idx][4:3] != 2'b00);
      region_lo = '0;
      region_hi = '0;
      case (pmpcfg_i[pmp_idx][4:3])
        2'b01: begin // TOR
          region_lo = (pmp_idx == 0) ? 64'd0 : ({32'd0, pmpaddr_i[pmp_idx-1]} << 2);
          region_hi = {32'd0, pmpaddr_i[pmp_idx]} << 2;
        end
        2'b10: begin // NA4
          region_lo = {32'd0, pmpaddr_i[pmp_idx]} << 2;
          region_hi = region_lo + 64'd4;
        end
        2'b11: begin // NAPOT
          trailing_ones = count_trailing_ones(pmpaddr_i[pmp_idx]);
          napot_mask = (64'd1 << (trailing_ones + 1)) - 1'b1;
          region_lo = ({32'd0, pmpaddr_i[pmp_idx]} & ~napot_mask) << 2;
          region_hi = region_lo + (64'd1 << (trailing_ones + 3));
        end
        default: begin end
      endcase

      region_overlap = region_active && (region_lo < region_hi) &&
                       (access_lo < region_hi) && (access_hi >= region_lo);
      region_full = (access_lo >= region_lo) && (access_hi < region_hi);
      if (search && region_overlap) begin
        search = 1'b0;
        matched_o = 1'b1;
        if (!region_full) begin
          allow_o = 1'b0;
        end else if (priv_m_i && !pmpcfg_i[pmp_idx][7]) begin
          allow_o = 1'b1;
        end else begin
          allow_o = (!access_r_i || pmpcfg_i[pmp_idx][0]) &&
                    (!access_w_i || pmpcfg_i[pmp_idx][1]) &&
                    (!access_x_i || pmpcfg_i[pmp_idx][2]);
        end
      end
    end
  end
endmodule
