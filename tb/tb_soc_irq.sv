`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_soc_irq: interrupt stress test for the RV32I core. The full SoC runs fw_irq_stress/firmware.hex.
//
// The testbench produces the core's interrupt request by forcing the wire dut.core_irq (normally the OR of the
// ECC system's irq_ue / irq_ce lines), at moments it chooses at random:
//   storm (SCRATCH0 = 2)  raise the request after a random delay (mostly 1..400 cycles, one time in ten 0..2 cycles:
//                         back-to-back), hold it until the handler acknowledges (it writes SCRATCH1), keep it
//                         high for a random 0..25 more cycles (so sometimes a second interrupt follows at once), drop it
//   SCRATCH0 = 3          raise the request while mstatus.MIE = 0 and hold it until it is finally taken
//   SCRATCH0 = 4          the same while mie.MEIE = 0
// The firmware checks the results itself (identical checksum with and without the storm, correct mcause/mepc, no
// interrupt taken while disabled) and writes 0x600D to SCRATCH2 when everything is right.
// Random choices are seeded: +seed=N repeats a run exactly. +max_cycles=N sets the timeout.
// -----------------------------------------------------------------------------
module tb_soc_irq;
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

    wire [31:0] sc0 = dut.u_mem.u_regs.scratch[0];     // phase handshake from the firmware
    wire [31:0] sc1 = dut.u_mem.u_regs.scratch[1];     // the handler's acknowledgement (its running count)
    wire [31:0] sig = dut.u_mem.u_regs.scratch[2];

    int fires = 0, acks = 0, storm_fires = 0, back_to_back = 0;
    int cycles = 0;
    always @(sc1) if (rst_n) acks = acks + 1;           // every interrupt taken = one write of SCRATCH1

    // ---------------- the interrupt request generator ----------------
    integer seed, seed_used, seed_dummy;
    initial begin
        int a0, d, d2, k;
        bit storm_done;
        seed = 1;
        if ($value$plusargs("seed=%d", seed)) begin end
        seed_used = seed;
        seed_dummy = $urandom(seed);
        force dut.core_irq = 1'b0;
        $display("[testbench] interrupt storm seed %0d", seed_used);

        wait (rst_n === 1'b1);
        wait (sc0 === 32'd2);
        $display("[testbench] cycle %0d: storm starts", cycles);
        storm_done = 1'b0;
        while (!storm_done && sc0 === 32'd2) begin
            k = $urandom_range(0, 9);
            if (k == 0) d = $urandom_range(0, 2); else d = $urandom_range(1, 400);
            repeat (d) @(posedge clk);
            if (sc0 !== 32'd2) begin
                storm_done = 1'b1;
            end else begin
                a0 = acks;
                force dut.core_irq = 1'b1;
                fires++; storm_fires++;
                while (acks == a0 && sc0 === 32'd2) @(posedge clk);       // until the handler acknowledges (or the storm ends)
                d2 = $urandom_range(0, 25);
                repeat (d2) @(posedge clk);
                force dut.core_irq = 1'b0;
            end
        end
        force dut.core_irq = 1'b0;
        $display("[testbench] cycle %0d: storm over, %0d requests raised, %0d interrupts taken", cycles, storm_fires, acks);

        // request while mstatus.MIE = 0
        wait (sc0 === 32'd3);
        a0 = acks;
        force dut.core_irq = 1'b1; fires++;
        $display("[testbench] cycle %0d: request raised while MIE = 0 (the core must not take it yet)", cycles);
        while (acks == a0) @(posedge clk);
        $display("[testbench] cycle %0d: taken after the firmware set MIE", cycles);
        d2 = $urandom_range(0, 25); repeat (d2) @(posedge clk);
        force dut.core_irq = 1'b0;

        // request while mie.MEIE = 0
        wait (sc0 === 32'd4);
        a0 = acks;
        force dut.core_irq = 1'b1; fires++;
        $display("[testbench] cycle %0d: request raised while mie.MEIE = 0 (the core must not take it yet)", cycles);
        while (acks == a0) @(posedge clk);
        $display("[testbench] cycle %0d: taken after the firmware set MEIE", cycles);
        d2 = $urandom_range(0, 25); repeat (d2) @(posedge clk);
        force dut.core_irq = 1'b0;
    end

    // ---------------- end-of-test detection ----------------
    int max_cycles = 6_000_000;
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
        $display("[testbench] requests raised: %0d, interrupts taken (handler acknowledgements): %0d", fires, acks);
        if (sig == 32'h0000_600D && acks >= storm_fires / 2 && acks > 50)
            $display("INTERRUPT TEST PASS (seed %0d)", seed_used);
        else
            $display("INTERRUPT TEST FAIL (seed %0d)", seed_used);
        $finish;
    end
endmodule
