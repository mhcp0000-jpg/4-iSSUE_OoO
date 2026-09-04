# Core Top-Level Behavior

## Frontend

`mycore_core` connects a decoupled instruction request/response channel to
`frontend_four`. The frontend tracks accepted request PC and epoch metadata,
buffers completed lines, and emits at most four sequential 32-bit instructions.
Redirect, invalidate, sleep, and predicted-taken events cancel younger metadata;
physical responses are still drained to preserve ordering.

## Rename and Allocation

One `dispatch_fire` updates rename state, ROB, PRF ownership, integer/memory IQs,
and SQ together. Same-bundle RAW dependencies use the newly allocated physical
destination and are marked unready until writeback. Resource checks count the
exact number of destinations, branches, memory operations, and stores.

## Integer Execution

The integer IQ chooses up to four oldest ready operations. Four ALU positions
exist, but only one branch and one MUL/DIV are accepted per cycle. Branch
results are registered and validated against ROB tag/epoch before recovery.

## Memory Execution

The memory IQ presents two oldest source-ready operations. Available LSU slots
capture them in age order. A captured load owns its external memory lane until
completion, latches forwarding bytes, and drains a killed response without
writeback. The SQ has two independent store-execute and load-query ports.

Committed stores use lane 0 only after reaching the serialized ROB head and do
not preempt an outstanding LSU0 load. Different-bank LSU requests can complete
in parallel; same-bank requests are arbitrated in the TIM.

## Writeback and Commit

Ten completion positions carry ROB index and epoch. PRF writes additionally
check the current physical-register owner. The ROB merges completion, retires a
program-order prefix up to width four, and stops at exceptions or serialized
operations. CSR, fence, store, trap, MRET, and WFI behavior is therefore precise.

## Recovery

- Branch recovery removes younger ROB/IQ/SQ entries.
- Rename restores checkpointed RAT and free-list state.
- Younger in-flight LSU operations are killed but drain external responses.
- Frontend request epochs prevent old-path lines from becoming executable.
- Full control flush restores the committed architectural mapping.
