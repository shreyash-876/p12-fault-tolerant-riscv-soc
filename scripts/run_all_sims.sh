#!/bin/sh
# One-command regression with Icarus Verilog (run from the project root):   sh scripts/run_all_sims.sh
# Optional: riscv-tests compliance, if a RISC-V GCC is on PATH and the path of a riscv-tests checkout is given:
#           sh scripts/run_all_sims.sh /path/to/riscv-tests
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
B=build; rm -rf $B; mkdir -p $B
RTL="rtl/mem/mem_pkg.sv rtl/core/*.sv rtl/ecc/*.sv rtl/mem/bram_sp.sv rtl/mem/axil_frontend.sv rtl/mem/mem_ctrl.sv rtl/mem/mem_ctrl_ecc.sv rtl/mem/mem_arbiter.sv rtl/mem/ecc_scrubber.sv rtl/mem/ecc_injector.sv rtl/mem/ecc_regs.sv rtl/mem/mem_subsystem.sv rtl/bus/axil_decoder.sv rtl/periph/*.sv rtl/soc/itcm.sv rtl/soc/soc_top.sv"
MEM="rtl/mem/mem_pkg.sv rtl/ecc/*.sv rtl/mem/bram_sp.sv rtl/mem/axil_frontend.sv rtl/mem/ecc_regs.sv rtl/mem/ecc_scrubber.sv rtl/mem/ecc_injector.sv rtl/mem/mem_arbiter.sv rtl/mem/mem_ctrl_ecc.sv rtl/mem/mem_subsystem.sv"
PASSN=0; FAILN=0; SUMMARY=""
# run NAME  "iverilog sources"  "plusargs"  "grep pattern for PASS"  [firmware dir]
run() {
  name=$1; srcs=$2; args=$3; pat=$4; fw=$5
  mkdir -p $B/$name
  [ -n "$fw" ] && cp fw/$fw/firmware.hex $B/$name/firmware.hex
  iverilog -g2012 -o $B/$name/sim $srcs > $B/$name/compile.log 2>&1
  (cd $B/$name && timeout 280 vvp sim $args > out.txt 2>&1)
  if grep -aq "$pat" $B/$name/out.txt; then r=PASS; PASSN=$((PASSN+1)); else r=FAIL; FAILN=$((FAILN+1)); fi
  line=$(grep -a "$pat" $B/$name/out.txt | head -1 | tr -d '\r' | cut -c1-90)
  [ -z "$line" ] && line="(no pass line; see $B/$name/out.txt)"
  printf "%-6s %-22s %s\n" "$r" "$name" "$line" | tee -a $B/summary.txt
}
echo "P12 regression ($(date))"
run tb_mem_arbiter    "rtl/mem/mem_pkg.sv rtl/mem/mem_arbiter.sv tb/tb_mem_arbiter.sv" "" "^PASS: arbiter"
run tb_mem_subsystem  "$MEM tb/tb_mem_subsystem.sv" "+verbose=0" "^PASS: 3052"
run tb_mem_ecc        "$MEM tb/tb_mem_ecc.sv" "" "^PASS: "
run tb_scrubber       "$MEM tb/tb_scrubber.sv" "" "^PASS: "
run tb_mega           "$MEM tb/tb_mega.sv" "" "^PASS: "
run tb_regs           "$MEM tb/tb_regs.sv" "" "^PASS: "
run soc_memtest       "tb/tb_soc.sv $RTL" "+max_cycles=3000000" "RESULT PASS" fw_memtest
run soc_ecc_demo      "tb/tb_soc_ecc.sv $RTL" "" "SYSTEM TEST PASS" fw_ecc_demo
run soc_csr_test      "tb/tb_soc.sv $RTL" "+max_cycles=500000" "RESULT PASS" fw_csr
run soc_irq_stress    "tb/tb_soc_irq.sv $RTL" "" "INTERRUPT TEST PASS" fw_irq_stress
run soc_error_log     "tb/tb_soc_log.sv $RTL" "+max_cycles=4000000" "ERROR-LOG SYSTEM TEST PASS" fw_ecc_log
if [ -n "$1" ] && command -v riscv-none-elf-gcc >/dev/null 2>&1; then
  r=$(sh sw/run_riscv_tests.sh "$1" 2>&1 | tail -1)
  case "$r" in *" 0 failed"*) PASSN=$((PASSN+1)); printf "PASS   riscv-tests            %s\n" "$r";; *) FAILN=$((FAILN+1)); printf "FAIL   riscv-tests            %s\n" "$r";; esac
fi
echo "----"; echo "passed: $PASSN   failed: $FAILN"
[ $FAILN -eq 0 ] && echo "ALL TESTS PASS" || echo "SOME TESTS FAILED"
