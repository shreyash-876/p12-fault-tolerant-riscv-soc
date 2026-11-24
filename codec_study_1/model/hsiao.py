#!/usr/bin/env python3
"""
hsiao.py  -  GOLDEN MODEL of the P12 Hsiao (39,32) SEC-DED code
================================================================

What this file is
-----------------
A small, slow, obviously-correct Python version of the error-correcting code that the
RTL implements. Every hardware result is compared against this file, so it is the
"answer key" of the project.  Nothing here is optimised: it is written to be READ.

The code in one paragraph
-------------------------
A 32-bit data word d[31:0] is stored together with 7 check bits c[6:0], giving a 39-bit
codeword.  Each check bit is the XOR (parity) of a fixed subset of the data bits.  When
the word is read back, the 7 parities are recomputed and compared with the stored check
bits; the 7-bit pattern of mismatches is the SYNDROME.
    * syndrome == 0                         -> no error
    * syndrome equals the "column" of bit j -> exactly bit j flipped: flip it back (ce=1)
    * anything else                         -> two (or more) bits flipped: detected,
                                               NOT correctable, data left alone (ue=1)

Codeword layout (bit numbers used everywhere, also in the RTL and the testbench)
    bit  0 .. 31  = data bits   d0 .. d31
    bit 32 .. 38  = check bits  c0 .. c6      (check bit i is codeword bit 32+i)

How to run it  (from the project folder; commands are the same on Windows and Linux)
    python model/hsiao.py                       full descriptive report (start here)
    python model/hsiao.py --matrix              the H matrix and the 7 check-bit equations
    python model/hsiao.py --plan                how the 54,204 test vectors are ordered
    python model/hsiao.py --vector 17963        explain ONE test vector, step by step
    python model/hsiao.py --vectors 100 20      table of 20 vectors starting at number 100
    python model/hsiao.py --data 89ABCDEF --err 0,4
                                                compact result for your own case
    python model/hsiao.py --data 89ABCDEF --err 0,4 --explain
                                                the same, with every step spelled out
    python model/hsiao.py --demo                a few example cases
    python model/hsiao.py --verify-hex tb/vectors/ecc_vectors.hex
                                                prove the vector file equals this model
(--err takes codeword bit numbers separated by commas: 0-31 are d0-d31, 32-38 are c0-c6.)

Other scripts that import this file (keep these names): H, K, R, N, build_h, row_bits,
encode, inject, syndrome, decode, test_words, self_test, card.
"""
import argparse
import random
import sys
from itertools import combinations

# =============================================================================
# 1. CODE PARAMETERS
# =============================================================================
K = 32                    # data bits per word
R = 7                     # check bits per word
N = K + R                 # codeword length = 39
DATA_MASK = (1 << K) - 1  # 0xFFFFFFFF, keeps only the 32 data bits of an integer


# =============================================================================
# 2. THE PARITY-CHECK MATRIX  H   (this is the whole definition of the code)
# =============================================================================
# H has R = 7 rows and N = 39 columns.  We store it column by column:
#     H[j]  is a 7-bit integer; bit i of H[j] is 1  <=>  codeword bit j takes part in
#     parity row i.
# Two facts make this a HSIAO code:
#     (a) every column has an ODD number of 1s, and
#     (b) all 39 columns are different.
# Then a single flipped bit gives an odd-weight syndrome and two flipped bits give an
# even-weight, non-zero one - which is exactly how the decoder tells the cases apart.
#
# How the columns are chosen:
#   * Check bit i uses the column 1 << i (weight 1: it takes part in row i only).
#   * Data bits use weight-3 columns (three 1s).  There are C(7,3) = 35 of them but we
#     only need 32, so we drop 3.  We drop the three below so that the rows end up with
#     almost the same number of data bits (13,13,14,14,14,14,14) - equal-sized rows mean
#     equally deep XOR trees in hardware.
DROP = ((0, 1, 2), (0, 1, 3), (4, 5, 6))      # row triples that are NOT used


