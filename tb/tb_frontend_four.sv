`timescale 1ns/1ps

module tb_frontend_four;
  import mycore_pkg::*;

  logic clk_i, rst_ni, consume_i, sleeping_i, invalidate_i;
  logic redirect_valid_i, recover_valid_i;
  logic [31:0] redirect_pc_i, recover_ras_top_i;
  logic [RASW:0] recover_ras_sp_i;
  logic imem_req_valid_o, imem_req_ready_i;
  logic [31:0] imem_req_addr_o, pc_o;
  logic [1:0] imem_req_size_o;
  logic imem_rsp_valid_i, imem_rsp_ready_o;
  logic [127:0] imem_rsp_rdata_i;
  logic [3:0] imem_rsp_error_i;
  fetch_inst_t fetch_o [FW];
  logic [FW-1:0] rvc_illegal_o, fetch_fault_o, cross_word_o;

  frontend_four dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic accept_request(input logic [31:0] expected_addr);
    begin
      @(negedge clk_i);
      imem_req_ready_i = 1'b1;
      #1;
      assert (imem_req_valid_o && imem_req_addr_o == expected_addr)
        else $error("request expected=%08x valid=%0b actual=%08x pc=%08x hold=%0b hold_addr=%08x next=%08x",
                    expected_addr, imem_req_valid_o, imem_req_addr_o, pc_o,
                    dut.req_hold_valid_q, dut.req_hold_addr_q, dut.next_req_pc_q);
      @(posedge clk_i); #1;
      imem_req_ready_i = 1'b0;
    end
  endtask

  task automatic send_response(
    input logic [127:0] line,
    input logic [3:0] errors
  );
    begin
      @(negedge clk_i);
      imem_rsp_valid_i = 1'b1;
      imem_rsp_rdata_i = line;
      imem_rsp_error_i = errors;
      #1;
      while (!imem_rsp_ready_o) begin
        @(posedge clk_i); #1;
      end
      @(posedge clk_i); #1;
      imem_rsp_valid_i = 1'b0;
    end
  endtask

  task automatic pulse_redirect(input logic [31:0] address);
    begin
      @(negedge clk_i);
      redirect_valid_i = 1'b1;
      redirect_pc_i = address;
      @(posedge clk_i); #1;
      redirect_valid_i = 1'b0;
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
    imem_req_ready_i = 0;
    imem_rsp_valid_i = 0;
    imem_rsp_rdata_i = 0;
    imem_rsp_error_i = 0;

    rst_ni = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1;

    // Sequential line requests remain valid and advance every accepted cycle.
    @(negedge clk_i);
    imem_req_ready_i = 1'b1;
    #1;
    assert (imem_req_valid_o && imem_req_addr_o == RESET_PC);
    @(posedge clk_i); #1;
    assert (imem_req_valid_o && imem_req_addr_o == RESET_PC + 16);
    @(posedge clk_i); #1;
    imem_req_ready_i = 1'b0;

    send_response({4{32'h0000_0013}}, 4'b0000);
    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b1111);
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      assert (fetch_o[lane_idx].pc == RESET_PC + 32'(lane_idx * 4));
      assert (fetch_o[lane_idx].inst == 32'h0000_0013);
    end
    consume_i = 1'b1;
    @(posedge clk_i); #1;
    consume_i = 1'b0;
    assert (pc_o == RESET_PC + 16);

    send_response({4{32'h0000_0013}}, 4'b0000);
    assert (fetch_o[0].valid && fetch_o[0].pc == RESET_PC + 16);

    // A predicted-taken bundle cancels its already accepted sequential line.
    pulse_redirect(RESET_PC + 32'h20);
    accept_request(RESET_PC + 32'h20);
    accept_request(RESET_PC + 32'h30);
    send_response({32'h0000_0013, 32'h0000_0013,
                   32'h0000_0013, 32'h0080_006f}, 4'b0000);
    assert (fetch_o[0].valid && fetch_o[0].pred_taken &&
            fetch_o[0].pred_target == RESET_PC + 32'h28);
    consume_i = 1'b1;
    @(posedge clk_i); #1;
    consume_i = 1'b0;
    assert (pc_o == RESET_PC + 32'h28 && !fetch_o[0].valid);
    accept_request(RESET_PC + 32'h40);
    accept_request(RESET_PC + 32'h28);
    send_response({4{32'haaaa_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'hbbbb_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'h0000_0013}}, 4'b0000);
    assert (fetch_o[0].valid && fetch_o[0].pc == RESET_PC + 32'h28);

    // A lane-specific response error remains associated with its requested line.
    pulse_redirect(RESET_PC + 32'h40);
    accept_request(RESET_PC + 32'h30);
    accept_request(RESET_PC + 32'h40);
    send_response({4{32'hdddd_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'h0000_0013}}, 4'b0100);
    assert ({fetch_o[3].valid, fetch_o[2].valid,
             fetch_o[1].valid, fetch_o[0].valid} == 4'b0111);
    assert (fetch_fault_o == 4'b0100);

    // Repeated redirects explicitly cancel old metadata. Responses still drain
    // in acceptance order and only the final target can become fetch-visible.
    pulse_redirect(RESET_PC + 32'h100);
    accept_request(RESET_PC + 32'h50);
    accept_request(RESET_PC + 32'h100);
    accept_request(RESET_PC + 32'h110);
    pulse_redirect(RESET_PC + 32'h200);
    accept_request(RESET_PC + 32'h200);
    pulse_redirect(RESET_PC + 32'h300);
    send_response({4{32'h9999_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    accept_request(RESET_PC + 32'h300);

    send_response({4{32'haaaa_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'hbbbb_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'hcccc_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({4{32'h0000_0013}}, 4'b0000);
    assert (fetch_o[0].valid && fetch_o[0].pc == RESET_PC + 32'h300 &&
            fetch_o[0].inst == 32'h0000_0013);

    // Redirect recovery restores the speculative RAS used by return prediction.
    recover_valid_i = 1'b1;
    recover_ras_sp_i = 1;
    recover_ras_top_i = RESET_PC + 32'h480;
    pulse_redirect(RESET_PC + 32'h400);
    recover_valid_i = 1'b0;
    accept_request(RESET_PC + 32'h310);
    accept_request(RESET_PC + 32'h400);
    send_response({4{32'heeee_0013}}, 4'b0000);
    assert (!fetch_o[0].valid);
    send_response({{3{32'h0000_0013}}, 32'h0000_8067}, 4'b0000);
    assert (fetch_o[0].valid && fetch_o[0].pred_taken &&
            fetch_o[0].pred_target == RESET_PC + 32'h480);

    // Sleep invalidates prefetched state and resumes at the undispatched PC.
    sleeping_i = 1'b1;
    @(posedge clk_i); #1;
    assert (!fetch_o[0].valid && imem_req_valid_o &&
            imem_req_addr_o == RESET_PC + 32'h410);
    accept_request(RESET_PC + 32'h410);
    send_response({4{32'hffff_0013}}, 4'b0000);
    assert (!fetch_o[0].valid && !imem_req_valid_o);
    sleeping_i = 1'b0;
    accept_request(RESET_PC + 32'h400);

    $display("PASS: tb_frontend_four");
    $finish;
  end
endmodule
