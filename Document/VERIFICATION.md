# Verification

## Current Method

Verification uses Verilator lint and directed SystemVerilog testbenches. The
repository-local MSYS2 toolchain builds tests through scripts in `scripts/`.

## Coverage Areas

| Area | Main scripts |
| --- | --- |
| Four-wide frontend/protocol | `run_frontend_tb.sh` |
| Rename/checkpoint recovery | `run_rename_tb.sh` |
| ROB allocate/commit/recovery | `run_rob_tb.sh` |
| PRF ownership/wakeup | `run_prf_tb.sh` |
| Integer/memory issue | `run_iq_tb.sh`, `run_backend_issue_tb.sh`, `run_mem_iq_tb.sh` |
| ALU/MUL/DIV | `run_execute_tb.sh` |
| LSU and dual LSU | `run_lsu_tb.sh`, `run_dual_lsu_tb.sh` |
| SQ/store commit | `run_sq_tb.sh`, `run_store_commit_tb.sh`, `run_store_path_tb.sh` |
| CSR/PMP | `run_csr_tb.sh`, `run_pmp_tb.sh` |
| SRAM/SoC/ELF | `run_sram_tb.sh`, `run_soc_tb.sh`, `run_elf_load_tb.sh` |
| End-to-end | `run_core_system_tb.sh`, `run_dpi_core_tb.sh` |
| Benchmark | `run_coremark_tb.sh` |

## Latest Verified Results

- Top-level Verilator lint: pass
- Directed non-CoreMark suite: pass
- Simple ELF hierarchy loader: pass, 564 cycles
- Simple ELF DPI loader: pass, 564 cycles
- CoreMark one-iteration validation: pass, 263,858 timed cycles

## Test Gaps

- No formal proof of ROB/IQ/SQ recovery invariants
- No randomized ISA differential testing against a reference simulator
- No multicore, debug module, virtual memory, or lower privilege tests
- No RV32F/RV32C execution tests because those extensions are disabled
- No synthesis, static timing analysis, CDC/RDC, power, or gate-level testing
- CoreMark run is an engineering one-iteration comparison, not official scoring
