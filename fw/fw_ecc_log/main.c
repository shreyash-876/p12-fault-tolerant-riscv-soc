// -----------------------------------------------------------------------------
// P12 firmware error log: a checksum program that keeps running while errors are injected.
//
//   * a protected buffer of 128 words in the ECC RAM; its correct content is a known function (golden())
//   * the main program checksums the buffer again and again; the result must ALWAYS be the same
//   * errors are injected into random words of the buffer (by the board buttons BTN1 = one bit, BTN2 = two bits; the
//     program points INJ_ADDR at a new random word before every pass)
//   * single-bit errors are corrected by the hardware while reading, and repaired in memory by the background scrubber
//   * a word that gets TWO flipped bits (a double injection, or two single ones that meet in the same word) is
//     uncorrectable: the memory answers SLVERR with wrong data. The memory system raises the interrupt, the
//     handler reads the hardware error log, stores every entry in a RAM ring buffer (the firmware error log) and
//     rewrites every reported word from its golden value. A checksum pass is accepted only if no error was reported
//     while it ran; otherwise it is repeated.
//   * the main program prints every log entry over the UART
//
// Result: ECC_SCRATCH2 = 0x600D (pass) or 0xBAD000nn (check nn failed). ECC_SCRATCH0 = 9 when the run is over.
// -----------------------------------------------------------------------------
#include "p12.h"
#include "p12_regs.h"
#include "p12_csr.h"
#include "common.h"

#define PASSES    40
#define LOG_SIZE  32
#define HOST_REF  0x96155E28u            // checksum of the golden buffer, computed on a PC by host_ref.c

static volatile uint32_t buf[NWORDS];

// ---------------- the firmware error log (filled by the interrupt handler) ----------------
typedef struct { uint32_t cycle, addr, info; } log_entry_t;
static volatile log_entry_t elog[LOG_SIZE];
static volatile uint32_t elog_head;                       // number of entries written so far
static volatile uint32_t isr_count, ce_events, ue_events, recovered, outside;
static volatile uint32_t isr_busy;

static uint32_t fails;
static void check(uint32_t n, int cond) {
    if (!cond) {
        if (fails == 0) ECC_SCRATCH2 = SIG_FAIL(n);
        fails++;
        uart_puts("   FAIL check "); uart_putdec(n); uart_puts("\r\n");
    }
}

// ---------------- interrupt handler: runs when the memory system reports an error ----------------
__attribute__((interrupt("machine"))) void isr(void) {
    uint32_t a, info;
    isr_busy = 1;
    isr_count = isr_count + 1;
    ECC_STATUS = ST_CE_SEEN | ST_UE_SEEN | ST_LOG_OVERRUN;          // acknowledge FIRST: an event after this raises the interrupt again
    while (ecc_log_pop(&a, &info)) {
        uint32_t t = csr_read(mcycle);
        uint32_t k = elog_head & (LOG_SIZE - 1u);
        elog[k].cycle = t; elog[k].addr = a; elog[k].info = info;
        elog_head = elog_head + 1;                                   // after the entry is complete
        if (info & LOG_UE) ue_events = ue_events + 1; else ce_events = ce_events + 1;
        // Recovery for EVERY reported word, corrected or not: rewrite it from its golden value (fresh check bits).
        // A corrected error is repaired at once instead of waiting for the scrubber, so errors cannot pile up in a
        // word. (Three flipped bits in one word are beyond SEC-DED: the hardware may "correct" the wrong bit and
        // report only a corrected error; rewriting the word heals that too.)
        uint32_t idx = (a - (uint32_t)&buf[0]) >> 2;                 // which word of the protected buffer?
        if (idx < NWORDS) {
            buf[idx] = golden(idx);
            recovered = recovered + 1;
        } else {
            outside = outside + 1;                                   // not ours: nothing we can repair
        }
    }
    isr_busy = 0;
}

// ---------------- main program ----------------
// The injection buttons hit the word that INJ_ADDR points at. It is re-aimed at a new random word of the buffer
// on EVERY iteration of the checksum loop. (If it stayed on one word for a whole pass, several presses could pile up
// 4 flipped bits in that word before anybody reads it. Four flips can form another valid codeword: the word is then
// wrong with syndrome 0, and no SEC-DED code can notice. Spreading the damage is what the scrubber and this handler
// rely on: every word is read often enough to be reported and repaired before a second error joins the first.)
static uint32_t lfsr_state = 0xACE12345u;
static int      aim_injector = 0;
static inline void aim(void) {
    lfsr_state = (lfsr_state >> 1) ^ ((lfsr_state & 1u) ? 0xA3000000u : 0u);
    ECC_INJ_ADDR = (uint32_t)&buf[lfsr_state & (NWORDS - 1u)];
}

static uint32_t checksum(void) {
    uint32_t s = 0x12345678u;
    for (uint32_t i = 0; i < NWORDS; i++) {
        if (aim_injector) aim();
        s = rol5(s) ^ buf[i] ^ (0x01000193u + i);
    }
    return s;
}

// A pass is accepted only if the memory system reported NO error while it ran: then every word read was clean and
// the checksum is right. If an error was reported, the handler repairs the word and the pass is repeated.
static uint32_t verified_checksum(uint32_t *retries) {
    uint32_t ev0, ev1, sum, tries = 0;
    do {
        ev0 = ECC_CE_COUNT + ECC_UE_COUNT;
        sum = checksum();
        ev1 = ECC_CE_COUNT + ECC_UE_COUNT;
        if (ev1 != ev0) {
            *retries = *retries + 1;
            while (isr_busy || (ECC_STATUS & (ST_CE_SEEN | ST_UE_SEEN))) ;   // wait until the handler has repaired it
        }
        tries++;
    } while (ev1 != ev0 && tries < 20);
    return sum;
}