def build_h(k=K, r=R, drop=DROP):
    """Return the list of the 39 column integers H[0..38].

    Keep this function separate from everything else: the research paper's code (for
    example a double-adjacent-error-correcting code) will supply its own build_h().
    """
    # every way to pick 3 of the 7 rows, in lexicographic order: (0,1,2),(0,1,3),...,(4,5,6)
    triples = [t for t in combinations(range(r), 3) if t not in drop]
    # turn a triple such as (0,1,4) into the 7-bit number with bits 0, 1 and 4 set
    data_cols = [sum(1 << row for row in t) for t in triples[:k]]
    assert len(data_cols) == k, "not enough weight-3 columns for this k"
    # check-bit columns: weight 1, bit i for check bit i
    check_cols = [1 << i for i in range(r)]
    return data_cols + check_cols


H = build_h()


def row_bits(h=H, k=K, r=R):
    """For every parity row i, the list of DATA bits that feed check bit i.

    Example: row_bits()[0] == [0,1,2,...,12]  means  c0 = d0 ^ d1 ^ ... ^ d12.
    """
    return [[j for j in range(k) if (h[j] >> i) & 1] for i in range(r)]


def check_matrix(h=H):
    """Verify the two Hsiao properties and return the row sizes."""
    assert len(h) == N and len(set(h)) == N, "columns must be distinct"
    assert all(popcount(c) % 2 == 1 for c in h), "Hsiao: every column must have odd weight"
    return [len(rw) for rw in row_bits(h)]


# =============================================================================
# 3. SMALL HELPERS
# =============================================================================
def popcount(x):
    """Number of 1 bits in x (the 'Hamming weight')."""
    return bin(x).count("1")


def bit_label(j):
    """Codeword bit number -> readable name: 5 -> 'd5', 34 -> 'c2'."""
    return ("d%d" % j) if j < K else ("c%d" % (j - K))


def flipped_list(mask):
    """Names of the bits that are 1 in an error mask, e.g. 'd0 d4' (or 'none')."""
    names = [bit_label(j) for j in range(N) if (mask >> j) & 1]
    return " ".join(names) if names else "none"


def bits_str(cw):
    """39-bit codeword as binary text, check bits and data bits separated: '0101010 | 1011...'"""
    return "%s | %s" % (format(cw >> K, "07b"), format(cw & DATA_MASK, "032b"))


# =============================================================================
# 4. THE FOUR OPERATIONS: encode / inject / syndrome / decode
# =============================================================================
def encode(data, h=H, k=K):
    """data (32-bit int) -> 39-bit codeword = data in the low 32 bits, check bits above.

    A check bit is the XOR of all data bits whose column has a 1 in that row.  So we
    walk over the data bits; every data bit that is 1 XORs its whole column into the
    7-bit accumulator `chk` (this updates all seven parities at once).
    """
    chk = 0
    for j in range(k):
        if (data >> j) & 1:
            chk ^= h[j]
    return (data & ((1 << k) - 1)) | (chk << k)        # check bits go to bits 32..38


def inject(cw, mask):
    """Flip the bits of the codeword that are 1 in `mask` (this models the radiation hit)."""
    return cw ^ mask


def syndrome(cw, h=H):
    """7-bit syndrome of a (possibly corrupted) 39-bit codeword.

    XOR together the column H[j] of every codeword bit j that is 1.  For an undamaged
    codeword the result is 0.  Key property: the syndrome depends ONLY on which bits
    were flipped, never on the data.  One flipped bit j gives syndrome == H[j]; two
    flipped bits a and b give H[a] XOR H[b].
    """
    s = 0
    for j in range(len(h)):
        if (cw >> j) & 1:
            s ^= h[j]
    return s


def decode(cw, h=H, k=K):
    """Decode a received 39-bit codeword.

    Returns the tuple (data_out, cw_out, syndrome, ce, ue, err_pos):
      data_out  32-bit data after correction (unchanged if nothing could be corrected)
      cw_out    the whole 39-bit codeword after correction
      syndrome  the 7-bit syndrome
      ce        1 = a single-bit error was found and corrected
      ue        1 = uncorrectable error detected (data NOT modified)
      err_pos   codeword bit number that was flipped back (0 when ce = 0)
    """
    s = syndrome(cw, h)
    data_mask = (1 << k) - 1
    if s == 0:                                  # all parities agree: no error
        return cw & data_mask, cw, 0, 0, 0, 0
    if s in h:                                  # syndrome equals the column of exactly one bit
        j = h.index(s)                          #   -> that bit flipped
        cw2 = cw ^ (1 << j)                     #   -> flip it back
        return cw2 & data_mask, cw2, s, 1, 0, j
    # Not zero and not a column: even weight (two errors) or an odd weight that matches
    # no column (three or more errors).  We cannot tell which bits are wrong -> change nothing.
    return cw & data_mask, cw, s, 0, 1, 0


