`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// bram_sp: single-port block RAM, read-first, 1-cycle synchronous read.
//   Stage 1 : WIDTH=32, NLANES=4  -> per-byte write enables (byte-write BRAM)
//   Stage 2 : WIDTH=39, NLANES=1  -> one write enable for the whole codeword
// Contents start at zero. An all-zero word is also a valid Hsiao codeword, so the
// ECC stage needs no initialisation pass. INIT_FILE (hex, one word per line) is
// optional; it is used to preload .data for firmware.
// -----------------------------------------------------------------------------
module bram_sp #(
    parameter int DEPTH     = 2048,
    parameter int WIDTH     = 32,
    parameter int NLANES    = 4,
    parameter     INIT_FILE = ""
)(
    input  logic                     clk,
    input  logic                     en,
    input  logic [NLANES-1:0]        we,
    input  logic [$clog2(DEPTH)-1:0] addr,
    input  logic [WIDTH-1:0]         din,
    output logic [WIDTH-1:0]         dout
);
    localparam int LANE_W = WIDTH / NLANES;

    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) mem[i] = '0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            for (int l = 0; l < NLANES; l++)
                if (we[l]) mem[addr][l*LANE_W +: LANE_W] <= din[l*LANE_W +: LANE_W];
            dout <= mem[addr];
        end
    end
endmodule
