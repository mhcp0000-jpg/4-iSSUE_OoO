`timescale 1ns/1ps

module tb_store_queue;
  import mycore_pkg::*;
  import soc_pkg::*;

  logic clk_i, rst_ni;
  logic [FW-1:0] dispatch_valid_i;
  ren_uop_t dispatch_uop_i [FW];
  logic dispatch_ready_o, dispatch_fire_i;
  logic [SW:0] sq_head_o, sq_tail_o;
  logic [NLSU-1:0] execute_valid_i;
  ren_uop_t execute_uop_i [NLSU];
  logic [31:0] execute_addr_i [NLSU], execute_data_i [NLSU];
  logic [3:0] execute_strb_i [NLSU];
  exec_wb_t execute_wb_o [NLSU];
  logic commit_ready_o, commit_fire_i;
  ren_uop_t commit_uop_o;
  logic [31:0] commit_addr_o, commit_data_o;
  logic [3:0] commit_strb_o;
  logic [NLSU-1:0] load_query_valid_i;
  logic [31:0] load_query_addr_i [NLSU];
  logic [SW:0] load_query_sq_i [NLSU];
  logic [NLSU-1:0] load_older_unknown_o;
  logic [3:0] load_forward_mask_o [NLSU];
  logic [31:0] load_forward_data_o [NLSU];
  logic flush_i, br_recover_fire_i;
  logic [SW:0] br_sq_tail_i;
  logic [$clog2(NSQ+1)-1:0] occupancy_o;

  store_queue dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      dispatch_valid_i = '0;
      dispatch_fire_i = 0;
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) dispatch_uop_i[lane_idx] = '0;
      execute_valid_i = 0;
      for (int lsu_idx = 0; lsu_idx < NLSU; lsu_idx++) begin
        execute_uop_i[lsu_idx] = '0;
        execute_addr_i[lsu_idx] = 0;
        execute_data_i[lsu_idx] = 0;
        execute_strb_i[lsu_idx] = 0;
        load_query_addr_i[lsu_idx] = 0;
        load_query_sq_i[lsu_idx] = 0;
      end
      commit_fire_i = 0;
      load_query_valid_i = 0;
      flush_i = 0;
      br_recover_fire_i = 0;
      br_sq_tail_i = 0;
      #1;
    end
  endtask

  task automatic set_store(input int lane, input logic [SW:0] sq, input logic [RW:0] rob);
    begin
      dispatch_valid_i[lane] = 1;
      dispatch_uop_i[lane] = '0;
      dispatch_uop_i[lane].d.valid = 1;
      dispatch_uop_i[lane].d.fu = FU_ST;
      dispatch_uop_i[lane].sq_idx = sq;
      dispatch_uop_i[lane].rob_idx = rob;
    end
  endtask

  task automatic execute_store(
    input logic [SW:0] sq,
    input logic [RW:0] rob,
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0] strb
  );
    begin
      execute_valid_i[0] = 1;
      execute_uop_i[0] = '0;
      execute_uop_i[0].sq_idx = sq;
      execute_uop_i[0].rob_idx = rob;
      execute_addr_i[0] = addr;
      execute_data_i[0] = data;
      execute_strb_i[0] = strb;
      #1;
      assert (execute_wb_o[0].rob.valid);
      @(posedge clk_i); #1;
      execute_valid_i[0] = 0;
    end
  endtask

  initial begin
    clear_inputs();
    rst_ni = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1;
    @(negedge clk_i); #1;

    set_store(0, 0, 0); set_store(1, 1, 1);
    set_store(2, 2, 2); set_store(3, 3, 3);
    assert (dispatch_ready_o);
    dispatch_fire_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 4 && sq_tail_o == 4);

    execute_valid_i = 2'b11;
    for (int execute_idx = 0; execute_idx < NLSU; execute_idx++) begin
      execute_uop_i[execute_idx] = dispatch_uop_i[execute_idx];
      execute_uop_i[execute_idx].sq_idx = (SW+1)'(execute_idx);
      execute_uop_i[execute_idx].rob_idx = (RW+1)'(execute_idx);
      execute_addr_i[execute_idx] = DTIM_BASE + 32'h100;
    end
    execute_data_i[0] = 32'h1122_3344;
    execute_strb_i[0] = 4'hf;
    execute_data_i[1] = 32'h0000_bbaa;
    execute_strb_i[1] = 4'b0011;
    #1;
    assert (execute_wb_o[0].rob.valid && execute_wb_o[1].rob.valid);
    @(posedge clk_i); #1;
    execute_valid_i = '0;
    load_query_valid_i = '1;
    load_query_addr_i[0] = DTIM_BASE + 32'h100;
    load_query_sq_i[0] = 2;
    load_query_addr_i[1] = DTIM_BASE + 32'h100;
    load_query_sq_i[1] = 4;
    #1;
    assert (!load_older_unknown_o[0] && load_forward_mask_o[0] == 4'hf);
    assert (load_forward_data_o[0] == 32'h1122_bbaa);
    assert (load_older_unknown_o[1] && load_forward_mask_o[1] == 4'hf);
    assert (load_forward_data_o[1] == 32'h1122_bbaa);

    execute_store(2, 2, DTIM_BASE + 32'h200, 32'h5566_7788, 4'hf);
    execute_store(3, 3, DTIM_BASE + 32'h300, 32'h99aa_bbcc, 4'hf);
    clear_inputs();
    assert (commit_ready_o && commit_uop_o.rob_idx == 0);
    assert (commit_addr_o == DTIM_BASE + 32'h100 && commit_data_o == 32'h1122_3344);
    commit_fire_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (sq_head_o == 1 && occupancy_o == 3);

    br_recover_fire_i = 1;
    br_sq_tail_i = 2;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (sq_tail_o == 2 && occupancy_o == 1);
    assert (commit_ready_o && commit_uop_o.rob_idx == 1);
    commit_fire_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (occupancy_o == 0 && sq_head_o == sq_tail_o);

    execute_valid_i[0] = 1;
    execute_uop_i[0].sq_idx = 2;
    execute_uop_i[0].rob_idx = 2;
    #1;
    assert (!execute_wb_o[0].rob.valid);

    // Device stores block younger loads and are never forwarded.
    flush_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    set_store(0, sq_tail_o, 10);
    dispatch_fire_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    execute_store(sq_head_o, 10, 32'h0200_0000, 32'h0000_0001, 4'hf);
    load_query_valid_i[0] = 1;
    load_query_addr_i[0] = 32'h0200_0000;
    load_query_sq_i[0] = sq_tail_o;
    #1;
    assert (load_older_unknown_o[0] && load_forward_mask_o[0] == 0);
    flush_i = 1;
    #1;
    assert (!commit_ready_o);
    @(posedge clk_i); #1;
    clear_inputs();

    $display("PASS: tb_store_queue");
    $finish;
  end
endmodule
