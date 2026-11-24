`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_soc_ecc: the full SoC (RV32 core, AXI4-Lite bus, ECC memory system with scrubber, register
// block and injection port) running the self-checking ECC demo firmware (fw_ecc_demo / main.c).
//
//  * prints everything the firmware sends on the UART
//  * presses board button BTN1 when the firmware asks for it (it writes 1 to SCRATCH0)
//  * watches the irq_ue line and reports every change
//  * ends when the firmware writes its signature to SCRATCH2 (0x4000_000C):
//        0x0000600D = PASS, 0xBAD0_00nn = check nn of the firmware failed
// The UART runs at CLKS_PER_BIT = 8 and the buttons are debounced over 8 cycles, to keep the simulation short.
// -----------------------------------------------------------------------------
module tb_soc_ecc;
    localparam int CPB = 8;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;            // 50 MHz

    logic [3:0] led;
    logic       uart_tx, irq_ue, irq_ce;
    logic [3:0] sw  = 4'b0000;
    logic [3:0] btn = 4'b0000;

    soc_top #(.ITCM_INIT("firmware.hex"), .CLKS_PER_BIT(CPB), .BTN_DEBOUNCE(8)) dut (
        .clk, .rst_n, .led, .sw, .btn, .uart_tx, .irq_ue, .irq_ce
    );

    // ---------------- UART receiver (prints characters) ----------------
    initial begin
        logic [7:0] ch;
        forever begin
            @(negedge uart_tx);
            repeat (CPB / 2) @(posedge clk);
            for (int i = 0; i < 8; i++) begin
                repeat (CPB) @(posedge clk);
                ch[i] = uart_tx;
            end
            repeat (CPB) @(posedge clk);
            $write("%c", ch);
        end
    end

    // ---------------- board button: pressed when the firmware asks (SCRATCH0 = 1) ----------------
    initial begin
        wait (rst_n === 1'b1);
        wait (dut.u_mem.u_regs.scratch[0] === 32'd1);
        repeat (50) @(posedge clk);
        $display("[testbench] BTN1 pressed");
        btn[1] = 1'b1;
        repeat (40) @(posedge clk);
        btn[1] = 1'b0;
    end

    // ---------------- interrupt line monitor ----------------
    logic irq_prev = 1'b0;
    int   irq_rises = 0, irq_falls = 0;
    int   cycles = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (irq_ue !== irq_prev) begin
                if (irq_ue) irq_rises = irq_rises + 1; else irq_falls = irq_falls + 1;
                $display("[testbench] cycle %0d: irq_ue went %b -> %b", cycles, irq_prev, irq_ue);
                irq_prev <= irq_ue;
            end
        end
    end

    // ---------------- end-of-test detection ----------------
    int max_cycles = 3_000_000;
    wire [31:0] sig = dut.u_mem.u_regs.scratch[2];

    initial begin
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin end
        repeat (5) @(posedge clk);
        rst_n = 1;
        while (sig == 32'h0 && cycles < max_cycles) begin @(posedge clk); cycles++; end
        repeat (20) @(posedge clk);
        if (sig == 32'h0000_600D)              $display("\nRESULT PASS after %0d cycles", cycles);
        else if (sig[31:16] == 16'hBAD0)       $display("\nRESULT FAIL check %0d", sig[15:0]);
        else if (cycles >= max_cycles)         $display("\nRESULT TIMEOUT (pc=%h)", dut.u_core.if_id_pc);
        else                                   $display("\nRESULT UNKNOWN signature %h", sig);
        $display("[testbench] irq_ue rose %0d time(s) and fell %0d time(s); final level %b", irq_rises, irq_falls, irq_ue);
        if (sig == 32'h0000_600D && irq_rises >= 1 && irq_falls >= 1 && irq_ue === 1'b0)
            $display("SYSTEM TEST PASS: firmware self-checks passed and the interrupt line behaved");
        else
            $display("SYSTEM TEST FAIL");
        $finish;
    end
endmodule
