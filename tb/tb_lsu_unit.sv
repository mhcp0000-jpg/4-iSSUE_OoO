`timescale 1ns/1ps

module tb_lsu_unit;
  import mycore_pkg::*;

  logic valid_i;
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
  logic ready_o;
  exec_wb_t wb_o;

  lsu_unit dut (.*);

  task automatic setup_load(input logic [5:0] op, input logic [31:0] addr);
    begin
      uop_i = '0;
      uop_i.d.valid = 1;
      uop_i.d.fu = FU_LD;
      uop_i.d.op = op;
      uop_i.d.rd = 1;
      uop_i.d.rd_valid = 1;
      uop_i.pdst = 64;
      uop_i.rob_idx = 3;
      uop_i.epoch = 2;
      base_i = addr;
      valid_i = 1;
      older_store_unknown_i = 0;
      forward_mask_i = 0;
      forward_data_i = 0;
      dmem_ready_i = 1;
      dmem_error_i = 0;
    end
  endtask

  initial begin
    valid_i = 0;
    uop_i = '0;
    base_i = 0;
    store_data_i = 0;
    older_store_unknown_i = 0;
    forward_mask_i = 0;
    forward_data_i = 0;
    dmem_ready_i = 0;
    dmem_rdata_i = 0;
    dmem_error_i = 0;

    setup_load(MEM_LB, 32'h101);
    dmem_rdata_i = 32'h0080_ff11;
    #1;
    assert (ready_o && wb_o.data == 32'hffff_ffff && dmem_addr_o == 32'h101);
    setup_load(MEM_LBU, 32'h102);
    dmem_rdata_i = 32'h0080_ff11;
    #1;
    assert (wb_o.data == 32'h80);
    setup_load(MEM_LH, 32'h102);
    dmem_rdata_i = 32'h8001_2211;
    #1;
    assert (wb_o.data == 32'hffff_8001);
    setup_load(MEM_LHU, 32'h100);
    dmem_rdata_i = 32'h8001_aa55;
    #1;
    assert (wb_o.data == 32'haa55);
    setup_load(MEM_LW, 32'h100);
    dmem_rdata_i = 32'h1234_5678;
    #1;
    assert (wb_o.write_pdst && wb_o.data == 32'h1234_5678);

    // Full forwarding completes without memory; partial bytes merge with RAM.
    setup_load(MEM_LW, 32'h100);
    dmem_ready_i = 0;
    forward_mask_i = 4'hf;
    forward_data_i = 32'hdead_beef;
    #1;
    assert (ready_o && !dmem_valid_o && wb_o.data == 32'hdead_beef);
    setup_load(MEM_LW, 32'h100);
    dmem_rdata_i = 32'h1122_3344;
    forward_mask_i = 4'b0011;
    forward_data_i = 32'h0000_bbaa;
    #1;
    assert (dmem_valid_o && wb_o.data == 32'h1122_bbaa);
    older_store_unknown_i = 1;
    #1;
    assert (!ready_o && !dmem_valid_o && !wb_o.rob.valid);

    setup_load(MEM_LW, 32'h102);
    #1;
    assert (ready_o && wb_o.rob.excp && wb_o.rob.cause == EXC_LADDR_MISALIGNED);
    setup_load(MEM_LW, 32'h100);
    dmem_error_i = 1;
    #1;
    assert (ready_o && wb_o.rob.excp && wb_o.rob.cause == EXC_LACCESS);

    // Stores produce shifted byte lanes but do not write memory speculatively.
    uop_i = '0;
    uop_i.d.valid = 1;
    uop_i.d.fu = FU_ST;
    uop_i.d.op = MEM_SB;
    uop_i.rob_idx = 4;
    uop_i.sq_idx = 1;
    base_i = 32'h103;
    store_data_i = 32'h0000_00aa;
    valid_i = 1;
    #1;
    assert (ready_o && store_execute_valid_o && store_execute_addr_o == 32'h103);
    assert (store_execute_strb_o == 4'b1000 && store_execute_data_o == 32'haa00_0000);
    assert (!dmem_valid_o && !wb_o.rob.valid);

    uop_i.d.op = MEM_SH;
    base_i = 32'h102;
    store_data_i = 32'h0000_bbaa;
    #1;
    assert (store_execute_strb_o == 4'b1100 && store_execute_data_o == 32'hbbaa_0000);
    base_i = 32'h101;
    #1;
    assert (ready_o && !store_execute_valid_o && wb_o.rob.excp &&
            wb_o.rob.cause == EXC_SADDR_MISALIGNED);

    $display("PASS: tb_lsu_unit");
    $finish;
  end
endmodule
