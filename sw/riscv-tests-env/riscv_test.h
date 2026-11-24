// Minimal bare-metal environment for riscv-tests rv32ui on the P12 SoC.
// No CSRs, no traps. PASS/FAIL is reported by writing a signature to the
// ECC scratch register SCRATCH2 (0x4000_000C):
//   PASS: 0x0000600D      FAIL: 0xBAD00000 | test number
#ifndef _ENV_P12_H
#define _ENV_P12_H

#define TESTNUM gp
#define SIG_ADDR 0x4000000C

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U .macro init; .endm

#define RVTEST_CODE_BEGIN                                   \
        .section .text.init;                                \
        .align  2;                                          \
        .globl _start;                                      \
_start:                                                     \
        la   t0, _data_lma;    /* copy .data ITCM -> RAM */ \
        la   t1, _data_start;                               \
        la   t2, _data_end;                                 \
1:      bgeu t1, t2, 2f;                                    \
        lw   t3, 0(t0);                                     \
        sw   t3, 0(t1);                                     \
        addi t0, t0, 4;                                     \
        addi t1, t1, 4;                                     \
        j    1b;                                            \
2:      li   TESTNUM, 0;                                    \
        init;

#define RVTEST_CODE_END                                     \
3:      j 3b;

#define RVTEST_PASS                                         \
        li   t0, SIG_ADDR;                                  \
        li   t1, 0x600D;                                    \
        sw   t1, 0(t0);                                     \
4:      j 4b;

#define RVTEST_FAIL                                         \
        li   t0, SIG_ADDR;                                  \
        li   t1, 0xBAD00000;                                \
        or   t1, t1, TESTNUM;                               \
        sw   t1, 0(t0);                                     \
5:      j 5b;

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN  EXTRA_DATA .section .data; .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END    .align 4; .global end_signature; end_signature:

#endif