# =============================================================================
# 5. THE TEST-VECTOR SET  (same order as tb/vectors/ecc_vectors.hex)
# =============================================================================
# A "test vector" = one data word + one error pattern (mask) + the golden answer.
# The set is built from a short list of data words (see test_words), and for each word:
#       1 clean vector                      (no error)
#      39 single-error vectors              (each of the 39 bits flipped alone)
#     741 double-error vectors              (every pair of bits, 39*38/2)
# followed by ALL 9,139 triple-error vectors for two of the words.
# Vector number n is line n+1 of ecc_vectors.hex and is printed as "vector #n" by the
# testbench; --vector n explains it.
TRIPLE_WORDS = (0x00000000, 0x89ABCDEF)
N_PAIRS = N * (N - 1) // 2                  # 741
N_TRIPLES = N * (N - 1) * (N - 2) // 6      # 9139
WORD_BLOCK = 1 + N + N_PAIRS                # 781 vectors per data word

_PAIRS = list(combinations(range(N), 2))    # pair order used by the generator
_TRIPLES = list(combinations(range(N), 3))  # triple order used by the generator


def test_words(n_random=10, seed=1):
    """The data words used for testing (in this order):
         word  0        0x00000000   all zeros
         word  1        0xFFFFFFFF   all ones
         word  2        0x55555555   alternating 0101...
         word  3        0xAAAAAAAA   alternating 1010...
         words 4..35    walking one: only bit (w-4) is 1
         words 36..    n_random pseudo-random words (fixed seed, so always the same)
    """
    rnd = random.Random(seed)
    words = [0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA]
    words += [1 << b for b in range(K)]
    words += [rnd.getrandbits(K) for _ in range(n_random)]
    return words


def word_description(w):
    """Human-readable meaning of data word number w."""
    if w == 0: return "all zeros"
    if w == 1: return "all ones"
    if w == 2: return "alternating 0101..."
    if w == 3: return "alternating 1010..."
    if w < 4 + K: return "walking one, only d%d = 1" % (w - 4)
    return "pseudo-random #%d" % (w - 4 - K)


def total_vectors():
    return len(test_words()) * WORD_BLOCK + len(TRIPLE_WORDS) * N_TRIPLES


def locate(idx):
    """Vector number -> (data, error mask, where-in-the-plan text).  No search needed:
    the order is a fixed formula, shown by --plan."""
    words = test_words()
    n_main = len(words) * WORD_BLOCK
    if idx < 0 or idx >= total_vectors():
        raise SystemExit("vector number must be 0..%d" % (total_vectors() - 1))
    if idx < n_main:
        w, off = divmod(idx, WORD_BLOCK)
        data = words[w]
        base = "data word #%d (%08x, %s), block offset %d: " % (w, data, word_description(w), off)
        if off == 0:
            return data, 0, base + "no error"
        if off <= N:
            return data, 1 << (off - 1), base + "single error at bit %d" % (off - 1)
        a, b = _PAIRS[off - 1 - N]
        return data, (1 << a) | (1 << b), base + "double error, pair #%d = bits %d and %d" % (off - 1 - N, a, b)
    t = idx - n_main
    wi, off = divmod(t, N_TRIPLES)
    data = TRIPLE_WORDS[wi]
    a, b, c = _TRIPLES[off]
    return (data, (1 << a) | (1 << b) | (1 << c),
            "triple-error block for data word %08x, triple #%d = bits %d, %d, %d" % (data, off, a, b, c))


KIND_TAGS = ["clean", "single-data", "single-check", "double-dd", "double-dc", "double-cc", "triple"]
KIND_NAMES = ["clean (no error)", "single error, data bit", "single error, check bit",
              "double error, data+data", "double error, data+check", "double error, check+check",
              "triple error"]


def kind_of(mask):
    """Classify an error mask: index into KIND_TAGS / KIND_NAMES."""
    n = popcount(mask)
    nd = popcount(mask & DATA_MASK)          # how many of the flipped bits are data bits
    if n == 0: return 0
    if n == 1: return 1 if nd == 1 else 2
    if n == 2: return 3 if nd == 2 else (4 if nd == 1 else 5)
    return 6


