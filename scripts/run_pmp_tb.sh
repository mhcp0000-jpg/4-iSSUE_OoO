#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/pmp_tb_vlt"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  --top-module tb_pmp_checker \
  --Mdir "$BUILD" \
  "$ROOT/rtl/csr_pkg.sv" \
  "$ROOT/rtl/pmp_checker.sv" \
  "$ROOT/tb/tb_pmp_checker.sv"

make --silent -C "$BUILD" -f Vtb_pmp_checker.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_pmp_checker.exe"
