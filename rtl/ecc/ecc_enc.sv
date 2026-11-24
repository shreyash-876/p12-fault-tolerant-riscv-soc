`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_enc (Phase 1): Hsiao (39,32) encoder. Purely combinational.
//
//   data_in[31:0]  ->  cw_out[38:0] = { chk[6:0] , data_in[31:0] }
//
// Check bit i is the parity (XOR) of the data bits selected by mask i:
//   data_in & MASK   keeps only the data bits that belong to row i
//   ^( ... )         XORs all the kept bits together (1 when the count of 1s is odd)
// The masks come from the golden model (python model\print_masks.py).
// -----------------------------------------------------------------------------
module ecc_enc (
    input  logic [31:0] data_in,    // the word to store
    output logic [38:0] cw_out      // codeword = {check bits c6..c0, data d31..d0}
);
    logic [6:0] chk;                // the 7 check bits

    assign chk[0] = ^(data_in & 32'h00001FFF);   // d0..d12
    assign chk[1] = ^(data_in & 32'h007FE007);   // d0 d1 d2 d13..d22
    assign chk[2] = ^(data_in & 32'h1F81E078);
    assign chk[3] = ^(data_in & 32'hE38E2388);
    assign chk[4] = ^(data_in & 32'h6CB24C91);
    assign chk[5] = ^(data_in & 32'hB5549522);
    assign chk[6] = ^(data_in & 32'hDA691A44);

    assign cw_out = {chk, data_in};              // check bits above the data bits
endmodule
