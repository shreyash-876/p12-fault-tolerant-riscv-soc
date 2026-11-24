// -----------------------------------------------------------------------------
// Stage 1 firmware: memory test of the AXI4-Lite data RAM path.
// Runs forever. Every pass:
//   1 walking ones / zeros          4 sub-word stores + sign/zero-extended loads
//   2 address-in-address            5 pseudo-random pattern (LFSR)
//   3 inverse address               6 register window (ID + scratch)
// LD0 blinks (toggles every 64 passes, a few Hz), LD1 follows SW0 (GPIO input path),
// LD3 lights and stays on after any failure. UART prints pass 1 and every 100th pass
// at 115200 8N1. The first pass also writes the simulation signature.
// This program must keep passing UNCHANGED in Stages 2 and 3.
// -----------------------------------------------------------------------------
#include "p12.h"

#define N_WORDS 1024                         // 4 KB test buffer in DMEM (.bss)
static volatile uint32_t buf[N_WORDS];
static uint32_t fails;                       // .bss
static uint32_t seed = 0xACE1u;              // .data (tests the ITCM->DMEM copy)
static const char banner[] = "\r\nP12 stage 1: AXI4-Lite BRAM memory test\r\n";  // .rodata in ITCM

static void check(uint32_t test, uint32_t idx, uint32_t got, uint32_t exp) {
    if (got != exp) {
        if (fails < 8) {
            uart_puts("  FAIL t"); uart_putdec(test);
            uart_puts(" @"); uart_puthex((uint32_t)&buf[idx]);
            uart_puts(" got "); uart_puthex(got);
            uart_puts(" exp "); uart_puthex(exp); uart_puts("\r\n");
        }
        if (fails == 0) ECC_SCRATCH2 = SIG_FAIL(test);
        fails++;
    }
}

static uint32_t lfsr(uint32_t x) {           // 32-bit Galois LFSR
    return (x >> 1) ^ (-(x & 1u) & 0xD0000001u);
}

static void run_tests(void) {
    // 1 walking ones and zeros on two words
    for (int b = 0; b < 32; b++) {
        buf[0] = 1u << b;       check(1, 0, buf[0], 1u << b);
        buf[1] = ~(1u << b);    check(1, 1, buf[1], ~(1u << b));
    }
    // 2 address-in-address
    for (int i = 0; i < N_WORDS; i++) buf[i] = (uint32_t)&buf[i];
    for (int i = 0; i < N_WORDS; i++) check(2, i, buf[i], (uint32_t)&buf[i]);
    // 3 inverse address
    for (int i = 0; i < N_WORDS; i++) buf[i] = ~(uint32_t)&buf[i];
    for (int i = 0; i < N_WORDS; i++) check(3, i, buf[i], ~(uint32_t)&buf[i]);
    // 4 sub-word accesses (generate WSTRB 0001/0010/0100/1000/0011/1100)
    for (int i = 0; i < 64; i++) {
        volatile uint8_t  *b8  = (volatile uint8_t  *)&buf[i];
        volatile uint16_t *b16 = (volatile uint16_t *)&buf[i];
        volatile int8_t   *s8  = (volatile int8_t   *)&buf[i];
        volatile int16_t  *s16 = (volatile int16_t  *)&buf[i];
        buf[i] = 0x11223344u;
        b8[1] = 0xA5;                       check(4, i, buf[i], 0x1122A544u);
        b8[3] = 0x80;                       check(4, i, buf[i], 0x8022A544u);
        b16[0] = 0xBEEF;                    check(4, i, buf[i], 0x8022BEEFu);
        b16[1] = 0x7FFE;                    check(4, i, buf[i], 0x7FFEBEEFu);
        check(4, i, (uint32_t)(int32_t)s8[0],  0xFFFFFFEFu);   // LB  sign-extends
        check(4, i, (uint32_t)b8[2],           0x000000FEu);   // LBU
        check(4, i, (uint32_t)(int32_t)s16[0], 0xFFFFBEEFu);   // LH
        check(4, i, (uint32_t)b16[1],          0x00007FFEu);   // LHU
    }
    // 5 pseudo-random pattern
    uint32_t x = seed;
    for (int i = 0; i < N_WORDS; i++) { buf[i] = x; x = lfsr(x); }
    x = seed;
    for (int i = 0; i < N_WORDS; i++) { check(5, i, buf[i], x); x = lfsr(x); }
    seed = x;
    // 6 register window
    check(6, 0, ECC_ID, 0x50312001u);
    ECC_SCRATCH0 = 0x12345678u;             check(6, 0, ECC_SCRATCH0, 0x12345678u);
}

int main(void) {
    uart_puts(banner);
    uart_puts("ECC block ID = "); uart_puthex(ECC_ID); uart_puts("\r\n");

    for (uint32_t pass = 1; ; pass++) {
        run_tests();
        GPIO_LED = ((pass >> 6) & 1u) | ((GPIO_SW & 1u) << 1) | (fails ? 0x8u : 0x0u);
        if (pass == 1 || pass % 100u == 0) {
            uart_puts("pass "); uart_putdec(pass);
            uart_puts(fails ? "  FAILURES=" : "  ok, failures=");
            uart_putdec(fails); uart_puts("\r\n");
        }
        if (pass == 1 && fails == 0) ECC_SCRATCH2 = SIG_PASS;   // tells tb_soc we are done
    }
}