def vector_record(idx):
    """Everything about vector number idx, including the golden answer."""
    data, mask, where = locate(idx)
    stored = encode(data)
    cw_in = inject(stored, mask)
    d, co, s, ce, ue, pos = decode(cw_in)
    return dict(idx=idx, data=data, mask=mask, where=where, kind=kind_of(mask), stored=stored,
                cw_in=cw_in, syndrome=s, ce=ce, ue=ue, pos=pos, data_out=d, cw_out=co)


def pack_vector(r):
    """One record -> the 42-hex-digit line used in ecc_vectors.hex.
        [166:128] error mask   [127:89] cw_in   [88:57] data_out   [56:18] cw_out
        [17:11]   syndrome     [10] ce   [9] ue   [8:3] err_pos   [2:0] 0
    """
    v = ((r["mask"] << 128) | (r["cw_in"] << 89) | (r["data_out"] << 57) | (r["cw_out"] << 18)
         | (r["syndrome"] << 11) | (r["ce"] << 10) | (r["ue"] << 9) | (r["pos"] << 3))
    return "%042x" % v


# =============================================================================
# 6. DESCRIPTIVE OUTPUT
# =============================================================================
def decision_text(mask, ce, ue, pos, syn):
    """One-sentence explanation of what the decoder did."""
    if not ce and not ue:
        return "no error detected: data passed through unchanged"
    if ce:
        t = "single error at %s (codeword bit %d) corrected: syndrome equals that bit's column of H" % (bit_label(pos), pos)
        if popcount(mask) >= 3:
            t += "  ** MISCORRECTION: %d errors were injected, decoder believes 1 **" % popcount(mask)
        return t
    if popcount(syn) % 2 == 0:
        return "even-weight syndrome => 2 errors: detected, NOT correctable, decoder leaves the received data as it is"
    return "odd-weight syndrome matching no column => 3+ errors: detected, NOT correctable, decoder leaves the received data as it is"


def card(data, mask, title=None):
    """Compact result for: store `data`, flip the bits in `mask`, read back, decode.
    (Same layout as the testbench console cards.)"""
    data &= DATA_MASK
    cw = encode(data)
    cw_in = inject(cw, mask)
    d, co, s, ce, ue, pos = decode(cw_in)
    print("=== golden model: %s %s" % (title or KIND_NAMES[kind_of(mask)], "=" * 33))
    print("  INPUT   data to store      : %08x" % data)
    print("  ENCODE  stored codeword    : %010x   (check bits %02x)" % (cw, cw >> K))
    print("  INJECT  error mask         : %010x   flipped bits: %s" % (mask, flipped_list(mask)))
    print("  READ    codeword read back : %010x" % cw_in)
    print("  DECODE  syndrome           : %s / %02x   (weight %d, %s)" % (
        format(s, "07b"), s, popcount(s), "odd" if popcount(s) % 2 else "even" if s else "zero"))
    print("          ce / ue            : %d / %d" % (ce, ue))
    print("          err_pos            : %d" % pos)
    print("          data_out           : %08x" % d)
    print("          cw_out             : %010x" % co)
    print("  DECISION: " + decision_text(mask, ce, ue, pos, s))
    print("  data_out %s the stored data" % ("EQUALS" if d == data else "DIFFERS FROM"))
    print()


