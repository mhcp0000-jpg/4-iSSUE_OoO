# SoC

## Hierarchy

`mycore_system` instantiates `mycore_core` and `mycore_soc`. External logic sees
only clock/reset, external interrupt, a 32-bit host access port, two 64-bit
mailboxes, and debug PC/ROB occupancy.

## Memory Map

| Region | Base | Size | Use |
| --- | ---: | ---: | --- |
| Boot ROM | `0x0000_1000` | 4 KiB | Reset and WFI sequence |
| CLINT | `0x0200_0000` | 64 KiB | MSIP, MTIMECMP, MTIME |
| ITIM | `0x8000_0000` | 128 KiB | Executable payload and constants |
| DTIM | `0x8002_0000` | 128 KiB | Data, stack, host mailboxes |

`tohost` is `0x8002_0000`; `fromhost` is `0x8002_0008`.

## TIM Organization

ITIM and DTIM each contain four interleaved 32-bit 1R1W synchronous banks.
The logical ports are two four-word instruction groups, LSU0, LSU1, and host.
Instruction groups allow two ordered line transactions to be resident. Four
words in a line map to four banks and complete as one 128-bit response.

LSU requests use fixed logical ports, preserving response ownership. Different
banks run concurrently; same-bank requests use round-robin arbitration. Writes
and reads to the same row are prevented from producing ambiguous data.

## Protection and Devices

Instruction PMP checks produce one error bit per fetched word plus an exact-PC
check. Each LSU has an independent data PMP checker. The host bypasses CPU PMP
so software images can be loaded before wakeup.

The CLINT has one physical CPU access path. LSU requests are deterministically
arbitrated onto it. Host and CPU interfaces can read/write MSIP, MTIME, and
MTIMECMP; interrupt outputs connect to machine-mode CSR logic.

## Boot Flow

1. Reset executes Boot ROM.
2. Boot code installs an ITIM trap vector and enables software interrupts.
3. The hart enters WFI.
4. DPI or text loader writes ELF `PT_LOAD` data through the host port.
5. Host sets MSIP.
6. The core wakes and executes the payload at `0x8000_0000`.
7. Software reports pass/fail through `tohost` and measurements through
   `fromhost`.
