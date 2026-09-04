#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/store_path_tb_vlt"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
  --top-module tb_store_path \
  --Mdir "$BUILD" \
  "$ROOT/rtl/soc_pkg.sv" \
  "$ROOT/rtl/csr_pkg.sv" \
  "$ROOT/rtl/mycore_pkg.sv" \
  "$ROOT/rtl/rob.sv" \
  "$ROOT/rtl/store_queue.sv" \
  "$ROOT/rtl/store_commit_unit.sv" \
  "$ROOT/rtl/bootrom.sv" \
  "$ROOT/rtl/sram_1r1w.sv" \
  "$ROOT/rtl/banked_sram_1r1w.sv" \
  "$ROOT/rtl/clint.sv" \
  "$ROOT/rtl/pmp_checker.sv" \
  "$ROOT/rtl/mycore_soc.sv" \
  "$ROOT/tb/tb_store_path.sv"

make --silent -C "$BUILD" -f Vtb_store_path.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_store_path.exe"
