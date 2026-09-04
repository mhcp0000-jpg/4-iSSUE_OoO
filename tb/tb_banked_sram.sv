`timescale 1ns/1ps

module tb_banked_sram;
  localparam int PORTS = 4;

  logic clk_i, rst_ni;
  logic [PORTS-1:0] read_valid_i, read_ready_o;
  logic [31:0] read_offset_i [PORTS], read_data_o [PORTS];
  logic [PORTS-1:0] write_valid_i, write_ready_o;
  logic [31:0] write_offset_i [PORTS], write_data_i [PORTS];
  logic [3:0] write_strb_i [PORTS];

  banked_sram_1r1w #(.BYTES(1024), .BANKS(4), .PORTS(PORTS)) dut (.*);

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic clear_inputs;
    begin
      read_valid_i = '0;
      write_valid_i = '0;
      for (int port_idx = 0; port_idx < PORTS; port_idx++) begin
        read_offset_i[port_idx] = '0;
        write_offset_i[port_idx] = '0;
        write_data_i[port_idx] = '0;
        write_strb_i[port_idx] = '0;
      end
      #1;
    end
  endtask

  initial begin
    clear_inputs();
    rst_ni = 0;
    write_valid_i[0] = 1;
    write_offset_i[0] = 0;
    write_data_i[0] = 32'hffff_ffff;
    write_strb_i[0] = 4'hf;
    #1;
    assert (write_ready_o == 0);
    clear_inputs();
    repeat (2) @(posedge clk_i);
    rst_ni = 1;
    @(negedge clk_i);

    // Four distinct banks accept four writes and reads in parallel.
    for (int port_idx = 0; port_idx < PORTS; port_idx++) begin
      write_valid_i[port_idx] = 1'b1;
      write_offset_i[port_idx] = port_idx * 4;
      write_data_i[port_idx] = 32'h1111_0000 + port_idx;
      write_strb_i[port_idx] = 4'hf;
    end
    #1;
    assert (write_ready_o == 4'b1111);
    @(posedge clk_i); #1;
    clear_inputs();
    for (int port_idx = 0; port_idx < PORTS; port_idx++) begin
      read_valid_i[port_idx] = 1'b1;
      read_offset_i[port_idx] = port_idx * 4;
    end
    #1;
    assert (read_ready_o == 0);
    @(posedge clk_i); #1;
    assert (read_ready_o == 4'b1111);
    for (int port_idx = 0; port_idx < PORTS; port_idx++)
      assert (read_data_o[port_idx] == 32'h1111_0000 + port_idx);
    clear_inputs();

    // Same-bank conflict grants the highest port, then services the waiter.
    read_valid_i[0] = 1;
    read_offset_i[0] = 32'h20;
    read_valid_i[3] = 1;
    read_offset_i[3] = 32'h10;
    @(posedge clk_i); #1;
    assert (read_ready_o[3] && !read_ready_o[0])
      else $fatal(1, "same-bank first response ready=%b", read_ready_o);
    read_valid_i[3] = 0;
    @(posedge clk_i); #1;
    assert (read_ready_o[0]);
    clear_inputs();

    // Different rows may read/write together; same row gives the write priority.
    read_valid_i[0] = 1;
    read_offset_i[0] = 0;
    write_valid_i[1] = 1;
    write_offset_i[1] = 0;
    write_data_i[1] = 32'haaaa_5555;
    write_strb_i[1] = 4'hf;
    #1;
    assert (write_ready_o[1]);
    @(posedge clk_i); #1;
    write_valid_i[1] = 0;
    @(posedge clk_i); #1;
    assert (read_ready_o[0] && read_data_o[0] == 32'haaaa_5555);

    $display("PASS: tb_banked_sram");
    $finish;
  end
endmodule
