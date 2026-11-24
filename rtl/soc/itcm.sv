`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// itcm: instruction memory, true dual-port block RAM, one clock.
//   Port A: instruction fetch (en_a = !fetch stall, so the output holds during stalls)
//   Port B: data-side READ port, served on the bus at 0x0000_0000 by
//           axil_frontend + mem_ctrl(READ_ONLY). Lets loads read .rodata (strings,
//           constant tables) and the .data initial values that crt0 copies to RAM.
// The program is loaded at bitstream time from INIT_FILE (one 32-bit hex word per line).
// -----------------------------------------------------------------------------
module itcm #(
    parameter int DEPTH     = 4096,          // 16 KB
    parameter     INIT_FILE = ""
)(
    input  logic                     clk,
    // Port A: fetch
    input  logic                     en_a,
    input  logic [$clog2(DEPTH)-1:0] addr_a,
    output logic [31:0]              dout_a,
    // Port B: data-side read
    input  logic                     en_b,
    input  logic [$clog2(DEPTH)-1:0] addr_b,
    output logic [31:0]              dout_b
);
    (* ram_style = "block" *) logic [31:0] ram [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) ram[i] = 32'h0000_0013;   // NOP
        if (INIT_FILE != "") $readmemh(INIT_FILE, ram);
    end

    always_ff @(posedge clk) if (en_a) dout_a <= ram[addr_a];
    always_ff @(posedge clk) if (en_b) dout_b <= ram[addr_b];
endmodule
