`timescale 1ns/1ps

module physical_regfile (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic                         alloc_fire_i,
  input  logic [mycore_pkg::FW-1:0]    alloc_valid_i,
  input  mycore_pkg::ren_uop_t         alloc_uop_i [mycore_pkg::FW],

  input  mycore_pkg::exec_wb_t         wb_i [mycore_pkg::NWB],
  output logic [mycore_pkg::NWB-1:0]   wb_accepted_o,

  input  logic [mycore_pkg::PW-1:0]    raddr_i [mycore_pkg::NREAD],
  output logic [31:0]                  rdata_o [mycore_pkg::NREAD],
  output logic [mycore_pkg::NREAD-1:0] rready_o,

  input  logic [mycore_pkg::PW-1:0]    serial_raddr_i,
  output logic [31:0]                  serial_rdata_o,
  output logic                         serial_rready_o
);
  import mycore_pkg::*;

  logic [31:0] data_q [NPRF], data_n [NPRF];
  logic [NPRF-1:0] ready_q, ready_n;
  logic [NPRF-1:0] owner_valid_q, owner_valid_n;
  logic [NPRF-1:0] wb_written;
  logic [RW:0] owner_rob_q [NPRF], owner_rob_n [NPRF];
  logic [EW-1:0] owner_epoch_q [NPRF], owner_epoch_n [NPRF];

  always_comb begin
    wb_accepted_o = '0;
    wb_written = '0;
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
      if (wb_i[wb_idx].rob.valid && wb_i[wb_idx].write_pdst &&
          !wb_i[wb_idx].rob.excp && (wb_i[wb_idx].pdst != '0) &&
          !wb_written[wb_i[wb_idx].pdst] && owner_valid_q[wb_i[wb_idx].pdst] &&
          (owner_rob_q[wb_i[wb_idx].pdst] == wb_i[wb_idx].rob.rob_idx) &&
          (owner_epoch_q[wb_i[wb_idx].pdst] == wb_i[wb_idx].rob.epoch)) begin
        wb_accepted_o[wb_idx] = 1'b1;
        wb_written[wb_i[wb_idx].pdst] = 1'b1;
      end
    end
  end

  always_comb begin
    serial_rdata_o = data_q[serial_raddr_i];
    serial_rready_o = ready_q[serial_raddr_i];
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
      if (wb_accepted_o[wb_idx] && (wb_i[wb_idx].pdst == serial_raddr_i)) begin
        serial_rdata_o = wb_i[wb_idx].data;
        serial_rready_o = 1'b1;
      end
    end
  end

  always_comb begin
    for (int preg_idx = 0; preg_idx < NPRF; preg_idx++) begin
      data_n[preg_idx] = data_q[preg_idx];
      owner_rob_n[preg_idx] = owner_rob_q[preg_idx];
      owner_epoch_n[preg_idx] = owner_epoch_q[preg_idx];
    end
    ready_n = ready_q;
    owner_valid_n = owner_valid_q;

    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
      if (wb_accepted_o[wb_idx]) begin
        data_n[wb_i[wb_idx].pdst] = wb_i[wb_idx].data;
        ready_n[wb_i[wb_idx].pdst] = 1'b1;
      end
    end

    // A newly allocated owner wins over a late write to the same physical ID.
    if (alloc_fire_i) begin
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
        if (alloc_valid_i[lane_idx] && alloc_uop_i[lane_idx].d.rd_valid &&
            (alloc_uop_i[lane_idx].d.rd != 6'd0)) begin
          ready_n[alloc_uop_i[lane_idx].pdst] = 1'b0;
          owner_valid_n[alloc_uop_i[lane_idx].pdst] = 1'b1;
          owner_rob_n[alloc_uop_i[lane_idx].pdst] = alloc_uop_i[lane_idx].rob_idx;
          owner_epoch_n[alloc_uop_i[lane_idx].pdst] = alloc_uop_i[lane_idx].epoch;
        end
      end
    end

    data_n[0] = '0;
    ready_n[0] = 1'b1;
    owner_valid_n[0] = 1'b0;

  end

  always_comb begin
    for (int read_idx = 0; read_idx < NREAD; read_idx++) begin
      rdata_o[read_idx] = data_q[raddr_i[read_idx]];
      rready_o[read_idx] = ready_q[raddr_i[read_idx]];
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
        if (wb_accepted_o[wb_idx] && (wb_i[wb_idx].pdst == raddr_i[read_idx])) begin
          rdata_o[read_idx] = wb_i[wb_idx].data;
          rready_o[read_idx] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ready_q <= {{(NPRF-64){1'b0}}, {64{1'b1}}};
      owner_valid_q <= '0;
      for (int preg_idx = 0; preg_idx < NPRF; preg_idx++) begin
        data_q[preg_idx] <= '0;
        owner_rob_q[preg_idx] <= '0;
        owner_epoch_q[preg_idx] <= '0;
      end
    end else begin
      ready_q <= ready_n;
      owner_valid_q <= owner_valid_n;
      for (int preg_idx = 0; preg_idx < NPRF; preg_idx++) begin
        data_q[preg_idx] <= data_n[preg_idx];
        owner_rob_q[preg_idx] <= owner_rob_n[preg_idx];
        owner_epoch_q[preg_idx] <= owner_epoch_n[preg_idx];
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni && alloc_fire_i) begin
      for (int lane_a = 0; lane_a < FW; lane_a++) begin
        if (alloc_valid_i[lane_a] && alloc_uop_i[lane_a].d.rd_valid)
          assert (alloc_uop_i[lane_a].pdst != '0);
        for (int lane_b = lane_a + 1; lane_b < FW; lane_b++) begin
          if (alloc_valid_i[lane_a] && alloc_valid_i[lane_b] &&
              alloc_uop_i[lane_a].d.rd_valid && alloc_uop_i[lane_b].d.rd_valid)
            assert (alloc_uop_i[lane_a].pdst != alloc_uop_i[lane_b].pdst);
        end
        for (int wb_idx = 0; wb_idx < NWB; wb_idx++) begin
          if (alloc_valid_i[lane_a] && alloc_uop_i[lane_a].d.rd_valid &&
              wb_accepted_o[wb_idx])
            assert (alloc_uop_i[lane_a].pdst != wb_i[wb_idx].pdst)
              else $error("PRF allocation collided with accepted writeback");
        end
      end
    end
  end
`endif
endmodule
