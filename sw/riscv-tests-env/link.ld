OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  ITCM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
  DMEM (rw)  : ORIGIN = 0x20000000, LENGTH = 8K
}
SECTIONS {
  .text : { *(.text.init) *(.text*) *(.rodata*) } > ITCM
  .data : { _data_start = .; *(.data*) *(.sdata*) . = ALIGN(4); _data_end = .; } > DMEM AT > ITCM
  _data_lma = LOADADDR(.data);
  .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > DMEM
}
