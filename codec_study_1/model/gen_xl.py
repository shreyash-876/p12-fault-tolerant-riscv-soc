#!/usr/bin/env python3
"""
gen_xl.py - XOR-limited schedules for the syndrome network (hand HLS, resource-constrained scheduling).

The syndrome network is the CSE encoder network (71 two-input XORs, from gen.enc_cse) plus the 7 XORs that
add the received check bits: 78 two-input XORs, 39 input bits (cw_in), 7 outputs.

A schedule assigns every XOR to a pipeline stage 1..S under two limits:
    K  = at most K two-input XOR gates in one stage          (the "XOR limit")
    C  = at most C XOR levels chained one after the other in one stage
A value that is produced in stage p and used in stage u > p is carried through u-p-1 extra registers; the
received codeword is carried to the end so that the corrector sees the data that belongs to the syndrome.
Throughput is one codeword per clock (fully pipelined), latency LAT = S clocks:

    cw_in -> [stage 1 XORs] -> reg -> [stage 2 XORs] -> reg -> ... -> reg(S) -> comparator -> outputs

Scheduler: list scheduling, priority = longest remaining path to an output, ties by name (deterministic).

Output files (do not edit):
    rtl/ecc/ecc_xl_pkg.sv      XL_NCFG and functions xl_k / xl_c / xl_lat
    rtl/ecc/ecc_dec_xl.sv      ecc_dec_xl_cfg0..N-1 and the wrapper ecc_dec_xl #(CFG)  (same ports as ecc_dec)
    reports/ecc_xl_metrics.md  hand metrics per configuration

Run:  python3 model/gen_xl.py
"""
import os, re, sys, random

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import hsiao
from hsiao import K as KD, R, N, encode
import gen as G

# (K, C): XOR limit per stage, chain depth per stage.  K = 78 means "no XOR limit".
CONFIGS = [
    (78, 5),    # cfg0: no limit, whole network in one stage      (S = 1)  == PIPE=1 with the CSE network
    (78, 2),    # cfg1: no XOR limit, two XOR levels per stage     (S = 3)
    (26, 2),    # cfg2: <= 26 XORs per stage                       (S = 4)
    (16, 2),    # cfg3: <= 16 XORs per stage                       (S = 5)
    (10, 2),    # cfg4: <= 10 XORs per stage                       (S = 8)
    (78, 1),    # cfg5: one XOR level per stage                    (S = 5)
    (8, 1),     # cfg6: <= 8 XORs per stage, one level per stage   (S = 10)
]

def build_dag():
    """Return (nodes, order): nodes[name] = (a, b) operands; input operands are 'cw[j]' (j = 0..38)."""
    lines, nets, xors, depth = G.enc_cse()
    outs = {int(i): n for i, n in (re.match(r"\s*assign c\[(\d)\] = (\S+);", l).groups() for l in lines)}
    sub = lambda x: ("cw[%d]" % int(x[2:-1])) if x.startswith("d[") else x
    nodes, order = {}, []
    for n, a, b in nets:
        nodes[n] = (sub(a), sub(b)); order.append(n)
    for i in range(R):
        nodes["s%d" % i] = (outs[i], "cw[%d]" % (32 + i)); order.append("s%d" % i)
    assert len(nodes) == 78
    return nodes, order

def schedule(nodes, k, c):
    users = {}
    for n, (a, b) in nodes.items():
        users.setdefault(a, []).append(n); users.setdefault(b, []).append(n)
    prio = {}
    def pr(n):
        if n not in prio:
            prio[n] = 1 + max([pr(u) for u in users.get(n, [])] or [0])
        return prio[n]
    for n in nodes: pr(n)
    stage, dep, s = {}, {}, 0
    while len(stage) < len(nodes):
        s += 1; cnt = 0
        while cnt < k:
            ready = []
            for n, (a, b) in nodes.items():
                if n in stage: continue
                ok, d = True, 0
                for x in (a, b):
                    if x in nodes:
                        if x not in stage: ok = False; break
                        if stage[x] == s: d = max(d, dep[x])
                if ok and d + 1 <= c: ready.append((n, d + 1))
            if not ready: break
            ready.sort(key=lambda t: (-prio[t[0]], t[0]))
            n, d = ready[0]; stage[n] = s; dep[n] = d; cnt += 1
        assert cnt > 0, "scheduler made no progress"
    return stage, dep, s

def check_schedule(nodes, stage, dep, S, k, c):
    per = {}
    for n, (a, b) in nodes.items():
        per[stage[n]] = per.get(stage[n], 0) + 1
        for x in (a, b):
            if x in nodes:
                assert stage[x] <= stage[n], "operand scheduled after its user"
                if stage[x] == stage[n]: assert dep[x] < dep[n]
        assert dep[n] <= c
    assert max(per.values()) <= k
    return per

