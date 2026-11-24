#!/usr/bin/env python3
"""Builds reports/ecc_xl_table.md from reports/ecc_xl_metrics.md (hand metrics, model/gen_xl.py),
reports/ooc_results_xl.csv (scripts/ooc_sweep_xl.tcl) and, as single-cycle / PIPE=1 anchors, reports/ooc_results.csv."""
import csv, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
def rd(f): return list(csv.DictReader(open(os.path.join(HERE, f))))
anch = {(r["kind"], r["impl"], r["pipe"], r["keep"]): r for r in rd("ooc_results.csv")}
xl = rd("ooc_results_xl.csv")
hand = {}
for l in open(os.path.join(HERE, "ecc_xl_metrics.md")):
    m = re.match(r"\| (\d+) \| (\S+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|", l)
    if m: hand[m.group(1)] = m.groups()[1:]
out = ["# XOR-limited pipelined decoders: delay / area (Vivado, xc7z010clg400-1, out of context, routed, 5 ns constraint)", "",
       "K = XORs allowed per stage, C = chained XOR levels per stage; throughput 1 word per clock for every row.",
       "Latency = number of register stages between input and the comparator corrector.", "",
       "| Decoder | K | C | Latency (clocks) | LUTs | FFs | SRL cells | Logic levels | Path (ns) | Fmax (MHz) | Slack at 50 MHz (ns) |",
       "|---|---|---|---|---|---|---|---|---|---|---|"]
def anchor(label, key, lat):
    r = anch[key]
    out.append("| %s | - | - | %d | %s | %s | 0 | %s | %s | %s | %s |" % (label, lat, r["luts"], r["ffs"], r["logic_levels"], r["path_ns"], r["fmax_mhz"], r["slack50_ns"]))
anchor("single-cycle, dec IMPL 2 (CSE), PIPE 0", ("dec", "2", "0", "0"), 0)
anchor("dec IMPL 2 (CSE), PIPE 1", ("dec", "2", "1", "0"), 1)
for r in xl:
    k, c, st, mx, regs = hand[r["cfg"]]
    out.append("| XL cfg %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (r["cfg"], k, c, st, r["luts"], r["ffs"], r.get("srls", "n/a"),
               r["logic_levels"], r["path_ns"], r["fmax_mhz"], r["slack50_ns"]))
open(os.path.join(HERE, "ecc_xl_table.md"), "w").write("\n".join(out) + "\n")
print("\n".join(out))
