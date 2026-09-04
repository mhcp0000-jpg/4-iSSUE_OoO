# CoreMark Baseline

This is a bring-up measurement, not an official reportable CoreMark score.
The run uses one iteration rather than the required ten-second reporting window.

## Configuration

- CoreMark revision: `1f483d5b8316753a742cbf5590caf5bd0a4e4777`
- Seeds: performance `0, 0, 0x66`
- Iterations: 1
- Compiler: GCC 15.2.0, `-O2 -march=rv32im_zicsr -mabi=ilp32`
- Memory: 128 KiB ITIM and DTIM, each four-bank 32-bit 1R1W SRAM

## Result

| Metric | Value |
| --- | ---: |
| Timed cycles | 654,795 |
| System cycles after MSIP | 693,153 |
| Cycles per iteration | 654,795 |
| Engineering CoreMark/MHz estimate | 1.527196 |

The validation seed `0x3415, 0x3415, 0x66` also passed at 654,902 timed
cycles. Future performance comparisons should continue to use one iteration.

## Current Bottlenecks

- The frontend supplies one instruction rather than four.
- Every taken branch is currently predicted not taken.
- The memory issue queue is conservative and single-issue.
- Synchronous SRAM reads add latency that is not yet hidden by fetch buffering.

Run with `scripts/run_coremark_tb.sh`. Use `scripts/fetch_coremark.sh` to obtain
the pinned benchmark source.
