`timescale 1ns/1ps

module tb_pmp_checker;
  import csr_pkg::*;

  logic [31:0] addr_i;
  logic [1:0] size_i;
  logic access_r_i, access_w_i, access_x_i, priv_m_i;
  logic [7:0] pmpcfg_i [NPMP];
  logic [31:0] pmpaddr_i [NPMP];
  logic matched_o, allow_o;

  pmp_checker dut (.*);

  task automatic clear_pmp;
    begin
      for (int pmp_idx = 0; pmp_idx < NPMP; pmp_idx++) begin
        pmpcfg_i[pmp_idx] = '0;
        pmpaddr_i[pmp_idx] = '0;
      end
    end
  endtask

  task automatic check_access(
    input logic [31:0] addr,
    input logic [1:0] size,
    input logic read_access,
    input logic write_access,
    input logic execute_access,
    input logic machine_mode,
    input logic expected_match,
    input logic expected_allow
  );
    begin
      addr_i = addr;
      size_i = size;
      access_r_i = read_access;
      access_w_i = write_access;
      access_x_i = execute_access;
      priv_m_i = machine_mode;
      #1;
      assert (matched_o == expected_match && allow_o == expected_allow)
        else $fatal(1, "PMP addr=%08x match=%0d allow=%0d", addr, matched_o, allow_o);
    end
  endtask

  initial begin
    clear_pmp();
    check_access(32'h1234_0000, 2, 1, 0, 0, 1, 0, 1);
    check_access(32'h1234_0000, 2, 1, 0, 0, 0, 0, 0);

    // Locked TOR region [0x1000, 0x2000) is read-only in M mode.
    pmpaddr_i[0] = 32'h1000 >> 2;
    pmpaddr_i[1] = 32'h2000 >> 2;
    pmpcfg_i[1] = 8'h89;
    check_access(32'h1000, 2, 1, 0, 0, 1, 1, 1);
    check_access(32'h1000, 2, 0, 1, 0, 1, 1, 0);
    check_access(32'h1000, 2, 0, 0, 1, 1, 1, 0);
    check_access(32'h0ffc, 2, 1, 0, 0, 1, 0, 1);
    check_access(32'h1fff, 2, 1, 0, 0, 1, 1, 0);

    // An unlocked match does not restrict M mode, but applies below M.
    clear_pmp();
    pmpaddr_i[0] = 32'h1800 >> 2;
    pmpcfg_i[0] = 8'h10;
    check_access(32'h1800, 2, 0, 1, 0, 1, 1, 1);
    check_access(32'h1800, 2, 0, 1, 0, 0, 1, 0);

    // Locked 16-byte NAPOT region at 0x8000_0000 permits R/W, not X.
    clear_pmp();
    pmpaddr_i[0] = (32'h8000_0000 >> 2) | 32'h1;
    pmpcfg_i[0] = 8'h9b;
    check_access(32'h8000_0000, 2, 1, 0, 0, 1, 1, 1);
    check_access(32'h8000_000c, 2, 0, 1, 0, 1, 1, 1);
    check_access(32'h8000_0000, 2, 0, 0, 1, 1, 1, 0);
    check_access(32'h8000_0010, 2, 1, 0, 0, 1, 0, 1);

    // Lowest numbered overlapping entry wins.
    pmpaddr_i[1] = (32'h8000_0000 >> 2) | 32'h1;
    pmpcfg_i[1] = 8'h9f;
    check_access(32'h8000_0000, 2, 0, 0, 1, 1, 1, 0);

    $display("PASS: tb_pmp_checker");
    $finish;
  end
endmodule
