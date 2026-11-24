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
Expected: 14 lines `EQUIVALENT`, then `RESULT: PASS - all equivalent`.

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
