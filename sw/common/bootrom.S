#include "soc.h"

  .section .text.init, "ax", @progbits
  .globl _start
  .option push
  .option norvc
_start:
  lui   t0, %hi(ITIM_BASE)
  csrw  mtvec, t0
  li    t0, 8
  csrs  mie, t0
  csrs  mstatus, t0
1:
  wfi
  j     1b
  .option pop
