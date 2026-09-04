# MYCORE

RV32IM four-issue out-of-order bring-up core and a small host-loadable SoC.

Detailed architecture, module, SoC, verification, performance, and completion
status is indexed in [`Document/README.md`](Document/README.md).

## Memory Map

| Region | Base | Size |
| --- | ---: | ---: |
| Boot ROM | `0x0000_1000` | 4 KiB |
| CLINT | `0x0200_0000` | 64 KiB |
| ITIM | `0x8000_0000` | 128 KiB |
| DTIM | `0x8002_0000` | 128 KiB |

The CLINT software-interrupt register is at `0x0200_0000`, `mtimecmp` is at
`0x0200_4000`, and `mtime` is at `0x0200_BFF8`. The 64-bit
`tohost` and `fromhost` mailboxes are at `0x8002_0000` and `0x8002_0008`.
The authoritative constants and address-decode helpers are in
`rtl/soc_pkg.sv`.

## Implemented

- RV32IM execution; F/C decode exists but is not advertised until execution support lands
- Four-wide fetch, decode, speculative rename, dispatch, integer issue, and commit
- Two-outstanding, 128-bit four-bank fetch with static prediction and a 16-entry RAS
- Eight branch checkpoints with recovery epochs
- 64-entry, four-wide reorder buffer with ten completion ports
- Precise ROB exceptions, serialized commit, and branch recovery
- 128-entry physical register file with validated ten-port wakeup
- Age-ordered integer and two-wide strict-order memory issue queues
- Integer ALU/branch, RV32M multiply/divide, two stateful LSUs, and speculative SQ
- Four-bank 1R1W synchronous-SRAM ITIM/DTIM, Boot ROM, CLINT, and host Xbar port
- Machine-mode CSRs, configurable F state, 64-bit counters, HPM events, and 16-entry PMP
- Boot-to-WFI, host ELF load, MSIP wakeup, and `tohost` end-to-end execution

## Current Performance

- Simple ELF: 564 cycles
- CoreMark: 263,858 timed cycles, one iteration
- Measured system IPC: 1.059870
- Engineering estimate: 3.789917 CoreMark/MHz
- Four-instruction dispatch: 62,119 cycles
- Four-instruction commit: 18,091 cycles

## Current Problems

- Frontend was empty for 107,211 CoreMark system cycles. There is no instruction
  cache, so redirects and line refills remain the largest observed loss.
- Static branch prediction recorded 9,760 misprediction event cycles.
- Commit was idle with a nonempty ROB for 101,519 cycles.
- Stateful LSUs preserve response ownership but add one cycle before an external
  SRAM request. Both LSUs were busy for 36,463 cycles.
- The current integer and memory issue networks are independent and can accept
  more than four aggregate uops. A strict global four-issue policy is not yet
  implemented.
- RV32F/RV32C execution, dynamic prediction, caches, formal verification,
  synthesis timing closure, and physical SRAM macros are not complete.

See [`Document/PERFORMANCE.md`](Document/PERFORMANCE.md) for all counters and
[`Document/ARCHITECTURE.md`](Document/ARCHITECTURE.md) for completion status.

## Simulation

The scripts use the project-local MSYS2 Verilator toolchain.

```sh
tools/msys64/usr/bin/bash.exe scripts/run_rename_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_rob_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_backend_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_soc_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_csr_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_pmp_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_elf_load_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_prf_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_iq_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_backend_issue_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_execute_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_sq_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_lsu_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_dual_lsu_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_mem_iq_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_store_commit_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_store_path_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_core_system_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_sram_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_dpi_core_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_coremark_tb.sh
```

Ordered synthesizable RTL sources are listed in `rtl/files.f`.
The one-iteration CoreMark baseline is recorded in `COREMARK.md`.
