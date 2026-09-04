`timescale 1ns/1ps

module tb_frontend_four;
  import mycore_pkg::*;

  logic clk_i, rst_ni, consume_i, sleeping_i, invalidate_i;
  logic redirect_valid_i, recover_valid_i;
  logic [31:0] redirect_pc_i, recover_ras_top_i;
  logic [RASW:0] recover_ras_sp_i;
  logic imem_valid_o, imem_ready_i;
  logic [31:0] imem_addr_o, pc_o;
  logic [1:0] imem_size_o;
  logic [127:0] imem_rdata_i;
  logic [3:0] imem_error_i;
  fetch_inst_t fetch_o [FW];
  logic [FW-1:0] rvc_illegal_o, fetch_fault_o, cross_word_o;

  frontend_four dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic redirect_to(
    input logic [31:0] address,
    input logic [127:0] line
  );
    begin
      redirect_valid_i = 1'b1;
      redirect_pc_i = address;
      invalidate_i = 1'b1;
      imem_rdata_i = line;
      @(posedge clk_i); #1;
      redirect_valid_i = 1'b0;
      invalidate_i = 1'b0;
      #1;
    end
  endtask

  initial begin
    consume_i = 0;
    sleeping_i = 0;
    invalidate_i = 0;
    redirect_valid_i = 0;
    redirect_pc_i = 0;
    recover_valid_i = 0;
    recover_ras_sp_i = 0;
    recover_ras_top_i = 0;
    imem_ready_i = 1;
    imem_rdata_i = {4{32'h0000_0013}};
    imem_error_i = 0;

    rst_ni = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1;
    #1;

    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b1111);
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      assert (fetch_o[lane_idx].pc == RESET_PC + 32'(lane_idx * 4));
      assert (fetch_o[lane_idx].inst == 32'h0000_0013);
    end
    consume_i = 1;
    @(posedge clk_i); #1;
    consume_i = 0;
    assert (pc_o == RESET_PC + 16);

    // A predicted-taken branch in lane 1 truncates lanes 2 and 3.
    redirect_to(RESET_PC,
                {{2{32'h0000_0013}}, 32'hfe00_0ee3, 32'h0000_0013});
    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b0011);
    assert (fetch_o[1].pred_taken && fetch_o[1].pred_target == RESET_PC);
    consume_i = 1;
    @(posedge clk_i); #1;
    consume_i = 0;
    assert (pc_o == RESET_PC);

    // A direct JAL in lane 2 emits a three-instruction prefix.
    redirect_to(RESET_PC + 32'h20,
                {32'h0000_0013, 32'h0080_006f,
                 32'h0000_0013, 32'h0000_0013});
    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b0111);
    assert (fetch_o[2].pred_taken &&
            fetch_o[2].pred_target == RESET_PC + 32'h30);

    // A lane-specific fetch error is precise and truncates younger lanes.
    redirect_to(RESET_PC + 32'h40, {4{32'h0000_0013}});
    imem_error_i = 4'b0100;
    #1;
    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b0111);
    assert (fetch_fault_o == 4'b0100);

    // Backpressure keeps the bundle and PC stable.
    imem_error_i = 0;
    repeat (2) begin
      @(posedge clk_i); #1;
      assert (pc_o == RESET_PC + 32'h40);
      assert ({fetch_o[3].valid, fetch_o[2].valid,
               fetch_o[1].valid, fetch_o[0].valid} == 4'b1111);
    end

    $display("PASS: tb_frontend_four");
    $finish;
  end
endmodule
