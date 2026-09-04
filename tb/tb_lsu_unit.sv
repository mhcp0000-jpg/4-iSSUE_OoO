`timescale 1ns/1ps

module tb_lsu_unit;
  import mycore_pkg::*;

  logic clk_i, rst_ni, valid_i;
  ren_uop_t uop_i;
  logic [31:0] base_i, store_data_i;
  logic older_store_unknown_i;
  logic [3:0] forward_mask_i;
  logic [31:0] forward_data_i;
  logic dmem_valid_o;
  logic [31:0] dmem_addr_o;
  logic [1:0] dmem_size_o;
  logic dmem_ready_i;
  logic [31:0] dmem_rdata_i;
  logic dmem_error_i;
  logic store_execute_valid_o;
  ren_uop_t store_execute_uop_o;
  logic [31:0] store_execute_addr_o, store_execute_data_o;
  logic [3:0] store_execute_strb_o;
  logic flush_i, br_recover_fire_i;
  logic [RW:0] br_rob_idx_i, rob_head_i;
  logic ready_o, busy_o;
  exec_wb_t wb_o;

  lsu_unit dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      valid_i = 1'b0;
      uop_i = '0;
      base_i = '0;
      store_data_i = '0;
      older_store_unknown_i = 1'b0;
      forward_mask_i = '0;
      forward_data_i = '0;
      dmem_ready_i = 1'b0;
      dmem_rdata_i = '0;
      dmem_error_i = 1'b0;
      flush_i = 1'b0;
      br_recover_fire_i = 1'b0;
      br_rob_idx_i = '0;
      rob_head_i = '0;
      #1;
    end
  endtask

  task automatic drive_load(input logic [5:0] op, input logic [31:0] addr,
                             input logic [RW:0] rob);
    begin
      uop_i = '0;
      uop_i.d.valid = 1'b1;
      uop_i.d.fu = FU_LD;
      uop_i.d.op = op;
      uop_i.d.rd = 1;
      uop_i.d.rd_valid = 1'b1;
      uop_i.pdst = 64 + rob[PW-1:0];
      uop_i.rob_idx = rob;
      uop_i.epoch = 2;
      base_i = addr;
      valid_i = 1'b1;
    end
  endtask

  initial begin
    clear_inputs();
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);

    // A captured load leaves its producer and holds address/forward metadata.
    drive_load(MEM_LW, 32'h100, 3);
    forward_mask_i = 4'b0011;
    forward_data_i = 32'h0000_bbaa;
    #1;
    assert (ready_o && !busy_o && !dmem_valid_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (busy_o && dmem_valid_o && dmem_addr_o == 32'h100);
    forward_mask_i = 4'hf;
    forward_data_i = 32'hdead_beef;
    dmem_rdata_i = 32'h1122_3344;
    dmem_ready_i = 1'b1;
    #1;
    assert (wb_o.rob.valid && wb_o.write_pdst && wb_o.data == 32'h1122_bbaa);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (!busy_o && !dmem_valid_o);

    // Full forwarding still uses the slot and completes on the following cycle.
    drive_load(MEM_LBU, 32'h102, 4);
    forward_mask_i = 4'b0100;
    forward_data_i = 32'h0080_0000;
    @(posedge clk_i); #1;
    valid_i = 1'b0;
    assert (busy_o && !dmem_valid_o && wb_o.rob.valid && wb_o.data == 32'h80);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (!busy_o);

    // Unknown older stores hold the candidate in the IQ.
    drive_load(MEM_LW, 32'h200, 5);
    older_store_unknown_i = 1'b1;
    #1;
    assert (!ready_o && !busy_o);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (!busy_o);

    // Misaligned loads are captured and report their precise exception.
    drive_load(MEM_LW, 32'h202, 6);
    @(posedge clk_i); #1;
    valid_i = 1'b0;
    assert (busy_o && !dmem_valid_o && wb_o.rob.valid && wb_o.rob.excp &&
            wb_o.rob.cause == EXC_LADDR_MISALIGNED && wb_o.rob.tval == 32'h202);
    @(posedge clk_i); #1;
    clear_inputs();

    // Wrong-path requests remain on their fixed lane until drained, without WB.
    drive_load(MEM_LW, 32'h300, 12);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (busy_o && dmem_valid_o);
    br_recover_fire_i = 1'b1;
    br_rob_idx_i = 10;
    rob_head_i = 0;
    @(posedge clk_i); #1;
    br_recover_fire_i = 1'b0;
    assert (busy_o && dmem_valid_o && !wb_o.rob.valid);
    dmem_ready_i = 1'b1;
    dmem_rdata_i = 32'h1234_5678;
    #1;
    assert (!wb_o.rob.valid);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (!busy_o);

    // Stores execute speculatively but never issue a data-memory request.
    uop_i = '0;
    uop_i.d.valid = 1'b1;
    uop_i.d.fu = FU_ST;
    uop_i.d.op = MEM_SB;
    uop_i.rob_idx = 13;
    uop_i.sq_idx = 1;
    base_i = 32'h103;
    store_data_i = 32'h0000_00aa;
    valid_i = 1'b1;
    #1;
    assert (ready_o && store_execute_valid_o && store_execute_addr_o == 32'h103);
    assert (store_execute_strb_o == 4'b1000 &&
            store_execute_data_o == 32'haa00_0000 && !dmem_valid_o);

    uop_i.d.op = MEM_SH;
    base_i = 32'h101;
    #1;
    assert (!store_execute_valid_o && wb_o.rob.valid && wb_o.rob.excp &&
            wb_o.rob.cause == EXC_SADDR_MISALIGNED);

    $display("PASS: tb_lsu_unit");
    $finish;
  end
endmodule
