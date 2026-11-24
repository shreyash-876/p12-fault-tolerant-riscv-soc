// Machine-mode CSR access for the P12 RV32I core (build with -march=rv32i_zicsr).
#pragma once
#include <stdint.h>

#define csr_read(csr)        ({ uint32_t __v; __asm__ volatile ("csrr %0, " #csr : "=r"(__v)); __v; })
#define csr_write(csr, val)  __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint32_t)(val)))
#define csr_set(csr, val)    __asm__ volatile ("csrs " #csr ", %0" :: "r"((uint32_t)(val)))
#define csr_clear(csr, val)  __asm__ volatile ("csrc " #csr ", %0" :: "r"((uint32_t)(val)))

#define MSTATUS_MIE   (1u << 3)      // global machine interrupt enable
#define MSTATUS_MPIE  (1u << 7)      // MIE before the trap
#define MIE_MEIE      (1u << 11)     // machine external interrupt enable
#define MCAUSE_MEI    0x8000000Bu    // machine external interrupt

static inline void irq_global_enable(void)  { csr_set(mstatus, MSTATUS_MIE); }
static inline void irq_global_disable(void) { csr_clear(mstatus, MSTATUS_MIE); }
