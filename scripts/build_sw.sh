#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TOOLCHAIN="$ROOT/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
BUILD="$ROOT/build/sw"

export PATH="$TOOLCHAIN:/usr/bin:$PATH"
mkdir -p "$BUILD"

COMMON_FLAGS=(
  -march=rv32imfc_zicsr
  -mabi=ilp32f
  -mcmodel=medany
  -ffreestanding
  -fno-builtin
  -fno-pic
  -nostdlib
  -nostartfiles
  -Os
  -Wall
  -Wextra
  -ffunction-sections
  -fdata-sections
  -I"$ROOT/sw/common"
)

riscv-none-elf-gcc "${COMMON_FLAGS[@]}" \
  -Wl,--build-id=none,--gc-sections \
  -T "$ROOT/sw/common/bootrom.ld" \
  "$ROOT/sw/common/bootrom.S" \
  -o "$BUILD/bootrom.elf"
riscv-none-elf-objcopy -O binary "$BUILD/bootrom.elf" "$BUILD/bootrom.bin"
riscv-none-elf-objdump -d "$BUILD/bootrom.elf" > "$BUILD/bootrom.dump"
python "$ROOT/scripts/check_bootrom.py" "$BUILD/bootrom.bin" "$ROOT/rtl/bootrom.sv"

riscv-none-elf-gcc "${COMMON_FLAGS[@]}" \
  -Wl,--build-id=none,--gc-sections \
  -T "$ROOT/sw/common/payload.ld" \
  "$ROOT/sw/common/crt0.S" \
  "$ROOT/sw/tests/simple.c" \
  -o "$BUILD/simple.elf"
riscv-none-elf-objdump -d -S "$BUILD/simple.elf" > "$BUILD/simple.dump"

python "$ROOT/scripts/elf_to_host.py" "$BUILD/simple.elf" "$BUILD/simple.host"
riscv-none-elf-size "$BUILD/bootrom.elf" "$BUILD/simple.elf"