def eval_dag(nodes, order, cw):
    v = {"cw[%d]" % j: (cw >> j) & 1 for j in range(39)}
    for n in order:
        a, b = nodes[n]; v[n] = v[a] ^ v[b]
    return sum(v["s%d" % i] << i for i in range(R))

def regs_needed(nodes, stage, S):
    prod = {"cw[%d]" % j: 1 for j in range(39)}
    for n in nodes: prod[n] = stage[n]
    last = {"cw[%d]" % j: S + 1 for j in range(39)}          # carried to the corrector
    for n in nodes: last[n] = stage[n]
    for n, (a, b) in nodes.items():
        for x in (a, b): last[x] = max(last[x], stage[n])
    for i in range(R): last["s%d" % i] = S + 1
    return prod, last

def vname(x):
    return re.sub(r"cw\[(\d+)\]", r"cw\1", x)

def emit_cfg(idx, k, c, nodes, order, stage, S, prod, last):
    def ref(x, u):
        p = prod[x]
        if x.startswith("cw["):
            return "cw_in[%s]" % x[3:-1] if u == 1 else "%s_r%d" % (vname(x), u - 1)
        return x if u == p else "%s_r%d" % (x, u - 1)
    decl_g = sorted(nodes, key=lambda n: order.index(n))
    chains = []
    for x, p in prod.items():
        for r in range(p, last[x]): chains.append("%s_r%d" % (vname(x), r))
    L = []
    A = L.append
    A("// -----------------------------------------------------------------------------")
    A("// cfg %d: at most %d XORs per stage, at most %d XOR levels per stage -> %d stages (LAT = %d)" % (idx, k, c, S, S))
    A("// -----------------------------------------------------------------------------")
    A("module ecc_dec_xl_cfg%d (" % idx)
    A("    input  logic        clk,")
    A("    input  logic        rst_n,")
    A("    input  logic        in_valid,")
    A("    input  logic [38:0] cw_in,")
    A("    output logic        out_valid,")
    A("    output logic [31:0] data_out,")
    A("    output logic [38:0] cw_out,")
    A("    output logic  [6:0] syndrome,")
    A("    output logic        ce,")
    A("    output logic        ue,")
    A("    output logic  [5:0] err_pos")
    A(");")
    A("    // XOR gates (%d), grouped by stage below" % len(nodes))
    for i in range(0, len(decl_g), 12): A("    logic " + ", ".join(decl_g[i:i + 12]) + ";")
    A("    // pipeline registers (%d)" % len(chains))
    for i in range(0, len(chains), 10): A("    logic " + ", ".join(chains[i:i + 10]) + ";")
    A("    logic [%d:0] v_r;" % (S - 1))
    A("")
    for s in range(1, S + 1):
        gs = [n for n in order if stage[n] == s]
        A("    // ---- stage %d: %d XORs ----" % (s, len(gs)))
        for n in gs:
            a, b = nodes[n]
            A("    assign %s = %s ^ %s;" % (n, ref(a, s), ref(b, s)))
    A("")
    A("    // ---- registers between the stages (and the aligned codeword) ----")
    A("    always_ff @(posedge clk) begin")
    for x, p in prod.items():
        for r in range(p, last[x]):
            src = ref(x, p) if r == p else "%s_r%d" % (vname(x) if x.startswith("cw[") else x, r - 1)
            A("        %s_r%d <= %s;" % (vname(x), r, src))
    A("    end")
    A("    always_ff @(posedge clk or negedge rst_n) begin")
    A("        if (!rst_n) v_r <= '0;")
    A("        else        v_r <= {v_r[%d:0], in_valid};" % (S - 2) if S > 1 else "        else        v_r <= in_valid;")
    A("    end")
    A("")
    A("    // ---- after the last register: aligned syndrome and codeword -> corrector ----")
    A("    logic  [6:0] syn;")
    A("    logic [38:0] cw_q;")
    for i in range(R): A("    assign syn[%d] = s%d_r%d;" % (i, i, S))
    for j in range(39): A("    assign cw_q[%d] = cw%d_r%d;" % (j, j, S))
    A("    logic [38:0] flip;")
    A("    logic        hit;")
    A("    ecc_corr_cmp u_corr (.syn(syn), .flip(flip), .ce(hit));")
    A("    always_comb begin")
    A("        err_pos = 6'd0;")
    A("        for (int j = 0; j < 39; j++)")
    A("            if (flip[j]) err_pos = err_pos | 6'(j);")
    A("    end")
    A("    assign ce        = hit;")
    A("    assign ue        = (syn != 7'd0) && !hit;")
    A("    assign cw_out    = cw_q ^ flip;")
    A("    assign data_out  = cw_out[31:0];")
    A("    assign syndrome  = syn;")
    A("    assign out_valid = v_r[%d];" % (S - 1))
    A("endmodule")
    A("")
    return "\n".join(L)

