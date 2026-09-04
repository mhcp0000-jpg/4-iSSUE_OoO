`timescale 1ns/1ps

module tb_backend;
  import mycore_pkg::*;

  logic clk_i;
  logic rst_ni;

  dec_uop_t dec_i [FW];
  logic dec_ready_o, dispatch_fire_o, backend_ready_i;
  logic [FW-1:0] dispatch_valid;
  ren_uop_t ren_uop [FW];
  logic rob_alloc_ready;
  logic [RW:0] rob_head, rob_tail, rob_occupancy;
  logic [EW-1:0] rob_epoch;

  rob_wb_t wb_i [NWB];
  logic [FW-1:0] rob_commit_valid;
  ren_uop_t rob_commit_uop [FW];
  logic [FW-1:0] rename_commit_valid;
  logic [5:0] rename_commit_rd [FW];
  logic [PW-1:0] rename_commit_pdst [FW];
  logic [PW-1:0] rename_commit_prev_pdst [FW];

  logic flush_i;
  logic br_resolve_valid_i, br_mispredict_i;
  logic [CW-1:0] br_ckpt_id_i;
  logic [RW:0] br_rob_idx_i;
  logic [EW-1:0] br_epoch_i;
  logic rob_recover_fire;
  logic [$clog2(NPRF+1)-1:0] free_count;
  logic [$clog2(NCKPT+1)-1:0] ckpt_free_count;
  logic rob_trap_valid;
  ren_uop_t rob_trap_uop;
  logic rob_serial_valid;
  ren_uop_t rob_serial_uop;
  logic [3:0] rob_trap_cause;

  always_comb begin
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      rename_commit_valid[lane_idx] = rob_commit_valid[lane_idx] &&
                                        rob_commit_uop[lane_idx].d.rd_valid &&
                                        (rob_commit_uop[lane_idx].d.rd != 6'd0);
      rename_commit_rd[lane_idx] = rob_commit_uop[lane_idx].d.rd;
      rename_commit_pdst[lane_idx] = rob_commit_uop[lane_idx].pdst;
      rename_commit_prev_pdst[lane_idx] = rob_commit_uop[lane_idx].prev_pdst;
    end
  end

  rename_stage u_rename (
    .clk_i,
    .rst_ni,
    .dec_i,
    .dec_ready_o,
    .ren_o               (ren_uop),
    .dispatch_valid_o    (dispatch_valid),
    .dispatch_ready_i    (rob_alloc_ready && backend_ready_i),
    .dispatch_fire_o,
    .rob_tail_i          (rob_tail),
    .sq_tail_i           ('0),
    .rob_head_i          (rob_head),
    .epoch_i             (rob_epoch),
    .flush_i,
    .br_resolve_valid_i,
    .br_mispredict_i,
    .br_ckpt_id_i,
    .br_rob_idx_i,
    .br_epoch_i,
    .commit_valid_i      (rename_commit_valid),
    .commit_rd_i         (rename_commit_rd),
    .commit_pdst_i       (rename_commit_pdst),
    .commit_prev_pdst_i  (rename_commit_prev_pdst),
    .free_count_o        (free_count),
    .ckpt_free_count_o   (ckpt_free_count)
  );

  rob u_rob (
    .clk_i,
    .rst_ni,
    .alloc_i             (ren_uop),
    .alloc_valid_i       (dispatch_valid),
    .alloc_ready_o       (rob_alloc_ready),
    .alloc_fire_i        (dispatch_fire_o),
    .wb_i,
    .commit_valid_o      (rob_commit_valid),
    .commit_uop_o        (rob_commit_uop),
    .commit_ready_i      (1'b1),
    .serial_ready_i      (1'b1),
    .serial_valid_o      (rob_serial_valid),
    .serial_uop_o        (rob_serial_uop),
    .trap_valid_o        (rob_trap_valid),
    .trap_uop_o          (rob_trap_uop),
    .trap_cause_o        (rob_trap_cause),
    .flush_i,
    .br_recover_valid_i  (br_resolve_valid_i && br_mispredict_i),
    .br_rob_idx_i,
    .br_epoch_i,
    .br_recover_fire_o   (rob_recover_fire),
    .rob_head_o          (rob_head),
    .rob_tail_o          (rob_tail),
    .occupancy_o         (rob_occupancy),
    .rob_epoch_o         (rob_epoch)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      for (int lane_idx = 0; lane_idx < FW; lane_idx++)
        dec_i[lane_idx] = '0;
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        wb_i[wb_idx] = '0;
      backend_ready_i = 1'b1;
      flush_i = 1'b0;
      br_resolve_valid_i = 1'b0;
      br_mispredict_i = 1'b0;
      br_ckpt_id_i = '0;
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
      assert (rob_occupancy == 0 && free_count == 64 && rob_epoch == 0);
    end
  endtask

  task automatic set_alu(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [5:0] rs1,
    input logic use1,
    input logic [5:0] rd,
    input logic rd_valid
  );
    begin
      dec_i[lane_idx] = '0;
      dec_i[lane_idx].valid = 1'b1;
      dec_i[lane_idx].fu = FU_ALU;
      dec_i[lane_idx].rs1 = rs1;
      dec_i[lane_idx].use1 = use1;
      dec_i[lane_idx].rd = rd;
      dec_i[lane_idx].rd_valid = rd_valid;
    end
  endtask

  task automatic set_branch(input logic [$clog2(FW)-1:0] lane_idx);
    begin
      dec_i[lane_idx] = '0;
      dec_i[lane_idx].valid = 1'b1;
      dec_i[lane_idx].fu = FU_BR;
      dec_i[lane_idx].is_branch = 1'b1;
    end
  endtask

  task automatic set_wb(
    input logic [$clog2(NWB)-1:0] port_idx,
    input logic [RW:0] rob_idx,
    input logic [EW-1:0] epoch
  );
    begin
      wb_i[port_idx] = '0;
      wb_i[port_idx].valid = 1'b1;
      wb_i[port_idx].rob_idx = rob_idx;
      wb_i[port_idx].epoch = epoch;
    end
  endtask

  initial begin
    reset_dut();

    // IQ backpressure holds rename and prevents repeated ROB allocation.
    set_alu(0, 0, 0, 1, 1);
    set_alu(1, 1, 1, 2, 1);
    backend_ready_i = 1'b0;
    #1;
    assert (!dec_ready_o && !dispatch_fire_o && rob_alloc_ready);
    assert (ren_uop[0].d.valid && ren_uop[1].ps1 == 64);
    repeat (2) @(posedge clk_i);
    #1;
    assert (rob_occupancy == 0 && free_count == 64);
    backend_ready_i = 1'b1;
    #1;
    assert (dec_ready_o && dispatch_fire_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 2 && free_count == 62 && rob_tail == 2);

    // ROB commit feeds the committed RAT and physical free set in the same cycle.
    set_wb(0, 0, 0); set_wb(1, 1, 0);
    #1;
    assert (rob_commit_valid == 4'b0011);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 0 && free_count == 64);
    set_alu(0, 1, 1, 0, 0);
    set_alu(1, 2, 1, 0, 0);
    #1;
    assert (ren_uop[0].ps1 == 64 && ren_uop[1].ps1 == 65);

    // Recovery rewinds both structures and advances the allocation epoch.
    reset_dut();
    set_branch(0);
    set_alu(1, 0, 0, 5, 1);
    set_alu(2, 0, 0, 6, 1);
    #1;
    assert (ren_uop[0].ckpt_id == 0 && ren_uop[1].rob_idx == 1);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 3 && free_count == 62);
    set_wb(0, 0, 0); set_wb(1, 1, 0); set_wb(2, 2, 0);
    br_resolve_valid_i = 1'b1;
    br_mispredict_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    br_epoch_i = 0;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 1 && rob_tail == 1 && free_count == 64);
    assert (rob_epoch == 1 && ckpt_free_count == $bits(ckpt_free_count)'(NCKPT));

    // Branch 0 retires while recovered-path tag 1 is allocated with epoch 1.
    set_alu(0, 0, 0, 5, 1);
    #1;
    assert (ren_uop[0].rob_idx == 1 && ren_uop[0].epoch == 1);
    assert (rob_commit_valid == 4'b0001 && dispatch_fire_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_head == 1 && rob_tail == 2 && rob_occupancy == 1);

    // Delayed wrong-path completion for old tag 1/epoch 0 is ignored.
    set_wb(0, 1, 0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_commit_valid == 0 && rob_occupancy == 1);
    set_wb(0, 1, 1);
    #1;
    assert (rob_commit_valid == 4'b0001);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 0);

    $display("PASS: tb_backend");
    $finish;
  end
endmodule
