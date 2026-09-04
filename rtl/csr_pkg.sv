`timescale 1ns/1ps

package csr_pkg;
  localparam int NPMP = 16;

  localparam logic [11:0] CSR_FFLAGS        = 12'h001;
  localparam logic [11:0] CSR_FRM           = 12'h002;
  localparam logic [11:0] CSR_FCSR          = 12'h003;
  localparam logic [11:0] CSR_MSTATUS       = 12'h300;
  localparam logic [11:0] CSR_MISA          = 12'h301;
  localparam logic [11:0] CSR_MIE           = 12'h304;
  localparam logic [11:0] CSR_MTVEC         = 12'h305;
  localparam logic [11:0] CSR_MSTATUSH      = 12'h310;
  localparam logic [11:0] CSR_MCOUNTINHIBIT = 12'h320;
  localparam logic [11:0] CSR_MHPMEVENT3    = 12'h323;
  localparam logic [11:0] CSR_MHPMEVENT31   = 12'h33f;
  localparam logic [11:0] CSR_MSCRATCH      = 12'h340;
  localparam logic [11:0] CSR_MEPC          = 12'h341;
  localparam logic [11:0] CSR_MCAUSE        = 12'h342;
  localparam logic [11:0] CSR_MTVAL         = 12'h343;
  localparam logic [11:0] CSR_MIP           = 12'h344;
  localparam logic [11:0] CSR_PMPCFG0       = 12'h3a0;
  localparam logic [11:0] CSR_PMPCFG3       = 12'h3a3;
  localparam logic [11:0] CSR_PMPADDR0      = 12'h3b0;
  localparam logic [11:0] CSR_PMPADDR15     = 12'h3bf;

  localparam logic [11:0] CSR_MCYCLE        = 12'hb00;
  localparam logic [11:0] CSR_MINSTRET      = 12'hb02;
  localparam logic [11:0] CSR_MHPMCOUNTER3  = 12'hb03;
  localparam logic [11:0] CSR_MHPMCOUNTER31 = 12'hb1f;
  localparam logic [11:0] CSR_MCYCLEH       = 12'hb80;
  localparam logic [11:0] CSR_MINSTRETH     = 12'hb82;
  localparam logic [11:0] CSR_MHPMCOUNTER3H = 12'hb83;
  localparam logic [11:0] CSR_MHPMCOUNTER31H= 12'hb9f;

  localparam logic [11:0] CSR_CYCLE         = 12'hc00;
  localparam logic [11:0] CSR_TIME          = 12'hc01;
  localparam logic [11:0] CSR_INSTRET       = 12'hc02;
  localparam logic [11:0] CSR_HPMCOUNTER3   = 12'hc03;
  localparam logic [11:0] CSR_HPMCOUNTER31  = 12'hc1f;
  localparam logic [11:0] CSR_CYCLEH        = 12'hc80;
  localparam logic [11:0] CSR_TIMEH         = 12'hc81;
  localparam logic [11:0] CSR_INSTRETH      = 12'hc82;
  localparam logic [11:0] CSR_HPMCOUNTER3H  = 12'hc83;
  localparam logic [11:0] CSR_HPMCOUNTER31H = 12'hc9f;

  localparam logic [11:0] CSR_MVENDORID     = 12'hf11;
  localparam logic [11:0] CSR_MARCHID       = 12'hf12;
  localparam logic [11:0] CSR_MIMPID        = 12'hf13;
  localparam logic [11:0] CSR_MHARTID       = 12'hf14;
  localparam logic [11:0] CSR_MCONFIGPTR    = 12'hf15;

  localparam logic [31:0] MISA_RV32IM = 32'h4000_1100;
  localparam logic [31:0] MISA_RV32IMF = 32'h4000_1120;
  localparam logic [31:0] MISA_RV32IMFC = 32'h4000_1124;
  localparam logic [31:0] MIP_MSIP = 32'h0000_0008;
  localparam logic [31:0] MIP_MTIP = 32'h0000_0080;
  localparam logic [31:0] MIP_MEIP = 32'h0000_0800;
  localparam logic [31:0] MIP_MACHINE_MASK = MIP_MSIP | MIP_MTIP | MIP_MEIP;

  localparam logic [4:0] IRQ_M_SOFTWARE = 5'd3;
  localparam logic [4:0] IRQ_M_TIMER    = 5'd7;
  localparam logic [4:0] IRQ_M_EXTERNAL = 5'd11;

  localparam logic [5:0] CSR_OP_RW  = 6'd0;
  localparam logic [5:0] CSR_OP_RS  = 6'd1;
  localparam logic [5:0] CSR_OP_RC  = 6'd2;
  localparam logic [5:0] CSR_OP_RWI = 6'd3;
  localparam logic [5:0] CSR_OP_RSI = 6'd4;
  localparam logic [5:0] CSR_OP_RCI = 6'd5;

  localparam logic [4:0] PERF_NONE          = 5'd0;
  localparam logic [4:0] PERF_BRANCH        = 5'd1;
  localparam logic [4:0] PERF_BRANCH_MISPRED= 5'd2;
  localparam logic [4:0] PERF_LOAD          = 5'd3;
  localparam logic [4:0] PERF_STORE         = 5'd4;
  localparam logic [4:0] PERF_ICACHE_MISS   = 5'd5;
  localparam logic [4:0] PERF_DCACHE_MISS   = 5'd6;
endpackage
