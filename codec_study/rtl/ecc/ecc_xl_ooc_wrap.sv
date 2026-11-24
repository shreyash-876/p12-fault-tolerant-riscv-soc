`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Register wrapper for out-of-context synthesis of the XOR-limited decoders (ecc_dec_xl).
// Every input and output is registered, as in ecc_ooc_wrap.sv, so the timing report measures the
// worst register -> logic -> register path inside the pipeline (or input/output stage).
// -----------------------------------------------------------------------------
module ecc_dec_xl_ooc #(
    parameter int CFG = 0
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
    output logic        ue,
    output logic  [5:0] err_pos
);
    logic [38:0] cw_q;
    logic        v_q;
    logic        ov_c, ce_c, ue_c;
    logic [31:0] d_c;
    logic [38:0] cwo_c;
    logic  [6:0] s_c;
    logic  [5:0] p_c;

    always_ff @(posedge clk) begin cw_q <= cw_in; v_q <= in_valid; end

    ecc_dec_xl #(.CFG(CFG)) u_dec (
        .clk, .rst_n, .in_valid(v_q), .cw_in(cw_q),
        .out_valid(ov_c), .data_out(d_c), .cw_out(cwo_c), .syndrome(s_c),
        .ce(ce_c), .ue(ue_c), .err_pos(p_c));

    always_ff @(posedge clk) begin
        out_valid <= ov_c; data_out <= d_c; cw_out <= cwo_c;
        syndrome <= s_c; ce <= ce_c; ue <= ue_c; err_pos <= p_c;
    end
endmodule
