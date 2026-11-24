// P12 ECC register block (base 0x4000_0000). Include p12.h first (it defines REG32).
#pragma once
#include <stdint.h>

#define ECC_BASE            0x40000000u

// ---- registers ----
#define ECC_CTRL            REG32(ECC_BASE + 0x10)   // see CTRL_* bits
#define ECC_STATUS          REG32(ECC_BASE + 0x14)   // sticky flags (write 1 to clear), log level, injector busy
#define ECC_CE_COUNT        REG32(ECC_BASE + 0x18)   // corrected errors seen (CPU accesses + scrubber)
#define ECC_UE_COUNT        REG32(ECC_BASE + 0x1C)   // uncorrectable errors seen
#define ECC_LOG_ADDR        REG32(ECC_BASE + 0x20)   // byte address of the oldest log entry
#define ECC_LOG_INFO        REG32(ECC_BASE + 0x24)   // oldest log entry; ANY WRITE pops it
#define ECC_SCRUB_INTERVAL  REG32(ECC_BASE + 0x28)   // clock cycles between two scrub operations
#define ECC_SCRUB_REPAIRED  REG32(ECC_BASE + 0x2C)   // words repaired by the scrubber
#define ECC_SCRUB_SWEEPS    REG32(ECC_BASE + 0x30)   // completed scrubber sweeps
#define ECC_INJ_ADDR        REG32(ECC_BASE + 0x34)   // byte address of the word to damage
#define ECC_INJ_MASK_LO     REG32(ECC_BASE + 0x38)   // flip mask, codeword bits 31..0 (data bits)
#define ECC_INJ_MASK_HI     REG32(ECC_BASE + 0x3C)   // flip mask, codeword bits 38..32 (check bits c0..c6 in bits 6..0)
#define ECC_INJ_CTRL        REG32(ECC_BASE + 0x40)   // see INJ_* bits
#define ECC_INJ_COUNT       REG32(ECC_BASE + 0x44)   // injections completed

// ---- CTRL ----
#define CTRL_SCRUB_EN       (1u << 0)    // scrubber on (reset value 1)
#define CTRL_IRQ_UE_EN      (1u << 1)    // interrupt line irq_ue follows STATUS.UE_SEEN
#define CTRL_IRQ_CE_EN      (1u << 2)    // interrupt line irq_ce follows STATUS.CE_SEEN
#define CTRL_CLEAR          (1u << 4)    // write 1: clear CE_COUNT, UE_COUNT and the log

// ---- STATUS ----
#define ST_CE_SEEN          (1u << 0)    // write 1 to clear
#define ST_UE_SEEN          (1u << 1)    // write 1 to clear (this is the interrupt source)
#define ST_LOG_OVERRUN      (1u << 2)    // write 1 to clear
#define ST_INJ_BUSY         (1u << 3)
#define ST_LOG_LEVEL(s)     (((s) >> 8) & 0xFu)

// ---- LOG_INFO fields ----
#define LOG_SYNDROME(i)     ((i) & 0x7Fu)
#define LOG_BIT(i)          (((i) >> 8) & 0x3Fu)   // corrected codeword bit (0-31 data, 32-38 check); valid if not UE
#define LOG_UE              (1u << 16)
#define LOG_SCRUB           (1u << 17)

// ---- INJ_CTRL ----
#define INJ_GO              (1u << 0)    // write 1 to inject
#define INJ_RANDOM          (1u << 1)    // use a random bit instead of INJ_MASK
#define INJ_DOUBLE          (1u << 2)    // with RANDOM: two bits
#define INJ_BUSY            (1u << 8)

// Pop the oldest log entry. Returns 1 and fills addr/info, or 0 when the log is empty.
static inline int ecc_log_pop(uint32_t *addr, uint32_t *info) {
    if (ST_LOG_LEVEL(ECC_STATUS) == 0) return 0;
    *addr = ECC_LOG_ADDR;
    *info = ECC_LOG_INFO;
    ECC_LOG_INFO = 0;
    return 1;
}

// Damage the stored word at byte address `addr`: flip the bits of the 39-bit mask.
static inline void ecc_inject(uint32_t addr, uint32_t mask_lo, uint32_t mask_hi) {
    ECC_INJ_ADDR    = addr;
    ECC_INJ_MASK_LO = mask_lo;
    ECC_INJ_MASK_HI = mask_hi;
    ECC_INJ_CTRL    = INJ_GO;
    while (ECC_INJ_CTRL & INJ_BUSY) ;
}
