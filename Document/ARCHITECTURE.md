# Architecture

## Purpose

MYCORE is an educational and engineering platform for a four-wide speculative
RV32 out-of-order core integrated with a small SRAM-based SoC. The immediate
goal is a correct and measurable RV32IM machine. The longer-term target adds
RV32F/RV32C execution, stronger prediction, caches, and implementation-quality
timing and verification.

## Implemented Specification

| Item | Current implementation |
| --- | --- |
| ISA | RV32IM plus Zicsr machine-mode CSR access |
| Advertised `misa` | I, M; F and C are disabled |
| Fetch | Four 32-bit instructions from a 128-bit line |
| Fetch transactions | Up to four frontend metadata entries, two SoC line slots |
| Decode/rename/dispatch | Four-wide, atomic packed-prefix bundle |
| Integer physical registers | 128 |
| ROB | 64 entries, four-wide allocate and commit |
| Branch checkpoints | 8 |
| Integer IQ | 24 entries, up to four selected operations |
| Memory IQ | 16 entries, two age-ordered candidates |
| Store queue | 16 entries, two execute/query ports, scalar commit |
| LSUs | 2 stateful load slots with fixed response ownership |
| Writeback | 10 validated completion ports |
| PMP | 16 entries |
| Privilege | Machine mode |

## Pipeline Flow

1. `frontend_four` requests sequential 128-bit lines and emits a packed bundle.
2. Prediction truncates the bundle after the first predicted-taken operation.
3. Four decoders produce RV32 uops and precise fetch/illegal exceptions.
4. Rename allocates physical destinations and branch checkpoints atomically.
5. ROB, integer IQ, memory IQ, and SQ allocate on one shared dispatch fire.
6. Ready integer uops issue out of order; memory candidates remain age ordered.
7. Results pass through owner/epoch-validated writeback ports.
8. The ROB commits up to four completed non-serial uops in order.
9. Stores, CSR operations, fences, traps, and returns are serialized at the head.

## Width Meaning

"Four-wide" currently means a maximum of four fetched, decoded, renamed,
dispatched, and committed instructions per cycle. Integer and memory issue
networks are independent, so the current backend can accept up to four integer
and two memory operations in one cycle. This aggregate maximum of six is wider
than a strict global four-issue definition and is an explicit item to resolve
when the final functional-unit scheduler policy is selected.

## Control Speculation

- Direct JAL is predicted taken.
- Conditional branches use backward-taken, forward-not-taken prediction.
- A 16-entry RAS predicts canonical returns.
- Eight rename checkpoints restore RAT/free-list state after misprediction.
- ROB, IQ, SQ, LSU, and frontend transactions carry recovery metadata.

## Completion Status

| Area | Status |
| --- | --- |
| RV32IM execution | Complete for current simulation target |
| Four-wide frontend/backend connection | Complete |
| Dual LSU/SQ/SoC path | Complete |
| Precise exceptions/CSR/PMP/CLINT | Complete for tested machine-mode cases |
| Host ELF boot flow | Complete |
| Dynamic branch predictor/BTB | Not implemented |
| Instruction/data cache | Not implemented |
| RV32F execution | Not implemented; decode scaffolding exists |
| RV32C execution | Not implemented; compressed encodings trap |
| Global four-issue arbitration | Not implemented; current FU networks are independent |
| Formal verification | Not implemented |
| Synthesis/STA/physical SRAM replacement | Not completed |
