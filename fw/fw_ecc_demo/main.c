// -----------------------------------------------------------------------------
// P12 ECC demo firmware: counters, error log, error injection, scrubber, interrupt flag.
// Self-checking: it writes the result signature to ECC_SCRATCH2 (0x600D = pass, 0xBAD000nn = check nn failed).
//   A  one single-bit error is injected, a CPU read corrects it: counter, flag, log entry
//   B  one single-bit error (a check bit) is repaired by the scrubber: counter, log entry "scrubber"
//   C  a double-bit error: counted, logged, STATUS.UE_SEEN (the interrupt source), acknowledge, recover
//   D  a board button (BTN1) injects an error; the program result stays correct
//   E  the checksum of the data buffer is unchanged after all of that
// -----------------------------------------------------------------------------
#include "p12.h"
#include "p12_regs.h"

static volatile uint32_t buf[64];
static volatile uint32_t spare[4];
static uint32_t fails;

static void check(uint32_t n, int cond) {
    if (!cond) {
        if (fails == 0) ECC_SCRATCH2 = SIG_FAIL(n);
        fails++;
        uart_puts("   FAIL check "); uart_putdec(n); uart_puts("\r\n");
    }
}

static uint32_t checksum(void) {                    // rotate-and-xor over the buffer (no multiply needed)
    uint32_t s = 0x12345678u;
    for (uint32_t i = 0; i < 64; i++) s = ((s << 5) | (s >> 27)) ^ buf[i] ^ (0x01000193u + i);
    return s;
}

static void print_entry(uint32_t a, uint32_t i) {
    uart_puts("   log: word "); uart_puthex(a);
    if (i & LOG_UE) uart_puts(", UNCORRECTABLE");
    else { uart_puts(", corrected bit "); uart_putdec(LOG_BIT(i)); }
    uart_puts(", syndrome "); uart_puthex(LOG_SYNDROME(i));
    uart_puts((i & LOG_SCRUB) ? ", found by the scrubber\r\n" : ", found by the CPU\r\n");
}

static void print_counters(void) {
    uart_puts("   counters: corrected "); uart_putdec(ECC_CE_COUNT);
    uart_puts(", uncorrectable "); uart_putdec(ECC_UE_COUNT);
    uart_puts(", injected "); uart_putdec(ECC_INJ_COUNT);
    uart_puts(", repaired by scrubber "); uart_putdec(ECC_SCRUB_REPAIRED); uart_puts("\r\n");
}

