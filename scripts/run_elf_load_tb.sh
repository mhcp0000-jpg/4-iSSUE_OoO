#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD="$ROOT/build/elf_load_tb_vlt"

export PATH="$ROOT/tools/msys64/ucrt64/bin:/usr/bin:$PATH"
mkdir -p "$BUILD"

"$ROOT/scripts/build_sw.sh"

verilator --cc --exe --main --timing --sv -Wall -Wno-fatal \
  -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET \
  --top-module tb_elf_load \
  --Mdir "$BUILD" \
  "$ROOT/rtl/soc_pkg.sv" \
  "$ROOT/rtl/csr_pkg.sv" \
  "$ROOT/rtl/mycore_pkg.sv" \
  "$ROOT/rtl/bootrom.sv" \
  "$ROOT/rtl/tim_ram.sv" \
  "$ROOT/rtl/clint.sv" \
  "$ROOT/rtl/pmp_checker.sv" \
  "$ROOT/rtl/mycore_soc.sv" \
  "$ROOT/tb/tb_elf_load.sv"

make --silent -C "$BUILD" -f Vtb_elf_load.mk \
  CXX="clang++ -stdlib=libc++ -std=c++20 -Wno-unused-command-line-argument -Wno-unknown-warning-option -Wno-macro-redefined" \
  LINK="clang++ -stdlib=libc++ -Wno-unused-command-line-argument"
"$BUILD/Vtb_elf_load.exe" +HOST_FILE="$ROOT/build/sw/simple.host"
