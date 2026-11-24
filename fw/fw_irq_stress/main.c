// -----------------------------------------------------------------------------
// Interrupt stress test (firmware side). The testbench (tb_soc_irq) raises the core's interrupt request at
// random moments while this program runs. The program is built so that ANY mistake in interrupt entry or return
// (an instruction skipped, executed twice, a register clobbered) changes its result:
//   * the same workload runs twice: once with interrupts off (the reference), once with the interrupt storm
//   * the workload has loads/stores of every size, branches, calls through function pointers, CSR instructions
//     and non-idempotent memory increments
// Handshake with the testbench through ECC_SCRATCH0:  2 = storm on, 3 = request while MIE = 0,
//   4 = request while mie.MEIE = 0, 5 = storm finished. The handler acknowledges by writing its count to ECC_SCRATCH1.
// Result: ECC_SCRATCH2 = 0x600D (pass) or 0xBAD000nn (check nn failed).
// -----------------------------------------------------------------------------
#include "p12.h"
#include "p12_regs.h"
#include "p12_csr.h"

static volatile uint32_t isr_count;
static volatile uint32_t bad_cause, bad_epc, last_epc;
static volatile uint8_t  epc_seen[1024];
static uint32_t fails;

static void check(uint32_t n, int cond) {
    if (!cond) {
        if (fails == 0) ECC_SCRATCH2 = SIG_FAIL(n);
        fails++;
        uart_puts("   FAIL check "); uart_putdec(n); uart_puts("\r\n");
    }
}

// ---------------- the interrupt handler ----------------
__attribute__((interrupt("machine"))) void isr(void) {
    uint32_t cause = csr_read(mcause);
    uint32_t epc   = csr_read(mepc);
    if (cause != MCAUSE_MEI) bad_cause++;
    if ((epc & 3u) != 0 || epc >= 0x4000u) bad_epc++;           // must be a word-aligned address inside the 16 KB ITCM
    last_epc = epc;
    epc_seen[(epc >> 2) & 1023u] = 1;
    isr_count = isr_count + 1;                                   // not idempotent: a replayed handler would show
    ECC_SCRATCH1 = isr_count;                                    // acknowledge: the testbench drops the request
}

// ---------------- the workload (shared with a PC program that computes the expected result) ----------------
#define WL_CSR_WRITE(v) csr_write(mscratch, v)
#define WL_CSR_READ()   csr_read(mscratch)
#include "workload.h"
#define HOST_REF 0x43DC6DC2u                          // run_all() as computed on a PC by host_ref.c

int main(void) {
    uint32_t c0, t;

    uart_puts("\r\nInterrupt stress test\r\n");
    for (int i = 0; i < 64; i++) { arr[i] = 0; bytes[i] = 0; }
    ECC_SCRUB_INTERVAL = 25;                         // the scrubber competes with the CPU for the memory all the time
    csr_write(mtvec, (uint32_t)&isr);
    csr_write(mie, MIE_MEIE);                        // interrupts enabled in mie, but not yet globally
    check(1, csr_read(mtvec) == (uint32_t)&isr);

    // ---- reference run: interrupts off ----
    for (int i = 0; i < 64; i++) { arr[i] = 0; bytes[i] = 0; }
    uint32_t expect = run_all();
    check(2, isr_count == 0);
    check(14, expect == HOST_REF);                   // the core computes what a PC computes (no interrupts involved)
    uart_puts("reference checksum: "); uart_puthex(expect); uart_puts("\r\n");

    // ---- storm: the testbench raises the request at random moments ----
    for (int i = 0; i < 64; i++) { arr[i] = 0; bytes[i] = 0; }
    ECC_SCRATCH0 = 2;
    irq_global_enable();
    uint32_t got = run_all();
    irq_global_disable();
    ECC_SCRATCH0 = 5;
    check(3, got == expect);                         // the result is identical although interrupts hit all over the code
    check(4, isr_count > 50);
    check(5, bad_cause == 0 && bad_epc == 0);
    uint32_t distinct = 0;
    for (uint32_t i = 0; i < 1024; i++) distinct += epc_seen[i];
    uart_puts("storm checksum:     "); uart_puthex(got); uart_puts("\r\n");
    uart_puts("interrupts taken: "); uart_putdec(isr_count);
    uart_puts(", at "); uart_putdec(distinct); uart_puts(" different instruction addresses\r\n");
    check(6, distinct > 40);

    // ---- request pending while mstatus.MIE = 0: must NOT be taken; mip shows it; taken right after enabling ----
    c0 = isr_count;
    irq_global_disable();
    ECC_SCRATCH0 = 3;                                // the testbench raises the request and holds it
    (void)work(99);                                  // plenty of instructions with the request pending
    check(7, isr_count == c0);
    check(8, (csr_read(mip) & MIE_MEIE) != 0);       // MEIP visible
    irq_global_enable();
    for (t = 0; isr_count == c0 && t < 2000; t++) ;
    check(9, isr_count == c0 + 1 || isr_count == c0 + 2);
    irq_global_disable();

    // ---- request pending while mie.MEIE = 0 (MIE = 1): must NOT be taken ----
    c0 = isr_count;
    csr_clear(mie, MIE_MEIE);
    irq_global_enable();
    ECC_SCRATCH0 = 4;
    (void)work(98);
    check(10, isr_count == c0);
    csr_set(mie, MIE_MEIE);                          // now it is taken
    for (t = 0; isr_count == c0 && t < 2000; t++) ;
    check(11, isr_count >= c0 + 1);
    irq_global_disable();
    ECC_SCRATCH0 = 6;

    // ---- the state after all that is sane ----
    check(12, (csr_read(mstatus) & MSTATUS_MIE) == 0);
    check(13, bad_cause == 0 && bad_epc == 0);

    uart_puts(fails ? "RESULT: FAIL\r\n" : "RESULT: PASS\r\n");
    if (fails == 0) ECC_SCRATCH2 = SIG_PASS;
    for (;;) ;
}
