#!/usr/bin/env python3
"""
bdd_equiv.py - BDD equivalence proof for the generated codec RTL.

Reads the RTL TEXT of the generated modules (not the generator's internal data),
builds a BDD for every output, and compares it with a BDD built directly from
the golden model (model/hsiao.py). For a fixed variable order, two Boolean
functions are equal if and only if their reduced ordered BDDs are the same node.

  * ecc_pkg.sv          : H_COL_FLAT / ROW_MASK_FLAT constants equal the model
  * ecc_enc_flat/cse/tree: each check bit c[i] (32 data variables) == XOR of row i
  * ecc_corr_cmp        : flip[j], ce (7 syndrome variables) == reference
  * ecc_corr_espresso   : flip[j] = flip_raw[j] & ce,  ce = ^syn & ce_odd  == reference

Needs:  pip install dd        Run from the project root:  python3 formal/bdd_equiv.py
"""
import os, re, sys
from dd.autoref import BDD

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
from hsiao import H, K, R, N, row_bits

ROWS = row_bits()
bdd = BDD()
bdd.declare(*["d%d" % j for j in range(K)], *["s%d" % i for i in range(R)])

class F:
    """BDD node with Verilog-style bitwise operators (& | ^ ~) and equality."""
    def __init__(self, u): self.u = u
    def __and__(self, o): return F(self.u & o.u)
    def __or__(self, o):  return F(self.u | o.u)
    def __xor__(self, o): return F(bdd.apply("xor", self.u, o.u))
    def __invert__(self): return F(~self.u)
    def __eq__(self, o):  return self.u == o.u
    def __ne__(self, o):  return self.u != o.u

FALSE, TRUE = F(bdd.false), F(bdd.true)
D = [F(bdd.var("d%d" % j)) for j in range(K)]
S = [F(bdd.var("s%d" % i)) for i in range(R)]

failures = 0
def report(name, ok, detail=""):
    global failures
    print("  %-46s %s%s" % (name, "EQUIVALENT" if ok else "DIFFERENT", (" " + detail) if detail else ""))
    if not ok: failures += 1

def read(rel):
    with open(os.path.join(ROOT, rel)) as f:
        return f.read()

ASSIGN = re.compile(r"^\s*assign\s+([\w\[\]]+)\s*=\s*(.+?);\s*$", re.M)

def to_python(expr):
    """Verilog bitwise expression -> Python expression over BDD nodes in env V."""
    expr = expr.replace("1'b0", "FALSE").replace("1'b1", "TRUE")
    return re.sub(r"\b([A-Za-z_]\w*(?:\[\d+\])?)", lambda m: m.group(1) if m.group(1) in ("FALSE", "TRUE")
                  else 'V["%s"]' % m.group(1), expr)

def eval_assigns(text, env):
    for lhs, rhs in ASSIGN.findall(text):
        if "==" in rhs or "{" in rhs or "^syn" in rhs or rhs.strip().startswith("|"):
            continue                      # template lines, handled by the caller
        env[lhs] = eval(to_python(rhs), {"V": env, "FALSE": FALSE, "TRUE": TRUE})
    return env

def xor_all(nodes):
    acc = FALSE
    for n in nodes: acc = acc ^ n
    return acc

# ---------------------------------------------------------------- reference functions
REF_CHK  = [xor_all([D[j] for j in ROWS[i]]) for i in range(R)]
def syn_eq(col):
    acc = TRUE
    for i in range(R): acc = acc & (S[i] if (col >> i) & 1 else ~S[i])
    return acc
REF_FLIP = [syn_eq(H[j]) for j in range(N)]
REF_CE   = FALSE
for f in REF_FLIP: REF_CE = REF_CE | f

print("BDD equivalence: generated RTL vs golden model (hsiao.py)")

# ---------------------------------------------------------------- package constants
pkg = read("rtl/ecc/ecc_pkg.sv")
cols = re.findall(r"7'b([01]{7})", pkg)[::-1]          # listed j = 38 ... 0
masks = re.findall(r"32'h([0-9A-Fa-f]{8})", pkg)[::-1]  # listed i = 6 ... 0
report("ecc_pkg H_COL_FLAT == model H", [int(c, 2) for c in cols] == list(H))
report("ecc_pkg ROW_MASK_FLAT == model rows",
       [int(m, 16) for m in masks] == [sum(1 << b for b in ROWS[i]) for i in range(R)])

