`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_soc_log: the whole system running the firmware error-log demo (fw_ecc_log/firmware.hex).
//
//   * the testbench plays the person pressing the injection buttons: after the firmware announces itself
//     (SCRATCH0 = 1) it presses BTN1 (one random bit flip, 70 %) or BTN2 (two random bit flips, 30 %) at random
//     intervals of 3000..15000 cycles, until the firmware says it is done (SCRATCH0 = 9)
//   * everything the firmware prints (the firmware error log) appears in the console
//   * the run ends when the firmware writes its signature to SCRATCH2: 0x600D = all its checks passed
// The UART runs at CLKS_PER_BIT = 8 and the buttons are debounced over 8 cycles to keep the simulation short.
// Random choices are seeded: +seed=N repeats a run exactly; +max_cycles=N sets the timeout.
// -----------------------------------------------------------------------------
module tb_soc_log;
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

    wire [31:0] sc0 = dut.u_mem.u_regs.scratch[0];
    wire [31:0] sig = dut.u_mem.u_regs.scratch[2];

    int presses_single = 0, presses_double = 0, cycles = 0;
    int irq_ue_rises = 0, irq_ce_rises = 0;
    logic irq_ue_d = 0, irq_ce_d = 0;
    always @(posedge clk) begin
        irq_ue_d <= irq_ue; irq_ce_d <= irq_ce;
        if (rst_n && irq_ue && !irq_ue_d) irq_ue_rises = irq_ue_rises + 1;
        if (rst_n && irq_ce && !irq_ce_d) irq_ce_rises = irq_ce_rises + 1;
    end

    // ---------------- the person pressing the buttons ----------------
    integer seed, seed_used, seed_dummy;
    initial begin
        int d, k;
        bit done;
        seed = 1;
        if ($value$plusargs("seed=%d", seed)) begin end
        seed_used = seed;
        seed_dummy = $urandom(seed);
        $display("[testbench] button-press seed %0d", seed_used);
        wait (rst_n === 1'b1);
        wait (sc0 === 32'd1);
        $display("[testbench] cycle %0d: firmware is running, button pressing starts", cycles);
        done = 1'b0;
        while (!done) begin
            d = $urandom_range(3000, 15000);
            repeat (d) @(posedge clk);
            if (sc0 === 32'd9) begin
                done = 1'b1;
            end else begin
                k = $urandom_range(0, 9);
                if (k < 7) begin
                    btn[1] = 1'b1; repeat (30) @(posedge clk); btn[1] = 1'b0;
                    presses_single = presses_single + 1;
                end else begin
                    btn[2] = 1'b1; repeat (30) @(posedge clk); btn[2] = 1'b0;
                    presses_double = presses_double + 1;
                end
            end
        end
    end

    // ---------------- end-of-test detection ----------------
    int max_cycles = 8_000_000;
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
        $display("[testbench] buttons pressed: %0d x BTN1 (single), %0d x BTN2 (double); injections done by the hardware: %0d",
                 presses_single, presses_double, dut.u_mem.ij_count);
        $display("[testbench] irq_ue rose %0d time(s), irq_ce rose %0d time(s); scrubber: %0d scanned, %0d repaired, %0d sweeps",
                 irq_ue_rises, irq_ce_rises, dut.u_mem.scrub_scanned, dut.u_mem.scrub_repaired, dut.u_mem.scrub_sweeps);
        if ($test$plusargs("dump")) begin
            int bw;
            if ($value$plusargs("bufword=%d", bw)) begin
                for (int i = 0; i < 128; i++) $display("MEMDUMP %0d %h", i, dut.u_mem.u_bram.mem[bw + i]);
            end
        end
        if (sig == 32'h0000_600D && dut.u_mem.ij_count > 5)
            $display("ERROR-LOG SYSTEM TEST PASS (seed %0d)", seed_used);
        else
            $display("ERROR-LOG SYSTEM TEST FAIL (seed %0d)", seed_used);
        $finish;
    end
endmodule
