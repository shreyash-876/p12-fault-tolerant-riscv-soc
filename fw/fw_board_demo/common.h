// Shared by the firmware (main.c) and a PC program (host_ref.c) that computes the expected checksum.
#pragma once
#define NWORDS 128

static inline uint32_t golden(uint32_t i) {            // the value word i of the protected buffer must always hold
    return 0x9E3779B9u ^ (i << 24) ^ (i << 12) ^ (i << 3) ^ ((i & 7u) << 29);
}
static inline uint32_t rol5(uint32_t x) { return (x << 5) | (x >> 27); }
