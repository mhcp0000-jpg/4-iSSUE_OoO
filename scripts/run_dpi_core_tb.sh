#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/dpi_core_tb_v2"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

"$ROOT/scripts/build_sw.sh"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
  --top-module tb_dpi_core_system \
  --Mdir "$BUILD" \
  -f "$ROOT/rtl/files.f" \
  "$ROOT/tb/tb_dpi_core_system.sv" \
  "$ROOT/tb/dpi/elf_loader.cpp"

make --silent -C "$BUILD" -f Vtb_dpi_core_system.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined -Wno-inconsistent-dllimport -Wno-ignored-attributes" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_dpi_core_system.exe" +ELF_FILE="$ROOT/build/sw/simple.elf"
