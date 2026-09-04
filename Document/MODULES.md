# RTL Modules

## Packages and Top Levels

| Module/file | Responsibility |
| --- | --- |
| `soc_pkg.sv` | Memory map, TIM bank/port indices, address-range helpers |
| `csr_pkg.sv` | CSR addresses, PMP count, performance event identifiers |
| `mycore_pkg.sv` | Core widths, uop records, FU/op encodings, age helpers |
| `mycore_system.sv` | Top-level core/SoC wiring and external host interface |
| `mycore_core.sv` | Frontend, rename, scheduling, execution, recovery, and commit integration |
| `mycore_soc.sv` | ROM/TIM/CLINT/host/PMP interconnect and mailbox state |

## Frontend and Backend

| Module | Current behavior |
| --- | --- |
| `frontend_four` | Decoupled line requests, ordered metadata/FIFO state, static prediction, RAS, four-uop bundle generation |
| `decoder` | RV32 integer, M, CSR, F/C decode; unsupported operations become precise illegal uops |
| `rename_stage` | Four-wide RAT lookup/update, free-list allocation, eight branch checkpoints |
| `rob` | 64-entry allocation, completion merge, branch truncation, precise trap, four-wide retirement |
| `physical_regfile` | 128 registers, owner/epoch validation, writeback bypass, readiness tracking |
| `issue_queue` | Parameterized age selection; four-wide integer and two-wide strict memory configurations |

## Execution and Memory Ordering

| Module | Current behavior |
| --- | --- |
| `alu_branch_unit` | Integer ALU, compare, JAL/JALR, next-PC and misprediction generation |
| `muldiv_unit` | RV32M multiply/divide/remainder operations |
| `lsu_unit` | Stateful single-entry load ownership, forwarding merge, alignment/access exceptions, killed-response drain |
| `store_queue` | Speculative store allocation, dual address execution, dual load forwarding query, branch rewind |
| `store_commit_unit` | Scalar side-effecting store request at serialized ROB head |

## Privileged and SoC Blocks

| Module | Current behavior |
| --- | --- |
| `csr_file` | Machine CSRs, traps, interrupt state, counters, HPM selectors, PMP registers |
| `pmp_checker` | TOR/NA4/NAPOT range and R/W/X permission checks |
| `clint` | MSIP, MTIME, MTIMECMP, software/timer interrupt generation |
| `bootrom` | Reset program that configures trap/interrupt state and enters WFI |
| `sram_1r1w` | Synchronous FF-based 32-bit 1R1W SRAM replacement model |
| `banked_sram_1r1w` | Four-bank read/write arbitration, response ownership, round-robin conflicts |
| `rvc_expand` | Compressed expansion scaffolding; C execution remains disabled |

## Important Integration Contracts

- Dispatch is all-or-none across all allocated structures.
- Valid bundle lanes are a packed prefix in program order.
- Physical-register and memory responses are accepted only for matching owner,
  ROB tag, and recovery epoch.
- Memory responses stay assigned to the LSU that launched the request.
- Stores modify architectural memory only after reaching the ROB head.
- Instruction responses remain ordered and stale epochs are drained, not reused.
