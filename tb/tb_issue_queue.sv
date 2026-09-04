`timescale 1ns/1ps

module tb_issue_queue;
  import mycore_pkg::*;

  localparam int DEPTH = 8;
  localparam int ISSUE_WIDTH = 2;
  localparam int OCW = $clog2(DEPTH + 1);

  logic clk_i;
  logic rst_ni;
  logic [FW-1:0] dispatch_valid_i;
  ren_uop_t dispatch_uop_i [FW];
  logic [FW-1:0] dispatch_src1_ready_i;
  logic [FW-1:0] dispatch_src2_ready_i;
  logic [FW-1:0] dispatch_src3_ready_i;
  logic dispatch_ready_o, dispatch_fire_i;
  exec_wb_t wb_i [NWB];
  logic [NWB-1:0] wb_accepted_i;
  logic [ISSUE_WIDTH-1:0] issue_valid_o;
  ren_uop_t issue_uop_o [ISSUE_WIDTH];
  logic [ISSUE_WIDTH-1:0] issue_accept_i;
  logic flush_i, br_recover_fire_i;
  logic [RW:0] br_rob_idx_i, rob_head_i;
  logic [$clog2(DEPTH+1)-1:0] occupancy_o;

  issue_queue #(.DEPTH(DEPTH), .ISSUE_WIDTH(ISSUE_WIDTH)) dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      dispatch_valid_i = '0;
      dispatch_src1_ready_i = '0;
      dispatch_src2_ready_i = '0;
      dispatch_src3_ready_i = '0;
      dispatch_fire_i = 1'b0;
      for (int lane_idx = 0; lane_idx < FW; lane_idx++)
        dispatch_uop_i[lane_idx] = '0;
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        wb_i[wb_idx] = '0;
      wb_accepted_i = '0;
      issue_accept_i = '0;
      flush_i = 1'b0;
      br_recover_fire_i = 1'b0;
      br_rob_idx_i = '0;
      rob_head_i = '0;
      #1;
    end
  endtask

  task automatic reset_dut;
    begin
      clear_inputs();
      rst_ni = 1'b0;
      repeat (2) @(posedge clk_i);
      rst_ni = 1'b1;
      @(negedge clk_i); #1;
      assert (occupancy_o == 0 && dispatch_ready_o);
    end
  endtask

  task automatic set_dispatch(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [RW:0] rob_idx,
    input logic source_ready,
    input logic [PW-1:0] ps1
  );
    begin
      dispatch_valid_i[lane_idx] = 1'b1;
      dispatch_src1_ready_i[lane_idx] = source_ready;
      dispatch_src2_ready_i[lane_idx] = 1'b1;
      dispatch_src3_ready_i[lane_idx] = 1'b1;
      dispatch_uop_i[lane_idx] = '0;
      dispatch_uop_i[lane_idx].d.valid = 1'b1;
      dispatch_uop_i[lane_idx].d.use1 = 1'b1;
      dispatch_uop_i[lane_idx].ps1 = ps1;
      dispatch_uop_i[lane_idx].rob_idx = rob_idx;
      dispatch_uop_i[lane_idx].epoch = 0;
    end
  endtask

  task automatic dispatch_bundle;
    begin
      #1;
      assert (dispatch_ready_o);
      dispatch_fire_i = 1'b1;
      @(posedge clk_i); #1;
      clear_inputs();
    end
  endtask

  initial begin
    reset_dut();

    set_dispatch(0, 0, 1, 60);
    set_dispatch(1, 1, 0, 64);
    set_dispatch(2, 2, 1, 61);
    set_dispatch(3, 3, 1, 62);
    dispatch_bundle();
    assert (occupancy_o == 4);
    assert (issue_valid_o == 2'b11);
    assert (issue_uop_o[0].rob_idx == 0 && issue_uop_o[1].rob_idx == 2);

    issue_accept_i = 2'b11;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 2 && issue_uop_o[0].rob_idx == 3);
    issue_accept_i[0] = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 1 && issue_valid_o == 0);

    // Validated wakeup can issue and remove the blocked entry in one cycle.
    wb_i[0].write_pdst = 1'b1;
    wb_i[0].pdst = 64;
    wb_accepted_i[0] = 1'b1;
    issue_accept_i[0] = 1'b1;
    #1;
    assert (issue_valid_o[0] && issue_uop_o[0].rob_idx == 1);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0);

    // A full queue first retires issues, then accepts dispatch next cycle.
    for (int batch_idx = 0; batch_idx < 2; batch_idx++) begin
      set_dispatch(0, 7'(batch_idx*4+0), 1, 1);
      set_dispatch(1, 7'(batch_idx*4+1), 1, 1);
      set_dispatch(2, 7'(batch_idx*4+2), 1, 1);
      set_dispatch(3, 7'(batch_idx*4+3), 1, 1);
      dispatch_bundle();
    end
    assert (occupancy_o == OCW'(DEPTH));
    set_dispatch(0, 8, 1, 1);
    #1;
    assert (!dispatch_ready_o);
    clear_inputs();
    issue_accept_i = 2'b11;
    set_dispatch(0, 8, 1, 1);
    set_dispatch(1, 9, 1, 1);
    #1;
    assert (!dispatch_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 6);
    set_dispatch(0, 8, 1, 1);
    set_dispatch(1, 9, 1, 1);
    #1;
    assert (dispatch_ready_o);
    dispatch_fire_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == OCW'(DEPTH));

    // Flush, then verify wrapped age order and branch squash.
    flush_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    rob_head_i = 126;
    set_dispatch(0, 126, 1, 1);
    set_dispatch(1, 127, 1, 1);
    set_dispatch(2, 0, 1, 1);
    set_dispatch(3, 1, 1, 1);
    dispatch_bundle();
    rob_head_i = 126;
    #1;
    assert (issue_uop_o[0].rob_idx == 126 && issue_uop_o[1].rob_idx == 127);
    br_recover_fire_i = 1'b1;
    br_rob_idx_i = 127;
    @(posedge clk_i); #1;
    clear_inputs();
    rob_head_i = 126;
    assert (occupancy_o == 2);
    assert (issue_uop_o[0].rob_idx == 126 && issue_uop_o[1].rob_idx == 127);

    $display("PASS: tb_issue_queue");
    $finish;
  end
endmodule
