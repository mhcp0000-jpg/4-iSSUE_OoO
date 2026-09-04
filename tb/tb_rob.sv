`timescale 1ns/1ps

module tb_rob;
  import mycore_pkg::*;

  logic clk_i;
  logic rst_ni;
  ren_uop_t alloc_i [FW];
  logic [FW-1:0] alloc_valid_i;
  logic alloc_ready_o;
  logic alloc_fire_i;
  rob_wb_t wb_i [NWB];
  logic [FW-1:0] commit_valid_o;
  ren_uop_t commit_uop_o [FW];
  logic commit_ready_i, serial_ready_i;
  logic trap_valid_o;
  ren_uop_t trap_uop_o;
  logic [3:0] trap_cause_o;
  logic flush_i, br_recover_valid_i;
  logic [RW:0] br_rob_idx_i;
  logic [EW-1:0] br_epoch_i;
  logic [RW:0] rob_head_o, rob_tail_o, occupancy_o;
  logic [EW-1:0] rob_epoch_o;

  rob dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      for (int lane_idx = 0; lane_idx < FW; lane_idx++)
        alloc_i[lane_idx] = '0;
      alloc_valid_i = '0;
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        wb_i[wb_idx] = '0;
      commit_ready_i = 1'b1;
      serial_ready_i = 1'b1;
      alloc_fire_i = 1'b0;
      flush_i = 1'b0;
      br_recover_valid_i = 1'b0;
      br_rob_idx_i = '0;
      br_epoch_i = '0;
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
      assert (occupancy_o == 0 && rob_head_o == 0 && rob_tail_o == 0);
    end
  endtask

  task automatic set_alloc(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [RW:0] rob_idx,
    input fu_e fu
  );
    begin
      alloc_i[lane_idx] = '0;
      alloc_i[lane_idx].d.valid = 1'b1;
      alloc_valid_i[lane_idx] = 1'b1;
      alloc_i[lane_idx].d.fu = fu;
      alloc_i[lane_idx].d.pc = RESET_PC + {23'd0, rob_idx, 2'b00};
      alloc_i[lane_idx].d.rd = 6'(lane_idx + 1'b1);
      alloc_i[lane_idx].d.rd_valid = 1'b1;
      alloc_i[lane_idx].pdst = PW'(64 + rob_idx[5:0]);
      alloc_i[lane_idx].prev_pdst = PW'(lane_idx + 1'b1);
      alloc_i[lane_idx].rob_idx = rob_idx;
      alloc_i[lane_idx].epoch = rob_epoch_o;
      alloc_fire_i = 1'b1;
    end
  endtask

  task automatic set_wb(
    input logic [$clog2(NWB)-1:0] port_idx,
    input logic [RW:0] rob_idx,
    input logic excp,
    input logic [3:0] cause
  );
    begin
      wb_i[port_idx].valid = 1'b1;
      wb_i[port_idx].rob_idx = rob_idx;
      wb_i[port_idx].epoch = rob_epoch_o;
      wb_i[port_idx].excp = excp;
      wb_i[port_idx].cause = cause;
    end
  endtask

  initial begin
    reset_dut();

    // Out-of-order completion still retires four entries in program order.
    set_alloc(0, 0, FU_ALU); set_alloc(1, 1, FU_ALU);
    set_alloc(2, 2, FU_ALU); set_alloc(3, 3, FU_ALU);
    #1;
    assert (alloc_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 4 && rob_tail_o == 4 && commit_valid_o == 0);
    set_wb(0, 1, 0, 0); set_wb(1, 2, 0, 0); set_wb(2, 3, 0, 0);
    #1;
    assert (commit_valid_o == 0);
    @(posedge clk_i); #1;
    clear_inputs();
    set_wb(0, 0, 0, 0);
    #1;
    assert (commit_valid_o == 4'b1111);
    assert (commit_uop_o[0].rob_idx == 0 && commit_uop_o[3].rob_idx == 3);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0 && rob_head_o == 4 && rob_tail_o == 4);

    // Commit backpressure keeps a completed head entry resident.
    reset_dut();
    set_alloc(0, 0, FU_ALU);
    @(posedge clk_i); #1;
    clear_inputs();
    commit_ready_i = 1'b0;
    set_wb(0, 0, 0, 0);
    #1;
    assert (commit_valid_o[0]);
    @(posedge clk_i); #1;
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) wb_i[wb_idx] = '0;
    #1;
    assert (occupancy_o == 1 && commit_valid_o[0]);
    commit_ready_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0);

    // Serialized operations wait for readiness and stop younger retirement.
    reset_dut();
    set_alloc(0, 0, FU_NONE);
    set_alloc(1, 1, FU_ALU);
    @(posedge clk_i); #1;
    clear_inputs();
    serial_ready_i = 1'b0;
    set_wb(0, 1, 0, 0);
    #1;
    assert (commit_valid_o == 0 && !alloc_ready_o);
    @(posedge clk_i); #1;
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) wb_i[wb_idx] = '0;
    serial_ready_i = 1'b1;
    #1;
    assert (commit_valid_o == 4'b0001 && commit_uop_o[0].rob_idx == 0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (commit_valid_o == 4'b0001 && commit_uop_o[0].rob_idx == 1);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0);

    // An exception retires older work but remains at the head until flush.
    reset_dut();
    set_alloc(0, 0, FU_ALU); set_alloc(1, 1, FU_ALU);
    @(posedge clk_i); #1;
    clear_inputs();
    set_wb(0, 0, 0, 0); set_wb(1, 1, 1, EXC_LACCESS);
    #1;
    assert (commit_valid_o == 4'b0001);
    assert (trap_valid_o && trap_uop_o.rob_idx == 1 && trap_cause_o == EXC_LACCESS);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 1 && rob_head_o == 1 && trap_valid_o);
    flush_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0 && rob_head_o == rob_tail_o);

    // Mispredict recovery retains the branch and all older completed entries.
    reset_dut();
    set_alloc(0, 0, FU_ALU); set_alloc(1, 1, FU_BR);
    set_alloc(2, 2, FU_ALU); set_alloc(3, 3, FU_ALU);
    @(posedge clk_i); #1;
    clear_inputs();
    set_wb(0, 0, 0, 0); set_wb(1, 1, 0, 0);
    set_wb(2, 2, 0, 0); set_wb(3, 3, 0, 0);
    br_recover_valid_i = 1'b1;
    br_rob_idx_i = 1;
    br_epoch_i = 0;
    #1;
    assert (!alloc_ready_o && commit_valid_o == 0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 2 && rob_tail_o == 2);
    assert (commit_valid_o == 4'b0011);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0);

    // Fill the ROB, then retire and replace four wrapped entries in one cycle.
    reset_dut();
    for (int batch_idx = 0; batch_idx < 16; batch_idx++) begin
      set_alloc(0, (RW+1)'(batch_idx * 4), FU_ALU);
      set_alloc(1, (RW+1)'(batch_idx * 4 + 1), FU_ALU);
      set_alloc(2, (RW+1)'(batch_idx * 4 + 2), FU_ALU);
      set_alloc(3, (RW+1)'(batch_idx * 4 + 3), FU_ALU);
      #1;
      assert (alloc_ready_o);
      @(posedge clk_i); #1;
      clear_inputs();
    end
    assert (occupancy_o == (RW+1)'(NROB) && rob_tail_o == 64);
    set_alloc(0, 64, FU_ALU);
    #1;
    assert (!alloc_ready_o);
    clear_inputs();
    set_wb(0, 0, 0, 0); set_wb(1, 1, 0, 0);
    set_wb(2, 2, 0, 0); set_wb(3, 3, 0, 0);
    set_alloc(0, 64, FU_ALU); set_alloc(1, 65, FU_BR);
    set_alloc(2, 66, FU_ALU); set_alloc(3, 67, FU_ALU);
    #1;
    assert (commit_valid_o == 4'b1111 && alloc_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == (RW+1)'(NROB) && rob_head_o == 4 && rob_tail_o == 68);

    // A stale completion with the same array slot cannot complete wrapped tag 64.
    set_wb(0, 0, 0, 0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (dut.entry_q[0].valid && dut.entry_q[0].uop.rob_idx == 64);
    assert (!dut.entry_q[0].complete);

    // Wrapped branch recovery keeps tags 4..65 and removes 66..67.
    br_recover_valid_i = 1'b1;
    br_rob_idx_i = 65;
    br_epoch_i = 0;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_head_o == 4 && rob_tail_o == 66 && occupancy_o == 62);

    // Reallocated tag 66 has a new epoch and ignores the old path's WB.
    assert (rob_epoch_o == 1);
    set_alloc(0, 66, FU_ALU);
    @(posedge clk_i); #1;
    clear_inputs();
    set_wb(0, 66, 0, 0);
    wb_i[0].epoch = 0;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (dut.entry_q[2].valid && dut.entry_q[2].uop.rob_idx == 66);
    assert (dut.entry_q[2].uop.epoch == 1 && !dut.entry_q[2].complete);

    $display("PASS: tb_rob");
    $finish;
  end
endmodule
