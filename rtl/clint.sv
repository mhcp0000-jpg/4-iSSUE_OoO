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

  output logic        irq_software_o,
  output logic        irq_timer_o,
  output logic [63:0] time_o
);
  import soc_pkg::*;

  logic msip_q, msip_n;
  logic [63:0] mtime_q, mtime_n, mtimecmp_q, mtimecmp_n;

  function automatic logic addr_valid(input logic [31:0] addr);
    return (addr == CLINT_MSIP_ADDR) ||
           (addr == CLINT_MTIMECMP_ADDR) ||
           (addr == CLINT_MTIMECMP_ADDR + 32'd4) ||
           (addr == CLINT_MTIME_ADDR) ||
           (addr == CLINT_MTIME_ADDR + 32'd4);
  endfunction

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

  always_comb begin
    cpu_rdata_o = '0;
    case (cpu_addr_i)
      CLINT_MSIP_ADDR:         cpu_rdata_o = {31'b0, msip_q};
      CLINT_MTIMECMP_ADDR:     cpu_rdata_o = mtimecmp_q[31:0];
      CLINT_MTIMECMP_ADDR + 4: cpu_rdata_o = mtimecmp_q[63:32];
      CLINT_MTIME_ADDR:        cpu_rdata_o = mtime_q[31:0];
      CLINT_MTIME_ADDR + 4:    cpu_rdata_o = mtime_q[63:32];
      default:                 cpu_rdata_o = '0;
    endcase
    host_rdata_o = '0;
    case (host_addr_i)
      CLINT_MSIP_ADDR:         host_rdata_o = {31'b0, msip_q};
      CLINT_MTIMECMP_ADDR:     host_rdata_o = mtimecmp_q[31:0];
      CLINT_MTIMECMP_ADDR + 4: host_rdata_o = mtimecmp_q[63:32];
      CLINT_MTIME_ADDR:        host_rdata_o = mtime_q[31:0];
      CLINT_MTIME_ADDR + 4:    host_rdata_o = mtime_q[63:32];
      default:                 host_rdata_o = '0;
    endcase
    cpu_error_o = cpu_valid_i && !addr_valid(cpu_addr_i);
    host_error_o = host_valid_i && !addr_valid(host_addr_i);
    irq_software_o = msip_q;
    irq_timer_o = (mtime_q >= mtimecmp_q);
    time_o = mtime_q;
  end

  always_comb begin
    msip_n = msip_q;
    mtime_n = mtime_q + 1'b1;
    mtimecmp_n = mtimecmp_q;

    if (cpu_valid_i && cpu_write_i) begin
      case (cpu_addr_i)
        CLINT_MSIP_ADDR: begin
          if (cpu_wstrb_i[0]) msip_n = cpu_wdata_i[0];
        end
        CLINT_MTIMECMP_ADDR:
          mtimecmp_n[31:0] = merge_bytes(mtimecmp_n[31:0], cpu_wdata_i, cpu_wstrb_i);
        CLINT_MTIMECMP_ADDR + 4:
          mtimecmp_n[63:32] = merge_bytes(mtimecmp_n[63:32], cpu_wdata_i, cpu_wstrb_i);
        CLINT_MTIME_ADDR:
          mtime_n[31:0] = merge_bytes(mtime_n[31:0], cpu_wdata_i, cpu_wstrb_i);
        CLINT_MTIME_ADDR + 4:
          mtime_n[63:32] = merge_bytes(mtime_n[63:32], cpu_wdata_i, cpu_wstrb_i);
        default: begin end
      endcase
    end

    if (host_valid_i && host_write_i) begin
      case (host_addr_i)
        CLINT_MSIP_ADDR: begin
          if (host_wstrb_i[0]) msip_n = host_wdata_i[0];
        end
        CLINT_MTIMECMP_ADDR:
          mtimecmp_n[31:0] = merge_bytes(mtimecmp_n[31:0], host_wdata_i, host_wstrb_i);
        CLINT_MTIMECMP_ADDR + 4:
          mtimecmp_n[63:32] = merge_bytes(mtimecmp_n[63:32], host_wdata_i, host_wstrb_i);
        CLINT_MTIME_ADDR:
          mtime_n[31:0] = merge_bytes(mtime_n[31:0], host_wdata_i, host_wstrb_i);
        CLINT_MTIME_ADDR + 4:
          mtime_n[63:32] = merge_bytes(mtime_n[63:32], host_wdata_i, host_wstrb_i);
        default: begin end
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      msip_q <= 1'b0;
      mtime_q <= '0;
      mtimecmp_q <= '1;
    end else begin
      msip_q <= msip_n;
      mtime_q <= mtime_n;
      mtimecmp_q <= mtimecmp_n;
    end
  end
endmodule
