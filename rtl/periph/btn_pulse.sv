`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// btn_pulse: board button -> clean one-cycle pulse on each press.
// Two-flip-flop synchroniser, then a debounce filter: the debounced level only changes after the
// input has been stable for DEBOUNCE_CYCLES clock cycles (500,000 at 50 MHz = 10 ms), then a
// one-cycle pulse is produced on the rising edge of the debounced level.
// -----------------------------------------------------------------------------
module btn_pulse #(
    parameter int DEBOUNCE_CYCLES = 500000
)(
    input  logic clk,
    input  logic rst_n,
    input  logic btn,
    output logic pulse
);
    (* ASYNC_REG = "TRUE" *) logic s1, s2;
    logic        stable;
    logic [31:0] cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= 1'b0; s2 <= 1'b0; stable <= 1'b0; cnt <= 32'd0; pulse <= 1'b0;
        end else begin
            s1 <= btn;
            s2 <= s1;
            pulse <= 1'b0;
            if (s2 == stable) begin
                cnt <= 32'd0;
            end else if (cnt >= DEBOUNCE_CYCLES - 1) begin
                stable <= s2;
                cnt    <= 32'd0;
                pulse  <= s2;                       // pulse on press, not on release
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
endmodule
