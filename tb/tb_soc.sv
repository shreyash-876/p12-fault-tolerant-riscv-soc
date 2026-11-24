`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_soc (STAGE 1b): full SoC (core + decoder + ITCM read port + data RAM +
// registers + GPIO + UART) running a program from firmware.hex.
//
//  * prints everything the firmware sends on the UART
//  * ends when the program writes a signature to SCRATCH2 (0x4000_000C):
//        0x0000600D = PASS, 0xBAD0_xxxx = FAIL (xxxx = failing test number)
//  * +max_cycles=N sets the timeout (default 2,000,000)
// The UART runs at CLKS_PER_BIT = 8 here so simulation is fast.
// -----------------------------------------------------------------------------
module tb_soc;
    localparam int CPB = 8;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;            // 50 MHz

    logic [3:0] led;
    logic       uart_tx, irq;
    logic [3:0] sw  = 4'b0000;
    logic [3:0] btn = 4'b0000;

    soc_top #(.ITCM_INIT("firmware.hex"), .CLKS_PER_BIT(CPB)) dut (
        .clk, .rst_n, .led, .sw, .btn, .uart_tx, .irq_ue(irq)
    );

    // ---------------- UART receiver (prints characters) ----------------
    initial begin
        logic [7:0] ch;
        forever begin
            @(negedge uart_tx);
            repeat (CPB / 2) @(posedge clk);          // middle of start bit
            for (int i = 0; i < 8; i++) begin
                repeat (CPB) @(posedge clk);
                ch[i] = uart_tx;
            end
            repeat (CPB) @(posedge clk);               // stop bit
            $write("%c", ch);
        end
    end

    // ---------------- end-of-test detection ----------------
    int max_cycles = 2_000_000;
    int cycles = 0;
    wire [31:0] sig = dut.u_mem.u_regs.scratch[2];

    initial begin
        if ($value$plusargs("max_cycles=%d", max_cycles));
        repeat (5) @(posedge clk);
        rst_n = 1;
        while (sig == 32'h0 && cycles < max_cycles) begin @(posedge clk); cycles++; end
        repeat (20) @(posedge clk);
        if (sig == 32'h0000_600D)              $display("\nRESULT PASS after %0d cycles", cycles);
        else if (sig[31:16] == 16'hBAD0)       $display("\nRESULT FAIL test %0d", sig[15:0]);
        else if (cycles >= max_cycles)         $display("\nRESULT TIMEOUT (pc=%h)", dut.u_core.if_id_pc);
        else                                   $display("\nRESULT UNKNOWN signature %h", sig);
        $finish;
    end
endmodule
