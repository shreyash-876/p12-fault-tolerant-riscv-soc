# Codec delay / area table (Vivado, xc7z010clg400-1, out of context, routed, clock constrained at 5 ns)

| Variant | Hand XORs / literals | Hand depth | LUTs | FFs | Logic levels | Path delay (ns) | Fmax (MHz) | Slack at 50 MHz (ns) |
|---|---|---|---|---|---|---|---|---|
| enc IMPL 0 (behavioural) | 89 before sharing | - | 21 | 71 | 2 | 2.938 | 334.1 | 17.007 |
| enc IMPL 1 (flat) | 89 | 13 (as written) | 21 | 71 | 2 | 2.618 | 374.1 | 17.327 |
| enc IMPL 2 (CSE) | 71 | 4 | 21 | 71 | 2 | 2.672 | 373.0 | 17.319 |
| enc IMPL 3 (tree) | 89 | 4 | 21 | 71 | 2 | 2.503 | 398.4 | 17.490 |
| enc IMPL 2 (CSE), ECC_KEEP | 71 | 4 | 71 | 71 | 4 | 4.345 | 227.3 | 15.600 |
| enc IMPL 3 (tree), ECC_KEEP | 89 | 4 | 80 | 71 | 4 | 4.261 | 231.8 | 15.686 |
| dec IMPL 0 (behavioural) | - | - | 93 | 95 | 4 | 4.565 | 216.5 | 15.380 |
| dec IMPL 1 (flat) | 89+7 XOR, 273 corr. literals | 14 + compare | 93 | 95 | 5 | 4.629 | 217.4 | 15.400 |
| dec IMPL 2 (CSE) | 71+7 XOR, 273 corr. literals | 5 + compare | 87 | 95 | 4 | 4.773 | 209.3 | 15.222 |
| dec IMPL 3 (ESPRESSO) | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 135 | 95 | 6 | 5.184 | 190.9 | 14.763 |
| dec IMPL 2 (CSE), ECC_KEEP | 71+7 XOR, 273 corr. literals | 5 + compare | 143 | 95 | 7 | 5.330 | 185.8 | 14.618 |
| dec IMPL 3 (ESPRESSO), ECC_KEEP | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 194 | 95 | 8 | 5.723 | 174.5 | 14.270 |
| dec IMPL 2 (CSE), PIPE 1 | 71+7 XOR, 273 corr. literals | 5 + compare | 85 | 142 | 1 | 3.377 | 295.7 | 16.618 |
| dec IMPL 3 (ESPRESSO), PIPE 1 | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 129 | 142 | 2 | 3.697 | 270.0 | 16.296 |

## Findings

1. **Encoder: the four ways of writing the same XOR network give the same hardware.** Behavioural, flat, CSE and
   tree all map to 21 LUTs in 2 logic levels (7 check bits x 3 LUT6 each). Path delay is 2.5-2.9 ns for all of them. The
   differences of up to 0.4 ns are within what place-and-route variation can produce (one run each, so no claim beyond that).
   A 6-input LUT absorbs a 6-input XOR, so a 13-14 input parity needs 3 LUTs in 2 levels however it is written. The
   hand metrics (71 vs 89 two-input XORs, depth 13 vs 4) matter for ASIC gates, not for LUT fabric.
2. **Forcing the hand structure (ECC_KEEP) is harmful on this FPGA.** The encoder grows from 21 to 71 (CSE) or 80 (tree)
   LUTs, and from 2 to 4 logic levels; Fmax drops from about 373 to 227-232 MHz. Each two-input XOR gets its own LUT.
   The decoder shows the same: 87 -> 143 LUTs (CSE), 135 -> 194 (ESPRESSO).
3. **The ESPRESSO corrector is worse than the comparators here, although it has fewer literals (168 vs 273).**
   Decoder IMPL 3: 135 LUTs, 6 levels, 5.18 ns, versus 93 LUTs, 4 levels, 4.57 ns for the reference. A literal count measures
   two-level logic; on LUT6 fabric a 7-input comparator already fits in one or two LUTs, and the minimised version adds
   the shared `ce` gating (parity AND ce_odd, fanout 39) on the path. This explanation is my reading of the numbers; the
   worst path of each variant is in `timing_dec_impl3_pipe0_keep0.txt` and can confirm it.
4. **CSE decoder (IMPL 2) is the smallest unpipelined decoder (87 LUTs vs 93), but 0.2 ns slower than the reference.** A
   difference of 6 LUTs is 0.03 % of the device.
5. **PIPE=1 (a register between syndrome and correction) buys speed for flip-flops.** CSE: Fmax 209 -> 296 MHz (+41 %),
   path 4.77 -> 3.38 ns, +47 FFs (95 -> 142), LUTs unchanged. ESPRESSO: 191 -> 270 MHz.
6. **At 50 MHz none of this limits the design.** Every decoder, including the slowest, has at least 14.27 ns slack
   at 50 MHz (20 ns period). The full SoC has WNS +6.67 ns, so its critical path is not in the codec.

## Decision

Keep the reference codec (`ecc_enc`, `ecc_dec` in `rtl/ecc`; equivalent to enc/dec IMPL 0):
- it is already in the verified bitstream, proven equal to the golden model by the BDD check, and has the lowest
  path delay among the unpipelined decoders except the 0.2 ns flat variant;
- the best alternative saves 6 LUTs;
- PIPE=1 is unnecessary at 50 MHz and is not a drop-in: the Stage 2 `ecc_dec` has `clk/in_valid` ports and a latency
  of `PIPE` cycles, while the reference decoder in `mem_ctrl_ecc` is purely combinational and its result is registered
  in state DEC. Using it would need an extra controller state and a full re-run of the regression.
- PIPE=1 would pay off only if the clock were raised: the unpipelined decoder alone reaches about 190-217 MHz, the pipelined one 270-296 MHz.