def explain(data, mask, title=None):
    """Spell out EVERY step for one case, using only the definitions above."""
    data &= DATA_MASK
    rows = row_bits()
    print("=" * 78)
    print("STEP-BY-STEP: %s" % (title or KIND_NAMES[kind_of(mask)]))
    print("=" * 78)

    # ---- step 1: encode --------------------------------------------------------
    print("\nSTEP 1  ENCODE   data word = %08x  =  %s" % (data, format(data, "032b")))
    print("  Each check bit is the parity (XOR) of the data bits listed for its row.")
    chk = 0
    for i, bits in enumerate(rows):
        vals = [(data >> b) & 1 for b in bits]
        ones = sum(vals)
        c = ones % 2
        chk |= c << i
        print("  c%d: data bits %-60s" % (i, " ".join("d%d" % b for b in bits)))
        print("      their values   %s   -> %d ones (%s) -> c%d = %d" % (
            "".join(str(v) for v in vals), ones, "odd" if ones % 2 else "even", i, c))
    stored = (data) | (chk << K)
    assert stored == encode(data)
    print("  check bits c6..c0 = %s = %02x" % (format(chk, "07b"), chk))
    print("  stored codeword (39 bits) = %010x" % stored)
    print("      c6..c0 | d31..d0")
    print("      %s" % bits_str(stored))

    # ---- step 2: inject --------------------------------------------------------
    cw_in = inject(stored, mask)
    print("\nSTEP 2  INJECT   error mask = %010x   flipped bits: %s" % (mask, flipped_list(mask)))
    print("  codeword read back = %010x" % cw_in)
    print("      %s" % bits_str(cw_in))

    # ---- step 3: syndrome ------------------------------------------------------
    print("\nSTEP 3  SYNDROME  recompute every parity on the RECEIVED word, including its own check bit.")
    print("  s_i = XOR( received data bits of row i , received c_i ).  s_i = 0 means row i is consistent.")
    syn = 0
    for i, bits in enumerate(rows):
        names = ["d%d" % b for b in bits] + ["c%d" % i]            # the bits that take part in row i
        vals = [(cw_in >> b) & 1 for b in bits] + [(cw_in >> (K + i)) & 1]
        ones = sum(vals)
        s_i = ones % 2
        syn |= s_i << i
        which = " ".join(n for n, v in zip(names, vals) if v) or "-"
        print("  s%d: received 1s in row %d: [%s]  -> %d (%s)  -> s%d = %d" % (
            i, i, which, ones, "odd" if ones % 2 else "even", i, s_i))
    assert syn == syndrome(cw_in)
    print("  syndrome s6..s0 = %s = 0x%02x   weight %d (%s)" % (
        format(syn, "07b"), syn, popcount(syn), "odd" if popcount(syn) % 2 else "even" if syn else "zero"))

    # ---- step 4: decide --------------------------------------------------------
    print("\nSTEP 4  DECIDE")
    d, co, s, ce, ue, pos = decode(cw_in)
    if syn == 0:
        print("  syndrome is 0 -> no error.")
    else:
        match = [j for j in range(N) if H[j] == syn]
        if match:
            print("  syndrome equals the column of %s (codeword bit %d, H[%d] = %s) -> single error there."
                  % (bit_label(match[0]), match[0], match[0], format(H[match[0]], "07b")))
            print("  the decoder flips that bit back.")
        else:
            kind = "even weight -> an even number of errors (2)" if popcount(syn) % 2 == 0 \
                   else "odd weight but no column matches -> 3 or more errors"
            print("  syndrome is not 0 and equals no column of H: %s." % kind)
            print("  the decoder cannot tell which bits are wrong -> ue = 1, nothing is changed.")

    # ---- step 5: result --------------------------------------------------------
    print("\nSTEP 5  RESULT")
    print("  ce = %d   ue = %d   err_pos = %d" % (ce, ue, pos))
    print("  cw_out   = %010x" % co)
    print("  data_out = %08x   (stored data was %08x) -> %s" % (
        d, data, "CORRECT" if d == data else "NOT equal to the stored data"))
    print("  " + decision_text(mask, ce, ue, pos, s))
    print()


def parse_bits(text):
    """'0,4' -> error mask with bits 0 and 4 set."""
    bits = [int(x) for x in text.replace(" ", "").split(",") if x != ""]
    for b in bits:
        if not 0 <= b < N:
            raise SystemExit("bit %d out of range 0..%d" % (b, N - 1))
    return sum(1 << b for b in set(bits))


