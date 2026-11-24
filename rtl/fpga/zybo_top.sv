`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// zybo_top: board wrapper for the Zybo Z7-10 (XC7Z010-1CLG400C). PL only, the
// Zynq PS is not used. Program over JTAG from the Vivado Hardware Manager.
//
//   sysclk 125 MHz (K17) -> MMCME2_BASE (x8 / 20) -> 50 MHz system clock
//   BTN3 = system reset (held in reset until the MMCM locks)
//   LD0..LD3, SW0..SW3, BTN0..BTN2 -> GPIO
//   uart_tx -> Pmod JE pin 1 (see zybo_z7_10.xdc)
// -----------------------------------------------------------------------------
module zybo_top (
    input  logic       sysclk,
    input  logic [3:0] sw,
    input  logic [3:0] btn,
    output logic [3:0] led,
    output logic       uart_tx
);
    // ---------------- clocking: 125 MHz -> 50 MHz ----------------
    logic clkfb, clk_mmcm, clk, locked;

    MMCME2_BASE #(
        .BANDWIDTH       ("OPTIMIZED"),
        .CLKIN1_PERIOD   (8.000),      // 125 MHz
        .DIVCLK_DIVIDE   (1),
        .CLKFBOUT_MULT_F (8.000),      // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F(20.000),     // 50 MHz
        .STARTUP_WAIT    ("FALSE")
    ) u_mmcm (
        .CLKIN1  (sysclk),
        .CLKFBIN (clkfb),
        .CLKFBOUT(clkfb),
        .CLKOUT0 (clk_mmcm),
        .LOCKED  (locked),
        .PWRDWN  (1'b0),
        .RST     (1'b0),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG u_bufg (.I(clk_mmcm), .O(clk));

    // ---------------- reset: async assert, sync release ----------------
    wire rst_req_n = locked & ~btn[3];
    (* ASYNC_REG = "TRUE" *) logic [2:0] rst_sync;
    always_ff @(posedge clk or negedge rst_req_n) begin
        if (!rst_req_n) rst_sync <= 3'b000;
        else            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire rst_n = rst_sync[2];

    // ---------------- SoC ----------------
    logic irq_ue, irq_ce;           // interrupt lines of the ECC system
    logic [3:0] led_gpio;           // LEDs as driven by the firmware through the GPIO block

    soc_top #(
        .ITCM_INIT   ("firmware.hex"),
        .CLKS_PER_BIT(434)                 // 50 MHz / 115200 baud
    ) u_soc (
        .clk, .rst_n,
        .led(led_gpio), .sw,
        .btn   ({1'b0, btn[2:0]}),
        .uart_tx,
        .irq_ue, .irq_ce
    );

    // LD2 lights while an uncorrectable error is flagged and its interrupt is enabled (or when firmware sets it)
    assign led = {led_gpio[3], led_gpio[2] | irq_ue, led_gpio[1:0]};
endmodule
