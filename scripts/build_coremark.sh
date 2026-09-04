#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CM="$ROOT/ext/coremark"
TOOLCHAIN="$ROOT/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
BUILD="$ROOT/build/coremark"
ITERATIONS=${ITERATIONS:-1}
RUN_TYPE=${RUN_TYPE:-PERFORMANCE}

if [[ "$RUN_TYPE" == "PERFORMANCE" ]]; then
  RUN_DEFINE=-DPERFORMANCE_RUN=1
elif [[ "$RUN_TYPE" == "VALIDATION" ]]; then
  RUN_DEFINE=-DVALIDATION_RUN=1
else
  echo "RUN_TYPE must be PERFORMANCE or VALIDATION" >&2
  exit 1
fi

if [[ ! -f "$CM/core_main.c" ]]; then
  echo "Missing ext/coremark. Clone https://github.com/eembc/coremark.git there." >&2
  exit 1
fi

export PATH="$TOOLCHAIN:/usr/bin:$PATH"
mkdir -p "$BUILD"

FLAGS=(
  -march=rv32im_zicsr
  -mabi=ilp32
  -mcmodel=medany
  -ffreestanding
  -fno-builtin
  -fno-pic
  -O2
  -Wall
  -Wextra
  -ffunction-sections
  -fdata-sections
  "$RUN_DEFINE"
  -DITERATIONS="$ITERATIONS"
  -DTOTAL_DATA_SIZE=2000
  -I"$ROOT/sw/coremark"
  -I"$ROOT/sw/common"
  -I"$CM"
)

for source in core_list_join core_matrix core_state core_util; do
  riscv-none-elf-gcc "${FLAGS[@]}" -c "$CM/$source.c" -o "$BUILD/$source.o"
done
riscv-none-elf-gcc "${FLAGS[@]}" -Dmain=coremark_main \
  -c "$CM/core_main.c" -o "$BUILD/core_main.o"
riscv-none-elf-gcc "${FLAGS[@]}" -c "$ROOT/sw/coremark/core_portme.c" \
  -o "$BUILD/core_portme.o"
riscv-none-elf-gcc "${FLAGS[@]}" -c "$ROOT/sw/coremark/coremark_entry.c" \
  -o "$BUILD/coremark_entry.o"
riscv-none-elf-gcc "${FLAGS[@]}" -c "$ROOT/sw/common/crt0.S" -o "$BUILD/crt0.o"

riscv-none-elf-gcc -nostdlib -nostartfiles -march=rv32im_zicsr -mabi=ilp32 \
  -Wl,--build-id=none,--gc-sections -T "$ROOT/sw/common/payload.ld" \
  "$BUILD/crt0.o" "$BUILD/coremark_entry.o" "$BUILD/core_portme.o" \
  "$BUILD/core_main.o" "$BUILD/core_list_join.o" "$BUILD/core_matrix.o" \
  "$BUILD/core_state.o" "$BUILD/core_util.o" -o "$BUILD/coremark.elf"

riscv-none-elf-objdump -d "$BUILD/coremark.elf" > "$BUILD/coremark.dump"
riscv-none-elf-size "$BUILD/coremark.elf"
if command -v python >/dev/null 2>&1; then
  python "$ROOT/scripts/elf_to_host.py" "$BUILD/coremark.elf" "$BUILD/coremark.host"
fi
