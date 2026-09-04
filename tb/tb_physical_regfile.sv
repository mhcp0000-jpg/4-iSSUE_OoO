`timescale 1ns/1ps

module tb_physical_regfile;
  import mycore_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic alloc_fire_i;
  logic [FW-1:0] alloc_valid_i;
  ren_uop_t alloc_uop_i [FW];
  exec_wb_t wb_i [NWB];
  logic [NWB-1:0] wb_accepted_o;
  logic [PW-1:0] raddr_i [NREAD];
  logic [31:0] rdata_o [NREAD];
  logic [NREAD-1:0] rready_o;

  physical_regfile dut (.*);

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      alloc_fire_i = 1'b0;
      alloc_valid_i = '0;
      for (int lane_idx = 0; lane_idx < FW; lane_idx++)
        alloc_uop_i[lane_idx] = '0;
      for (int wb_idx = 0; wb_idx < NWB; wb_idx++)
        wb_i[wb_idx] = '0;
      for (int read_idx = 0; read_idx < NREAD; read_idx++)
        raddr_i[read_idx] = '0;
      #1;
    end
  endtask

  task automatic set_alloc(
    input logic [$clog2(FW)-1:0] lane_idx,
    input logic [PW-1:0] pdst,
    input logic [RW:0] rob_idx,
    input logic [EW-1:0] epoch
  );
    begin
      alloc_valid_i[lane_idx] = 1'b1;
      alloc_uop_i[lane_idx] = '0;
      alloc_uop_i[lane_idx].d.valid = 1'b1;
      alloc_uop_i[lane_idx].d.rd_valid = 1'b1;
      alloc_uop_i[lane_idx].d.rd = 6'(lane_idx + 1);
      alloc_uop_i[lane_idx].pdst = pdst;
      alloc_uop_i[lane_idx].rob_idx = rob_idx;
      alloc_uop_i[lane_idx].epoch = epoch;
      alloc_fire_i = 1'b1;
    end
  endtask

  task automatic set_wb(
    input logic [$clog2(NWB)-1:0] port_idx,
    input logic [PW-1:0] pdst,
    input logic [RW:0] rob_idx,
    input logic [EW-1:0] epoch,
    input logic [31:0] data
  );
    begin
      wb_i[port_idx] = '0;
      wb_i[port_idx].rob.valid = 1'b1;
      wb_i[port_idx].rob.rob_idx = rob_idx;
      wb_i[port_idx].rob.epoch = epoch;
      wb_i[port_idx].write_pdst = 1'b1;
      wb_i[port_idx].pdst = pdst;
      wb_i[port_idx].data = data;
    end
  endtask

  initial begin
    clear_inputs();
    rst_ni = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i); #1;
    raddr_i[0] = 0;
    raddr_i[1] = 1;
    raddr_i[2] = 64;
    #1;
    assert (rready_o[0] && rdata_o[0] == 0);
    assert (rready_o[1] && !rready_o[2]);

    set_alloc(0, 64, 0, 0); set_alloc(1, 65, 1, 0);
    set_alloc(2, 66, 2, 0); set_alloc(3, 67, 3, 0);
    raddr_i[0] = 64; raddr_i[1] = 65;
    #1;
    assert (!rready_o[0] && !rready_o[1]);
    @(posedge clk_i); #1;
    clear_inputs();

    // Matching writes bypass to reads before the active edge.
    raddr_i[0] = 64; raddr_i[1] = 65;
    set_wb(0, 64, 0, 0, 32'h1111_2222);
    set_wb(1, 65, 1, 0, 32'h3333_4444);
    #1;
    assert (wb_accepted_o[1:0] == 2'b11);
    assert (rready_o[0] && rdata_o[0] == 32'h1111_2222);
    assert (rready_o[1] && rdata_o[1] == 32'h3333_4444);
    @(posedge clk_i); #1;
    clear_inputs();

    // A stale epoch cannot update or wake the current owner.
    raddr_i[0] = 66;
    set_wb(0, 66, 2, 1, 32'hdead_beef);
    #1;
    assert (!wb_accepted_o[0] && !rready_o[0]);
    @(posedge clk_i); #1;
    clear_inputs();

    // Faulting and duplicate writes never publish invalid wakeups.
    raddr_i[0] = 66;
    set_wb(0, 66, 2, 0, 32'hdead_beef);
    wb_i[0].rob.excp = 1'b1;
    #1;
    assert (!wb_accepted_o[0] && !rready_o[0]);
    clear_inputs();
    raddr_i[0] = 65;
    set_wb(0, 65, 1, 0, 32'h1111_1111);
    set_wb(1, 65, 1, 0, 32'h2222_2222);
    #1;
    assert (wb_accepted_o[0] && !wb_accepted_o[1]);
    assert (rdata_o[0] == 32'h1111_1111);
    clear_inputs();

    // Reallocation wins over a same-cycle completion from the old owner.
    raddr_i[0] = 64;
    set_wb(0, 64, 0, 0, 32'haaaa_aaaa);
    set_alloc(0, 64, 4, 1);
    #1;
    assert (!wb_accepted_o[0] && !rready_o[0]);
    @(posedge clk_i); #1;
    clear_inputs();
    raddr_i[0] = 64;
    set_wb(0, 64, 0, 0, 32'hbbbb_bbbb);
    #1;
    assert (!wb_accepted_o[0] && !rready_o[0]);
    clear_inputs();
    raddr_i[0] = 64;
    set_wb(0, 64, 4, 1, 32'h5555_aaaa);
    #1;
    assert (wb_accepted_o[0] && rready_o[0] && rdata_o[0] == 32'h5555_aaaa);

    // Physical zero remains immutable even if malformed writeback arrives.
    clear_inputs();
    raddr_i[0] = 0;
    set_wb(0, 0, 0, 0, 32'hffff_ffff);
    #1;
    assert (!wb_accepted_o[0] && rready_o[0] && rdata_o[0] == 0);

    $display("PASS: tb_physical_regfile");
    $finish;
  end
endmodule
