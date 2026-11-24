// The deterministic workload of the interrupt stress test. It is included by the firmware (main.c) and by a PC program
// (host_ref.c) that computes the correct result independently of the RISC-V core.
// The includer defines WL_CSR_WRITE(v) / WL_CSR_READ() (a CSR instruction on the core, a plain variable on the PC).
#pragma once

#define PASSES 24

static volatile uint32_t arr[64];
static volatile uint8_t  bytes[64];

static uint32_t rol(uint32_t x, uint32_t n) { return (x << n) | (x >> (32u - n)); }
typedef uint32_t (*op_fn)(uint32_t);
static uint32_t op_a(uint32_t x) { return rol(x, 3) ^ 0x9E3779B9u; }
static uint32_t op_b(uint32_t x) { return x + (x >> 7) + 12345u; }
static uint32_t op_c(uint32_t x) { return ~x ^ (x << 11); }
static uint32_t op_d(uint32_t x) { arr[x & 63u]++; return x ^ arr[(x >> 6) & 63u]; }   // memory read-modify-write
static op_fn ops[4] = { op_a, op_b, op_c, op_d };

static uint32_t work(uint32_t seed) {
    uint32_t s = seed;
    for (uint32_t i = 0; i < 64; i++) { arr[i] = s ^ i; s = rol(s, 5) + arr[i]; }            // word stores, load-use
    for (uint32_t i = 0; i < 64; i++) { bytes[i] = (uint8_t)(s >> (i & 24u)); s ^= (uint32_t)bytes[i] << (i & 7u); }   // byte stores/loads
    for (uint32_t i = 0; i < 32; i++) {                                                         // halfword stores/loads
        ((volatile uint16_t *)arr)[i] = (uint16_t)(s + i);
        s += ((volatile uint16_t *)arr)[i ^ 1u];
    }
    for (uint32_t i = 0; i < 100; i++) {                                                        // calls through pointers, branches
        s = ops[(s >> 3) & 3u](s);
        if (s & 1u) s += i; else s ^= i;
    }
    for (uint32_t i = 0; i < 16; i++) {                                                         // CSR instructions
        WL_CSR_WRITE(s);
        s = rol(WL_CSR_READ(), 1) + (s >> 3) + i;
    }
    return s;
}

static uint32_t run_all(void) {
    uint32_t sum = 0;
    for (uint32_t p = 0; p < PASSES; p++) sum ^= work(p) + p;
    return sum;
}
