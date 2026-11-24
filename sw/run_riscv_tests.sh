#!/bin/bash
# Builds riscv-tests rv32ui and runs each one on the full SoC (tb_soc.sv).
# Usage: ./run_riscv_tests.sh <path-to-riscv-tests>
set -e
RT=${1:-../../riscv-tests-master}
HERE=$(cd $(dirname $0) && pwd)
ROOT=$HERE/..
OUT=$HERE/build_rt; mkdir -p $OUT
CC=riscv-none-elf-gcc; OBJCOPY=riscv-none-elf-objcopy
RTL="$ROOT/rtl/mem/mem_pkg.sv $ROOT/rtl/core/*.sv $ROOT/rtl/ecc/*.sv $ROOT/rtl/mem/bram_sp.sv $ROOT/rtl/mem/axil_frontend.sv \
     $ROOT/rtl/mem/mem_ctrl.sv $ROOT/rtl/mem/mem_ctrl_ecc.sv $ROOT/rtl/mem/mem_arbiter.sv $ROOT/rtl/mem/ecc_scrubber.sv $ROOT/rtl/mem/ecc_injector.sv $ROOT/rtl/mem/ecc_regs.sv $ROOT/rtl/mem/mem_subsystem.sv \
     $ROOT/rtl/bus/axil_decoder.sv $ROOT/rtl/periph/*.sv $ROOT/rtl/soc/itcm.sv $ROOT/rtl/soc/soc_top.sv"
iverilog -g2012 -o $OUT/sim $ROOT/tb/tb_soc.sv $RTL 2>/dev/null
cd $OUT
pass=0; fail=0
for t in $(ls $RT/isa/rv32ui/*.S | xargs -n1 basename | sed 's/\.S//'); do
  case $t in fence_i|ma_data) continue;; esac       # need self-modifying code / misaligned traps
  $CC -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static -T $HERE/riscv-tests-env/link.ld \
      -I $HERE/riscv-tests-env -I $RT/isa/macros/scalar $RT/isa/rv32ui/$t.S -o $t.elf
  $OBJCOPY -O binary -j .text -j .data $t.elf $t.bin
  python3 $HERE/bin2hex.py $t.bin firmware.hex 4096
  r=$(vvp sim +max_cycles=200000 | grep -E "^RESULT" || true)
  if echo "$r" | grep -q PASS; then pass=$((pass+1)); printf "%-8s PASS\n" $t; else fail=$((fail+1)); printf "%-8s FAIL  %s\n" $t "$r"; fi
done
echo "rv32ui: $pass passed, $fail failed"
