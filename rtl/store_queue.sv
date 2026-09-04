`timescale 1ns/1ps

module store_queue (
  input  logic                         clk_i,
  input  logic                         rst_ni,

  input  logic [mycore_pkg::FW-1:0]    dispatch_valid_i,
  input  mycore_pkg::ren_uop_t         dispatch_uop_i [mycore_pkg::FW],
  output logic                         dispatch_ready_o,
  input  logic                         dispatch_fire_i,
  output logic [mycore_pkg::SW:0]      sq_head_o,
  output logic [mycore_pkg::SW:0]      sq_tail_o,

  input  logic                         execute_valid_i,
  input  mycore_pkg::ren_uop_t         execute_uop_i,
  input  logic [31:0]                  execute_addr_i,
  input  logic [31:0]                  execute_data_i,
  input  logic [3:0]                   execute_strb_i,
  output mycore_pkg::exec_wb_t         execute_wb_o,

  output logic                         commit_ready_o,
  output mycore_pkg::ren_uop_t         commit_uop_o,
  output logic [31:0]                  commit_addr_o,
  output logic [31:0]                  commit_data_o,
  output logic [3:0]                   commit_strb_o,
  input  logic                         commit_fire_i,

  input  logic                         load_query_valid_i,
  input  logic [31:0]                  load_query_addr_i,
  input  logic [mycore_pkg::RW:0]      load_query_rob_i,
  input  logic [mycore_pkg::RW:0]      rob_head_i,
  output logic                         load_older_unknown_o,
  output logic [3:0]                   load_forward_mask_o,
  output logic [31:0]                  load_forward_data_o,

  input  logic                         flush_i,
  input  logic                         br_recover_fire_i,
  input  logic [mycore_pkg::SW:0]      br_sq_tail_i,

  output logic [$clog2(mycore_pkg::NSQ+1)-1:0] occupancy_o
);
  import mycore_pkg::*;
  import soc_pkg::*;

  typedef struct packed {
    logic     valid;
    logic     addr_valid;
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0] strb;
    ren_uop_t uop;
  } sq_entry_t;

  sq_entry_t entry_q [NSQ], entry_n [NSQ];
  logic [SW:0] head_q, head_n, tail_q, tail_n, alloc_ptr;
  logic execute_match;
  integer dispatch_count, load_distance, store_distance;
  integer best_store_distance [4];

  always_comb begin
    sq_head_o = head_q;
    sq_tail_o = tail_q;
    occupancy_o = tail_q - head_q;
    dispatch_count = 0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      if (dispatch_valid_i[lane_idx])
        dispatch_count++;
    end
    dispatch_ready_o = !flush_i && !br_recover_fire_i &&
                       ((NSQ - int'(occupancy_o)) >= dispatch_count);
  end

  always_comb begin
    execute_match = execute_valid_i &&
                    entry_q[execute_uop_i.sq_idx[SW-1:0]].valid &&
                    (entry_q[execute_uop_i.sq_idx[SW-1:0]].uop.sq_idx == execute_uop_i.sq_idx) &&
                    (entry_q[execute_uop_i.sq_idx[SW-1:0]].uop.rob_idx == execute_uop_i.rob_idx) &&
                    (entry_q[execute_uop_i.sq_idx[SW-1:0]].uop.epoch == execute_uop_i.epoch);
    execute_wb_o = '0;
    execute_wb_o.rob.valid = execute_match;
    execute_wb_o.rob.rob_idx = execute_uop_i.rob_idx;
    execute_wb_o.rob.epoch = execute_uop_i.epoch;

    commit_ready_o = !flush_i && !br_recover_fire_i &&
                     entry_q[head_q[SW-1:0]].valid &&
                     entry_q[head_q[SW-1:0]].addr_valid &&
                     (entry_q[head_q[SW-1:0]].uop.sq_idx == head_q);
    commit_uop_o = entry_q[head_q[SW-1:0]].uop;
    commit_addr_o = entry_q[head_q[SW-1:0]].addr;
    commit_data_o = entry_q[head_q[SW-1:0]].data;
    commit_strb_o = entry_q[head_q[SW-1:0]].strb;

    load_older_unknown_o = 1'b0;
    load_forward_mask_o = '0;
    load_forward_data_o = '0;
    load_distance = int'(rob_distance(load_query_rob_i, rob_head_i));
    store_distance = 0;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++)
      best_store_distance[byte_idx] = -1;

    if (load_query_valid_i) begin
      for (int entry_idx = 0; entry_idx < NSQ; entry_idx++) begin
        store_distance = int'(rob_distance(entry_q[entry_idx].uop.rob_idx, rob_head_i));
        if (entry_q[entry_idx].valid && (store_distance < load_distance)) begin
          if (!entry_q[entry_idx].addr_valid) begin
            load_older_unknown_o = 1'b1;
          end else if (!addr_is_itim(entry_q[entry_idx].addr) &&
                       !addr_is_dtim(entry_q[entry_idx].addr)) begin
            // Device writes can transform data and are never forwarded.
            load_older_unknown_o = 1'b1;
          end else if ({entry_q[entry_idx].addr[31:2], 2'b00} ==
                       {load_query_addr_i[31:2], 2'b00}) begin
            for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
              if (entry_q[entry_idx].strb[byte_idx] &&
                  (store_distance > best_store_distance[byte_idx])) begin
                best_store_distance[byte_idx] = store_distance;
                load_forward_mask_o[byte_idx] = 1'b1;
                load_forward_data_o[byte_idx*8 +: 8] =
                  entry_q[entry_idx].data[byte_idx*8 +: 8];
              end
            end
          end
        end
      end
    end
  end

  always_comb begin
    for (int entry_idx = 0; entry_idx < NSQ; entry_idx++)
      entry_n[entry_idx] = entry_q[entry_idx];
    head_n = head_q;
    tail_n = tail_q;
    alloc_ptr = tail_q;

    if (execute_match) begin
      entry_n[execute_uop_i.sq_idx[SW-1:0]].addr_valid = 1'b1;
      entry_n[execute_uop_i.sq_idx[SW-1:0]].addr = execute_addr_i;
      entry_n[execute_uop_i.sq_idx[SW-1:0]].data = execute_data_i;
      entry_n[execute_uop_i.sq_idx[SW-1:0]].strb = execute_strb_i;
    end

    if (flush_i) begin
      for (int entry_idx = 0; entry_idx < NSQ; entry_idx++)
        entry_n[entry_idx].valid = 1'b0;
      head_n = tail_q;
      tail_n = tail_q;
    end else if (br_recover_fire_i) begin
      for (int entry_idx = 0; entry_idx < NSQ; entry_idx++) begin
        if (entry_q[entry_idx].valid &&
            (sq_distance(entry_q[entry_idx].uop.sq_idx, head_q) >=
             sq_distance(br_sq_tail_i, head_q)))
          entry_n[entry_idx].valid = 1'b0;
      end
      tail_n = br_sq_tail_i;
    end else begin
      if (commit_fire_i && commit_ready_o) begin
        entry_n[head_q[SW-1:0]].valid = 1'b0;
        head_n = head_q + 1'b1;
      end

      if (dispatch_fire_i) begin
        for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
          if (dispatch_valid_i[lane_idx]) begin
            entry_n[alloc_ptr[SW-1:0]] = '0;
            entry_n[alloc_ptr[SW-1:0]].valid = 1'b1;
            entry_n[alloc_ptr[SW-1:0]].uop = dispatch_uop_i[lane_idx];
            alloc_ptr++;
          end
        end
        tail_n = alloc_ptr;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      head_q <= '0;
      tail_q <= '0;
      for (int entry_idx = 0; entry_idx < NSQ; entry_idx++)
        entry_q[entry_idx] <= '0;
    end else begin
      head_q <= head_n;
      tail_q <= tail_n;
      for (int entry_idx = 0; entry_idx < NSQ; entry_idx++)
        entry_q[entry_idx] <= entry_n[entry_idx];
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni && dispatch_fire_i) begin
      logic [SW:0] expected_idx;
      assert (dispatch_ready_o);
      expected_idx = tail_q;
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
        if (dispatch_valid_i[lane_idx]) begin
          assert (dispatch_uop_i[lane_idx].sq_idx == expected_idx);
          expected_idx++;
        end
      end
    end
    if (rst_ni && commit_fire_i)
      assert (commit_ready_o);
  end
`endif
endmodule
