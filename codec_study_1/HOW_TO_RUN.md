# Codec design-space study: how to run (inside p12_final/codec_study)

All paths below are relative to `p12_final/codec_study`. On Windows, use `python` instead of `python3`.

## 1. Golden model self-test

```
python model/hsiao.py
```
Expected last line: `RESULT: PASS`.

## 2. BDD equivalence proof

This proves the 3 encoder variants, the 2 correctors, and your FPGA codec in `../rtl/ecc` equal to the golden model.

```
python -m pip install dd
python formal/bdd_equiv.py
```
Expected: 40 lines `EQUIVALENT`, then `RESULT: PASS - all equivalent`. The last 12 lines are the SEC-DED-DAEC codec of the paper (package, 3 encoders, corrector), the 14 before them the XOR-limited pipelined decoders (function, and register depth of every path).

To demonstrate that the check catches errors:

1. Change one bit in a copy of `../rtl/ecc/ecc_dec.sv`, for example in the line for `flip[29]` change `7'b0111000` to `7'b0111001`.
2. Run the check again. Expected: `DIFFERENT` lines and `RESULT: FAIL`.
3. Undo the change.

## 3. Simulation of every variant against the 54,204 golden vectors

**Vivado xsim:** in the Vivado Tcl console, with no project open:
```
source scripts/create_codec_project.tcl
```
Then click Run Behavioral Simulation and run all.

**Icarus:** see `README_ecc.md`.

Expected: `PASS: 542250 checks, 0 errors`.

## 4. Delay/area sweep (Vivado)

1. Open the "Vivado 2025.2 Tcl Shell" from the Start menu. Use the shell, not the GUI with your project open.
2. Run:
   ```
   cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study
   vivado -mode batch -source scripts/ooc_sweep.tcl
   ```
   There are 14 configurations, each synthesized and routed. Expect roughly 20 to 40 minutes in total.
3. The results are written to:
   - `reports/ooc_results.csv`
   - `reports/timing_*.txt`, the worst path of each variant.
4. Build the table:
   ```
   python reports/fill_table.py
   ```
   This writes `reports/ecc_area_delay_filled.md`.

Verified in the sandbox: steps 1–3 (Icarus) pass. Step 4 needs Vivado and has not been run yet.

## 5. XOR-limited schedules (spec: "XOR-limited schedules, single-cycle vs pipelined decode")

**What it is.** `model/gen_xl.py` takes the CSE syndrome network (78 two-input XORs) and schedules it under two limits:
at most **K** XORs in one pipeline stage and at most **C** chained XOR levels in one stage (resource-constrained list
scheduling). Values that live across stages are carried through registers, and the received codeword is carried along
so the corrector sees the matching data. Each configuration accepts one codeword per clock; its latency is the number
of stages. `reports/ecc_xl_metrics.md` lists the 7 configurations (1 to 10 stages).

**Generate (only needed if you change `gen_xl.py`):**
```
python model/gen_xl.py
```

**Simulate** (Icarus; xsim works the same, add `ecc_xl_pkg.sv`, `ecc_corr_cmp.sv`, `ecc_dec_xl.sv`, `tb_ecc_xl.sv`):
```
mkdir sim && cd sim && copy ..\tb\vectors\ecc_vectors.hex .
iverilog -g2012 -o sim_xl ../rtl/ecc/ecc_pkg.sv ../rtl/ecc/ecc_xl_pkg.sv ../rtl/ecc/ecc_corr_cmp.sv ../rtl/ecc/ecc_dec_xl.sv ../tb/tb_ecc_xl.sv
vvp sim_xl
```
Expected: `PASS: 5438398 checks, 0 errors` (all 54,204 vectors twice, back-to-back and with random idle cycles, for 7 configurations).

**Simulate inside Vivado (no command-line setup, same method as the first codec project):** in the Vivado Tcl Shell
```
cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
source scripts/create_xl_sim_project.tcl
launch_simulation
```
The simulation runs to the end by itself; the last lines of the Tcl console show `PASS: 5438398 checks, 0 errors`.

**Prove:** the BDD run in section 2 includes them.

**Delay/area** (Vivado 2025.2 Tcl Shell, about 15 to 25 minutes):
```
cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study
vivado -mode batch -source scripts/ooc_sweep_xl.tcl
python reports/fill_table_xl.py
```
This writes `reports/ooc_results_xl.csv` and `reports/ecc_xl_table.md` (with the single-cycle and PIPE=1 rows from the earlier sweep as anchors).

## 6. SEC-DED-DAEC codec of the paper (Dutta and Touba, VTS 2007)

**Golden model, properties and the exhaustive Hsiao-vs-DAEC table:**
```
python model/daec.py --report
```
Prints the properties of the paper's H-matrix (they equal the paper's Table 1: 0 forbidden 4-cycles, 1363 total, 379 bad, 96 XORs, depth 4)
and the exhaustive classification of all 39 singles, 741 doubles and 9139 triples; writes `reports/daec_capability.md`.

**Generate the RTL, the golden vectors and the hand metrics** (only needed if you change the model):
```
python model/gen_daec.py
```

**Simulate** inside Vivado (no command-line setup):
```
cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
source scripts/create_daec_sim_project.tcl
launch_simulation
```
Expected last line: `PASS: 4860517 checks, 0 errors`. It checks 4 encoders and 5 decoder configurations against the 54,204 golden vectors, back-to-back and with random idle cycles.
Icarus: `iverilog -g2012 -o sim_daec rtl/ecc/daec_pkg.sv rtl/ecc/daec_enc_flat.sv rtl/ecc/daec_enc_cse.sv rtl/ecc/daec_enc_tree.sv rtl/ecc/daec_corr_cmp.sv rtl/ecc/daec_enc.sv rtl/ecc/daec_dec.sv tb/tb_daec_codec.sv`
(run from a folder that contains `daec_vectors.hex`).

**Prove:** the BDD run in section 2 includes the DAEC codec.

**Delay/area, baseline vs paper code** (Vivado 2025.2 Tcl Shell, about 10 to 15 minutes):
```
cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
source scripts/ooc_sweep_daec.tcl
```
This writes `reports/ooc_results_daec.csv`.
