`timescale 1ns/1ps

// Initial tightly integrated memory model: instruction read, CPU data, host.
module tim_ram #(
  parameter int unsigned BYTES = 128 * 1024,
  parameter bit ENABLE_PROBES = 1'b0
) (
  input  logic        clk_i,

  input  logic        if_valid_i,
  input  logic [31:0] if_offset_i,
  output logic [31:0] if_rdata_o,

  input  logic        cpu_valid_i,
  input  logic        cpu_write_i,
  input  logic [31:0] cpu_offset_i,
  input  logic [31:0] cpu_wdata_i,
  input  logic [3:0]  cpu_wstrb_i,
  output logic [31:0] cpu_rdata_o,

  input  logic        host_valid_i,
  input  logic        host_write_i,
  input  logic [31:0] host_offset_i,
  input  logic [31:0] host_wdata_i,
  input  logic [3:0]  host_wstrb_i,
  output logic [31:0] host_rdata_o,

  output logic [63:0] probe0_o,
  output logic [63:0] probe1_o
);
  localparam int unsigned WORDS = BYTES / 4;
  localparam int unsigned AW = $clog2(WORDS);

  logic [31:0] mem [WORDS];
  logic [AW-1:0] if_word, cpu_word, host_word;

  always_comb begin
    if_word = if_offset_i[AW+1:2];
    cpu_word = cpu_offset_i[AW+1:2];
    host_word = host_offset_i[AW+1:2];
    if_rdata_o = if_valid_i ? mem[if_word] : '0;
    cpu_rdata_o = cpu_valid_i ? mem[cpu_word] : '0;
    host_rdata_o = host_valid_i ? mem[host_word] : '0;
    if (ENABLE_PROBES) begin
      probe0_o = {mem[1], mem[0]};
      probe1_o = {mem[3], mem[2]};
    end else begin
      probe0_o = '0;
      probe1_o = '0;
    end
  end

  // Host writes win byte-by-byte if both ports target the same word.
  always_ff @(posedge clk_i) begin
    if (cpu_valid_i && cpu_write_i) begin
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (cpu_wstrb_i[byte_idx])
          mem[cpu_word][byte_idx*8 +: 8] <= cpu_wdata_i[byte_idx*8 +: 8];
      end
    end
    if (host_valid_i && host_write_i) begin
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (host_wstrb_i[byte_idx])
          mem[host_word][byte_idx*8 +: 8] <= host_wdata_i[byte_idx*8 +: 8];
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    for (int word_idx = 0; word_idx < WORDS; word_idx++)
      mem[word_idx] = '0;
  end
`endif
endmodule
