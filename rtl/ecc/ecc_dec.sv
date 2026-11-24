`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_dec (Phase 3): Hsiao (39,32) decoder / corrector. Purely combinational.
//
// Input : cw_in    39-bit word read from memory (any bit may have flipped)
// Output: syndrome 7-bit syndrome (Phase 2)
//         ce       1 = a single-bit error was found and corrected
//         ue       1 = uncorrectable error detected (nothing was changed)
//         err_pos  codeword bit number that was flipped back (0 when ce = 0)
//         cw_out   39-bit codeword after correction (the scrubber will write this back)
//         data_out 32-bit data after correction = cw_out[31:0]
//
// Decision rule (everything follows from the syndrome):
//   syndrome == 0                          -> no error
//   syndrome == column j of H              -> bit j flipped: flip it back, ce = 1
//   anything else (not 0, not a column)    -> 2 or more errors: ue = 1, change nothing
// -----------------------------------------------------------------------------
module ecc_dec (
    input  logic [38:0] cw_in,       // codeword read from memory
    output logic [31:0] data_out,    // data after correction
    output logic [38:0] cw_out,      // codeword after correction
    output logic  [6:0] syndrome,
    output logic        ce,          // single error corrected
    output logic        ue,          // uncorrectable error detected
    output logic  [5:0] err_pos      // which codeword bit was corrected
);
    // ---- step 1: syndrome (Phase 2 module) ----------------------------------
    ecc_syn u_syn (.cw_in(cw_in), .syndrome(syndrome));

    // ---- step 2: does the syndrome equal the column of one particular bit? ---
    // flip[j] = 1 when syndrome == column j of H (column written as 7 bits, row 6
    // on the left). All 39 columns are different, so at most one flip bit is 1.
    logic [38:0] flip;
    assign flip[0]  = (syndrome == 7'b0010011);   // d0
    assign flip[1]  = (syndrome == 7'b0100011);   // d1
    assign flip[2]  = (syndrome == 7'b1000011);   // d2
    assign flip[3]  = (syndrome == 7'b0001101);   // d3
    assign flip[4]  = (syndrome == 7'b0010101);   // d4
    assign flip[5]  = (syndrome == 7'b0100101);   // d5
    assign flip[6]  = (syndrome == 7'b1000101);   // d6
    assign flip[7]  = (syndrome == 7'b0011001);   // d7
    assign flip[8]  = (syndrome == 7'b0101001);   // d8
    assign flip[9]  = (syndrome == 7'b1001001);   // d9
    assign flip[10] = (syndrome == 7'b0110001);   // d10
    assign flip[11] = (syndrome == 7'b1010001);   // d11
    assign flip[12] = (syndrome == 7'b1100001);   // d12
    assign flip[13] = (syndrome == 7'b0001110);   // d13
    assign flip[14] = (syndrome == 7'b0010110);   // d14
    assign flip[15] = (syndrome == 7'b0100110);   // d15
    assign flip[16] = (syndrome == 7'b1000110);   // d16
    assign flip[17] = (syndrome == 7'b0011010);   // d17
    assign flip[18] = (syndrome == 7'b0101010);   // d18
    assign flip[19] = (syndrome == 7'b1001010);   // d19
    assign flip[20] = (syndrome == 7'b0110010);   // d20
    assign flip[21] = (syndrome == 7'b1010010);   // d21
    assign flip[22] = (syndrome == 7'b1100010);   // d22
    assign flip[23] = (syndrome == 7'b0011100);   // d23
    assign flip[24] = (syndrome == 7'b0101100);   // d24
    assign flip[25] = (syndrome == 7'b1001100);   // d25
    assign flip[26] = (syndrome == 7'b0110100);   // d26
    assign flip[27] = (syndrome == 7'b1010100);   // d27
    assign flip[28] = (syndrome == 7'b1100100);   // d28
    assign flip[29] = (syndrome == 7'b0111000);   // d29
    assign flip[30] = (syndrome == 7'b1011000);   // d30
    assign flip[31] = (syndrome == 7'b1101000);   // d31
    assign flip[32] = (syndrome == 7'b0000001);   // c0
    assign flip[33] = (syndrome == 7'b0000010);   // c1
    assign flip[34] = (syndrome == 7'b0000100);   // c2
    assign flip[35] = (syndrome == 7'b0001000);   // c3
    assign flip[36] = (syndrome == 7'b0010000);   // c4
    assign flip[37] = (syndrome == 7'b0100000);   // c5
    assign flip[38] = (syndrome == 7'b1000000);   // c6

    // ---- step 3: flags -------------------------------------------------------
    assign ce = |flip;                        // some column matched -> single error
    assign ue = (syndrome != 7'd0) && !ce;    // not zero, and no column matched

    // ---- step 4: correction --------------------------------------------------
    // flip is all zeros unless ce = 1, so on "no error" and on "uncorrectable" the
    // word passes through unchanged.
    assign cw_out   = cw_in ^ flip;
    assign data_out = cw_out[31:0];

    // ---- step 5: position of the corrected bit -------------------------------
    // (only one flip bit can be 1, so this simply finds it)
    always_comb begin
        err_pos = 6'd0;
        for (int j = 0; j < 39; j++)
            if (flip[j]) err_pos = 6'(j);
    end
endmodule
