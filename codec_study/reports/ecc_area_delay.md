# Codec delay / area table (spec section 6)

Hand metrics come from `model/gen.py` (see `ecc_hand_metrics.md`). Vivado columns come from
`scripts/ooc_sweep.tcl` -> `ooc_results.csv` (xc7z010clg400-1, 50 MHz, out of context, routed).

| Variant | Hand 2-input XORs | Hand logic depth | LUTs | FFs | Logic levels | WNS at 50 MHz (ns) | Max frequency (MHz) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| enc IMPL 0 (reference) | 89 | - |  |  |  |  |  |
| enc IMPL 1 (flat) | 89 | 13 (as written) |  |  |  |  |  |
| enc IMPL 2 (CSE) | 71 | 4 |  |  |  |  |  |
| enc IMPL 3 (tree) | 89 | 4 |  |  |  |  |  |
| enc IMPL 2, ECC_KEEP | 71 | 4 |  |  |  |  |  |
| enc IMPL 3, ECC_KEEP | 89 | 4 |  |  |  |  |  |
| dec IMPL 0, PIPE 0 | - | - |  |  |  |  |  |
| dec IMPL 1, PIPE 0 | 89 + 7, 273 corr. literals | 14 + compare |  |  |  |  |  |
| dec IMPL 2, PIPE 0 | 71 + 7, 273 corr. literals | 5 + compare |  |  |  |  |  |
| dec IMPL 3 (ESPRESSO), PIPE 0 | 89 + 7, 168 corr. literals | 5 + 3-input AND |  |  |  |  |  |
| dec IMPL 2, PIPE 0, ECC_KEEP |  |  |  |  |  |  |  |
| dec IMPL 3, PIPE 0, ECC_KEEP |  |  |  |  |  |  |  |
| dec IMPL 2, PIPE 1 |  |  |  |  |  |  |  |
| dec IMPL 3, PIPE 1 |  |  |  |  |  |  |  |

## Discussion (to write after the sweep)

- Does CSE (71 vs 89 XORs) reduce LUTs? A 6-input LUT absorbs a 6-input XOR, so a
  14-input parity needs about 3 LUTs in 2 levels whichever way it is written; expect
  small differences unless ECC_KEEP forces the 2-input structure.
- Does the ESPRESSO corrector (168 vs 273 literals) reduce LUTs and depth?
- Cost of PIPE=1: extra FFs vs higher fmax; is it needed at 50 MHz?
