#!/usr/bin/env python3
"""Reads reports/ooc_results.csv (from scripts/ooc_sweep.tcl) and writes reports/ecc_area_delay_filled.md."""
import csv, os
HERE = os.path.dirname(os.path.abspath(__file__))
HAND = {  # hand metrics from model/gen.py: (2-input XORs / literals, hand depth)
    ("enc","0"): ("89 before sharing", "-"), ("enc","1"): ("89", "13 (as written)"),
    ("enc","2"): ("71", "4"), ("enc","3"): ("89", "4"),
    ("dec","0"): ("-", "-"), ("dec","1"): ("89+7 XOR, 273 corr. literals", "14 + compare"),
    ("dec","2"): ("71+7 XOR, 273 corr. literals", "5 + compare"),
    ("dec","3"): ("89+7 XOR, 168 corr. literals (ESPRESSO)", "5 + 3-input AND"),
}
NAME = {"0": "behavioural", "1": "flat", "2": "CSE", "3": "tree / ESPRESSO"}
rows = list(csv.DictReader(open(os.path.join(HERE, "ooc_results.csv"))))
out = ["# Codec delay / area table (Vivado, xc7z010clg400-1, out of context, routed, clock constrained at 5 ns)", "",
       "| Variant | Hand XORs / literals | Hand depth | LUTs | FFs | Logic levels | Path delay (ns) | Fmax (MHz) | Slack at 50 MHz (ns) |",
       "|---|---|---|---|---|---|---|---|---|"]
for r in rows:
    k, i, p, kp = r["kind"], r["impl"], r["pipe"], r["keep"]
    label = "%s IMPL %s (%s)%s%s" % ("enc" if k == "enc" else "dec", i,
            NAME[i] if k == "dec" or i != "3" else "tree", ", PIPE 1" if p == "1" else "", ", ECC_KEEP" if kp == "1" else "")
    if k == "enc" and i == "3": label = "enc IMPL 3 (tree)" + (", ECC_KEEP" if kp == "1" else "")
    if k == "dec" and i == "3": label = "dec IMPL 3 (ESPRESSO)" + (", PIPE 1" if p == "1" else "") + (", ECC_KEEP" if kp == "1" else "")
    h = HAND.get((k, i), ("", ""))
    out.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (label, h[0], h[1], r["luts"], r["ffs"], r["logic_levels"],
               r["path_ns"], r["fmax_mhz"], r["slack50_ns"]))
open(os.path.join(HERE, "ecc_area_delay_filled.md"), "w").write("\n".join(out) + "\n")
print("\n".join(out))
