# P12 final tree: integration, verification and board bring-up

This folder is the complete, consolidated design (latest version of every file). Integrating = use this folder, do not merge
the earlier partial packages.

```
rtl/bus  rtl/core  rtl/ecc  rtl/fpga  rtl/mem  rtl/periph  rtl/soc     the design (same folder names as your Vivado tree + rtl/ecc)
tb/                                                                    10 testbenches
fw/   fw_board_demo  fw_ecc_log  fw_irq_stress  fw_csr  fw_ecc_demo  fw_memtest    firmware (C sources + prebuilt firmware.hex)
constr/zybo_z7_10.xdc    scripts/ (create_project, build_bitstream, program_board, run_all_sims.sh)    sw/ (riscv-tests runner)
reports/                 results of the checks done for this delivery
```

## 1. Integrate (Vivado)
1. Easiest: `vivado -mode batch -source scripts/create_project.tcl` (or `source` it in the Tcl console). It builds a clean project with every file.
   If you keep your old project instead: remove its sources, add the files of rtl/ in this order: `rtl/mem/mem_pkg.sv` first, then everything else,
   set all `.sv` to SystemVerilog, top = `zybo_top`, add `constr/zybo_z7_10.xdc`.
2. ITCM program: one file, `vivado_fw/firmware.hex` (type: Memory Initialization File). `set_firmware <name>` in the Tcl console copies a program there.
3. mem_subsystem has two NEW input ports (`hw_inj_single`, `hw_inj_double`) and a new output `irq_ce`; every testbench in tb/ already ties them.

## 2. Check with the testbenches
**Icarus Verilog, one command:** `sh scripts/run_all_sims.sh [path-to-riscv-tests]`  (RISC-V GCC on PATH for the riscv-tests step).
**Vivado xsim:** set the simulation top, set `set_firmware <program>` when a row asks for one, runtime = all, expected last line in the table.

| Top | Firmware | Expected result line |
|---|---|---|
| `tb_mem_arbiter` | - | `PASS: arbiter properties hold in both scenarios` |
| `tb_mem_subsystem` | - | `PASS: 3052 checks, 0 errors` |
| `tb_mem_ecc` | - | `PASS: 3406 checks, 0 errors` |
| `tb_scrubber` | - | `PASS: 3684 checks, 0 errors` |
| `tb_mega` | - | `PASS: 5770 checks, 0 failures` |
| `tb_regs` | - | `PASS: 2586 checks, 0 failures` |
| `tb_soc` | fw_memtest | `RESULT PASS after ~141221 cycles` |
| `tb_soc` | fw_csr | `RESULT PASS after ~4056 cycles` |
| `tb_soc_ecc` | fw_ecc_demo | `SYSTEM TEST PASS` |
| `tb_soc_irq` | fw_irq_stress | `INTERRUPT TEST PASS` (about 30 s of simulation) |
| `tb_soc_log` | fw_ecc_log | `ERROR-LOG SYSTEM TEST PASS` (about 1 minute) |

## 3. Build and program the board
```
vivado -mode batch -source scripts/build_bitstream.tcl     # synthesis, implementation, reports, p12_zybo.bit
vivado -mode batch -source scripts/program_board.tcl       # JTAG (micro-USB PROG port)
```
Reports to read: `vivado/util_synth.rpt` (block RAM: the 39-bit data RAM needs more than the 2 RAMB36 of Stage 1), `vivado/timing_impl.rpt`
(the script prints WNS/WHS), `vivado/check_timing_synth.rpt`, `vivado/drc_synth.rpt`.

**Bring-up with the default program (fw_board_demo):**
1. UART: a 3.3 V USB-serial adapter, its RX to Pmod JE pin 1 (V12), GND to JE pin 5 (GND), terminal 115200 8N1. (The board's own USB-UART belongs to the PS and is not used.)
2. After programming: the banner `P12 board demo ...` and `expected checksum 96155E28`, then a `status:` line every ~2 s. LD0 toggles with it.
3. BTN1 injects one flipped bit, BTN2 two flipped bits, into a random word of the protected buffer. BTN3 is reset.
   Single flips appear as `corrected bit N ... (CPU read)` or `(scrubber)` log lines; double flips as `UNCORRECTABLE`, LD2 flickers (irq_ue), and the pass is repeated.
4. The status line's `wrong` counter must stay 0 and LD3 must stay off: the checksum program never gives a wrong result.
5. ILA ("Set Up Debug"): nets marked `mark_debug` include `scrub_*`, `ev_*`, `ij_count`, `c_req_*`, `c_rsp_*`, and in the core `mem_stall`, `global_stall`, `axi_state`.

## 4. If timing fails (not checked: Vivado was not available)
New paths since Stage 1: BRAM output -> `ecc_dec` -> register (`mem_ctrl_ecc`); `ext_irq` -> `trap_take` -> PC redirect (`csr_unit`, `rv32i_core`);
CSR read -> EX/MEM register. If WNS < 0 at 50 MHz, look at `timing_impl.rpt` first for these. Simplest remedies: register `ext_irq` once
(one flop before the core, costs one cycle of interrupt latency), or lower the clock in `zybo_top` (the MMCM divider).

## 5. What was verified, and what was not
| Checked here (Icarus Verilog, Verilator, Python) | Result |
|---|---|
| 11 regression suites above | all PASS (`reports/regression_result.txt`) |
| riscv-tests rv32ui | 40 of 40 |
| Verilator -Wall lint of the whole design including `zybo_top` | clean, no latches |
| Pin assignments vs Digilent's master XDC | all 14 match (`reports/xdc_check.txt`) |
| Deliberately broken designs (ECC, scrubber, registers, interrupt logic) | all caught by the testbenches |
| Board firmware in simulation (`reports/board_demo_sim_output.txt`) | runs, prints log and status lines, `wrong 0` |

| NOT checked | Why |
|---|---|
| Vivado synthesis, utilization, timing at 50 MHz, DRC | no Vivado in the working environment (Yosys cannot parse this SystemVerilog) |
| The vivado/*.tcl scripts | written but never run |
| Anything on the board | no hardware |
| xsim runs of the testbenches | Icarus only; they use `force`, hierarchical references into `u_bram.mem` and `$sformatf`, which xsim supports, but this is unconfirmed |
| Pmod/UART wiring, button bounce on real hardware | hardware dependent (buttons are debounced over 10 ms in `btn_pulse`) |

## 6. Specification items still open
- CTL proof that the scrubber never starves the CPU (NuSMV): not started. The arbiter's fairness is only checked by simulation (`tb_mem_arbiter`).
- Hand-HLS delay/area table for the encoder/decoder variants (`ooc_sweep.tcl` from Stage 2 needs Vivado) and the PIPE=0/1 decision.
- Research paper (adjacent-error / MCU-tolerant code or scrubbing-rate study compared with Hsiao): code not started.
- Final board demo recording and report.
