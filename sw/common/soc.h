#ifndef MYCORE_SOC_H
#define MYCORE_SOC_H

#define BOOTROM_BASE        0x00001000
#define CLINT_BASE          0x02000000
#define CLINT_MSIP_ADDR     0x02000000
#define CLINT_MTIMECMP_ADDR 0x02004000
#define CLINT_MTIME_ADDR    0x0200BFF8
#define ITIM_BASE           0x80000000
#define ITIM_SIZE           0x00020000
#define DTIM_BASE           0x80020000
#define DTIM_SIZE           0x00020000
#define TOHOST_ADDR         0x80020000
#define FROMHOST_ADDR       0x80020008

#ifndef __ASSEMBLER__
#include <stdint.h>

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define MMIO64(addr) (*(volatile uint64_t *)(uintptr_t)(addr))
#endif

#endif
