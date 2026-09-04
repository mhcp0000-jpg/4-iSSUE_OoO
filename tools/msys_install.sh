#!/bin/bash
set -x
TOOLS_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
M="$TOOLS_DIR/msys64"
# first run initializes keyring etc.
"$M/usr/bin/bash.exe" -lc 'pacman-key --init 2>&1 | tail -3; pacman-key --populate msys2 2>&1 | tail -3'
"$M/usr/bin/bash.exe" -lc 'pacman -Syu --noconfirm 2>&1 | tail -5'
"$M/usr/bin/bash.exe" -lc 'pacman -Syu --noconfirm 2>&1 | tail -5'
"$M/usr/bin/bash.exe" -lc 'pacman -S --noconfirm --needed make mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-clang mingw-w64-ucrt-x86_64-libc++ mingw-w64-ucrt-x86_64-verilator mingw-w64-ucrt-x86_64-iverilog 2>&1 | tail -15'
"$M/usr/bin/bash.exe" -lc 'export PATH=/ucrt64/bin:$PATH; which clang++ verilator iverilog make; verilator --version; iverilog -V | head -1; clang++ --version | head -1'
