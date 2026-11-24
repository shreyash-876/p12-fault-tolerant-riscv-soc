/* P12 SoC memory map (frozen in Stage 1)                                     */
/*   0x0000_0000 ITCM 16 KB : code, read-only data, .data load image          */
/*   0x2000_0000 DMEM  8 KB : .data, .bss, stack (ECC-protected from Stage 2) */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  ITCM (rx) : ORIGIN = 0x00000000, LENGTH = 16K
  DMEM (rw) : ORIGIN = 0x20000000, LENGTH = 8K
}
_stack_size = 1K;
SECTIONS {
  .text : {
    *(.text.init) *(.text*)
    *(.rodata*) *(.srodata*)
    . = ALIGN(4);
  } > ITCM
  .data : {
    _data_start = .;
    *(.data*) *(.sdata*)
    . = ALIGN(4);
    _data_end = .;
  } > DMEM AT > ITCM
  _data_lma = LOADADDR(.data);
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss*) *(.sbss*) *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DMEM
  _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
  ASSERT(_bss_end + _stack_size <= _stack_top, "DMEM overflow: .data + .bss + stack > 8 KB")
}
