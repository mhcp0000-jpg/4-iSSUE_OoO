# Performance

## Current CoreMark Result

| Metric | Value |
| --- | ---: |
| Timed cycles | 263,858 |
| System cycles | 287,188 |
| Retired instructions | 304,382 |
| IPC | 1.059870 |
| CoreMark/MHz engineering estimate | 3.789917 |

Configuration: one performance-seed iteration, GCC 15.2.0, `-O2`, RV32IM
Zicsr. This is not an official reportable CoreMark score.

## Width Utilization

| Dispatch width | Cycles |
| ---: | ---: |
| 1 | 23,104 |
| 2 | 31,517 |
| 3 | 20,850 |
| 4 | 62,119 |

| Commit width | Cycles |
| ---: | ---: |
| 0 | 119,429 |
| 1 | 85,239 |
| 2 | 46,508 |
| 3 | 17,921 |
| 4 | 18,091 |

All four commit lanes are active. Retired instruction totals by commit lane are
167,759, 82,520, 36,012, and 18,091 respectively.

## Commit Lane Versus Dispatch Origin

| Commit lane | Origin 0 | Origin 1 | Origin 2 | Origin 3 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 60,970 | 41,432 | 39,322 | 26,035 |
| 1 | 28,902 | 29,930 | 13,771 | 9,917 |
| 2 | 19,030 | 7,256 | 6,616 | 3,110 |
| 3 | 2,858 | 10,605 | 2,171 | 2,457 |

Origin totals are 111,760, 89,223, 61,880, and 41,519. Lanes 2 and 3 are
therefore used materially, although control flow and line alignment favor lower
lanes.

## Bottleneck Counters

| Counter | Cycles |
| --- | ---: |
| Frontend empty | 107,211 |
| Backend stall with valid bundle | 42,387 |
| ROB-related dispatch stall | 21,630 |
| Integer-IQ dispatch stall | 9,062 |
| Memory-IQ dispatch stall | 568 |
| SQ dispatch stall | 6 |
| Commit idle with nonempty ROB | 101,519 |
| Serial store wait | 11,208 |
| Memory head blocked | 13,398 |
| Both LSUs busy | 36,463 |
| Exactly one LSU busy | 71,715 |
| Older-store-unknown load block | 5,027 |

Average/max occupancy: ROB 11.30/64, integer IQ 4.88/24, memory IQ 2.29/16,
SQ 0.77/16. Capacity is not the dominant average limitation; dependencies,
serial stores, redirects, and instruction availability dominate.

## Current Problems and Next Work

1. Frontend empty time is the largest visible loss. There is no instruction
   cache, and redirects discard useful lines. A first direct-mapped line-cache
   experiment exposed stale/full-queue interactions and was reverted rather
   than committed in a broken state. The next design needs explicit cache fill
   and response-drain rules independent of the ordered line FIFO.
2. Static prediction still produces 9,760 misprediction cycles/events out of
   66,396 branch event cycles. A BTB plus dynamic conditional predictor is the
   next low-risk frontend feature.
3. Commit is idle for 101,519 cycles. Dependency-chain latency, branch recovery,
   and stateful load latency should be split into additional counters.
4. ROB dispatch stalls include both full capacity and serialized-head gating;
   these causes should be separated before changing allocation policy.
5. LSU capture adds a cycle before external SRAM launch. A safe bypass requires
   a decoupled data-memory request interface to avoid combinational ready loops.
6. Performance event bits currently count event cycles, not the number of two
   simultaneous LSU operations.

## Optimization History

| Configuration | Timed cycles | CoreMark/MHz |
| --- | ---: | ---: |
| Static not-taken baseline | 654,795 | 1.527196 |
| Backward-taken/JAL prediction | 599,817 | 1.667175 |
| Return-address stack | 595,444 | 1.679419 |
| 128-bit fetch line | 414,135 | 2.414672 |
| Four-wide frontend | 261,917 | 3.818003 |
| Two-outstanding fetch and dual LSU | 263,858 | 3.789917 |