# ---------------------------------------------------------------- encoders
for mod in ("ecc_enc_flat", "ecc_enc_cse", "ecc_enc_tree"):
    env = {"d[%d]" % j: D[j] for j in range(K)}
    eval_assigns(read("rtl/ecc/%s.sv" % mod), env)
    ok = all(env["c[%d]" % i] == REF_CHK[i] for i in range(R))
    report("%s: c[6:0] (32 inputs)" % mod, ok)

# ---------------------------------------------------------------- comparator corrector
txt = read("rtl/ecc/ecc_corr_cmp.sv")
flips = {}
for j, bits in re.findall(r"assign flip\[(\d+)\] = \(syn == 7'b([01]{7})\);", txt):
    flips[int(j)] = syn_eq(int(bits, 2))
ce = FALSE
for f in flips.values(): ce = ce | f
assert "assign ce = |flip;" in txt
report("ecc_corr_cmp: flip[38:0]", len(flips) == N and all(flips[j] == REF_FLIP[j] for j in range(N)))
report("ecc_corr_cmp: ce", ce == REF_CE)

# ---------------------------------------------------------------- ESPRESSO corrector
txt = read("rtl/ecc/ecc_corr_espresso.sv")
env = {"syn[%d]" % i: S[i] for i in range(R)}
eval_assigns(txt, env)
assert "assign ce   = (^syn) & ce_odd;" in txt and "assign flip = flip_raw & {39{ce}};" in txt
ce = xor_all(S) & env["ce_odd"]
flip = [env["flip_raw[%d]" % j] & ce for j in range(N)]
report("ecc_corr_espresso: ce", ce == REF_CE)
report("ecc_corr_espresso: flip[38:0]", all(flip[j] == REF_FLIP[j] for j in range(N)))
# how much did the don't-cares buy? (raw outputs differ from the reference off the columns)
raw_diff = sum(1 for j in range(N) if env["flip_raw[%d]" % j] != REF_FLIP[j])
print("  (info) %d of 39 raw flip outputs use don't-cares; equal to the reference only after gating by ce" % raw_diff)

# ---------------------------------------------------------------- the codec that runs on the FPGA
# When this study sits inside p12_final (folder codec_study/), also prove the user's own codec in
# ../rtl/ecc (ecc_enc, ecc_dec - the one in the bitstream) against the same model.
FPGA = os.path.join(ROOT, "..", "rtl", "ecc")
if os.path.isdir(FPGA) and os.path.isfile(os.path.join(FPGA, "ecc_enc.sv")):
    print("FPGA codec (p12_final/rtl/ecc) vs golden model")
    enc = open(os.path.join(FPGA, "ecc_enc.sv")).read()
    rows = re.findall(r"assign chk\[(\d)\]\s*=\s*\^\(data_in & 32'h([0-9A-Fa-f]{8})\);", enc)
    chk = {}
    for i, m in rows:
        chk[int(i)] = xor_all([D[j] for j in range(K) if (int(m, 16) >> j) & 1])
    report("ecc_enc: chk[6:0] (32 inputs)", len(chk) == R and all(chk[i] == REF_CHK[i] for i in range(R)))
    dec = open(os.path.join(FPGA, "ecc_dec.sv")).read()
    fl = {int(j): syn_eq(int(b, 2)) for j, b in re.findall(r"assign flip\[(\d+)\]\s*=\s*\(syndrome == 7'b([01]{7})\);", dec)}
    report("ecc_dec: flip[38:0]", len(fl) == N and all(fl[j] == REF_FLIP[j] for j in range(N)))
    assert "assign ce = |flip;" in dec and "assign ue = (syndrome != 7'd0) && !ce;" in dec
    ce = FALSE
    for f in fl.values(): ce = ce | f
    nz = FALSE
    for x in S: nz = nz | x
    REF_UE = nz & ~REF_CE
    report("ecc_dec: ce", ce == REF_CE)
    report("ecc_dec: ue", (nz & ~ce) == REF_UE)
    syn = open(os.path.join(FPGA, "ecc_syn.sv")).read()
    report("ecc_syn: syndrome = re-encode XOR received check bits",
           "assign syndrome = recalc[38:32] ^ cw_in[38:32];" in syn)

print("RESULT:", "PASS - all equivalent" if failures == 0 else "FAIL - %d differences" % failures)
sys.stdout.flush()
os._exit(1 if failures else 0)   # skip dd teardown at interpreter exit
