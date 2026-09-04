OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ITIM (rx)  : ORIGIN = 0x80000000, LENGTH = 128K
  DTIM (rwx) : ORIGIN = 0x80020100, LENGTH = 0x1ff00
}

SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.text.init))
    *(.text .text.*)
    *(.text.trap)
  } > ITIM

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
  } > ITIM

  .data : ALIGN(16)
  {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __global_pointer$ = . + 0x800;
    __data_end = .;
  } > DTIM

  .bss (NOLOAD) : ALIGN(16)
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.* COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > DTIM

  __heap_start = ALIGN(16);
  __stack_top = ORIGIN(DTIM) + LENGTH(DTIM);
  PROVIDE(tohost = 0x80020000);
  PROVIDE(fromhost = 0x80020008);

  ASSERT(__heap_start < __stack_top, "DTIM overflow")
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
