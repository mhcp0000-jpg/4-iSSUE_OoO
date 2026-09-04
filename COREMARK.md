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
| Timed cycles | 261,917 |
| System cycles after MSIP | 278,293 |
| Cycles per iteration | 261,917 |
| Retired IPC | 1.093768 |
| Engineering CoreMark/MHz estimate | 3.818003 |

The validation seed `0x3415, 0x3415, 0x66` also passed at 654,902 timed
cycles. Future performance comparisons should continue to use one iteration.

## Current Bottlenecks

- Forward taken branches and indirect JALR targets still mispredict.
- The memory issue queue is conservative and single-issue.
- The synchronous ITIM supplies at most one 128-bit line every two cycles.

## Optimization History

| Configuration | Timed cycles | CoreMark/MHz | Change |
| --- | ---: | ---: | ---: |
| Static not-taken baseline | 654,795 | 1.527196 | - |
| Backward-taken/JAL prediction | 599,817 | 1.667175 | -8.4% cycles |
| 8-entry return-address stack | 595,444 | 1.679419 | -0.7% cycles |
| 128-bit fetch line buffer | 414,135 | 2.414672 | -30.4% cycles |
| Four-wide fetch/decode/dispatch | 261,917 | 3.818003 | -36.8% cycles |

The simple ELF test improved from 1,454 to 618 execution cycles across these
changes.

The four-wide run retired 304,388 instructions in 278,293 system cycles. It
dispatched four instructions in 53,482 of 123,202 active dispatch cycles,
confirming that all four frontend and backend lanes are exercised.

Run with `scripts/run_coremark_tb.sh`. Use `scripts/fetch_coremark.sh` to obtain
the pinned benchmark source.
