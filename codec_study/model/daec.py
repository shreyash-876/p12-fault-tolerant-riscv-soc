#!/usr/bin/env python3
"""
daec.py - GOLDEN MODEL of the SEC-DED-DAEC (39,32) code of Dutta and Touba
==========================================================================
Source: A. Dutta and N. A. Touba, "Multiple Bit Upset Tolerant Memory Using a Selective Cycle
Avoidance Based SEC-DED-DAEC Code", 25th IEEE VLSI Test Symposium (VTS 2007), pp. 349-354.
The H-matrix below is Fig. 2 of that paper, typed in without change.

Same conventions as model/hsiao.py:
    codeword bit 0..31  = data bits d0..d31,   bit 32..38 = check bits c0..c6
    column j of H is a 7-bit integer, bit i of it = row i of H
    syndrome = XOR of the columns of all bits that are 1

Decoding algorithm (paper, section 6):
    1. syndrome = 0                              -> no error
    2. syndrome equals column j                  -> single error, flip bit j
    3. syndrome equals column i XOR column i+1   -> double ADJACENT error, flip bits i and i+1
    4. anything else                             -> uncorrectable (UE), data left unchanged

Run:  python model/daec.py            self-test, property check against the paper's Table 1,
                                      exhaustive error classification, comparison with Hsiao
      python model/daec.py --report   also write reports/daec_capability.md
"""
import os, sys
from itertools import combinations

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hsiao

K, R, N = 32, 7, 39

# ---- H-matrix of the paper, Fig. 2 (7 rows x 39 columns), row 0 first ----
PAPER_ROWS = [
    "101110010101100001001010011100001000000",
    "010101001011000100011100011000010100000",
    "101010100110001010110000110000110010000",
    "010100011100010101100001100001110001000",
    "001001100000101101001011000011100000100",
    "100001001001011010010110100111000000010",
    "010010110010110010100101001110000000001",
]

def build_h(rows=PAPER_ROWS):
    assert len(rows) == R and all(len(r) == N for r in rows)
    return [sum(int(rows[i][j]) << i for i in range(R)) for j in range(N)]

H = build_h()
ADJ = [H[i] ^ H[i + 1] for i in range(N - 1)]            # syndromes of the 38 adjacent double errors
SINGLE = {c: j for j, c in enumerate(H)}
ADJMAP = {s: i for i, s in enumerate(ADJ)}

def popcount(x): return bin(x).count("1")

def syndrome(cw, h=H):
    s = 0
    for j in range(N):
        if (cw >> j) & 1: s ^= h[j]
    return s

def row_masks(h=H):
    """data bits feeding check bit i (the P part of H = [P | I])."""
    return [sum(1 << j for j in range(K) if (h[j] >> i) & 1) for i in range(R)]

def encode(data, h=H):
    chk = 0
    for i, m in enumerate(row_masks(h)):
        chk |= (popcount(data & m) & 1) << i
    return (chk << K) | data

def decode(cw, h=H):
    """returns (data_out, cw_out, syndrome, kind, flipped) ; kind in 'ok','single','adjacent','ue'"""
    s = syndrome(cw, h)
    single = {c: j for j, c in enumerate(h)}
    adj = {h[i] ^ h[i + 1]: i for i in range(N - 1)}
    if s == 0: return cw & 0xFFFFFFFF, cw, s, "ok", ()
    if s in single:
        j = single[s]; out = cw ^ (1 << j); return out & 0xFFFFFFFF, out, s, "single", (j,)
    if s in adj:
        i = adj[s]; out = cw ^ (3 << i); return out & 0xFFFFFFFF, out, s, "adjacent", (i, i + 1)
    return cw & 0xFFFFFFFF, cw, s, "ue", ()

# ---------------------------------------------------------------- code properties (paper section 4)
def properties(h=H):
    out = {}
    out["systematic [P|I]"] = all(h[K + i] == (1 << i) for i in range(R))
    out["cond 1: no zero column"] = all(c != 0 for c in h)
    out["cond 2: all columns distinct"] = len(set(h)) == N
    out["cond 3: no 3-cycle"] = all((h[a] ^ h[b]) not in set(h) for a, b in combinations(range(N), 2))
    # count each 4-cycle once: sets {i<j<k<m} with XOR zero
    fc = bc = tot = 0
    for i, j, k, m in combinations(range(N), 4):
        if h[i] ^ h[j] ^ h[k] ^ h[m] == 0:
            tot += 1
            forbidden = (j == i + 1 and m == k + 1)
            bad = (j == i + 1 or k == j + 1 or m == k + 1)
            if forbidden: fc += 1
            elif bad: bc += 1
    out["forbidden 4-cycles (4FC)"] = fc
    out["total 4-cycles"] = tot
    out["bad 4-cycles (4BC)"] = bc
    rw = [popcount(sum(((h[j] >> i) & 1) << j for j in range(N))) for i in range(R)]
    out["row weights"] = rw
    out["2-input XOR gates = sum(row weight - 1)"] = sum(w - 1 for w in rw)
    out["max logic depth = ceil(log2(max row weight))"] = (max(rw) - 1).bit_length()
    out["adjacent syndromes distinct from each other"] = len(set(ADJ)) == N - 1 if h is H else None
    return out

