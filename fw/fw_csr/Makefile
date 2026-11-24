CROSS   ?= riscv-none-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
CFLAGS  := -march=rv32i_zicsr -mabi=ilp32 -O2 -ffreestanding -fno-builtin -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -static -T link.ld -Wl,--gc-sections
all: firmware.hex
firmware.elf: crt0.S main.c p12.h p12_regs.h p12_csr.h link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S main.c -lgcc -o $@
	$(CROSS)size $@
firmware.bin: firmware.elf
	$(OBJCOPY) -O binary -j .text -j .data $< $@
firmware.hex: firmware.bin
	python3 bin2hex.py $< $@ 4096
clean:
	rm -f firmware.elf firmware.bin firmware.hex
