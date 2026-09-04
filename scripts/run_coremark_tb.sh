#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/coremark_tb_vlt"
cd "$ROOT"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

ITERATIONS=1 "$ROOT/scripts/build_coremark.sh"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
  --top-module tb_coremark_system \
  --Mdir "$BUILD" \
  -f "$ROOT/rtl/files.f" \
  "$ROOT/tb/tb_coremark_system.sv" \
  "$ROOT/tb/dpi/elf_loader.cpp"

make --silent -C "$BUILD" -f Vtb_coremark_system.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined -Wno-inconsistent-dllimport -Wno-ignored-attributes" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_coremark_system.exe" +ELF_FILE="$ROOT/build/coremark/coremark.elf"
