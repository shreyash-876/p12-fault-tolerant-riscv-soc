`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Register wrappers for out-of-context synthesis of the SEC-DED-DAEC codec (same method as ecc_ooc_wrap.sv):
// every input and output is registered, so the timing report measures the register -> codec -> register path.
// -----------------------------------------------------------------------------
module daec_enc_ooc #(
    parameter int IMPL = 0
)(
    input  logic        clk,
    input  logic [31:0] data_in,
    output logic [38:0] cw_out
);
    logic [31:0] d_q;
    logic [38:0] cw_c;
    always_ff @(posedge clk) d_q <= data_in;
    daec_enc #(.IMPL(IMPL)) u_enc (.data_in(d_q), .cw_out(cw_c));
    always_ff @(posedge clk) cw_out <= cw_c;
endmodule

module daec_dec_ooc #(
    parameter int IMPL = 0,
    parameter int PIPE = 0
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [38:0] cw_in,
    output logic        out_valid,
    output logic [31:0] data_out,
    output logic [38:0] cw_out,
    output logic  [6:0] syndrome,
    output logic        ce,
    output logic        ae,
    output logic        ue,
    output logic  [5:0] err_pos
);
    logic [38:0] cw_q;
    logic        v_q;
    logic        ov_c, ce_c, ae_c, ue_c;
    logic [31:0] d_c;
    logic [38:0] cwo_c;
    logic  [6:0] s_c;
    logic  [5:0] p_c;

    always_ff @(posedge clk) begin cw_q <= cw_in; v_q <= in_valid; end

    daec_dec #(.IMPL(IMPL), .PIPE(PIPE)) u_dec (
        .clk, .rst_n, .in_valid(v_q), .cw_in(cw_q),
        .out_valid(ov_c), .data_out(d_c), .cw_out(cwo_c), .syndrome(s_c),
        .ce(ce_c), .ae(ae_c), .ue(ue_c), .err_pos(p_c));

    always_ff @(posedge clk) begin
        out_valid <= ov_c; data_out <= d_c; cw_out <= cwo_c;
        syndrome <= s_c; ce <= ce_c; ae <= ae_c; ue <= ue_c; err_pos <= p_c;
    end
endmodule
