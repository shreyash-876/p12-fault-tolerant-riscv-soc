# XOR-limited pipelined decoders: delay / area (Vivado, xc7z010clg400-1, out of context, routed, 5 ns constraint)

K = XORs allowed per stage, C = chained XOR levels per stage; throughput 1 word per clock for every row.
Latency = number of register stages between input and the comparator corrector.

| Decoder | K | C | Latency (clocks) | LUTs | FFs | SRL cells | Logic levels | Path (ns) | Fmax (MHz) | Slack at 50 MHz (ns) |
|---|---|---|---|---|---|---|---|---|---|---|
| single-cycle, dec IMPL 2 (CSE), PIPE 0 | - | - | 0 | 87 | 95 | 0 | 4 | 4.773 | 209.3 | 15.222 |
| dec IMPL 2 (CSE), PIPE 1 | - | - | 1 | 85 | 142 | 0 | 1 | 3.377 | 295.7 | 16.618 |
| XL cfg 0 | none | 5 | 1 | 85 | 142 | n/a | 2 | 3.047 | 322.7 | 16.901 |
| XL cfg 1 | none | 2 | 3 | 102 | 189 | n/a | 1 | 3.395 | 292.8 | 16.585 |
| XL cfg 2 | 26 | 2 | 4 | 126 | 221 | n/a | 1 | 3.362 | 292.7 | 16.583 |
| XL cfg 3 | 16 | 2 | 5 | 132 | 267 | n/a | 2 | 2.792 | 351.5 | 17.155 |
| XL cfg 4 | 10 | 2 | 8 | 139 | 313 | n/a | 1 | 3.068 | 320.4 | 16.879 |
| XL cfg 5 | none | 1 | 5 | 142 | 231 | n/a | 2 | 2.835 | 346.0 | 17.110 |
| XL cfg 6 | 8 | 1 | 10 | 142 | 322 | n/a | 2 | 3.365 | 295.4 | 16.615 |

Note on the area columns of the XL rows (first sweep): Vivado converts long delay chains into shift-register
primitives (SRL), which the first version of the sweep script counted in neither the LUT nor the FF column. The generator's
register count (47, 158, 223, 287, 460, 283, 574 for cfg 0-6) minus the flip-flops Vivado reports (47, 94, 126, 172, 218,
136, 227, after subtracting 95 wrapper flip-flops) leaves 0, 64, 97, 115, 242, 147, 347 registers that sit in shift registers.
The updated `ooc_sweep_xl.tcl` records the SRL cell count and a utilization report per configuration.

## Findings

1. **Splitting the syndrome from the correction (one register) is the only step that buys speed.** Single-cycle decoder
   209 MHz, one register stage 296-323 MHz (a 40-50 % gain). More stages do not help further:
   Fmax of the seven XL configurations is 293-352 MHz with no trend in the number of stages (1 to 10) or in K.
2. **The run-to-run spread is about 10 %.** XL cfg 0 and `dec IMPL 2, PIPE 1` are the same hardware (same 85 LUTs, same
   142 FFs) and differ by 9 % in Fmax (322.7 vs 295.7 MHz). Differences of that size between rows are place-and-route noise,
   not a property of the schedule. Only one run per configuration was made.
3. **Deeper pipelines cost area and add latency without speed.** LUTs grow from 85 to 102-142 (+20 to +67 %) because a register
   between two XOR stages stops the tool from packing neighbouring XORs into one LUT6. Flip-flops grow from 142 to 322, and
   the registers sitting in shift registers come on top (see the note). Latency grows from 1 to 10 clocks.
4. **Likely reason for finding 1 (not yet confirmed):** once the XOR network is cut, the worst path is no longer in the XORs
   but in the final stage (registered syndrome -> comparator -> output register) and in routing. The worst path of each
   configuration is in `timing_xl_cfgN.txt`: the Source and Destination cells show it.
5. **At 50 MHz none of the configurations is needed.** Every row has at least 16.58 ns slack at 50 MHz. A XOR-limited schedule
   would matter where the number of XOR gates per stage is itself the constraint (a gate-level or ASIC implementation).
   On this LUT fabric the tool already packs the XORs and the limit buys nothing.

## Decision

Keep the single-cycle reference decoder in the SoC (see the first table). The XOR-limited schedules are a design-space result:
they show that on a 6-input-LUT FPGA, limiting XORs per stage lengthens the pipeline and increases area without raising the
frequency beyond what one register between syndrome and correction already gives.
