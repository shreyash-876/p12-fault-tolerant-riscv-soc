#!/usr/bin/env python3
"""bin2hex.py in.bin out.hex [pad_words]
-> one little-endian 32-bit word per line ($readmemh format), optionally padded
   with NOPs (0x00000013) to pad_words so $readmemh does not warn."""
import sys
data = open(sys.argv[1], "rb").read()
data += b"\x00" * (-len(data) % 4)
with open(sys.argv[2], "w") as f:
    n = 0
    for i in range(0, len(data), 4):
        f.write("%08x\n" % int.from_bytes(data[i:i+4], "little")); n += 1
    pad = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    if n > pad > 0:
        sys.exit("program (%d words) does not fit in %d words" % (n, pad))
    for _ in range(max(0, pad - n)):
        f.write("00000013\n")