static void print_entry(const volatile log_entry_t *e) {
    uint32_t info = e->info;
    uart_puts("  [");  uart_puthex(e->cycle); uart_puts("] ");
    if (info & LOG_UE) uart_puts("UNCORRECTABLE   ");
    else { uart_puts("corrected bit "); uart_putdec(LOG_BIT(info)); uart_puts((LOG_BIT(info) < 10) ? "   " : "  "); }
    uart_puts("word "); uart_puthex(e->addr);
    uart_puts(" syndrome "); uart_puthex(LOG_SYNDROME(info));
    uart_puts((info & LOG_SCRUB) ? "  (scrubber)\r\n" : "  (CPU read)\r\n");
}

int main(void) {
    uint32_t printed = 0;
    uint32_t retries = 0, mismatches = 0, passes_done = 0;

    uart_puts("\r\nP12 firmware error log: checksum under error injection\r\n");
    for (uint32_t i = 0; i < NWORDS; i++) buf[i] = golden(i);
    uint32_t expect = checksum();
    check(1, expect == HOST_REF);
    uart_puts("expected checksum "); uart_puthex(expect); uart_puts(" (PC reference agrees)\r\n");

    // ---- interrupts: ECC system -> core ----
    ECC_STATUS = ST_CE_SEEN | ST_UE_SEEN | ST_LOG_OVERRUN;
    ECC_CTRL = CTRL_SCRUB_EN | CTRL_CLEAR;
    ECC_SCRUB_INTERVAL = 40;                                         // quick demonstration: a sweep of the RAM takes ~90k cycles
    ECC_CTRL = CTRL_SCRUB_EN | CTRL_IRQ_UE_EN | CTRL_IRQ_CE_EN;
    csr_write(mtvec, (uint32_t)&isr);
    csr_write(mie, MIE_MEIE);
    irq_global_enable();
    aim_injector = 1;                                                // from now on checksum() keeps re-aiming the injection buttons
    ECC_SCRATCH0 = 1;                                                // tells the testbench: start pressing the buttons

    for (uint32_t p = 0; p < PASSES; p++) {
        uint32_t sum = verified_checksum(&retries);
        if (sum != expect) {
            mismatches++;
            if (mismatches <= 3) {                                    // diagnostic: which word is wrong right now?
                for (uint32_t i = 0; i < NWORDS; i++)
                    if (buf[i] != golden(i)) {
                        uart_puts("  MISMATCH: word "); uart_putdec(i); uart_puts(" at "); uart_puthex((uint32_t)&buf[i]);
                        uart_puts(" reads "); uart_puthex(buf[i]); uart_puts(" expected "); uart_puthex(golden(i));
                        uart_puts(" (hw events so far: CE "); uart_putdec(ECC_CE_COUNT); uart_puts(", UE "); uart_putdec(ECC_UE_COUNT); uart_puts(")\r\n");
                    }
            }
        }
        passes_done++;

        if ((p % 10u) == 9u) { uart_puts("  -- pass "); uart_putdec(p + 1); uart_puts(" of "); uart_putdec(PASSES); uart_puts(" done, retries so far "); uart_putdec(retries); uart_puts("\r\n"); }
        // print the log entries the handler has collected
        uint32_t head = elog_head;
        if (head - printed > LOG_SIZE) printed = head - LOG_SIZE;    // the ring wrapped: the oldest entries are gone
        while (printed != head) { print_entry(&elog[printed & (LOG_SIZE - 1u)]); printed++; }
    }

    ECC_SCRATCH0 = 9;                                                // tells the testbench: stop pressing the buttons
    uint32_t t0 = csr_read(mcycle);
    while (csr_read(mcycle) - t0 < 8000u) ;                          // let the last injections arrive and be repaired (handler still on)
    uint32_t fin = verified_checksum(&retries);
    aim_injector = 0;
    irq_global_disable();
    while (ST_LOG_LEVEL(ECC_STATUS) != 0) { uint32_t a, i; (void)ecc_log_pop(&a, &i); }

    uart_puts("\r\nsummary after "); uart_putdec(passes_done); uart_puts(" checksum passes\r\n");
    uart_puts("  checksum mismatches:      "); uart_putdec(mismatches); uart_puts("\r\n");
    uart_puts("  passes repeated (error seen): "); uart_putdec(retries); uart_puts("\r\n");
    uart_puts("  injections done:          "); uart_putdec(ECC_INJ_COUNT); uart_puts("\r\n");
    uart_puts("  corrected errors:         "); uart_putdec(ECC_CE_COUNT); uart_puts("   uncorrectable: "); uart_putdec(ECC_UE_COUNT); uart_puts("\r\n");
    uart_puts("  repaired by the scrubber: "); uart_putdec(ECC_SCRUB_REPAIRED); uart_puts("\r\n");
    uart_puts("  interrupts taken:         "); uart_putdec(isr_count); uart_puts("\r\n");
    uart_puts("  log entries handled:      "); uart_putdec(ce_events + ue_events);
    uart_puts(" ("); uart_putdec(ue_events); uart_puts(" uncorrectable); words rewritten by the handler: "); uart_putdec(recovered); uart_puts("\r\n");

    check(2, mismatches == 0);                                       // the program result stayed correct under errors
    check(3, ECC_INJ_COUNT > 0);
    check(4, isr_count > 0 && ce_events + ue_events > 0);
    check(5, outside == 0);
    check(6, fin == expect);                                         // and still is at the end, once the last errors are repaired

    uart_puts(fails ? "RESULT: FAIL\r\n" : "RESULT: PASS\r\n");
    if (fails == 0) ECC_SCRATCH2 = SIG_PASS;
    for (;;) ;
}
