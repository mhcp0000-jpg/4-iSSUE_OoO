`timescale 1ns/1ps

// RVC (RV32C, with F subset) -> 32-bit expansion
module rvc_expand (
  input  logic [15:0] c,
  output logic [31:0] o,
  output logic        illegal
);
  import mycore_pkg::*;
  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] opc);
    return {imm, rs1, f3, rd, opc};
  endfunction
  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3, input logic [6:0] opc);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], opc};
  endfunction
  function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
  endfunction
  function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
  endfunction
  function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] opc);
    return {f7, rs2, rs1, f3, rd, opc};
  endfunction

  logic [4:0] rdp, rs1p, rs2p, rd, rs2;
  logic [11:0] imm_ci;     // c.addi/li/andi
  logic [12:0] imm_cb;
  logic [20:0] imm_cj;
  logic [11:0] uimm_lw, uimm_lwsp, uimm_swsp, nzuimm_4spn, nzimm_16sp;
  logic [19:0] imm_lui;

  always_comb begin
    rdp  = {2'b01, c[4:2]};
    rs1p = {2'b01, c[9:7]};
    rs2p = {2'b01, c[4:2]};
    rd   = c[11:7];
    rs2  = c[6:2];
    imm_ci  = {{7{c[12]}}, c[6:2]};
    imm_cb  = {{5{c[12]}}, c[6:5], c[2], c[11:10], c[4:3], 1'b0};
    imm_cj  = {{10{c[12]}}, c[8], c[10:9], c[6], c[7], c[2], c[11], c[5:3], 1'b0};
    uimm_lw   = {5'b0, c[5], c[12:10], c[6], 2'b0};
    uimm_lwsp = {4'b0, c[3:2], c[12], c[6:4], 2'b0};
    uimm_swsp = {4'b0, c[8:7], c[12:9], 2'b0};
    nzuimm_4spn = {2'b0, c[10:7], c[12:11], c[5], c[6], 2'b0};
    nzimm_16sp  = {{3{c[12]}}, c[4:3], c[5], c[2], c[6], 4'b0};
    imm_lui   = {{15{c[12]}}, c[6:2]};
    o = 32'h0000_0013; // nop
    illegal = 1'b0;
    case (c[1:0])
      2'b00: begin
        case (c[15:13])
          3'b000: begin o = enc_i(nzuimm_4spn, 5'd2, 3'b000, rdp, 7'b0010011); illegal = (nzuimm_4spn == 0); end
          3'b010: o = enc_i(uimm_lw, rs1p, 3'b010, rdp, 7'b0000011);          // c.lw
          3'b011: o = enc_i(uimm_lw, rs1p, 3'b010, rdp, 7'b0000111);          // c.flw
          3'b110: o = enc_s(uimm_lw, rs2p, rs1p, 3'b010, 7'b0100011);         // c.sw
          3'b111: o = enc_s(uimm_lw, rs2p, rs1p, 3'b010, 7'b0100111);         // c.fsw
          default: illegal = 1'b1;
        endcase
      end
      2'b01: begin
        case (c[15:13])
          3'b000: o = enc_i(imm_ci, rd, 3'b000, rd, 7'b0010011);              // c.addi / c.nop
          3'b001: o = enc_j(imm_cj, 5'd1);                                     // c.jal
          3'b010: o = enc_i(imm_ci, 5'd0, 3'b000, rd, 7'b0010011);            // c.li
          3'b011: begin
            if (rd == 5'd2) begin o = enc_i(nzimm_16sp, 5'd2, 3'b000, 5'd2, 7'b0010011); illegal = (nzimm_16sp == 0); end
            else begin o = {imm_lui, rd, 7'b0110111}; illegal = (rd == 0) || ({c[12], c[6:2]} == 0); end
          end
          3'b100: begin
            case (c[11:10])
              2'b00: begin o = enc_r(7'b0000000, c[6:2], rs1p, 3'b101, rs1p, 7'b0010011); illegal = c[12]; end // c.srli
              2'b01: begin o = enc_r(7'b0100000, c[6:2], rs1p, 3'b101, rs1p, 7'b0010011); illegal = c[12]; end // c.srai
              2'b10: o = enc_i(imm_ci, rs1p, 3'b111, rs1p, 7'b0010011);                                        // c.andi
              2'b11: begin
                if (c[12]) illegal = 1'b1;
                else case (c[6:5])
                  2'b00: o = enc_r(7'b0100000, rs2p, rs1p, 3'b000, rs1p, 7'b0110011); // c.sub
                  2'b01: o = enc_r(7'b0000000, rs2p, rs1p, 3'b100, rs1p, 7'b0110011); // c.xor
                  2'b10: o = enc_r(7'b0000000, rs2p, rs1p, 3'b110, rs1p, 7'b0110011); // c.or
                  2'b11: o = enc_r(7'b0000000, rs2p, rs1p, 3'b111, rs1p, 7'b0110011); // c.and
                endcase
              end
            endcase
          end
          3'b101: o = enc_j(imm_cj, 5'd0);                                     // c.j
          3'b110: o = enc_b(imm_cb, 5'd0, rs1p, 3'b000);                       // c.beqz
          3'b111: o = enc_b(imm_cb, 5'd0, rs1p, 3'b001);                       // c.bnez
        endcase
      end
      2'b10: begin
        case (c[15:13])
          3'b000: begin o = enc_r(7'b0000000, c[6:2], rd, 3'b001, rd, 7'b0010011); illegal = c[12]; end // c.slli
          3'b010: begin o = enc_i(uimm_lwsp, 5'd2, 3'b010, rd, 7'b0000011); illegal = (rd == 0); end   // c.lwsp
          3'b011: o = enc_i(uimm_lwsp, 5'd2, 3'b010, rd, 7'b0000111);                                  // c.flwsp
          3'b100: begin
            if (!c[12]) begin
              if (rs2 == 0) begin o = enc_i(12'd0, rd, 3'b000, 5'd0, 7'b1100111); illegal = (rd == 0); end // c.jr
              else o = enc_r(7'b0, rs2, 5'd0, 3'b000, rd, 7'b0110011);                                   // c.mv
            end else begin
              if (rs2 == 0 && rd == 0) o = 32'h0010_0073;                                                // c.ebreak
              else if (rs2 == 0) o = enc_i(12'd0, rd, 3'b000, 5'd1, 7'b1100111);                         // c.jalr
              else o = enc_r(7'b0, rs2, rd, 3'b000, rd, 7'b0110011);                                     // c.add
            end
          end
          3'b110: o = enc_s(uimm_swsp, rs2, 5'd2, 3'b010, 7'b0100011);         // c.swsp
          3'b111: o = enc_s(uimm_swsp, rs2, 5'd2, 3'b010, 7'b0100111);         // c.fswsp
          default: illegal = 1'b1;
        endcase
      end
      default: illegal = 1'b1; // 32-bit: not handled here
    endcase
  end
endmodule
