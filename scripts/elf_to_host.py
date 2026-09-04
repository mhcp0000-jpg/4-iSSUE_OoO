#!/usr/bin/env python3
import argparse
import struct
from pathlib import Path

ITIM_BASE = 0x80000000
ITIM_END = 0x80020000
DTIM_BASE = 0x80020000
DTIM_END = 0x80040000


def mapped(address: int) -> bool:
    return ITIM_BASE <= address < ITIM_END or DTIM_BASE <= address < DTIM_END


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert RV32 ELF PT_LOAD data to host writes")
    parser.add_argument("elf", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    image = args.elf.read_bytes()
    if image[:4] != b"\x7fELF" or image[4] != 1 or image[5] != 1:
        raise SystemExit("expected a little-endian ELF32 image")

    machine = struct.unpack_from("<H", image, 18)[0]
    if machine != 243:
        raise SystemExit(f"expected EM_RISCV, got {machine}")

    entry, phoff = struct.unpack_from("<II", image, 24)
    phentsize, phnum = struct.unpack_from("<HH", image, 42)
    memory: dict[int, int] = {}

    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, _, _ = struct.unpack_from(
            "<IIIIIIII", image, offset
        )
        if p_type != 1 or p_memsz == 0:
            continue
        address = p_paddr or p_vaddr
        if not mapped(address) or not mapped(address + p_memsz - 1):
            raise SystemExit(f"PT_LOAD 0x{address:08x}+0x{p_memsz:x} is outside ITIM/DTIM")
        segment = image[p_offset : p_offset + p_filesz]
        for byte_offset in range(p_memsz):
            memory[address + byte_offset] = segment[byte_offset] if byte_offset < p_filesz else 0

    words: dict[int, tuple[int, int]] = {}
    for address, byte_value in memory.items():
        word_address = address & ~3
        word_value, strobe = words.get(word_address, (0, 0))
        lane = address & 3
        word_value = (word_value & ~(0xFF << (lane * 8))) | (byte_value << (lane * 8))
        words[word_address] = (word_value, strobe | (1 << lane))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii", newline="\n") as output:
        output.write(f"E {entry:08x} 00000000 0\n")
        for address in sorted(words):
            value, strobe = words[address]
            output.write(f"W {address:08x} {value:08x} {strobe:x}\n")

    print(f"entry=0x{entry:08x} writes={len(words)} bytes={len(memory)}")


if __name__ == "__main__":
    main()