def print_code_definition():
    """H matrix columns, row sizes, check-bit equations, and what the 128 syndromes mean."""
    sizes = check_matrix()
    print("=" * 78)
    print("[1] THE CODE: Hsiao (39,32) SEC-DED")
    print("=" * 78)
    print("32 data bits d0..d31 + 7 check bits c0..c6 = 39-bit codeword.")
    print("H column of each bit (7-bit, row 6 on the left; bit i of the column = 1 means the")
    print("bit takes part in parity row i):\n")
    print("   bit  name  column    weight  in rows")
    for j in range(N):
        rows_in = [i for i in range(R) if (H[j] >> i) & 1]
        print("   %-4d %-4s  %s   %d       %s" % (j, bit_label(j), format(H[j], "07b"), popcount(H[j]),
                                                 ",".join(str(i) for i in rows_in)))
    print("\nChecks: 39 columns, all different, all odd weight  ->  Hsiao property holds.")
    print("Row sizes (data bits per check bit): %s   (total %d ones)\n" % (sizes, sum(sizes)))
    print("Check-bit equations (c_i = XOR of the listed data bits):")
    for i, bits in enumerate(row_bits()):
        print("  c%d = %s    (%d bits)" % (i, " ^ ".join("d%d" % b for b in bits), len(bits)))

    # what every possible syndrome means
    cols = set(H)
    odd_unused = [s for s in range(1 << R) if popcount(s) % 2 == 1 and s not in cols]
    even_nz = sum(1 for s in range(1, 1 << R) if popcount(s) % 2 == 0)
    print("\n" + "=" * 78)
    print("[2] WHAT EACH OF THE 2^7 = 128 POSSIBLE SYNDROMES MEANS")
    print("=" * 78)
    print("  %3d  syndrome 0000000                      -> no error" % 1)
    print("  %3d  odd weight, equal to a column of H    -> single error, corrected (7 check-bit + 32 data-bit columns)" % len(cols))
    print("  %3d  even weight, not 0                    -> double error (or more), detected only" % even_nz)
    print("  %3d  odd weight, matching NO column        -> 3 or more errors, detected only (unused odd syndromes:"
          % len(odd_unused))
    print("       weight 3: %d, weight 5: %d, weight 7: %d)" % (
        sum(1 for s in odd_unused if popcount(s) == 3), sum(1 for s in odd_unused if popcount(s) == 5),
        sum(1 for s in odd_unused if popcount(s) == 7)))
    print("  total %d" % (1 + len(cols) + even_nz + len(odd_unused)))
    print()


def print_vector_plan():
    """Explain how vector numbers map to data words and error patterns."""
    words = test_words()
    n_main = len(words) * WORD_BLOCK
    print("=" * 78)
    print("[3] THE TEST VECTORS: %d in total (vector n = line n+1 of ecc_vectors.hex)" % total_vectors())
    print("=" * 78)
    print("%d data words (see table) x %d vectors each = %d, then triple-error blocks." % (len(words), WORD_BLOCK, n_main))
    print("Inside each data word's block of %d vectors:" % WORD_BLOCK)
    print("   offset 0            clean (no error)")
    print("   offsets 1..%d       single error: offset k flips codeword bit k-1  (k=1 -> d0 ... k=39 -> c6)" % N)
    print("   offsets %d..%d     double error: the %d pairs of bits (a,b), a<b, in the order" % (N + 1, WORD_BLOCK - 1, N_PAIRS))
    print("                       (0,1) (0,2) ... (0,38) (1,2) ... (37,38)")
    print("   so vector n of word w: offset = n - %d*w.\n" % WORD_BLOCK)
    print("   word  data      meaning                       vector numbers")
    for w, d in enumerate(words):
        print("   %-4d  %08x  %-28s  %d .. %d" % (w, d, word_description(w), w * WORD_BLOCK, (w + 1) * WORD_BLOCK - 1))
    for k, d in enumerate(TRIPLE_WORDS):
        lo = n_main + k * N_TRIPLES
        print("   T%-3d  %08x  all %d triple errors (a<b<c)   %d .. %d" % (k, d, N_TRIPLES, lo, lo + N_TRIPLES - 1))
    print()


def print_vector_table(recs):
    """Table of vectors: everything needed to map a hex line to its meaning."""
    print("%6s  %-12s %-8s %-10s %-14s %-10s %-3s %-2s %-2s %-3s %-8s" % (
        "vec#", "kind", "data", "err mask", "flipped bits", "cw_in", "syn", "ce", "ue", "pos", "data_out"))
    print("-" * 104)
    for r in recs:
        print("%6d  %-12s %08x %010x %-14s %010x %02x  %-2d %-2d %-3d %08x" % (
            r["idx"], KIND_TAGS[r["kind"]], r["data"], r["mask"], flipped_list(r["mask"]), r["cw_in"],
            r["syndrome"], r["ce"], r["ue"], r["pos"], r["data_out"]))
    print()


