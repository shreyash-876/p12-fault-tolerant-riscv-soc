// -----------------------------------------------------------------------------
// CSR instruction test (no interrupts yet): result = ECC_SCRATCH2 (0x600D pass, 0xBAD000nn = check nn failed)
// -----------------------------------------------------------------------------
#include "p12.h"
#include "p12_regs.h"
#include "p12_csr.h"

static uint32_t fails;
static void check(uint32_t n, int cond) {
    if (!cond) {
        if (fails == 0) ECC_SCRATCH2 = SIG_FAIL(n);
        fails++;
        uart_puts("   FAIL check "); uart_putdec(n); uart_puts("\r\n");
    }
}

static volatile uint32_t mem_word = 0xCAFE0001u;
static volatile uint32_t mem_tab[4] = {0x11111111u, 0x22222222u, 0x33333333u, 0x44444444u};

int main(void) {
    uint32_t old, v;
    uart_puts("\r\nCSR instruction test\r\n");

    // ---- read-only / fixed values ----
    check(1, csr_read(misa) == 0x40000100u);
    check(2, csr_read(mip) == 0);                       // no interrupt pending

    // ---- the six forms on mscratch: old value returned, new value written ----
    csr_write(mscratch, 0x12345678u);
    check(3, csr_read(mscratch) == 0x12345678u);
    __asm__ volatile ("csrrw %0, mscratch, %1" : "=r"(old) : "r"(0xA5A5A5A5u));
    check(4, old == 0x12345678u && csr_read(mscratch) == 0xA5A5A5A5u);
    __asm__ volatile ("csrrs %0, mscratch, %1" : "=r"(old) : "r"(0x0000FF00u));
    check(5, old == 0xA5A5A5A5u && csr_read(mscratch) == 0xA5A5FFA5u);
    __asm__ volatile ("csrrc %0, mscratch, %1" : "=r"(old) : "r"(0x000000F0u));
    check(6, old == 0xA5A5FFA5u && csr_read(mscratch) == 0xA5A5FF05u);
    __asm__ volatile ("csrrwi %0, mscratch, 21" : "=r"(old));
    check(7, old == 0xA5A5FF05u && csr_read(mscratch) == 21u);
    __asm__ volatile ("csrrsi %0, mscratch, 3" : "=r"(old));
    check(8, old == 21u && csr_read(mscratch) == 23u);
    __asm__ volatile ("csrrci %0, mscratch, 1" : "=r"(old));
    check(9, old == 23u && csr_read(mscratch) == 22u);

    // ---- csrrs/csrrc with rs1 = x0 or a zero immediate only READ ----
    __asm__ volatile ("csrrs %0, mscratch, x0" : "=r"(old));
    check(10, old == 22u && csr_read(mscratch) == 22u);
    __asm__ volatile ("csrrc %0, mscratch, x0" : "=r"(old));
    check(11, old == 22u && csr_read(mscratch) == 22u);
    __asm__ volatile ("csrrsi %0, mscratch, 0" : "=r"(old));
    check(12, old == 22u && csr_read(mscratch) == 22u);
    __asm__ volatile ("csrrci %0, mscratch, 0" : "=r"(old));
    check(13, old == 22u && csr_read(mscratch) == 22u);

    // ---- register fields that are not fully implemented ----
    csr_write(mtvec, 0x00001003u);
    check(14, csr_read(mtvec) == 0x00001000u);          // direct mode, bits 1:0 read as 0
    csr_write(mepc, 0x12345679u);
    check(15, csr_read(mepc) == 0x12345678u);           // bit 0 reads as 0
    csr_write(mie, 0xFFFFFFFFu);
    check(16, csr_read(mie) == MIE_MEIE);               // only MEIE exists
    csr_write(mie, 0);
    check(17, csr_read(mie) == 0);
    v = csr_read(mstatus);
    check(18, (v & MSTATUS_MIE) == 0 && (v & 0x1800u) == 0x1800u);   // MIE off after reset, MPP reads 11
    csr_set(mstatus, MSTATUS_MIE);
    check(19, (csr_read(mstatus) & MSTATUS_MIE) != 0);
    csr_clear(mstatus, MSTATUS_MIE);
    check(20, (csr_read(mstatus) & MSTATUS_MIE) == 0);
    csr_write(mstatus, MSTATUS_MPIE);
    check(21, (csr_read(mstatus) & (MSTATUS_MPIE | MSTATUS_MIE)) == MSTATUS_MPIE);
    csr_write(mstatus, 0);

    // ---- the cycle counter counts ----
    uint32_t c0 = csr_read(mcycle), c1 = csr_read(mcycle);
    check(22, c1 > c0 && (c1 - c0) < 100u);

    // ---- unimplemented CSRs read 0 and ignore writes ----
    check(23, csr_read(mhartid) == 0);
    csr_write(mtval, 0x55555555u);
    check(24, csr_read(mtval) == 0);

    // ---- pipeline interplay: forwarding into and out of CSR instructions, load-use, CSR result as an address ----
    __asm__ volatile (
        "li   t0, 5\n"
        "csrw mscratch, t0\n"          // value forwarded from the previous instruction
        "csrr t1, mscratch\n"
        "addi t2, t1, 1\n"             // CSR result forwarded into an ALU instruction
        "csrw mscratch, t2\n"
        "csrr %0, mscratch\n"
        : "=r"(v) :: "t0", "t1", "t2");
    check(25, v == 6u);

    __asm__ volatile (
        "lw   t0, 0(%1)\n"
        "csrw mscratch, t0\n"          // load-use into a CSR write
        "csrr %0, mscratch\n"
        : "=r"(v) : "r"(&mem_word) : "t0");
    check(26, v == 0xCAFE0001u);

    __asm__ volatile (
        "csrw mscratch, %1\n"
        "csrr t0, mscratch\n"
        "lw   %0, 8(t0)\n"             // CSR result used as an address immediately
        : "=r"(v) : "r"(&mem_tab[0]) : "t0");
    check(27, v == 0x33333333u);

    __asm__ volatile (
        "li   t0, 1\n"
        "csrrw t1, mscratch, t0\n"     // back-to-back CSR instructions
        "csrrs t2, mscratch, t0\n"
        "csrrw t3, mscratch, t2\n"
        "csrr %0, mscratch\n"
        : "=r"(v) :: "t0", "t1", "t2", "t3");
    check(28, v == 1u);

    // ---- a loop that mixes CSR reads with branches ----
    uint32_t acc = 0;
    csr_write(mscratch, 0);
    for (int i = 0; i < 20; i++) {
        csr_set(mscratch, 1u << (i & 7));
        acc += csr_read(mscratch) & 0xFFu;
    }
    check(29, acc != 0);

    uart_puts(fails ? "RESULT: FAIL\r\n" : "RESULT: PASS\r\n");
    if (fails == 0) ECC_SCRATCH2 = SIG_PASS;
    for (;;) ;
}
