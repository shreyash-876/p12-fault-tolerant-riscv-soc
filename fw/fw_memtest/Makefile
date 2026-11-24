# Builds firmware.hex for the ITCM.  Needs riscv-none-elf-gcc (xPack) or
# riscv64-unknown-elf-gcc on PATH:   make            or   make CROSS=riscv64-unknown-elf-
CROSS   ?= riscv-none-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
CFLAGS  := -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -static -T link.ld -Wl,--gc-sections

all: firmware.hex firmware.lst

firmware.elf: crt0.S main.c p12.h link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S main.c -lgcc -o $@
	$(CROSS)size $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary -j .text -j .data $< $@

firmware.hex: firmware.bin
	python3 ../sw/bin2hex.py $< $@ 4096

firmware.lst: firmware.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -f firmware.elf firmware.bin firmware.hex firmware.lst