# =============================================================================
# 7. SELF-TEST
# =============================================================================
def self_test(verbose=True):
    """Check the model against its own promises. Returns (miscorrected, flagged) for triples.

    Part A (136 data words, as before): every single error is corrected, every double error
            is detected with the data unchanged.
    Part B (only when verbose): run through the actual 54,204-vector test set and report,
            per kind, how many vectors there are and what the decoder did with them.
    """
    weights = check_matrix()
    n_single = n_double = 0
    for d in test_words(100):
        cw = encode(d)
        assert decode(cw) == (d, cw, 0, 0, 0, 0)
        for j in range(N):
            r = decode(inject(cw, 1 << j))
            assert r[0] == d and r[1] == cw and r[3] == 1 and r[4] == 0 and r[5] == j, (hex(d), j, r)
            n_single += 1
        for a, b in combinations(range(N), 2):
            bad = inject(cw, (1 << a) | (1 << b))
            r = decode(bad)
            assert r[0] == (bad & DATA_MASK) and r[3] == 0 and r[4] == 1, (hex(d), a, b, r)
            assert popcount(r[2]) % 2 == 0
            n_double += 1
    # triple errors: the syndrome does not depend on the data, so one pass is enough
    mis = det = 0
    for a, b, c in combinations(range(N), 3):
        s = syndrome((1 << a) | (1 << b) | (1 << c))
        if s in H: mis += 1
        else:      det += 1

    if verbose:
        print("=" * 78)
        print("[4] SELF-TEST")
        print("=" * 78)
        print("Part A: %d data words x all single and all double errors" % len(test_words(100)))
        print("  row sizes %s, total %d ones" % (weights, sum(weights)))
        print("  %6d single errors : every one corrected, right position, data restored" % n_single)
        print("  %6d double errors : every one detected (ue=1, ce=0), data left unchanged, even syndrome" % n_double)
        print("  %6d triple errors : %d MISCORRECTED (look like a single error), %d flagged uncorrectable"
              % (mis + det, mis, det))
        print("  -> triple errors have no guarantee; this is the limit of SEC-DED.\n")
        _vector_set_report()
    return mis, det


def _vector_set_report():
    """Part B: classify and check the whole test-vector set, print a table per kind."""
    stats = [dict(n=0, ce=0, ue=0, clean=0, data_ok=0) for _ in KIND_TAGS]
    first = [[] for _ in KIND_TAGS]
    for idx in range(total_vectors()):
        r = vector_record(idx)
        k = r["kind"]
        s = stats[k]
        s["n"] += 1
        s["ce"] += r["ce"]
        s["ue"] += r["ue"]
        s["clean"] += 1 if (r["ce"] == 0 and r["ue"] == 0) else 0
        s["data_ok"] += 1 if r["data_out"] == r["data"] else 0
        if len(first[k]) < 3:
            first[k].append(idx)
        # the promises, checked on every vector of the set
        if k == 0:
            assert (r["ce"], r["ue"], r["data_out"]) == (0, 0, r["data"])
        elif k in (1, 2):
            assert (r["ce"], r["ue"]) == (1, 0) and r["data_out"] == r["data"] and r["cw_out"] == r["stored"]
            assert r["pos"] == r["mask"].bit_length() - 1
        elif k in (3, 4, 5):
            assert (r["ce"], r["ue"]) == (0, 1) and r["data_out"] == (r["cw_in"] & DATA_MASK)
            assert popcount(r["syndrome"]) % 2 == 0
    print("Part B: the %d vectors of the test set, grouped by kind" % total_vectors())
    print("  kind                          vectors  corrected(ce)  uncorrectable(ue)  no flag  data_out==stored  first vector numbers")
    for k, name in enumerate(KIND_NAMES):
        s = stats[k]
        print("  %-27s %8d %14d %18d %8d %17d  %s" % (
            name, s["n"], s["ce"], s["ue"], s["clean"], s["data_ok"], ", ".join(str(i) for i in first[k])))
    print("  How to read the table:")
    print("   - clean: nothing flagged.   single: every one corrected (ce=1) and the data is restored.")
    print("   - double: every one flagged ue=1, nothing corrected. 'data_out==stored' is 0 for data+data and")
    print("     data+check because a data bit stays wrong; it is 966 (all) for check+check only because those")
    print("     errors never touched the data bits - the error is still detected (ue=1).")
    print("   - triple: no guarantee. ce=1 means a WRONG correction (miscorrection, data still wrong);")
    print("     ue=1 means detected. The 6 vectors with data_out==stored are triples confined to check bits")
    print("     (c0 c1 c2, c0 c1 c3, c4 c5 c6 for each of the 2 words) that were flagged ue=1.")
    print("  (all single/double/clean expectations are asserted on every vector: PASS)\n")


