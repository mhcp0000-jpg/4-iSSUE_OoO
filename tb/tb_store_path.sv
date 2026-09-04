`timescale 1ns/1ps

module tb_store_path;
  import mycore_pkg::*;
  import csr_pkg::NPMP;
  import soc_pkg::*;

  logic clk_i, rst_ni, flush_i;
  ren_uop_t alloc_uop [FW];
  logic [FW-1:0] alloc_valid, sq_dispatch_valid;
  logic rob_alloc_ready, rob_alloc_fire, sq_dispatch_ready;
  rob_wb_t rob_wb [NWB];
  exec_wb_t sq_execute_wb, store_fault_wb;
  logic [FW-1:0] rob_commit_valid;
  ren_uop_t rob_commit_uop [FW];
  logic rob_serial_valid, rob_serial_ready, rob_recover_fire;
  ren_uop_t rob_serial_uop;
  logic rob_trap_valid;
  ren_uop_t rob_trap_uop;
  logic [3:0] rob_trap_cause;
  logic [31:0] rob_trap_tval;
  logic [RW:0] rob_head, rob_tail, rob_occupancy;
  logic [EW-1:0] rob_epoch;

  logic [SW:0] sq_head, sq_tail;
  logic sq_execute_valid;
  ren_uop_t sq_execute_uop, sq_commit_uop;
  logic [31:0] sq_execute_addr, sq_execute_data;
  logic [3:0] sq_execute_strb;
  logic sq_commit_ready, sq_commit_fire;
  logic [31:0] sq_commit_addr, sq_commit_data;
  logic [3:0] sq_commit_strb;
  logic [$clog2(NSQ+1)-1:0] sq_occupancy;

  logic store_dmem_valid, store_dmem_write, memory_gate;
  logic [31:0] store_dmem_addr, store_dmem_wdata;
  logic [1:0] store_dmem_size;
  logic [3:0] store_dmem_wstrb;
  logic store_dmem_ready, store_dmem_error;

  logic soc_dmem_valid, soc_dmem_ready, soc_dmem_error;
  logic [31:0] soc_dmem_rdata;
  logic host_valid_i, host_write_i, host_ready_o, host_error_o;
  logic [31:0] host_addr_i, host_wdata_i, host_rdata_o;
  logic [3:0] host_wstrb_i;
  logic [7:0] pmpcfg_i [NPMP];
  logic [31:0] pmpaddr_i [NPMP];
  logic irq_software_o, irq_timer_o;
  logic [63:0] time_o, tohost_o, fromhost_o;

  always_comb begin
    for (int wb_idx = 0; wb_idx < NWB; wb_idx++) rob_wb[wb_idx] = '0;
    rob_wb[0] = sq_execute_wb.rob;
    rob_wb[1] = store_fault_wb.rob;
    sq_commit_fire = rob_commit_valid[0] &&
                     (rob_commit_uop[0].d.fu == FU_ST);
    soc_dmem_valid = memory_gate && store_dmem_valid;
    store_dmem_ready = memory_gate && soc_dmem_ready;
    store_dmem_error = memory_gate && soc_dmem_error;
  end

  rob u_rob (
    .clk_i, .rst_ni, .alloc_i(alloc_uop), .alloc_valid_i(alloc_valid),
    .alloc_ready_o(rob_alloc_ready), .alloc_fire_i(rob_alloc_fire), .wb_i(rob_wb),
    .commit_valid_o(rob_commit_valid), .commit_uop_o(rob_commit_uop),
    .commit_ready_i(1'b1), .serial_ready_i(rob_serial_ready),
    .serial_valid_o(rob_serial_valid), .serial_uop_o(rob_serial_uop),
    .trap_valid_o(rob_trap_valid), .trap_uop_o(rob_trap_uop),
    .trap_cause_o(rob_trap_cause), .flush_i,
    .trap_tval_o(rob_trap_tval),
    .br_recover_valid_i(1'b0), .br_rob_idx_i('0), .br_epoch_i('0),
    .br_recover_fire_o(rob_recover_fire), .rob_head_o(rob_head),
    .rob_tail_o(rob_tail), .occupancy_o(rob_occupancy), .rob_epoch_o(rob_epoch)
  );

  store_queue u_sq (
    .clk_i, .rst_ni, .dispatch_valid_i(sq_dispatch_valid),
    .dispatch_uop_i(alloc_uop), .dispatch_ready_o(sq_dispatch_ready),
    .dispatch_fire_i(rob_alloc_fire), .sq_head_o(sq_head), .sq_tail_o(sq_tail),
    .execute_valid_i(sq_execute_valid), .execute_uop_i(sq_execute_uop),
    .execute_addr_i(sq_execute_addr), .execute_data_i(sq_execute_data),
    .execute_strb_i(sq_execute_strb), .execute_wb_o(sq_execute_wb),
    .commit_ready_o(sq_commit_ready), .commit_uop_o(sq_commit_uop),
    .commit_addr_o(sq_commit_addr), .commit_data_o(sq_commit_data),
    .commit_strb_o(sq_commit_strb), .commit_fire_i(sq_commit_fire),
    .load_query_valid_i(1'b0), .load_query_addr_i('0), .load_query_rob_i('0),
    .rob_head_i(rob_head), .load_older_unknown_o(), .load_forward_mask_o(),
    .load_forward_data_o(), .flush_i, .br_recover_fire_i(1'b0),
    .br_sq_tail_i('0), .occupancy_o(sq_occupancy)
  );

  store_commit_unit u_store_commit (
    .clk_i, .rst_ni, .cancel_i(flush_i), .serial_valid_i(rob_serial_valid),
    .serial_uop_i(rob_serial_uop), .commit_ready_i(1'b1), .commit_fire_i(sq_commit_fire),
    .other_serial_ready_i(1'b1), .sq_ready_i(sq_commit_ready),
    .sq_uop_i(sq_commit_uop), .sq_addr_i(sq_commit_addr),
    .sq_data_i(sq_commit_data), .sq_strb_i(sq_commit_strb),
    .dmem_valid_o(store_dmem_valid), .dmem_write_o(store_dmem_write),
    .dmem_addr_o(store_dmem_addr), .dmem_size_o(store_dmem_size),
    .dmem_wdata_o(store_dmem_wdata), .dmem_wstrb_o(store_dmem_wstrb),
    .dmem_ready_i(store_dmem_ready), .dmem_error_i(store_dmem_error),
    .serial_ready_o(rob_serial_ready), .fault_wb_o(store_fault_wb)
  );

  mycore_soc u_soc (
    .clk_i, .rst_ni, .imem_valid_i(1'b0), .imem_addr_i('0), .imem_size_i(2'd2),
    .imem_ready_o(), .imem_rdata_o(), .imem_error_o(),
    .dmem_valid_i(soc_dmem_valid), .dmem_write_i(store_dmem_write),
    .dmem_addr_i(store_dmem_addr), .dmem_size_i(store_dmem_size),
    .dmem_wdata_i(store_dmem_wdata), .dmem_wstrb_i(store_dmem_wstrb),
    .dmem_ready_o(soc_dmem_ready), .dmem_rdata_o(soc_dmem_rdata),
    .dmem_error_o(soc_dmem_error), .host_valid_i, .host_write_i,
    .host_addr_i, .host_wdata_i, .host_wstrb_i, .host_ready_o,
    .host_rdata_o, .host_error_o, .pmp_priv_m_i(1'b1),
    .pmpcfg_i, .pmpaddr_i, .irq_software_o, .irq_timer_o, .time_o,
    .tohost_o, .fromhost_o
  );

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      alloc_valid = '0;
      sq_dispatch_valid = '0;
      rob_alloc_fire = 0;
      for (int lane_idx = 0; lane_idx < FW; lane_idx++) alloc_uop[lane_idx] = '0;
      sq_execute_valid = 0;
      sq_execute_uop = '0;
      sq_execute_addr = 0;
      sq_execute_data = 0;
      sq_execute_strb = 0;
      flush_i = 0;
      host_valid_i = 0;
      host_write_i = 0;
      host_addr_i = 0;
      host_wdata_i = 0;
      host_wstrb_i = 0;
      #1;
    end
  endtask

  task automatic allocate_store(input logic [31:0] address_tag);
    begin
      alloc_uop[0] = '0;
      alloc_uop[0].d.valid = 1;
      alloc_uop[0].d.fu = FU_ST;
      alloc_uop[0].d.op = MEM_SW;
      alloc_uop[0].rob_idx = rob_tail;
      alloc_uop[0].epoch = rob_epoch;
      alloc_uop[0].sq_idx = sq_tail;
      alloc_uop[0].d.pc = address_tag;
      alloc_valid[0] = 1;
      sq_dispatch_valid[0] = 1;
      assert (rob_alloc_ready && sq_dispatch_ready);
      rob_alloc_fire = 1;
      @(posedge clk_i); #1;
      clear_inputs();
    end
  endtask

  task automatic execute_store(
    input logic [31:0] addr,
    input logic [31:0] data
  );
    begin
      sq_execute_uop = alloc_uop[0];
      sq_execute_uop.rob_idx = rob_tail - 1'b1;
      sq_execute_uop.sq_idx = sq_tail - 1'b1;
      sq_execute_uop.epoch = rob_epoch;
      sq_execute_valid = 1;
      sq_execute_addr = addr;
      sq_execute_data = data;
      sq_execute_strb = 4'hf;
      #1;
      assert (sq_execute_wb.rob.valid);
      @(posedge clk_i); #1;
      clear_inputs();
    end
  endtask

  task automatic host_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      host_valid_i = 1;
      host_addr_i = addr;
      #1;
      while (!host_ready_o) begin
        @(posedge clk_i); #1;
      end
      assert (host_ready_o && !host_error_o);
      data = host_rdata_o;
      host_valid_i = 0;
    end
  endtask

  logic [31:0] read_data;

  initial begin
    for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
      pmpcfg_i[pmp_idx] = 0;
      pmpaddr_i[pmp_idx] = 0;
    end
    memory_gate = 0;
    clear_inputs();
    rst_ni = 0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1;
    @(negedge clk_i); #1;

    allocate_store(32'h1000);
    execute_store(DTIM_BASE + 32'h100, 32'hdead_beef);
    assert (rob_serial_valid && !rob_serial_ready && store_dmem_valid);
    @(posedge clk_i); #1;
    assert (store_dmem_valid); // held while the memory gate is closed
    memory_gate = 1;
    #1;
    assert (rob_serial_ready && rob_commit_valid[0]);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 0 && sq_occupancy == 0);
    host_read(DTIM_BASE + 32'h100, read_data);
    assert (read_data == 32'hdead_beef);

    // Unmapped store returns SACCESS to the ROB and cannot retire.
    allocate_store(32'h1004);
    execute_store(32'h4000_0000, 32'h1234_5678);
    #1;
    assert (store_fault_wb.rob.valid && !rob_serial_ready && !rob_commit_valid[0]);
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_trap_valid && rob_trap_cause == EXC_SACCESS);
    assert (rob_trap_tval == 32'h4000_0000);
    assert (rob_occupancy == 1 && sq_occupancy == 1);
    flush_i = 1;
    @(posedge clk_i); #1;
    clear_inputs();
    assert (rob_occupancy == 0 && sq_occupancy == 0 && !store_dmem_valid);

    $display("PASS: tb_store_path");
    $finish;
  end
endmodule
