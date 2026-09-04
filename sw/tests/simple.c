#include <stdint.h>

static volatile uint32_t seed = 0x12345678u;
static uint32_t scratch[32];

int main(void)
{
  uint32_t value = seed;
  uint32_t cycle;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(cycle));
  if (cycle == 0)
    return 2;

  for (uint32_t i = 0; i < 32; ++i) {
    value = (value << 5) ^ (value >> 3) ^ (i * 0x1021u);
    scratch[i] = value;
  }

  for (uint32_t i = 1; i < 32; ++i)
    scratch[i] ^= scratch[i - 1];

  return scratch[31] == 0xcfeb6640u ? 0 : 1;
}
