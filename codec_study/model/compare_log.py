#!/usr/bin/env python3
"""
compare_log.py - side-by-side check of the RTL testbench log against the Python golden model.

The testbench (tb/tb_ecc_codec.sv) writes one line per vector shown in phase A:

    VEC idx=.. kind=.. data=.. mask=.. cw_in=.. enc=.. syn=.. ce=.. ue=.. pos=.. dout=.. cwout=..

This script ignores everything the vector file claims and recomputes each case from
only `data` and `mask` with model/hsiao.py:

    encode(data)  ->  stored codeword      (compared with the RTL encoder output  `enc`)
    ^ mask        ->  codeword read back   (compared with the testbench `cw_in`)
    decode(...)   ->  syndrome, ce, ue, err_pos, data_out, cw_out   (compared with the RTL decoder)

Usage (from the project folder):
    python model/compare_log.py <path to ecc_tb_log.txt>            first 40 vectors + summary
    python model/compare_log.py <path to ecc_tb_log.txt> --all      every logged vector
    python model/compare_log.py <path to ecc_tb_log.txt> --cards    full golden-model card for each

Exit status 0 = every logged vector matches, 1 = at least one mismatch.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hsiao
from hsiao import encode, decode, inject, N

TOKEN = re.compile(r"(\w+)=(\S+)")


def parse(path):
    header, rows = [], []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#"):
                header.append(line)
            elif line.startswith("VEC "):
                kv = dict(TOKEN.findall(line))
                rows.append(dict(
                    idx=int(kv["idx"]), kind=kv["kind"],
                    data=int(kv["data"], 16), mask=int(kv["mask"], 16), cw_in=int(kv["cw_in"], 16),
                    enc=int(kv["enc"], 16), syn=int(kv["syn"], 16), ce=int(kv["ce"]), ue=int(kv["ue"]),
                    pos=int(kv["pos"]), dout=int(kv["dout"], 16), cwout=int(kv["cwout"], 16)))
    return header, rows


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    header, rows = parse(args[0])
    if not rows:
        print("no VEC lines found in", args[0])
        return 2
    for h in header:
        print(h)

    show_all = "--all" in flags
    show_cards = "--cards" in flags
    limit = len(rows) if (show_all or show_cards) else 40

    print()
    print("%-6s %-12s %-8s %-10s | %-35s | %-35s | %s" % (
        "idx", "kind", "data", "err mask",
        "RTL  syn ce ue pos data_out", "PYTHON  syn ce ue pos data_out", "result"))
    print("-" * 140)

    bad = 0
    for n, r in enumerate(rows):
        stored = encode(r["data"])
        cw_in = inject(stored, r["mask"])
        d, co, s, ce, ue, pos = decode(cw_in)
        problems = []
        if r["enc"] != stored:
            problems.append("encoder %010x != python %010x" % (r["enc"], stored))
        if r["cw_in"] != cw_in:
            problems.append("cw_in %010x != python %010x" % (r["cw_in"], cw_in))
        if (r["syn"], r["ce"], r["ue"], r["pos"], r["dout"], r["cwout"]) != (s, ce, ue, pos, d, co):
            problems.append("decoder output differs")
        if problems:
            bad += 1
        if n < limit:
            print("%-6d %-12s %08x %010x | %02x  %d  %d  %2d  %08x           | %02x  %d  %d  %2d  %08x           | %s" % (
                r["idx"], r["kind"], r["data"], r["mask"],
                r["syn"], r["ce"], r["ue"], r["pos"], r["dout"],
                s, ce, ue, pos, d,
                "MATCH" if not problems else "MISMATCH: " + "; ".join(problems)))
            if show_cards:
                print()
                hsiao.card(r["data"], r["mask"])
    if len(rows) > limit:
        print("... %d more vectors not shown (use --all)" % (len(rows) - limit))
    print("-" * 140)
    print("%d of %d logged vectors match the Python golden model%s" % (
        len(rows) - bad, len(rows), "" if bad == 0 else "  <-- %d MISMATCHES" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
