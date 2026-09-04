`timescale 1ns/1ps

module banked_sram_1r1w #(
  parameter int BYTES = 128 * 1024,
  parameter int BANKS = 4,
  parameter int PORTS = 4
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [PORTS-1:0]      read_valid_i,
  input  logic [31:0]           read_offset_i [PORTS],
  output logic [PORTS-1:0]      read_ready_o,
  output logic [31:0]           read_data_o [PORTS],

  input  logic [PORTS-1:0]      write_valid_i,
  input  logic [31:0]           write_offset_i [PORTS],
  input  logic [31:0]           write_data_i [PORTS],
  input  logic [3:0]            write_strb_i [PORTS],
  output logic [PORTS-1:0]      write_ready_o
);
  localparam int WORDS = BYTES / 4;
  localparam int ROWS = WORDS / BANKS;
  localparam int BW = $clog2(BANKS);
  localparam int RAW = $clog2(ROWS);
  localparam int POW = $clog2(PORTS);

  logic [PORTS-1:0] read_busy_q, read_busy_n;
  logic [BANKS-1:0] bank_read_en, bank_read_valid;
  logic [RAW-1:0] bank_read_addr [BANKS];
  logic [31:0] bank_read_data [BANKS];
  logic [BANKS-1:0] bank_write_en;
  logic [RAW-1:0] bank_write_addr [BANKS];
  logic [31:0] bank_write_data [BANKS];
  logic [3:0] bank_write_strb [BANKS];
  logic [POW-1:0] read_owner_q [BANKS], read_owner_n [BANKS];
  logic [31:0] read_tag_q [BANKS], read_tag_n [BANKS];
  logic [POW-1:0] read_rr_q [BANKS], read_rr_n [BANKS];
  logic [POW-1:0] write_rr_q [BANKS], write_rr_n [BANKS];
  logic [BANKS-1:0] read_owner_valid_q, read_owner_valid_n;
  integer selected_port, candidate_port;
  logic candidate_has_write;

  always_comb begin
    read_ready_o = '0;
    write_ready_o = '0;
    read_busy_n = read_busy_q;
    read_owner_valid_n = '0;
    selected_port = -1;
    candidate_port = 0;
    candidate_has_write = 1'b0;
    for (int port_idx = 0; port_idx < PORTS; port_idx++)
      read_data_o[port_idx] = '0;
    for (int bank_idx = 0; bank_idx < BANKS; bank_idx++) begin
      bank_read_en[bank_idx] = 1'b0;
      bank_read_addr[bank_idx] = '0;
      bank_write_en[bank_idx] = 1'b0;
      bank_write_addr[bank_idx] = '0;
      bank_write_data[bank_idx] = '0;
      bank_write_strb[bank_idx] = '0;
      read_owner_n[bank_idx] = read_owner_q[bank_idx];
      read_tag_n[bank_idx] = read_tag_q[bank_idx];
      read_rr_n[bank_idx] = read_rr_q[bank_idx];
      write_rr_n[bank_idx] = write_rr_q[bank_idx];
    end

    // Retire every bank response before considering new requests.
    for (int bank_idx = 0; bank_idx < BANKS; bank_idx++) begin
      if (bank_read_valid[bank_idx] && read_owner_valid_q[bank_idx]) begin
        read_busy_n[read_owner_q[bank_idx]] = 1'b0;
        if (read_valid_i[read_owner_q[bank_idx]] &&
            (read_offset_i[read_owner_q[bank_idx]] == read_tag_q[bank_idx])) begin
          read_ready_o[read_owner_q[bank_idx]] = 1'b1;
          read_data_o[read_owner_q[bank_idx]] = bank_read_data[bank_idx];
        end
      end
    end

    // Each bank independently accepts one read and one write.
    for (int bank_idx = 0; bank_idx < BANKS; bank_idx++) begin
      selected_port = -1;
      for (int priority_idx = 0; priority_idx < PORTS; priority_idx++) begin
        candidate_port = (int'(read_rr_q[bank_idx]) + priority_idx) % PORTS;
        candidate_has_write = 1'b0;
        for (int write_port = 0; write_port < PORTS; write_port++) begin
          if (rst_ni && write_valid_i[write_port] &&
              (write_offset_i[write_port][BW+1:2] == BW'(bank_idx)) &&
              (write_offset_i[write_port][RAW+BW+1:BW+2] ==
               read_offset_i[candidate_port][RAW+BW+1:BW+2]))
            candidate_has_write = 1'b1;
        end
        if ((selected_port < 0) && rst_ni && read_valid_i[candidate_port] &&
            !read_busy_n[candidate_port] && !read_ready_o[candidate_port] &&
            !candidate_has_write &&
            (read_offset_i[candidate_port][BW+1:2] == BW'(bank_idx)))
          selected_port = candidate_port;
      end
      if (selected_port >= 0) begin
        bank_read_en[bank_idx] = 1'b1;
        bank_read_addr[bank_idx] = read_offset_i[selected_port][RAW+BW+1:BW+2];
        read_owner_n[bank_idx] = POW'(selected_port);
        read_tag_n[bank_idx] = read_offset_i[selected_port];
        read_busy_n[selected_port] = 1'b1;
        read_rr_n[bank_idx] = POW'((selected_port + 1) % PORTS);
      end
      read_owner_valid_n[bank_idx] = bank_read_en[bank_idx];

      selected_port = -1;
      for (int priority_idx = 0; priority_idx < PORTS; priority_idx++) begin
        candidate_port = (int'(write_rr_q[bank_idx]) + priority_idx) % PORTS;
        if ((selected_port < 0) && rst_ni && write_valid_i[candidate_port] &&
            (write_offset_i[candidate_port][BW+1:2] == BW'(bank_idx)) &&
            (!bank_read_en[bank_idx] ||
             (write_offset_i[candidate_port][RAW+BW+1:BW+2] !=
              bank_read_addr[bank_idx])))
          selected_port = candidate_port;
      end
      if (selected_port >= 0) begin
        bank_write_en[bank_idx] = 1'b1;
        bank_write_addr[bank_idx] = write_offset_i[selected_port][RAW+BW+1:BW+2];
        bank_write_data[bank_idx] = write_data_i[selected_port];
        bank_write_strb[bank_idx] = write_strb_i[selected_port];
        write_ready_o[selected_port] = 1'b1;
        write_rr_n[bank_idx] = POW'((selected_port + 1) % PORTS);
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_busy_q <= '0;
      read_owner_valid_q <= '0;
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++)
        read_owner_q[bank_idx] <= '0;
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++)
        read_tag_q[bank_idx] <= '0;
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++) begin
        read_rr_q[bank_idx] <= '0;
        write_rr_q[bank_idx] <= '0;
      end
    end else begin
      read_busy_q <= read_busy_n;
      read_owner_valid_q <= read_owner_valid_n;
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++)
        read_owner_q[bank_idx] <= read_owner_n[bank_idx];
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++)
        read_tag_q[bank_idx] <= read_tag_n[bank_idx];
      for (int bank_idx = 0; bank_idx < BANKS; bank_idx++) begin
        read_rr_q[bank_idx] <= read_rr_n[bank_idx];
        write_rr_q[bank_idx] <= write_rr_n[bank_idx];
      end
    end
  end

  for (genvar bank_idx = 0; bank_idx < BANKS; bank_idx++) begin : g_bank
    sram_1r1w #(.DEPTH(ROWS), .AW(RAW)) u_sram (
      .clk_i, .rst_ni,
      .read_en_i(bank_read_en[bank_idx]),
      .read_addr_i(bank_read_addr[bank_idx]),
      .read_valid_o(bank_read_valid[bank_idx]),
      .read_data_o(bank_read_data[bank_idx]),
      .write_en_i(bank_write_en[bank_idx]),
      .write_addr_i(bank_write_addr[bank_idx]),
      .write_data_i(bank_write_data[bank_idx]),
      .write_strb_i(bank_write_strb[bank_idx])
    );
  end

`ifndef SYNTHESIS
  initial begin
    assert ((BANKS & (BANKS - 1)) == 0);
    assert ((WORDS % BANKS) == 0);
  end
`endif
endmodule
