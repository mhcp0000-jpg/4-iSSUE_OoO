#include "soc.h"

  .section .text.init, "ax", @progbits
  .globl _start
  .option push
  .option norvc
_start:
  li    t0, CLINT_MSIP_ADDR
  sw    zero, 0(t0)
  la    t0, trap_fail
  csrw  mtvec, t0

  .option push
  .option norelax
  la    gp, __global_pointer$
  .option pop
  la    sp, __stack_top

  la    t0, __bss_start
  la    t1, __bss_end
.Lclear_bss:
  bgeu  t0, t1, .Lrun_main
  sw    zero, 0(t0)
  addi  t0, t0, 4
  j     .Lclear_bss

.Lrun_main:
  call  main
  slli  a0, a0, 1
  ori   a0, a0, 1
  li    t0, TOHOST_ADDR
  sw    zero, 4(t0)
  sw    a0, 0(t0)
.Ldone:
  wfi
  j     .Ldone
  .option pop

  .section .text.trap, "ax", @progbits
  .align 2
  .globl trap_fail
trap_fail:
  csrr  a0, mcause
  slli  a0, a0, 1
  ori   a0, a0, 3
  li    t0, TOHOST_ADDR
  sw    zero, 4(t0)
  sw    a0, 0(t0)
  j     .Ldone