int main(void) {
    uint32_t a, i, v, t, ce0, ic0;
    uint32_t exp10, exp20, exp30;

    uart_puts("\r\nP12 ECC demo: injection, counters, log, scrubber, interrupt flag\r\n");
    check(1, ECC_ID == 0x50312001u);

    // start clean, scrubber off for now
    ECC_CTRL = CTRL_SCRUB_EN | CTRL_CLEAR;
    ECC_STATUS = ST_CE_SEEN | ST_UE_SEEN | ST_LOG_OVERRUN;
    ECC_CTRL = 0;

    for (int k = 0; k < 64; k++) buf[k] = 0x9E3779B9u ^ ((uint32_t)k << 11) ^ ((uint32_t)k << 24);
    for (int k = 0; k < 4; k++) spare[k] = 0;
    uint32_t sum0 = checksum();
    check(28, sum0 == 0x40A0F352u);                // the value an independent Python computation gives
    exp10 = buf[10]; exp20 = buf[20]; exp30 = buf[30];

    // ---------------- A: single error, found by a CPU read ----------------
    uart_puts("A: flip data bit 5 of buf[10], then read it\r\n");
    ecc_inject((uint32_t)&buf[10], 1u << 5, 0);
    check(2, ECC_INJ_COUNT == 1);
    check(3, ECC_CE_COUNT == 0 && ECC_UE_COUNT == 0);          // an injection is not an error event
    v = buf[10];                                               // corrected on the fly
    check(4, v == exp10);
    check(5, ECC_CE_COUNT == 1 && ECC_UE_COUNT == 0);
    check(6, (ECC_STATUS & ST_CE_SEEN) != 0 && ST_LOG_LEVEL(ECC_STATUS) == 1);
    check(7, ecc_log_pop(&a, &i));
    print_entry(a, i);
    check(8, a == (uint32_t)&buf[10] && LOG_BIT(i) == 5 && !(i & LOG_UE) && !(i & LOG_SCRUB));
    ECC_STATUS = ST_CE_SEEN;
    check(9, (ECC_STATUS & ST_CE_SEEN) == 0);
    buf[10] = exp10;                       // a read corrects the value but does NOT repair the stored word: rewrite it
    print_counters();

    // ---------------- B: single error (a check bit), repaired by the scrubber ----------------
    uart_puts("B: flip check bit c2 of buf[20]; the scrubber repairs it\r\n");
    ecc_inject((uint32_t)&buf[20], 0, 1u << 2);
    ECC_SCRUB_INTERVAL = 4;
    ECC_CTRL = CTRL_SCRUB_EN;
    for (t = 0; ECC_SCRUB_REPAIRED == 0 && t < 200000; t++) ;
    ECC_CTRL = 0;
    check(10, ECC_SCRUB_REPAIRED == 1);
    check(11, ECC_CE_COUNT == 2);
    check(12, ecc_log_pop(&a, &i));
    print_entry(a, i);
    check(13, a == (uint32_t)&buf[20] && LOG_BIT(i) == 34 && !(i & LOG_UE) && (i & LOG_SCRUB));
    ECC_STATUS = ST_CE_SEEN;
    print_counters();
    uart_puts("   scrubber sweeps completed so far: "); uart_putdec(ECC_SCRUB_SWEEPS); uart_puts("\r\n");

    // ---------------- C: double error: counted, logged, flag, acknowledge, recover ----------------
    uart_puts("C: flip data bits 3 and 17 of spare[0]: uncorrectable\r\n");
    ECC_CTRL = CTRL_IRQ_UE_EN;                                 // the irq_ue line now follows STATUS.UE_SEEN
    ecc_inject((uint32_t)&spare[0], (1u << 3) | (1u << 17), 0);
    v = spare[0];                                              // the bus answers SLVERR; the data is returned as stored
    check(14, v == ((1u << 3) | (1u << 17)));
    check(15, ECC_UE_COUNT == 1);
    check(16, (ECC_STATUS & ST_UE_SEEN) != 0);
    check(17, ecc_log_pop(&a, &i));
    print_entry(a, i);
    check(18, a == (uint32_t)&spare[0] && (i & LOG_UE) && !(i & LOG_SCRUB));
    uart_puts("   handler: acknowledge the flag, rewrite the word\r\n");
    ECC_STATUS = ST_UE_SEEN;
    spare[0] = 0x12345678u;
    check(19, spare[0] == 0x12345678u);
    check(20, ECC_UE_COUNT == 1 && (ECC_STATUS & ST_UE_SEEN) == 0);
    ECC_CTRL = 0;
    print_counters();

    // ---------------- D: board button BTN1 injects one random flip into buf[30] ----------------
    uart_puts("D: waiting for BTN1 (random single flip into buf[30])\r\n");
    ECC_INJ_ADDR = (uint32_t)&buf[30];
    ic0 = ECC_INJ_COUNT;
    ce0 = ECC_CE_COUNT;
    ECC_SCRATCH0 = 1;                                          // tells the testbench: press the button now
    for (t = 0; ECC_INJ_COUNT == ic0 && t < 200000; t++) ;
    ECC_SCRATCH0 = 0;
    check(21, ECC_INJ_COUNT == ic0 + 1);
    v = buf[30];                                               // corrected on the fly
    check(22, v == exp30);
    check(23, ECC_CE_COUNT == ce0 + 1);
    check(24, ecc_log_pop(&a, &i));
    print_entry(a, i);
    check(25, a == (uint32_t)&buf[30] && !(i & LOG_UE));
    ECC_STATUS = ST_CE_SEEN;

    // ---------------- E: the program result stays correct ----------------
    check(26, buf[10] == exp10 && buf[20] == exp20 && buf[30] == exp30);
    check(27, checksum() == sum0);
    uart_puts("E: checksum of the buffer unchanged: "); uart_puthex(sum0); uart_puts("\r\n");
    print_counters();
    ECC_CTRL = CTRL_SCRUB_EN;

    uart_puts(fails ? "RESULT: FAIL\r\n" : "RESULT: PASS\r\n");
    if (fails == 0) ECC_SCRATCH2 = SIG_PASS;
    for (;;) ;
}
