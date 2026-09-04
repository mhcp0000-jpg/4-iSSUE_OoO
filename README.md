# MYCORE

RV32IM four-issue out-of-order bring-up core and a small host-loadable SoC.

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
- Four-wide speculative rename with a 128-entry unified physical register map
- Eight branch checkpoints with recovery epochs
- 64-entry, four-wide reorder buffer with ten completion ports
- Precise ROB exceptions, serialized commit, and branch recovery
- 128-entry physical register file with validated ten-port wakeup
- Age-ordered integer and strict-order memory issue queues
- Integer ALU/branch, RV32M multiply/divide, LSU, and speculative store queue
- Four-bank 1R1W synchronous-SRAM ITIM/DTIM, Boot ROM, CLINT, and host Xbar port
- Machine-mode CSRs, configurable F state, 64-bit counters, HPM events, and 16-entry PMP
- Boot-to-WFI, host ELF load, MSIP wakeup, and `tohost` end-to-end execution

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
tools/msys64/usr/bin/bash.exe scripts/run_store_commit_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_store_path_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_core_system_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_sram_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_dpi_core_tb.sh
```

Ordered synthesizable RTL sources are listed in `rtl/files.f`.
