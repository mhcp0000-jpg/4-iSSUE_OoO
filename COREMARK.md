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
| Timed cycles | 263,858 |
| System cycles after MSIP | 287,188 |
| Cycles per iteration | 263,858 |
| Retired IPC | 1.059891 |
| Engineering CoreMark/MHz estimate | 3.789917 |

The validation seed `0x3415, 0x3415, 0x66` also passed at 654,902 timed
cycles. Future performance comparisons should continue to use one iteration.

## Current Bottlenecks

- Forward taken branches and indirect JALR targets still mispredict.
- Each stateful LSU launches an external load one cycle after IQ capture.
- Serial stores and same-bank LSU conflicts still reduce memory throughput.

## Optimization History

| Configuration | Timed cycles | CoreMark/MHz | Change |
| --- | ---: | ---: | ---: |
| Static not-taken baseline | 654,795 | 1.527196 | - |
| Backward-taken/JAL prediction | 599,817 | 1.667175 | -8.4% cycles |
| 8-entry return-address stack | 595,444 | 1.679419 | -0.7% cycles |
| 128-bit fetch line buffer | 414,135 | 2.414672 | -30.4% cycles |
| Four-wide fetch/decode/dispatch | 261,917 | 3.818003 | -36.8% cycles |
| Two-outstanding fetch and dual LSU | 263,858 | 3.789917 | +0.7% cycles |

The simple ELF test improved from 1,454 to 564 execution cycles across these
changes.

The latest run retired 304,388 instructions in 287,188 system cycles and used
all four dispatch lanes in 62,120 cycles. The decoupled fetch path reduced
request and response wait counts to 11,657 cycles each. The additional LSU
capture stage currently offsets that gain on CoreMark.

Run with `scripts/run_coremark_tb.sh`. Use `scripts/fetch_coremark.sh` to obtain
the pinned benchmark source.
