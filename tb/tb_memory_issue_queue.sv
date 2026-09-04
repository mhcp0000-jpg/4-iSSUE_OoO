`timescale 1ns/1ps

module tb_memory_issue_queue;
  import mycore_pkg::*;

  localparam int DEPTH = 8;
  logic clk_i, rst_ni;
  logic [FW-1:0] dispatch_valid_i;
  ren_uop_t dispatch_uop_i [FW];
  logic [FW-1:0] dispatch_src1_ready_i, dispatch_src2_ready_i;
  logic [FW-1:0] dispatch_src3_ready_i;
  logic dispatch_ready_o, dispatch_fire_i;
  exec_wb_t wb_i [NWB];
  logic [NWB-1:0] wb_accepted_i;
  logic [NLSU-1:0] issue_valid_o, issue_accept_i;
  ren_uop_t issue_uop_o [NLSU];
  logic flush_i, br_recover_fire_i;
  logic [RW:0] br_rob_idx_i, rob_head_i;
  logic [$clog2(DEPTH+1)-1:0] occupancy_o;

  issue_queue #(.DEPTH(DEPTH), .ISSUE_WIDTH(NLSU), .STRICT_ORDER(1'b1)) dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    dispatch_valid_i = '0;
    dispatch_src1_ready_i = '0;
    dispatch_src2_ready_i = '1;
    dispatch_src3_ready_i = '1;
    dispatch_fire_i = 1'b0;
    wb_accepted_i = '0;
    issue_accept_i = '0;
    flush_i = 1'b0;
    br_recover_fire_i = 1'b0;
    br_rob_idx_i = '0;
    rob_head_i = '0;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++)
      dispatch_uop_i[lane_idx] = '0;
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
      wb_i[wb_idx] = '0;

    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);

    // The oldest unready operation blocks both younger candidates.
    for (int lane_idx = 0; lane_idx < 3; lane_idx++) begin
      dispatch_valid_i[lane_idx] = 1'b1;
      dispatch_uop_i[lane_idx].d.valid = 1'b1;
      dispatch_uop_i[lane_idx].d.use1 = 1'b1;
      dispatch_uop_i[lane_idx].ps1 = PW'(64 + lane_idx);
      dispatch_uop_i[lane_idx].rob_idx = (RW+1)'(20 + lane_idx);
      dispatch_src1_ready_i[lane_idx] = (lane_idx != 0);
    end
    dispatch_fire_i = 1'b1;
    @(posedge clk_i); #1;
    dispatch_fire_i = 1'b0;
    dispatch_valid_i = '0;
    assert (issue_valid_o == 0);
    assert (issue_uop_o[0].rob_idx == 20 && issue_uop_o[1].rob_idx == 21);

    wb_i[0].rob.valid = 1'b1;
    wb_i[0].write_pdst = 1'b1;
    wb_i[0].pdst = 64;
    wb_accepted_i[0] = 1'b1;
    #1;
    assert (issue_valid_o == 2'b11);
    assert (issue_uop_o[0].rob_idx == 20 && issue_uop_o[1].rob_idx == 21);
    issue_accept_i = 2'b11;
    @(posedge clk_i); #1;
    wb_i[0] = '0;
    wb_accepted_i = '0;
    issue_accept_i = '0;
    assert (occupancy_o == 1 && issue_valid_o[0] &&
            issue_uop_o[0].rob_idx == 22 && !issue_valid_o[1]);

    // Wrapped ROB pointers retain strict oldest-first selection.
    flush_i = 1'b1;
    @(posedge clk_i); #1;
    flush_i = 1'b0;
    rob_head_i = 127;
    for (int lane_idx = 0; lane_idx < 3; lane_idx++) begin
      dispatch_valid_i[lane_idx] = 1'b1;
      dispatch_src1_ready_i[lane_idx] = 1'b1;
      dispatch_uop_i[lane_idx].rob_idx = (RW+1)'((lane_idx == 0) ?
                                                 127 : lane_idx - 1);
    end
    dispatch_fire_i = 1'b1;
    @(posedge clk_i); #1;
    dispatch_fire_i = 1'b0;
    dispatch_valid_i = '0;
    assert (issue_valid_o == 2'b11 && issue_uop_o[0].rob_idx == 127 &&
            issue_uop_o[1].rob_idx == 0);

    $display("PASS: tb_memory_issue_queue");
    $finish;
  end
endmodule