def main():
    print("P12 XOR-limited schedule generator")
    hsiao.self_test(verbose=False)
    nodes, order = build_dag()
    body, md_rows, lat = [], [], []
    rnd = random.Random(5)
    for idx, (k, c) in enumerate(CONFIGS):
        stage, dep, S = schedule(nodes, k, c)
        per = check_schedule(nodes, stage, dep, S, k, c)
        for _ in range(2000):                                    # the DAG computes the golden syndrome
            d = rnd.getrandbits(32); m = rnd.getrandbits(39)
            cw = encode(d) ^ m
            assert eval_dag(nodes, order, cw) == hsiao.syndrome(cw)
        prod, last = regs_needed(nodes, stage, S)
        nreg = sum(last[x] - prod[x] for x in prod) + S           # + valid chain
        body.append(emit_cfg(idx, k, c, nodes, order, stage, S, prod, last))
        md_rows.append((idx, k, c, S, max(per.values()), nreg))
        lat.append(S)
        print("  cfg%d  K=%2d C=%d  stages=%2d  max XORs/stage=%2d  registers=%d" % (idx, k, c, S, max(per.values()), nreg))
    hdr = G.HDR.replace("model/gen.py from model/hsiao.py", "model/gen_xl.py")
    pkg = hdr + """// XOR-limited decoder configurations (see model/gen_xl.py)
package ecc_xl_pkg;
    localparam int XL_NCFG = %d;
    function automatic int xl_k(input int cfg);      // XOR limit per stage
        case (cfg)
%s            default: return 0;
        endcase
    endfunction
    function automatic int xl_c(input int cfg);      // chained XOR levels per stage
        case (cfg)
%s            default: return 0;
        endcase
    endfunction
    function automatic int xl_lat(input int cfg);    // latency in clocks (= number of stages)
        case (cfg)
%s            default: return 0;
        endcase
    endfunction
endpackage
""" % (len(CONFIGS),
       "".join("            %d: return %d;\n" % (i, k) for i, (k, c) in enumerate(CONFIGS)),
       "".join("            %d: return %d;\n" % (i, c) for i, (k, c) in enumerate(CONFIGS)),
       "".join("            %d: return %d;\n" % (i, s) for i, s in enumerate(lat)))
    G.wpath("rtl/ecc/ecc_xl_pkg.sv", pkg)
    wrap = ["// Wrapper: choose the configuration with CFG (same ports as ecc_dec; latency = ecc_xl_pkg::xl_lat(CFG))",
            "module ecc_dec_xl #(",
            "    parameter int CFG = 0",
            ")(",
            "    input  logic        clk,", "    input  logic        rst_n,", "    input  logic        in_valid,",
            "    input  logic [38:0] cw_in,", "    output logic        out_valid,", "    output logic [31:0] data_out,",
            "    output logic [38:0] cw_out,", "    output logic  [6:0] syndrome,", "    output logic        ce,",
            "    output logic        ue,", "    output logic  [5:0] err_pos", ");",
            "    generate"]
    for i in range(len(CONFIGS)):
        wrap.append("        %s (CFG == %d) begin : g_cfg%d" % ("if" if i == 0 else "end else if", i, i))
        wrap.append("            ecc_dec_xl_cfg%d u (.*);" % i)
    wrap += ["        end", "    endgenerate", "endmodule", ""]
    G.wpath("rtl/ecc/ecc_dec_xl.sv", hdr + "// XOR-limited, pipelined syndrome + comparator corrector.\n\n"
            + "\n".join(body) + "\n" + "\n".join(wrap))
    md = ["# XOR-limited schedules: hand metrics (generated by model/gen_xl.py)", "",
          "Syndrome network = CSE encoder network (71 XORs) + 7 XORs for the received check bits = 78 two-input XORs.",
          "K = XOR limit per stage, C = chained XOR levels per stage, throughput 1 codeword per clock.",
          "'Registers' counts every flip-flop in the generated module (pipeline values, aligned codeword, valid chain).", "",
          "| cfg | K (XORs/stage) | C (levels/stage) | Stages = latency | Most XORs in a stage | Registers |",
          "| --- | --- | --- | --- | --- | --- |"]
    for idx, k, c, S, mx, nreg in md_rows:
        md.append("| %d | %s | %d | %d | %d | %d |" % (idx, "none" if k >= 78 else k, c, S, mx, nreg))
    G.wpath("reports/ecc_xl_metrics.md", "\n".join(md) + "\n")

if __name__ == "__main__":
    main()
