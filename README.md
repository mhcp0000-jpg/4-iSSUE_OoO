# MYCORE

RV32IMFC four-issue out-of-order core and a small host-loadable SoC.

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

- RV32IMFC and compressed-instruction decode
- Four-wide speculative rename with a 128-entry unified physical register map
- Eight branch checkpoints with recovery epochs
- 64-entry, four-wide reorder buffer with ten completion ports
- Precise ROB exceptions, serialized commit, and branch recovery
- Boot ROM, 128 KiB ITIM, 128 KiB DTIM, CLINT MSIP, and host load port
- Machine-mode CSRs, F state, 64-bit counters, HPM events, and 16-entry PMP

## Simulation

The scripts use the project-local MSYS2 Verilator toolchain.

```sh
tools/msys64/usr/bin/bash.exe scripts/run_rename_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_rob_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_backend_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_soc_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_csr_tb.sh
tools/msys64/usr/bin/bash.exe scripts/run_pmp_tb.sh
```

Ordered synthesizable RTL sources are listed in `rtl/files.f`.
