`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_enc: Hsiao (39,32) SEC-DED encoder. Purely combinational, latency 0.
//   cw_out[31:0] = data_in, cw_out[32+i] = XOR of the data bits in parity row i.
//   IMPL 0 reference (behavioural, from ecc_pkg::row_mask)
//        1 flat XOR expression per row       (ecc_enc_flat, generated)
//        2 common sub-expression elimination (ecc_enc_cse,  generated)
//        3 balanced 2-input XOR tree per row (ecc_enc_tree, generated)
// All IMPL values compute the same function.
// -----------------------------------------------------------------------------
module ecc_enc
    import ecc_pkg::*;
#(
    parameter int IMPL = 0
)(
    input  logic [31:0] data_in,
    output logic [38:0] cw_out
);
    logic [6:0] chk;

    generate
        if (IMPL == 1) begin : g_flat
            ecc_enc_flat u_net (.d(data_in), .c(chk));
        end else if (IMPL == 2) begin : g_cse
            ecc_enc_cse  u_net (.d(data_in), .c(chk));
        end else if (IMPL == 3) begin : g_tree
            ecc_enc_tree u_net (.d(data_in), .c(chk));
        end else begin : g_ref
            always_comb
                for (int i = 0; i < CHK_W; i++) chk[i] = ^(data_in & row_mask(i));
        end
    endgenerate

    assign cw_out = {chk, data_in};
endmodule
