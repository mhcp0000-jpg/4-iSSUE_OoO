`timescale 1ns/1ps

module tb_backend_issue;
  import mycore_pkg::*;

  localparam int IQ_DEPTH = 8;
  localparam int ISSUE_WIDTH = 2;

  logic clk_i, rst_ni;
  dec_uop_t dec_i [FW];
  ren_uop_t ren_uop [FW];
  logic dec_ready, dispatch_fire, backend_ready;
  logic [FW-1:0] dispatch_valid;
  logic rob_ready, iq_ready, rob_recover_fire;
  logic [RW:0] rob_head, rob_tail, rob_occupancy;
  logic [EW-1:0] rob_epoch;

  exec_wb_t exec_wb [NWB];
  rob_wb_t rob_wb [NWB];
  logic [NWB-1:0] wb_accepted;
  logic [PW-1:0] prf_raddr [NREAD];
  logic [31:0] prf_rdata [NREAD];
  logic [NREAD-1:0] prf_rready;
  logic [FW-1:0] src1_ready, src2_ready, src3_ready;

  logic [ISSUE_WIDTH-1:0] issue_valid, issue_accept;
  ren_uop_t issue_uop [ISSUE_WIDTH];
  logic [$clog2(IQ_DEPTH+1)-1:0] iq_occupancy;

  logic [FW-1:0] rob_commit_valid, rename_commit_valid;
  ren_uop_t rob_commit_uop [FW];
  logic [5:0] rename_commit_rd [FW];
  logic [PW-1:0] rename_commit_pdst [FW], rename_commit_prev [FW];
  logic [$clog2(NPRF+1)-1:0] free_count;
  logic [$clog2(NCKPT+1)-1:0] ckpt_free_count;

  logic flush_i, br_valid, br_mispredict;
  logic [CW-1:0] br_ckpt;
  logic [RW:0] br_rob;
  logic [EW-1:0] br_epoch;
  logic rob_trap_valid;
  ren_uop_t rob_trap_uop;
  logic rob_serial_valid;
  ren_uop_t rob_serial_uop;
  logic [3:0] rob_trap_cause;

  always_comb begin
    backend_ready = rob_ready && iq_ready;
    for (int lane_idx = 0; lane_idx < FW; lane_idx++) begin
      prf_raddr[lane_idx*3] = ren_uop[lane_idx].ps1;
      prf_raddr[lane_idx*3+1] = ren_uop[lane_idx].ps2;
      prf_raddr[lane_idx*3+2] = ren_uop[lane_idx].ps3;
      src1_ready[lane_idx] = prf_rready[lane_idx*3];
      src2_ready[lane_idx] = prf_rready[lane_idx*3+1];
      src3_ready[lane_idx] = prf_rready[lane_idx*3+2];

      rename_commit_valid[lane_idx] = rob_commit_valid[lane_idx] &&
                                       rob_commit_uop[lane_idx].d.rd_valid &&
                                       (rob_commit_uop[lane_idx].d.rd != 0);
      rename_commit_rd[lane_idx] = rob_commit_uop[lane_idx].d.rd;
      rename_commit_pdst[lane_idx] = rob_commit_uop[lane_idx].pdst;
      rename_commit_prev[lane_idx] = rob_commit_uop[lane_idx].prev_pdst;
    end
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
      rob_wb[wb_idx] = exec_wb[wb_idx].rob;
  end

  rename_stage u_rename (
    .clk_i, .rst_ni, .dec_i, .dec_ready_o(dec_ready), .ren_o(ren_uop),
    .dispatch_valid_o(dispatch_valid), .dispatch_ready_i(backend_ready),
    .dispatch_fire_o(dispatch_fire), .rob_tail_i(rob_tail), .sq_tail_i('0),
    .rob_head_i(rob_head), .epoch_i(rob_epoch), .flush_i,
    .br_resolve_valid_i(br_valid), .br_mispredict_i(br_mispredict),
    .br_ckpt_id_i(br_ckpt), .br_rob_idx_i(br_rob), .br_epoch_i(br_epoch),
    .commit_valid_i(rename_commit_valid), .commit_rd_i(rename_commit_rd),
    .commit_pdst_i(rename_commit_pdst), .commit_prev_pdst_i(rename_commit_prev),
    .free_count_o(free_count), .ckpt_free_count_o(ckpt_free_count)
  );

  rob u_rob (
    .clk_i, .rst_ni, .alloc_i(ren_uop), .alloc_valid_i(dispatch_valid),
    .alloc_ready_o(rob_ready), .alloc_fire_i(dispatch_fire), .wb_i(rob_wb),
    .commit_valid_o(rob_commit_valid), .commit_uop_o(rob_commit_uop),
    .commit_ready_i(1'b1), .serial_ready_i(1'b1),
    .serial_valid_o(rob_serial_valid), .serial_uop_o(rob_serial_uop),
    .trap_valid_o(rob_trap_valid), .trap_uop_o(rob_trap_uop),
    .trap_cause_o(rob_trap_cause), .flush_i,
    .br_recover_valid_i(br_valid && br_mispredict), .br_rob_idx_i(br_rob),
    .br_epoch_i(br_epoch), .br_recover_fire_o(rob_recover_fire),
    .rob_head_o(rob_head), .rob_tail_o(rob_tail), .occupancy_o(rob_occupancy),
    .rob_epoch_o(rob_epoch)
  );

  physical_regfile u_prf (
    .clk_i, .rst_ni, .alloc_fire_i(dispatch_fire), .alloc_valid_i(dispatch_valid),
    .alloc_uop_i(ren_uop), .wb_i(exec_wb), .wb_accepted_o(wb_accepted),
    .raddr_i(prf_raddr), .rdata_o(prf_rdata), .rready_o(prf_rready)
  );

  issue_queue #(.DEPTH(IQ_DEPTH), .ISSUE_WIDTH(ISSUE_WIDTH)) u_iq (
    .clk_i, .rst_ni, .dispatch_valid_i(dispatch_valid), .dispatch_uop_i(ren_uop),
    .dispatch_src1_ready_i(src1_ready), .dispatch_src2_ready_i(src2_ready),
    .dispatch_src3_ready_i(src3_ready), .dispatch_ready_o(iq_ready),
    .dispatch_fire_i(dispatch_fire), .wb_i(exec_wb), .wb_accepted_i(wb_accepted),
    .issue_valid_o(issue_valid), .issue_uop_o(issue_uop),
    .issue_accept_i(issue_accept), .flush_i,
    .br_recover_fire_i(rob_recover_fire), .br_rob_idx_i(br_rob),
    .rob_head_i(rob_head), .occupancy_o(iq_occupancy)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) dec_i[lane_idx] = '0;
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++) exec_wb[wb_idx] = '0;
      issue_accept = '0;
      flush_i = 1'b0;
      br_valid = 1'b0;
      br_mispredict = 1'b0;
      br_ckpt = '0;
      br_rob = '0;
      br_epoch = '0;
      #1;
    end
  endtask

  task automatic set_alu(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [5:0] rs1,
    input logic use1,
    input logic [5:0] rd
  );
    begin
      dec_i[lane_idx] = '0;
      dec_i[lane_idx].valid = 1'b1;
      dec_i[lane_idx].fu = FU_ALU;
      dec_i[lane_idx].rs1 = rs1;
      dec_i[lane_idx].use1 = use1;
      dec_i[lane_idx].rd = rd;
      dec_i[lane_idx].rd_valid = (rd != 0);
    end
  endtask

  task automatic set_wb(
    input logic [$clog2(NWB)-1:0] port_idx,
    input logic [RW:0] rob_idx,
    input logic [EW-1:0] epoch,
    input logic [PW-1:0] pdst,
    input logic [31:0] data
  );
    begin
      exec_wb[port_idx] = '0;
      exec_wb[port_idx].rob.valid = 1'b1;
      exec_wb[port_idx].rob.rob_idx = rob_idx;
      exec_wb[port_idx].rob.epoch = epoch;
      exec_wb[port_idx].write_pdst = 1'b1;
      exec_wb[port_idx].pdst = pdst;
      exec_wb[port_idx].data = data;
    end
  endtask

  initial begin
    clear_inputs();
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i); #1;

    // x1 -> x2 -> x3 is blocked in the IQ; independent x4 can issue.
    set_alu(0, 0, 0, 1);
    set_alu(1, 1, 1, 2);
    set_alu(2, 2, 1, 3);
    set_alu(3, 0, 0, 4);
    #1;
    assert (dec_ready && dispatch_fire);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 4 && iq_occupancy == 4 && free_count == 60);
    assert (issue_uop[0].rob_idx == 0 && issue_uop[1].rob_idx == 3);

    issue_accept[0] = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    set_wb(0, 0, 0, 64, 10);
    issue_accept = 2'b11;
    #1;
    assert (issue_uop[0].rob_idx == 1 && issue_uop[1].rob_idx == 3);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_head == 1);

    set_wb(0, 1, 0, 65, 20);
    set_wb(1, 3, 0, 67, 40);
    issue_accept[0] = 1'b1;
    #1;
    assert (issue_uop[0].rob_idx == 2);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_head == 2 && iq_occupancy == 0);

    set_wb(0, 2, 0, 66, 30);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 0 && rob_head == 4 && free_count == 64);
    set_alu(0, 1, 1, 0);
    set_alu(1, 2, 1, 0);
    set_alu(2, 3, 1, 0);
    set_alu(3, 4, 1, 0);
    #1;
    assert (prf_rdata[0] == 10 && prf_rdata[3] == 20 &&
            prf_rdata[6] == 30 && prf_rdata[9] == 40);
    clear_inputs();

    // A raw stale recovery is rejected by the ROB and never reaches the IQ.
    set_alu(0, 0, 0, 5);
    set_alu(1, 5, 1, 6);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (iq_occupancy == 2 && rob_occupancy == 2);
    br_valid = 1'b1;
    br_mispredict = 1'b1;
    br_rob = 0;
    br_epoch = 0;
    #1;
    assert (!rob_recover_fire);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (iq_occupancy == 2 && rob_occupancy == 2);

    flush_i = 1'b1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (iq_occupancy == 0 && rob_occupancy == 0);

    $display("PASS: tb_backend_issue");
    $finish;
  end
endmodule
