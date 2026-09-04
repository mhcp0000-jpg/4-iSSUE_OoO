`timescale 1ns/1ps

module tb_store_commit_unit;
  import mycore_pkg::*;

  logic clk_i, rst_ni, cancel_i;
  logic serial_valid_i, commit_ready_i, commit_fire_i, other_serial_ready_i;
  ren_uop_t serial_uop_i;
  logic sq_ready_i;
  ren_uop_t sq_uop_i;
  logic [31:0] sq_addr_i, sq_data_i;
  logic [3:0] sq_strb_i;
  logic dmem_valid_o, dmem_write_o;
  logic [31:0] dmem_addr_o, dmem_wdata_o;
  logic [1:0] dmem_size_o;
  logic [3:0] dmem_wstrb_o;
  logic dmem_ready_i, dmem_error_i, serial_ready_o;
  exec_wb_t fault_wb_o;

  store_commit_unit dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni = 0;
    cancel_i = 0;
    serial_valid_i = 0;
    serial_uop_i = '0;
    commit_ready_i = 1;
    commit_fire_i = 0;
    other_serial_ready_i = 1;
    sq_ready_i = 0;
    sq_uop_i = '0;
    sq_addr_i = 32'h8002_0103;
    sq_data_i = 32'haa00_0000;
    sq_strb_i = 4'b1000;
    dmem_ready_i = 1;
    dmem_error_i = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1;
    @(negedge clk_i);

    serial_valid_i = 1;
    serial_uop_i.d.fu = FU_CSR;
    #1;
    assert (serial_ready_o && !dmem_valid_o);

    serial_uop_i.d.fu = FU_ST;
    serial_uop_i.d.op = MEM_SB;
    serial_uop_i.rob_idx = 7;
    serial_uop_i.epoch = 2;
    serial_uop_i.sq_idx = 3;
    #1;
    assert (!serial_ready_o && !dmem_valid_o);

    sq_ready_i = 1;
    sq_uop_i = serial_uop_i;
    dmem_ready_i = 0;
    #1;
    assert (dmem_valid_o && dmem_write_o && !serial_ready_o);
    assert (dmem_addr_o == sq_addr_i && dmem_size_o == 0 &&
            dmem_wdata_o == sq_data_i && dmem_wstrb_o == sq_strb_i);
    @(posedge clk_i); #1;
    sq_addr_i = 32'hdead_beef;
    sq_data_i = 32'h1234_5678;
    sq_strb_i = 4'hf;
    #1;
    assert (dmem_valid_o && dmem_addr_o == 32'h8002_0103 &&
            dmem_wdata_o == 32'haa00_0000 && dmem_wstrb_o == 4'b1000);

    dmem_ready_i = 1;
    dmem_error_i = 1;
    #1;
    assert (!serial_ready_o && fault_wb_o.rob.valid && fault_wb_o.rob.excp);
    assert (fault_wb_o.rob.cause == EXC_SACCESS && fault_wb_o.rob.rob_idx == 7);
    commit_ready_i = 0;
    @(posedge clk_i); #1;
    assert (!dmem_valid_o);

    commit_ready_i = 1;
    dmem_error_i = 0;
    sq_addr_i = 32'h8002_0103;
    sq_data_i = 32'haa00_0000;
    sq_strb_i = 4'b1000;
    #1;
    assert (serial_ready_o && !fault_wb_o.rob.valid);
    @(posedge clk_i); #1;
    assert (!dmem_valid_o && serial_ready_o);
    commit_fire_i = 1;
    @(posedge clk_i); #1;
    commit_fire_i = 0;
    serial_valid_i = 0;
    commit_ready_i = 0;
    #1;
    assert (!dmem_valid_o && serial_ready_o);

    $display("PASS: tb_store_commit_unit");
    $finish;
  end
endmodule
