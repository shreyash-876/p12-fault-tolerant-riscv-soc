# P12 Stage 2 — Hsiao (39,32) SEC-DED codec

Standalone codec project, built to the Stage 2 specification (Claude Doc "P12 Stage 2 —
SEC-DED Hsiao (39,32) codec"). It is integrated into `mem_ctrl` in the next step.

## Layout
```
model/hsiao.py            golden model: build_h, encode, inject, syndrome, decode, self-test
                          + CLI: --demo, --data HEX --err 0,4, --matrix
model/compare_log.py      recomputes the testbench log in Python, prints RTL vs Python side by side
model/gen.py              generates everything marked (gen) below
model/decoder.pla         (gen) ESPRESSO input, Berkeley PLA type fdr
model/decoder_min.pla     (gen) ESPRESSO result
rtl/ecc/ecc_pkg.sv        (gen) H columns and row masks + h_col(j), row_mask(i)
rtl/ecc/ecc_enc_flat.sv   (gen) encoder IMPL 1
rtl/ecc/ecc_enc_cse.sv    (gen) encoder IMPL 2
rtl/ecc/ecc_enc_tree.sv   (gen) encoder IMPL 3
rtl/ecc/ecc_corr_cmp.sv   (gen) comparator corrector (decoder IMPL 1, 2)
rtl/ecc/ecc_corr_espresso.sv (gen) ESPRESSO corrector (decoder IMPL 3)
rtl/ecc/ecc_enc.sv        encoder wrapper, parameter IMPL
rtl/ecc/ecc_dec.sv        decoder wrapper, parameters IMPL and PIPE, localparam LAT
rtl/ecc/ecc_ooc_wrap.sv   register wrappers for out-of-context synthesis
tb/tb_ecc_codec.sv        self-checking testbench, all variants
tb/vectors/ecc_vectors.hex (gen) 54,204 golden-model vectors (data mask + results per line)
formal/bdd_equiv.py       BDD equivalence of the generated RTL text vs the model
scripts/create_codec_project.tcl   Vivado project (simulation)
scripts/ooc_sweep.tcl     Vivado out-of-context sweep -> reports/ooc_results.csv
reports/                  hand metrics (gen), delay/area table to fill in
```

## Run order and expected results

| Step | Command (from this folder) | Expected |
|---|---|---|
| 1 Golden model | `python3 model/hsiao.py` | 5,304 single corrected, 100,776 double detected, PASS |
| 2 Generate | `pip install pyeda dd` then `python3 model/gen.py` | files listed above; hand-metric table printed |
| 3 Simulate | see below | `PASS: 542250 checks, 0 errors` (210 in phase A + 542,040 streamed) |
| 4 BDD proof | `python3 formal/bdd_equiv.py` | 9 lines `EQUIVALENT`, `RESULT: PASS` |
| 5 Lint | see below | no warnings |
| 6 Delay/area | `vivado -mode batch -source scripts/ooc_sweep.tcl` | `reports/ooc_results.csv`, copy into `ecc_area_delay.md` |

Simulation with Icarus Verilog 12:
```
mkdir -p sim && cd sim && cp ../tb/vectors/ecc_vectors.hex .
iverilog -g2012 -o sim_ecc ../rtl/ecc/ecc_pkg.sv ../rtl/ecc/ecc_enc_flat.sv ../rtl/ecc/ecc_enc_cse.sv \
  ../rtl/ecc/ecc_enc_tree.sv ../rtl/ecc/ecc_corr_cmp.sv ../rtl/ecc/ecc_corr_espresso.sv \
  ../rtl/ecc/ecc_enc.sv ../rtl/ecc/ecc_dec.sv ../tb/tb_ecc_codec.sv
vvp sim_ecc
```
Vivado xsim: `source scripts/create_codec_project.tcl`, then Run Behavioral Simulation
(`ecc_vectors.hex` is added as a Memory Initialization File, runtime = all).

Lint: `verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -GIMPL=2 -GPIPE=0 --top-module ecc_dec_ooc rtl/ecc/*.sv`

## Seeing the vectors and comparing with Python

`tb_ecc_codec` has two phases. **Phase A** applies a few vectors of every kind one at a time and prints
data -> encoded codeword -> injected error -> codeword read back -> decoder outputs (RTL vs golden,
field by field, all 4 encoders and 6 decoders). **Phase B** streams all 54,204 vectors silently.

```
python model/hsiao.py                               full descriptive report (code, syndrome map, vector plan, self-test)
python model/hsiao.py --vector 17963                explain one test vector step by step (number = line-1 of ecc_vectors.hex)
python model/hsiao.py --vectors 100 20              table of vectors 100..119
python model/hsiao.py --plan                        how the 54,204 vectors are numbered
python model/hsiao.py --data 89ABCDEF --err 0,4 [--explain]   your own case (bits: 0-31 = d0-d31, 32-38 = c0-c6)
python model/hsiao.py --matrix | --demo
python model/hsiao.py --verify-hex tb/vectors/ecc_vectors.hex  prove the vector file equals the model
```
Testbench options (parameters at the top of `tb_ecc_codec.sv`, or xsim `-testplusarg`): `show=N` vectors per kind
(default 3), `dut=K` decoder shown in detail (0..3 = IMPL 0..3, 4 = IMPL 2 PIPE 1, 5 = IMPL 3 PIPE 1),
`console=0` log file only. The log `ecc_tb_log.txt` is written to the simulator's run folder
(`vivado/p12_codec.sim/sim_1/behav/xsim/`), or set the `LOG_FILE` parameter to a full path. Then:
```
python model/compare_log.py <path>/ecc_tb_log.txt          RTL and Python side by side (first 40)
python model/compare_log.py <path>/ecc_tb_log.txt --all    every logged vector
```
For every vector in every logged row, the script recomputes encode, inject and decode from the data word and the
error mask alone, with `hsiao.py`, and compares with what the RTL produced. To log all 54,204 vectors
(about a minute in Icarus): `+show=100000 +console=0`. If the vector file is from an older version, the
testbench stops with a message; regenerate it with `python model/gen.py --vectors-only` (no pyeda needed).

## Interfaces (unchanged from the spec)
```
ecc_enc #(IMPL)        data_in[31:0] -> cw_out[38:0] = {c[6:0], data_in}         latency 0
ecc_dec #(IMPL, PIPE)  clk, rst_n, in_valid, cw_in[38:0] ->
                       out_valid, data_out[31:0], cw_out[38:0], syndrome[6:0],
                       ce, ue, err_pos[5:0]                                       latency LAT = PIPE
```
`ue = 1` never changes the data. `cw_out` is the corrected codeword (for scrub write-back).

## Design decisions worth knowing
- **Package constants are flat vectors** (`H_COL_FLAT`, `ROW_MASK_FLAT`) with accessor functions
  `h_col(j)` and `row_mask(i)`, instead of 2-D arrays, because Icarus Verilog cannot index
  packed 2-D parameters. Same content as the spec.
- **Decoder syndrome reuses the encoder variant:** syndrome = encoder network on the received
  data XOR the received check bits. So decoder IMPL k exercises encoder IMPL k (IMPL 3 uses the tree).
- **ESPRESSO decision (spec section 5, item 4).** Minimised *single-output* with don't-cares:
  `flip_raw[j]` only has to be right on the 39 column syndromes, and `ce_odd` only on odd
  syndromes; then `ce = (^syn) & ce_odd` (exact) and `flip = flip_raw & ce`. Result: every data
  flip is a 3-input AND (e.g. `flip[0] = s0 & s1 & s4`), 168 literals vs 273. Because flips are
  gated by an exact `ce`, the don't-cares can never flip a bit on an uncorrectable syndrome.
  Minimising all outputs together (multi-output) gives no reduction: ESPRESSO counts product
  terms and reuses ce's 39 full minterms for free.
- **Triple errors** (no guarantee): 5,452 of 9,139 patterns are miscorrected, 3,687 flagged.
  Every variant behaves exactly like the model on them (they are in the vectors).

## Verification status
| Check | Result |
|---|---|
| Golden model self-test | PASS |
| tb_ecc_codec, 4 encoders + 6 decoders x 54,204 vectors | PASS, 542,040 checks |
| BDD equivalence, 9 properties | PASS |
| Verilator -Wall, every IMPL x PIPE, with/without ECC_KEEP | clean |
| Mutation checks (wrong CSE term, ungated ESPRESSO flips, dropped literal) | all caught by tb and BDD |
| Vivado OOC delay/area | to run (`scripts/ooc_sweep.tcl`) |
