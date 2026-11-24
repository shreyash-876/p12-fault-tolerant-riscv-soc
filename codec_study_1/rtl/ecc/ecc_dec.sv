`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_dec: Hsiao (39,32) SEC-DED decoder / corrector.
//
//   syndrome = (check bits recomputed from the received data) XOR (received check bits)
//   syndrome == 0            -> no error
//   syndrome == column j of H -> single error at bit j: flip it          (ce = 1)
//   any other syndrome       -> double (or worse) error: change nothing  (ue = 1)
//
//   IMPL 0 reference : behavioural syndrome + loop comparing against ecc_pkg::h_col()
//        1 flat      : ecc_enc_flat syndrome + ecc_corr_cmp
//        2 CSE       : ecc_enc_cse  syndrome + ecc_corr_cmp
//        3 ESPRESSO  : ecc_enc_tree syndrome + ecc_corr_espresso
//   PIPE 0 : combinational (LAT = 0)
//        1 : register after the syndrome; correction in the second cycle (LAT = 1)
// All outputs are valid when out_valid = 1 (out_valid = in_valid delayed by LAT).
// -----------------------------------------------------------------------------
module ecc_dec
    import ecc_pkg::*;
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
    output logic        ce,
    output logic        ue,
    output logic  [5:0] err_pos
);
    // Latency exported for the controller (read as u_dec.LAT); not used inside this module.
    /* verilator lint_off UNUSEDPARAM */
    localparam int LAT = PIPE;
    /* verilator lint_on UNUSEDPARAM */

    // ---------------- stage 1: syndrome ----------------
    logic [38:0] recalc;
    logic  [6:0] syn_c;

    ecc_enc #(.IMPL(IMPL)) u_syn (.data_in(cw_in[31:0]), .cw_out(recalc));
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
    logic        hit;

    generate
        if (IMPL == 3) begin : g_esp
            ecc_corr_espresso u_corr (.syn(syn), .flip(flip), .ce(hit));
        end else if (IMPL == 1 || IMPL == 2) begin : g_cmp
            ecc_corr_cmp      u_corr (.syn(syn), .flip(flip), .ce(hit));
        end else begin : g_ref
            always_comb begin
                for (int j = 0; j < CW_W; j++) flip[j] = (syn == h_col(j));
                hit = |flip;
            end
        end
    endgenerate

    // one-hot flip -> bit position (OR-encoder)
    always_comb begin
        err_pos = 6'd0;
        for (int j = 0; j < CW_W; j++)
            if (flip[j]) err_pos = err_pos | 6'(j);
    end

    assign ce        = hit;
    assign ue        = (syn != 7'd0) && !hit;
    assign cw_out    = cw ^ flip;            // flip is all-zero unless ce
    assign data_out  = cw_out[31:0];
    assign syndrome  = syn;
    assign out_valid = vld;
endmodule
