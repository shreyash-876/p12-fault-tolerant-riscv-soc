`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// daec_enc: SEC-DED-DAEC (39,32) encoder (H-matrix of Dutta and Touba, VTS 2007). Purely combinational.
//   cw_out[31:0] = data_in, cw_out[32+i] = XOR of the data bits in parity row i.
//   IMPL 0 reference (behavioural, from daec_pkg::drow_mask)
//        1 flat XOR expression per row       (daec_enc_flat, generated)
//        2 common sub-expression elimination (daec_enc_cse,  generated)
//        3 balanced 2-input XOR tree per row (daec_enc_tree, generated)
// All IMPL values compute the same function.
// -----------------------------------------------------------------------------
module daec_enc
    import daec_pkg::*;
#(
    parameter int IMPL = 0
)(
    input  logic [31:0] data_in,
    output logic [38:0] cw_out
);
    logic [6:0] chk;

    generate
        if (IMPL == 1) begin : g_flat
            daec_enc_flat u_net (.d(data_in), .c(chk));
        end else if (IMPL == 2) begin : g_cse
            daec_enc_cse  u_net (.d(data_in), .c(chk));
        end else if (IMPL == 3) begin : g_tree
            daec_enc_tree u_net (.d(data_in), .c(chk));
        end else begin : g_ref
            always_comb
                for (int i = 0; i < CHK_W; i++) chk[i] = ^(data_in & drow_mask(i));
        end
    endgenerate

    assign cw_out = {chk, data_in};
endmodule
