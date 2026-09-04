# MYCORE Documentation

This directory describes the core without requiring readers to inspect RTL.

| Document | Scope |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Purpose, implemented specification, pipeline, and completion status |
| [MODULES.md](MODULES.md) | Responsibilities and interfaces of every synthesizable RTL module |
| [CORE_TOP.md](CORE_TOP.md) | Core-level data flow, recovery, memory ordering, and commit behavior |
| [SOC.md](SOC.md) | SoC hierarchy, memory map, SRAM banking, host loading, PMP, and interrupts |
| [VERIFICATION.md](VERIFICATION.md) | Test strategy, scripts, coverage, and latest verified results |
| [PERFORMANCE.md](PERFORMANCE.md) | CoreMark results, lane utilization, bottleneck counters, and roadmap |

## Current State

MYCORE is a bootable RV32IM out-of-order implementation with four-wide fetch,
decode, rename, dispatch, and commit. It has four integer issue positions, one
branch and one multiply/divide acceptance limit per cycle, and two stateful
LSUs. The SoC boots from ROM, loads ELF segments through a host port, wakes by
MSIP, executes from ITIM, and reports through `tohost`.

The implementation is functionally validated in simulation. It is not yet a
finished production CPU: RV32F/RV32C execution, caches, a dynamic branch
predictor, synthesis timing closure, formal verification, and physical SRAM
macros remain future work.

## Latest Measured State

- Simple ELF: 564 system cycles
- CoreMark timed cycles: 263,858
- CoreMark system IPC: 1.059870
- Engineering estimate: 3.789917 CoreMark/MHz
- CoreMark validation: passed, one iteration

The one-iteration result is for engineering comparison only and is not an
official reportable CoreMark score.
