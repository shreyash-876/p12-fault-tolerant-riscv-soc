// P12 SoC register map (frozen in Stage 1)
#pragma once
#include <stdint.h>

#define REG32(a)        (*(volatile uint32_t *)(a))

// data RAM (ECC-protected from Stage 2)
#define DMEM_BASE       0x20000000u

// ECC register window (Stage 1: ID + scratch only)
#define ECC_ID          REG32(0x40000000u)
#define ECC_SCRATCH0    REG32(0x40000004u)
#define ECC_SCRATCH1    REG32(0x40000008u)
#define ECC_SCRATCH2    REG32(0x4000000Cu)   // simulation result signature
#define SIG_PASS        0x0000600Du
#define SIG_FAIL(n)     (0xBAD00000u | (n))

// GPIO
#define GPIO_LED        REG32(0x80000000u)
#define GPIO_SW         REG32(0x80000004u)
#define GPIO_BTN        REG32(0x80000008u)

// UART
#define UART_TXDATA     REG32(0x80001000u)
#define UART_STATUS     REG32(0x80001004u)

static inline void uart_putc(char c) { while (UART_STATUS & 1u) ; UART_TXDATA = (uint8_t)c; }
static inline void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
static inline void uart_puthex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789ABCDEF"[(v >> i) & 0xF]);
}
static inline void uart_putdec(uint32_t v) {
    char b[11]; int n = 0;
    do { b[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) uart_putc(b[--n]);
}
