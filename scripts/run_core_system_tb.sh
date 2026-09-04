#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/core_system_tb_vlt"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

"$ROOT/scripts/build_sw.sh"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
  --top-module tb_core_system \
  --Mdir "$BUILD" \
  -f "$ROOT/rtl/files.f" \
  "$ROOT/tb/tb_core_system.sv"

make --silent -C "$BUILD" -f Vtb_core_system.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_core_system.exe" +HOST_FILE="$ROOT/build/sw/simple.host"
