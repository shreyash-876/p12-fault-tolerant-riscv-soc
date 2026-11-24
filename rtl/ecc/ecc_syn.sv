`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_syn (Phase 2): syndrome calculator for the Hsiao (39,32) code.
//
// Input : cw_in  = the 39-bit word READ BACK FROM MEMORY. Any bit of it, data or
//                  check, may have been flipped since it was written.
// Output: syndrome[6:0]; bit i = 1 means parity row i does not agree.
//
// How it works:
//   1. Take the 32 data bits as read (cw_in[31:0]) and run them through the SAME
//      encoder used at write time. The result (recalc[38:32]) is what the check
//      bits should be for the data that came back.
//   2. XOR those recomputed check bits with the check bits that actually came back
//      (cw_in[38:32]). Where they differ, the syndrome bit is 1.
//
// The check bits stored at write time were computed from the CLEAN data, so they
// are a record of what the data should be. If anything flipped after that, the
// recomputed and stored check bits no longer agree, and the pattern of
// disagreements depends only on WHICH bits flipped, never on the data.
// No flip -> syndrome 0.  One flipped bit j -> syndrome equals column j of H.
// -----------------------------------------------------------------------------
module ecc_syn (
    input  logic [38:0] cw_in,       // codeword read from memory (maybe corrupted)
    output logic  [6:0] syndrome
);
    logic [38:0] recalc;             // codeword rebuilt from the RECEIVED data bits

    // step 1: re-encode the received data bits (only recalc[38:32] is used)
    ecc_enc u_enc (
        .data_in (cw_in[31:0]),
        .cw_out  (recalc)
    );

    // step 2: recomputed check bits XOR received check bits
    assign syndrome = recalc[38:32] ^ cw_in[38:32];
endmodule
