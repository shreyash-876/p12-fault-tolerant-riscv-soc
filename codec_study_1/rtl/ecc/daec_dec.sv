`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// daec_dec: SEC-DED-DAEC (39,32) decoder / corrector (algorithm of the paper, section 6).
//
//   syndrome = (check bits recomputed from the received data) XOR (received check bits)
//   syndrome == 0                       -> no error
//   syndrome == column j                -> single error in bit j: flip it                    (ce = 1)
//   syndrome == column i XOR column i+1 -> double ADJACENT error in bits i, i+1: flip both   (ae = 1)
//   anything else                       -> uncorrectable: change nothing                     (ue = 1)
//   NOTE: a non-adjacent double error whose syndrome equals an adjacent-pair syndrome is
//   corrected wrongly (silent miscorrection); that is the price of the code (see reports/daec_capability.md).
//
//   IMPL 0 reference : behavioural syndrome + loops over daec_pkg::dh_col / dadj_col
//        1 flat      : daec_enc_flat syndrome + daec_corr_cmp
//        2 CSE       : daec_enc_cse  syndrome + daec_corr_cmp
//        3 tree      : daec_enc_tree syndrome + daec_corr_cmp
//   PIPE 0 : combinational (LAT = 0)
//        1 : register after the syndrome; correction in the second cycle (LAT = 1)
//   err_pos = lowest corrected bit (the single bit, or bit i of the pair i, i+1); 0 when nothing is corrected.
// Ports as ecc_dec, plus ae.
// -----------------------------------------------------------------------------
module daec_dec
    import daec_pkg::*;
#(
    parameter int IMPL = 0,
    parameter int PIPE = 0
)(
    input  logic        clk,        // used only when PIPE = 1
    input  logic        rst_n,      // resets out_valid only
    input  logic        in_valid,
    input  logic [38:0] cw_in,
    output logic        out_valid,
    output logic [31:0] data_out,
    output logic [38:0] cw_out,
    output logic  [6:0] syndrome,
    output logic        ce,         // single error corrected
    output logic        ae,         // adjacent double error corrected
    output logic        ue,         // uncorrectable error detected
    output logic  [5:0] err_pos
);
    /* verilator lint_off UNUSEDPARAM */
    localparam int LAT = PIPE;
    /* verilator lint_on UNUSEDPARAM */

    // ---------------- stage 1: syndrome ----------------
    logic [38:0] recalc;
    logic  [6:0] syn_c;

    daec_enc #(.IMPL(IMPL)) u_syn (.data_in(cw_in[31:0]), .cw_out(recalc));
    assign syn_c = recalc[38:32] ^ cw_in[38:32];

    // ---------------- optional pipeline register ----------------
    logic  [6:0] syn;
    logic [38:0] cw;
    logic        vld;

    generate
        if (PIPE == 1) begin : g_pipe
            always_ff @(posedge clk) begin
                syn <= syn_c;
                cw  <= cw_in;
            end
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) vld <= 1'b0;
                else        vld <= in_valid;
            end
        end else begin : g_comb
            assign syn = syn_c;
            assign cw  = cw_in;
            assign vld = in_valid;
        end
    endgenerate

    // ---------------- stage 2: classify and correct ----------------
    logic [38:0] flip;
    logic        hit_s, hit_a;

    generate
        if (IMPL == 0) begin : g_ref
            always_comb begin
                logic [38:0] fs;
                logic [37:0] fa;
                for (int j = 0; j < CW_W; j++)     fs[j] = (syn == dh_col(j));
                for (int i = 0; i < CW_W - 1; i++) fa[i] = (syn == dadj_col(i));
                flip = fs;
                for (int i = 0; i < CW_W - 1; i++)
                    if (fa[i]) begin flip[i] = 1'b1; flip[i + 1] = 1'b1; end
                hit_s = |fs;
                hit_a = |fa;
            end
        end else begin : g_cmp
            daec_corr_cmp u_corr (.syn(syn), .flip(flip), .ce(hit_s), .ae(hit_a));
        end
    endgenerate

    // lowest flipped bit (a single error sets one bit, an adjacent pair sets bits i and i+1)
    always_comb begin
        err_pos = 6'd0;
        for (int j = CW_W - 1; j >= 0; j--)
            if (flip[j]) err_pos = 6'(j);
    end

    assign ce        = hit_s;
    assign ae        = hit_a;
    assign ue        = (syn != 7'd0) && !hit_s && !hit_a;
    assign cw_out    = cw ^ flip;            // flip is all-zero unless ce or ae
    assign data_out  = cw_out[31:0];
    assign syndrome  = syn;
    assign out_valid = vld;
endmodule
