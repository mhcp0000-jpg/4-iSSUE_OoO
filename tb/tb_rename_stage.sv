`timescale 1ns/1ps

module tb_rename_stage;
  import mycore_pkg::*;
  localparam int CCOUNT_W = $clog2(NCKPT + 1);

  logic clk_i;
  logic rst_ni;
  dec_uop_t dec_i [FW];
  logic dec_ready_o;
  logic [FW-1:0] dispatch_valid_o;
  logic dispatch_fire_o;
  ren_uop_t ren_o [FW];
  logic dispatch_ready_i;
  logic [RW:0] rob_tail_i, rob_head_i;
  logic [SW:0] sq_tail_i;
  logic [EW-1:0] epoch_i;
  logic flush_i;
  logic br_resolve_valid_i, br_mispredict_i;
  logic [CW-1:0] br_ckpt_id_i;
  logic [RW:0] br_rob_idx_i;
  logic [EW-1:0] br_epoch_i;
  logic [FW-1:0] commit_valid_i;
  logic [5:0] commit_rd_i [FW];
  logic [PW-1:0] commit_pdst_i [FW];
  logic [PW-1:0] commit_prev_pdst_i [FW];
  logic [$clog2(NPRF+1)-1:0] free_count_o;
  logic [$clog2(NCKPT+1)-1:0] ckpt_free_count_o;

  rename_stage dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    integer i;
    begin
      for (i = 0; i < FW; i++) begin
        dec_i[i] = '0;
        commit_rd_i[i] = '0;
        commit_pdst_i[i] = '0;
        commit_prev_pdst_i[i] = '0;
      end
      dispatch_ready_i = 1'b1;
      rob_tail_i = '0;
      rob_head_i = '0;
      sq_tail_i = '0;
      epoch_i = '0;
      flush_i = 1'b0;
      br_resolve_valid_i = 1'b0;
      br_mispredict_i = 1'b0;
      br_ckpt_id_i = '0;
      br_rob_idx_i = '0;
      br_epoch_i = '0;
      commit_valid_i = '0;
      #1;
    end
  endtask

  task automatic reset_dut;
    begin
      clear_inputs();
      rst_ni = 1'b0;
      repeat (2) @(posedge clk_i);
      rst_ni = 1'b1;
      @(negedge clk_i);
      assert (free_count_o == 64) else $fatal(1, "reset free count: %0d", free_count_o);
      assert (ckpt_free_count_o == CCOUNT_W'(NCKPT)) else $fatal(1, "reset checkpoint count: %0d", ckpt_free_count_o);
    end
  endtask

  task automatic set_alu(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [5:0] rs1,
    input logic       use1,
    input logic [5:0] rd,
    input logic       rd_valid
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

  initial begin
    reset_dut();

    // Four-wide RAW/WAW forwarding through the in-cycle speculative RAT.
    set_alu(0, 6'd0, 1'b0, 6'd10, 1'b1);
    set_alu(1, 6'd10, 1'b1, 6'd11, 1'b1);
    set_alu(2, 6'd0, 1'b0, 6'd10, 1'b1);
    set_alu(3, 6'd10, 1'b1, 6'd0, 1'b0);
    rob_tail_i = 7'd12;
    #1;
    assert (dec_ready_o);
    assert (dispatch_fire_o);
    assert (dispatch_valid_o == 4'b1111);
    assert (ren_o[0].pdst == 7'd64 && ren_o[0].prev_pdst == 7'd10);
    assert (ren_o[1].ps1 == 7'd64 && ren_o[1].pdst == 7'd65);
    assert (ren_o[2].pdst == 7'd66 && ren_o[2].prev_pdst == 7'd64);
    assert (ren_o[3].ps1 == 7'd66);
    assert (ren_o[0].rob_idx == 7'd12 && ren_o[3].rob_idx == 7'd15);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 61) else $fatal(1, "allocation count: %0d", free_count_o);

    // Backpressure must leave all rename state untouched.
    @(negedge clk_i);
    set_alu(0, 6'd0, 1'b0, 6'd12, 1'b1);
    dispatch_ready_i = 1'b0;
    #1;
    assert (!dec_ready_o);
    assert (!dispatch_fire_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 61) else $fatal(1, "backpressure changed free count");

    // Retirement returns old mappings; the lowest returned register is reused.
    @(negedge clk_i);
    commit_valid_i = 4'b0111;
    commit_rd_i[0] = 6'd10; commit_pdst_i[0] = 7'd64; commit_prev_pdst_i[0] = 7'd10;
    commit_rd_i[1] = 6'd11; commit_pdst_i[1] = 7'd65; commit_prev_pdst_i[1] = 7'd11;
    commit_rd_i[2] = 6'd10; commit_pdst_i[2] = 7'd66; commit_prev_pdst_i[2] = 7'd64;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 64) else $fatal(1, "commit free count: %0d", free_count_o);
    set_alu(0, 6'd10, 1'b1, 6'd12, 1'b1);
    #1;
    assert (ren_o[0].ps1 == 7'd66);
    assert (ren_o[0].pdst == 7'd10);

    // A mispredict restores the branch's map and releases all younger state.
    reset_dut();
    set_branch(0);
    set_alu(1, 6'd0, 1'b0, 6'd5, 1'b1);
    set_branch(2);
    set_alu(3, 6'd0, 1'b0, 6'd6, 1'b1);
    #1;
    assert (ren_o[0].ckpt_id == 0 && ren_o[2].ckpt_id == 1);
    assert (ren_o[1].pdst == 7'd64 && ren_o[3].pdst == 7'd65);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 62 && ckpt_free_count_o == 6);

    @(negedge clk_i);
    br_resolve_valid_i = 1'b1;
    br_mispredict_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    br_epoch_i = 0;
    #1;
    assert (!dec_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 64 && ckpt_free_count_o == 8);
    set_alu(0, 6'd5, 1'b1, 6'd0, 1'b0);
    set_alu(1, 6'd6, 1'b1, 6'd0, 1'b0);
    #1;
    assert (ren_o[0].ps1 == 7'd5 && ren_o[1].ps1 == 7'd6);

    // Correct resolution may release and reuse a checkpoint in one cycle.
    reset_dut();
    set_branch(0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 7);
    @(negedge clk_i);
    br_resolve_valid_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    set_branch(0);
    rob_tail_i = 7'd1;
    #1;
    assert (dec_ready_o && ren_o[0].ckpt_id == 0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 7);

    // Epoch and ROB tag prevent a stale response from hitting a reused ID.
    reset_dut();
    epoch_i = 0;
    set_branch(0);
    @(posedge clk_i); #1;
    clear_inputs();
    br_resolve_valid_i = 1'b1;
    br_mispredict_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    br_epoch_i = 0;
    @(posedge clk_i); #1;
    clear_inputs();
    epoch_i = 1;
    set_branch(0);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 7);
    epoch_i = 1;
    br_resolve_valid_i = 1'b1;
    br_mispredict_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    br_epoch_i = 0;
    #1;
    assert (dec_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 7);
    epoch_i = 1;
    br_resolve_valid_i = 1'b1;
    br_ckpt_id_i = 0;
    br_rob_idx_i = 0;
    br_epoch_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 8);

    // All eight branch checkpoints can be consumed; the ninth branch stalls.
    reset_dut();
    set_branch(0); set_branch(1); set_branch(2); set_branch(3);
    #1;
    assert (ren_o[0].ckpt_id == 0 && ren_o[1].ckpt_id == 1 &&
            ren_o[2].ckpt_id == 2 && ren_o[3].ckpt_id == 3);
    @(posedge clk_i); #1;
    clear_inputs();
    set_branch(0); set_branch(1); set_branch(2); set_branch(3);
    #1;
    assert (ren_o[0].ckpt_id == 4 && ren_o[1].ckpt_id == 5 &&
            ren_o[2].ckpt_id == 6 && ren_o[3].ckpt_id == 7);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (ckpt_free_count_o == 0);
    set_branch(0);
    #1;
    assert (!dec_ready_o && ren_o[0].d.valid && !dispatch_fire_o);

    // Exhaust the PRF, then reuse a register returned by commit that cycle.
    reset_dut();
    for (int cycle_idx = 0; cycle_idx < 16; cycle_idx++) begin
      set_alu(0, 6'd0, 1'b0, 6'd1, 1'b1);
      set_alu(1, 6'd0, 1'b0, 6'd1, 1'b1);
      set_alu(2, 6'd0, 1'b0, 6'd1, 1'b1);
      set_alu(3, 6'd0, 1'b0, 6'd1, 1'b1);
      #1;
      assert (dec_ready_o);
      @(posedge clk_i); #1;
      clear_inputs();
    end
    assert (free_count_o == 0);
    set_alu(0, 6'd0, 1'b0, 6'd2, 1'b1);
    #1;
    assert (!dec_ready_o && ren_o[0].d.valid && !dispatch_fire_o);
    clear_inputs();
    commit_valid_i[0] = 1'b1;
    commit_rd_i[0] = 6'd1;
    commit_pdst_i[0] = 7'd64;
    commit_prev_pdst_i[0] = 7'd1;
    set_alu(0, 6'd0, 1'b0, 6'd2, 1'b1);
    #1;
    assert (dec_ready_o && ren_o[0].pdst == 7'd1);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 0);

    // Sparse lanes still receive packed ROB and store-queue indices.
    reset_dut();
    dec_i[0].valid = 1'b1; dec_i[0].fu = FU_ST;
    set_alu(2, 6'd0, 1'b0, 6'd0, 1'b0);
    dec_i[3].valid = 1'b1; dec_i[3].fu = FU_ST;
    rob_tail_i = 7'd126;
    sq_tail_i = 5'd31;
    #1;
    assert (ren_o[0].rob_idx == 7'd126 && ren_o[0].sq_idx == 5'd31);
    assert (ren_o[2].rob_idx == 7'd127 && ren_o[2].sq_idx == 5'd0);
    assert (ren_o[3].rob_idx == 7'd0 && ren_o[3].sq_idx == 5'd0);

    // Full flush keeps committed state and discards a younger WAW mapping.
    reset_dut();
    set_alu(0, 6'd0, 1'b0, 6'd7, 1'b1);
    @(posedge clk_i); #1;
    clear_inputs();
    @(negedge clk_i);
    commit_valid_i[0] = 1'b1;
    commit_rd_i[0] = 6'd7;
    commit_pdst_i[0] = 7'd64;
    commit_prev_pdst_i[0] = 7'd7;
    set_alu(0, 6'd0, 1'b0, 6'd7, 1'b1);
    #1;
    assert (ren_o[0].pdst == 7'd7 && ren_o[0].prev_pdst == 7'd64);
    @(posedge clk_i); #1;
    clear_inputs();
    @(negedge clk_i);
    flush_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (free_count_o == 64);
    set_alu(0, 6'd7, 1'b1, 6'd0, 1'b0);
    #1;
    assert (ren_o[0].ps1 == 7'd64);

    $display("PASS: tb_rename_stage");
    $finish;
  end
endmodule
