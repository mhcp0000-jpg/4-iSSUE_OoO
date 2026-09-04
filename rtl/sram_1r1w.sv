`timescale 1ns/1ps

// Flip-flop model with a replaceable synchronous 1R1W SRAM interface.
module sram_1r1w #(
  parameter int DEPTH = 8192,
  parameter int AW = $clog2(DEPTH)
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          read_en_i,
  input  logic [AW-1:0] read_addr_i,
  output logic          read_valid_o,
  output logic [31:0]   read_data_o,
  input  logic          write_en_i,
  input  logic [AW-1:0] write_addr_i,
  input  logic [31:0]   write_data_i,
  input  logic [3:0]    write_strb_i
);
  logic [31:0] mem [DEPTH];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_valid_o <= 1'b0;
      read_data_o <= '0;
    end else begin
      read_valid_o <= read_en_i;
      if (read_en_i)
        read_data_o <= mem[read_addr_i]; // read-first on same-address R/W
      if (write_en_i) begin
        for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
          if (write_strb_i[byte_idx])
            mem[write_addr_i][byte_idx*8 +: 8] <= write_data_i[byte_idx*8 +: 8];
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    for (int word_idx = 0; word_idx < DEPTH; word_idx++)
      mem[word_idx] = '0;
  end
`endif
endmodule
