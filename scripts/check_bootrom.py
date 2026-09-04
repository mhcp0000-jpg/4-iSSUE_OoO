#!/usr/bin/env python3
import re
import struct
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: check_bootrom.py <bootrom.bin> <bootrom.sv>")

    binary = Path(sys.argv[1]).read_bytes()
    rtl = Path(sys.argv[2]).read_text(encoding="ascii")
    if len(binary) % 4:
        raise SystemExit("boot ROM binary is not word aligned")

    elf_words = list(struct.unpack(f"<{len(binary) // 4}I", binary))
    rtl_words = [
        int(value.replace("_", ""), 16)
        for value in re.findall(r"\d+:\s+rdata_o\s*=\s*32'h([0-9a-fA-F_]+)", rtl)
    ]
    if elf_words != rtl_words:
        raise SystemExit(f"boot ROM mismatch: ELF={elf_words!r} RTL={rtl_words!r}")
    print(f"bootrom image matches RTL ({len(elf_words)} words)")


if __name__ == "__main__":
    main()