# =============================================================================
# 8. COMMAND LINE
# =============================================================================
def demo():
    data = 0x89ABCDEF
    cases = [(0, "no error"),
             (1 << 5, "single error in data bit d5"),
             (1 << 35, "single error in check bit c3"),
             ((1 << 0) | (1 << 4), "double error, d0 and d4"),
             ((1 << 3) | (1 << 35), "double error, d3 and c3"),
             ((1 << 33) | (1 << 36), "double error, c1 and c4"),
             ((1 << 1) | (1 << 2) | (1 << 3), "triple error d1 d2 d3 (no guarantee)")]
    for m, title in cases:
        card(data, m, title)


def matrix():
    print_code_definition()


def verify_hex(path):
    """Compare every line of a vector file with this model. Returns 0 if identical."""
    with open(path) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    total = total_vectors()
    print("file %s: %d lines; the model expects %d vectors of %d hex digits" % (path, len(lines), total, 42))
    if lines and len(lines[0]) != 42:
        print("line length %d is not 42: this is the OLD vector format (no error mask)." % len(lines[0]))
        print("Regenerate with:  python model/gen.py --vectors-only")
        return 1
    bad = 0
    for idx in range(min(len(lines), total)):
        want = pack_vector(vector_record(idx))
        if lines[idx] != want:
            bad += 1
            if bad <= 5:
                print("  MISMATCH at vector #%d (line %d):\n    file : %s\n    model: %s" % (idx, idx + 1, lines[idx], want))
    if len(lines) != total:
        print("  line count differs: file %d, model %d" % (len(lines), total))
        bad += 1
    print("RESULT: %s" % ("every line of the file equals the golden model" if bad == 0 else "%d differences" % bad))
    return 1 if bad else 0


def report():
    """Default output: everything, in order."""
    print_code_definition()
    print_vector_plan()
    self_test(verbose=True)
    print("[5] EXPLORE FURTHER")
    print("  python model/hsiao.py --vector 17963              explain one test vector step by step")
    print("  python model/hsiao.py --vectors 0 45              table of vectors 0..44")
    print("  python model/hsiao.py --data 89ABCDEF --err 0,4 --explain   your own case")
    print("  python model/hsiao.py --verify-hex tb/vectors/ecc_vectors.hex   check the vector file")
    print("RESULT: PASS")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Golden model of the P12 Hsiao (39,32) code", add_help=True)
    ap.add_argument("--matrix", action="store_true", help="H matrix and check-bit equations")
    ap.add_argument("--plan", action="store_true", help="how the test vectors are numbered")
    ap.add_argument("--demo", action="store_true", help="example cases")
    ap.add_argument("--vector", type=int, metavar="N", help="explain vector number N step by step")
    ap.add_argument("--vectors", type=int, nargs=2, metavar=("START", "COUNT"), help="table of vectors")
    ap.add_argument("--data", metavar="HEX", help="data word (hex) for your own case")
    ap.add_argument("--err", metavar="BITS", help="codeword bit numbers to flip, e.g. 0,4")
    ap.add_argument("--explain", action="store_true", help="with --data: spell out every step")
    ap.add_argument("--verify-hex", metavar="FILE", help="check a vector file against this model")
    a = ap.parse_args(argv)

    if a.matrix:
        matrix()
    elif a.plan:
        print_vector_plan()
    elif a.demo:
        demo()
    elif a.vector is not None:
        r = vector_record(a.vector)
        print("VECTOR #%d   (line %d of ecc_vectors.hex)" % (r["idx"], r["idx"] + 1))
        print("  plan position : %s" % r["where"])
        print("  packed hex    : %s" % pack_vector(r))
        print("                  [166:128] mask  [127:89] cw_in  [88:57] data_out  [56:18] cw_out  [17:11] syndrome  [10] ce  [9] ue  [8:3] err_pos")
        print()
        explain(r["data"], r["mask"], "%s  (vector #%d)" % (KIND_NAMES[r["kind"]], r["idx"]))
    elif a.vectors:
        start, count = a.vectors
        end = min(start + count, total_vectors())
        print_vector_table([vector_record(i) for i in range(start, end)])
    elif a.data is not None:
        data = int(a.data, 16)
        mask = parse_bits(a.err) if a.err else 0
        if a.explain:
            explain(data, mask)
        else:
            card(data, mask)
    elif a.verify_hex:
        return verify_hex(a.verify_hex)
    else:
        report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
