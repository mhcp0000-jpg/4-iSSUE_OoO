#include "coremark.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;
volatile ee_u32 coremark_elapsed_ticks;
volatile ee_u32 coremark_validated;
volatile ee_u32 coremark_errors;

static CORETIMETYPE start_time_value;
static CORETIMETYPE stop_time_value;

static inline ee_u32 read_cycle(void)
{
    ee_u32 value;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
    return value;
}

static int starts_with(const char *text, const char *prefix)
{
    while (*prefix) {
        if (*text++ != *prefix++)
            return 0;
    }
    return 1;
}

void start_time(void)
{
    start_time_value = read_cycle();
}

void stop_time(void)
{
    stop_time_value = read_cycle();
}

CORE_TICKS get_time(void)
{
    coremark_elapsed_ticks = stop_time_value - start_time_value;
    return coremark_elapsed_ticks;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    coremark_elapsed_ticks = 0;
    coremark_validated = 0;
    coremark_errors = 0;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *) || sizeof(ee_u32) != 4)
        coremark_errors = 1;
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
}

void *portable_malloc(ee_size_t size)
{
    (void)size;
    return NULL;
}

void portable_free(void *p)
{
    (void)p;
}

int ee_printf(const char *fmt, ...)
{
    if (starts_with(fmt, "Correct operation validated"))
        coremark_validated = 1;
    if (starts_with(fmt, "Errors detected") ||
        starts_with(fmt, "Cannot validate") ||
        starts_with(fmt, "ERROR!"))
        coremark_errors = 1;
    return 0;
}
