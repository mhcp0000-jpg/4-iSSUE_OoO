OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x00001000;
  .text : { KEEP(*(.text.init)) *(.text .text.*) }
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
