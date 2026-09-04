#include "core_portme.h"
#include "soc.h"

int coremark_main(void);

int main(void)
{
    (void)coremark_main();
    MMIO32(FROMHOST_ADDR) = coremark_elapsed_ticks;
    MMIO32(FROMHOST_ADDR + 4) = ITERATIONS;
    return (coremark_validated && !coremark_errors) ? 0 : 1;
}
