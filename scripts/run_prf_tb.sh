#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/prf_tb_vlt"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET \
  --top-module tb_physical_regfile \
  --Mdir "$BUILD" \
  "$ROOT/rtl/soc_pkg.sv" \
  "$ROOT/rtl/mycore_pkg.sv" \
  "$ROOT/rtl/physical_regfile.sv" \
  "$ROOT/tb/tb_physical_regfile.sv"

make --silent -C "$BUILD" -f Vtb_physical_regfile.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_physical_regfile.exe"
