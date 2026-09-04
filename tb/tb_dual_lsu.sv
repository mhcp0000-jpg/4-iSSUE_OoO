`timescale 1ns/1ps

module tb_dual_lsu;
  import mycore_pkg::*;

  logic clk_i, rst_ni;
  logic [NLSU-1:0] valid_i, older_store_unknown_i;
  ren_uop_t uop_i [NLSU];
  logic [31:0] base_i [NLSU], store_data_i [NLSU];
  logic [3:0] forward_mask_i [NLSU];
  logic [31:0] forward_data_i [NLSU];
  logic [NLSU-1:0] dmem_valid_o, dmem_ready_i, dmem_error_i;
  logic [31:0] dmem_addr_o [NLSU], dmem_rdata_i [NLSU];
  logic [1:0] dmem_size_o [NLSU];
  logic [NLSU-1:0] store_execute_valid_o;
  ren_uop_t store_execute_uop_o [NLSU];
  logic [31:0] store_execute_addr_o [NLSU], store_execute_data_o [NLSU];
  logic [3:0] store_execute_strb_o [NLSU];
  logic flush_i, br_recover_fire_i;
  logic [RW:0] br_rob_idx_i, rob_head_i;
  logic [NLSU-1:0] ready_o, busy_o;
  exec_wb_t wb_o [NLSU];

  for (genvar lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin : g_lsu
    lsu_unit dut (
      .clk_i, .rst_ni, .valid_i(valid_i[lsu_idx]), .uop_i(uop_i[lsu_idx]),
      .base_i(base_i[lsu_idx]), .store_data_i(store_data_i[lsu_idx]),
      .older_store_unknown_i(older_store_unknown_i[lsu_idx]),
      .forward_mask_i(forward_mask_i[lsu_idx]),
      .forward_data_i(forward_data_i[lsu_idx]),
      .dmem_valid_o(dmem_valid_o[lsu_idx]), .dmem_addr_o(dmem_addr_o[lsu_idx]),
      .dmem_size_o(dmem_size_o[lsu_idx]), .dmem_ready_i(dmem_ready_i[lsu_idx]),
      .dmem_rdata_i(dmem_rdata_i[lsu_idx]), .dmem_error_i(dmem_error_i[lsu_idx]),
      .store_execute_valid_o(store_execute_valid_o[lsu_idx]),
      .store_execute_uop_o(store_execute_uop_o[lsu_idx]),
      .store_execute_addr_o(store_execute_addr_o[lsu_idx]),
      .store_execute_data_o(store_execute_data_o[lsu_idx]),
      .store_execute_strb_o(store_execute_strb_o[lsu_idx]),
      .flush_i, .br_recover_fire_i, .br_rob_idx_i, .rob_head_i,
      .ready_o(ready_o[lsu_idx]), .busy_o(busy_o[lsu_idx]), .wb_o(wb_o[lsu_idx])
    );
  end

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    valid_i = '0;
    older_store_unknown_i = '0;
    dmem_ready_i = '0;
    dmem_error_i = '0;
    flush_i = 1'b0;
    br_recover_fire_i = 1'b0;
    br_rob_idx_i = '0;
    rob_head_i = '0;
    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      uop_i[lsu_idx] = '0;
      base_i[lsu_idx] = '0;
      store_data_i[lsu_idx] = '0;
      forward_mask_i[lsu_idx] = '0;
      forward_data_i[lsu_idx] = '0;
      dmem_rdata_i[lsu_idx] = '0;
    end

    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);

    for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
      valid_i[lsu_idx] = 1'b1;
      uop_i[lsu_idx].d.valid = 1'b1;
      uop_i[lsu_idx].d.fu = FU_LD;
      uop_i[lsu_idx].d.op = MEM_LW;
      uop_i[lsu_idx].d.rd = 6'(1 + lsu_idx);
      uop_i[lsu_idx].d.rd_valid = 1'b1;
      uop_i[lsu_idx].pdst = PW'(64 + lsu_idx);
      uop_i[lsu_idx].rob_idx = (RW+1)'(8 + lsu_idx);
      base_i[lsu_idx] = 32'h8002_0100 + 4 * lsu_idx;
    end
    forward_mask_i[0] = 4'b0011;
    forward_data_i[0] = 32'h0000_bbaa;
    #1;
    assert (ready_o == 2'b11);
    @(posedge clk_i); #1;
    valid_i = '0;
    assert (busy_o == 2'b11 && dmem_valid_o == 2'b11);
    assert (dmem_addr_o[0] == 32'h8002_0100 &&
            dmem_addr_o[1] == 32'h8002_0104);

    // Lane 1 may complete first without moving or disturbing lane 0.
    dmem_ready_i[1] = 1'b1;
    dmem_rdata_i[1] = 32'h5566_7788;
    #1;
    assert (!wb_o[0].rob.valid && wb_o[1].rob.valid &&
            wb_o[1].data == 32'h5566_7788);
    @(posedge clk_i); #1;
    dmem_ready_i[1] = 1'b0;
    assert (busy_o == 2'b01 && dmem_valid_o == 2'b01 &&
            dmem_addr_o[0] == 32'h8002_0100);

    dmem_ready_i[0] = 1'b1;
    dmem_rdata_i[0] = 32'h1122_3344;
    #1;
    assert (wb_o[0].rob.valid && wb_o[0].data == 32'h1122_bbaa &&
            !wb_o[1].rob.valid);
    @(posedge clk_i); #1;
    dmem_ready_i = '0;
    assert (busy_o == 0 && dmem_valid_o == 0);

    $display("PASS: tb_dual_lsu");
    $finish;
  end
endmodule
