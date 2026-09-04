#include <cstdint>
#include <fstream>
#include <map>
#include <string>
#include <vector>

namespace {
struct Write {
    uint32_t address;
    uint32_t data;
    uint8_t strobe;
};

std::vector<Write> writes;
std::size_t cursor;
uint32_t entry_point;

uint16_t read16(const std::vector<uint8_t>& image, std::size_t offset) {
    return static_cast<uint16_t>(image.at(offset)) |
           (static_cast<uint16_t>(image.at(offset + 1)) << 8);
}

uint32_t read32(const std::vector<uint8_t>& image, std::size_t offset) {
    return static_cast<uint32_t>(read16(image, offset)) |
           (static_cast<uint32_t>(read16(image, offset + 2)) << 16);
}

bool mapped(uint32_t address) {
    return (address >= 0x80000000u && address < 0x80020000u) ||
           (address >= 0x80020000u && address < 0x80040000u);
}
}  // namespace

extern "C" int elf_open(const char* path) {
    try {
        std::ifstream file(path, std::ios::binary);
        if (!file) return -1;
        std::vector<uint8_t> image((std::istreambuf_iterator<char>(file)), {});
        if (image.size() < 52 || image[0] != 0x7f || image[1] != 'E' ||
            image[2] != 'L' || image[3] != 'F' || image[4] != 1 || image[5] != 1)
            return -2;
        if (read16(image, 18) != 243) return -3;

        entry_point = read32(image, 24);
        const uint32_t phoff = read32(image, 28);
        const uint16_t phentsize = read16(image, 42);
        const uint16_t phnum = read16(image, 44);
        std::map<uint32_t, uint8_t> bytes;

        for (uint16_t index = 0; index < phnum; ++index) {
            const std::size_t offset = phoff + static_cast<std::size_t>(index) * phentsize;
            if (read32(image, offset) != 1) continue;
            const uint32_t file_offset = read32(image, offset + 4);
            const uint32_t vaddr = read32(image, offset + 8);
            const uint32_t paddr = read32(image, offset + 12);
            const uint32_t filesz = read32(image, offset + 16);
            const uint32_t memsz = read32(image, offset + 20);
            const uint32_t address = paddr ? paddr : vaddr;
            if (!memsz) continue;
            if (!mapped(address) || !mapped(address + memsz - 1)) return -4;
            if (static_cast<uint64_t>(file_offset) + filesz > image.size()) return -5;
            for (uint32_t byte = 0; byte < memsz; ++byte)
                bytes[address + byte] = byte < filesz ? image[file_offset + byte] : 0;
        }

        struct Word { uint32_t data = 0; uint8_t strobe = 0; };
        std::map<uint32_t, Word> words;
        for (const auto& [address, value] : bytes) {
            const uint32_t word_address = address & ~3u;
            const uint32_t lane = address & 3u;
            auto& word = words[word_address];
            word.data = (word.data & ~(0xffu << (lane * 8))) |
                        (static_cast<uint32_t>(value) << (lane * 8));
            word.strobe |= static_cast<uint8_t>(1u << lane);
        }

        writes.clear();
        writes.reserve(words.size());
        for (const auto& [address, word] : words)
            writes.push_back({address, word.data, word.strobe});
        cursor = 0;
        return static_cast<int>(writes.size());
    } catch (...) {
        return -6;
    }
}

extern "C" uint32_t elf_entry() { return entry_point; }

extern "C" int elf_next(uint32_t* address, uint32_t* data, uint8_t* strobe) {
    if (cursor >= writes.size()) return 0;
    const auto& write = writes[cursor++];
    *address = write.address;
    *data = write.data;
    *strobe = write.strobe;
    return 1;
}

extern "C" void elf_close() {
    writes.clear();
    cursor = 0;
}