# ---------------------------------------------------------------- exhaustive classification
def classify(mask, dec):
    """Apply the error mask to the all-zero codeword (the code is linear, so behaviour does not depend on the data)
    and report what the decoder does:  'corrected' (data and codeword restored), 'miscorrected' (a wrong correction:
    silent corruption), 'detected' (UE flagged, nothing changed), 'undetected' (zero syndrome, error stays)."""
    cw0 = 0
    cwe = cw0 ^ mask
    d, cwo, s, kind, fl = dec(cwe)
    if mask == 0: return "clean"
    if kind == "ok":  return "undetected"
    if kind == "ue":  return "detected"
    return "corrected" if cwo == cw0 else "miscorrected"

def hsiao_dec(cw):
    """adapt hsiao.decode to the (data, cw_out, syndrome, kind, flipped) shape used by classify()"""
    d, cwo, syn, ce, ue, pos = hsiao.decode(cw)
    if syn == 0: return d, cwo, syn, "ok", ()
    if ce: return d, cwo, syn, "single", (pos,)
    return d, cwo, syn, "ue", ()

def table(dec, name):
    rows = {}
    for t, label in ((1, "single"), (2, "double"), (3, "triple")):
        cnt = {"corrected": 0, "miscorrected": 0, "detected": 0, "undetected": 0}
        for pos in combinations(range(N), t):
            mask = sum(1 << p for p in pos)
            cnt[classify(mask, dec)] += 1
        rows[label] = cnt
    adj = {"corrected": 0, "miscorrected": 0, "detected": 0, "undetected": 0}
    non = {"corrected": 0, "miscorrected": 0, "detected": 0, "undetected": 0}
    for a, b in combinations(range(N), 2):
        mask = (1 << a) | (1 << b)
        (adj if b == a + 1 else non)[classify(mask, dec)] += 1
    rows["double adjacent"] = adj; rows["double non-adjacent"] = non
    return rows

def self_test():
    import random
    rnd = random.Random(7)
    for _ in range(2000):
        d = rnd.getrandbits(32); cw = encode(d)
        assert syndrome(cw) == 0 and cw & 0xFFFFFFFF == d
        for j in range(N):
            assert decode(cw ^ (1 << j))[1] == cw
        for i in range(N - 1):
            assert decode(cw ^ (3 << i))[1] == cw
    return True

if __name__ == "__main__":
    print("SEC-DED-DAEC (39,32), Dutta & Touba, VTS 2007, Fig. 2")
    self_test(); print("self-test: encode/decode, all 39 single and all 38 adjacent double errors corrected: PASS")
    p = properties()
    print("\nProperties of the H-matrix as typed in:")
    for k, v in p.items(): print("  %-48s %s" % (k, v))
    print("\nPaper Table 1, 'Proposed SEC-DED-DAEC (Fig. 2)': 96 XOR gates, depth 4, 4FC 0, total 4-cycles 1363, 4BC 379")
    print("Paper Table 1, 'Hsiao Code [Hsiao 70]' (39,32):   96 XOR gates, depth 4, 4FC 23, total 4-cycles 1363, 4BC 425")

    # ------------------------------------------------------------ exhaustive classification
    tD = table(decode, "SEC-DED-DAEC")
    tH = table(hsiao_dec, "Hsiao")
    order = ["single", "double", "double adjacent", "double non-adjacent", "triple"]
    cols = ["corrected", "miscorrected", "detected", "undetected"]
    total = {"single": 39, "double": 741, "double adjacent": 38, "double non-adjacent": 703, "triple": 9139}
    lines = []
    lines.append("| Error pattern | Patterns | Hsiao corr. | Hsiao detected | Hsiao miscorr. | Hsiao undet. | DAEC corr. | DAEC detected | DAEC miscorr. | DAEC undet. |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for o in order:
        h, d = tH[o], tD[o]
        lines.append("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d |" % (
            o, total[o], h["corrected"], h["detected"], h["miscorrected"], h["undetected"],
            d["corrected"], d["detected"], d["miscorrected"], d["undetected"]))
    print("\nExhaustive classification (every pattern; the code is linear, so the data word does not matter):")
    print("\n".join(lines))
    mis = tD["double non-adjacent"]["miscorrected"]
    print("\nDAEC: %d of 703 non-adjacent double errors (%.1f %%) are silently miscorrected as an adjacent pair." % (mis, 100.0 * mis / 703))
    print("      paper's estimate #4BC / (C(39,2) - 38) = 379 / 703 = %.1f %%" % (100.0 * 379 / 703))
    ph = properties(hsiao.H) if False else None
    if "--report" in sys.argv:
        out = os.path.join(os.path.dirname(HERE), "reports", "daec_capability.md")
        with open(out, "w") as f:
            f.write("# Correction capability: Hsiao (39,32) vs SEC-DED-DAEC (39,32) of Dutta and Touba (VTS 2007)\n\n")
            f.write("Generated by `python model/daec.py --report`. Every error pattern is applied to a codeword and decoded;\n")
            f.write("the code is linear, so the result does not depend on the data word.\n\n")
            f.write("Outcomes: corrected = the original codeword is restored; detected = uncorrectable flag, nothing changed;\n")
            f.write("miscorrected = a wrong correction without any flag (silent data corruption); undetected = zero syndrome, error stays.\n\n")
            f.write("\n".join(lines) + "\n")
        print("wrote", out)
