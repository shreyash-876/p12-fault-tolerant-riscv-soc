`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_scrubber: the background scrubber inside mem_subsystem.
//
// A small RAM (64 words), a fast scrubber (one word every 12 cycles) and short patience make
// a whole sweep take about 1000 cycles. As in tb_mem_ecc the testbench plays the radiation:
// it flips bits of the STORED 39-bit words directly in the RAM array, behind the controller.
// "force dut.scrub_enable" pauses / resumes the scrubber.
//
//   [1] repair          single errors are removed by the scrubber with NO CPU access at all
//   [2] why scrubbing   a second error in the same word: uncorrectable without the scrubber,
//                       harmless with it
//   [3] uncorrectable   a word with two flipped bits is reported, left untouched, and the
//                       sweep carries on and still repairs other words
//   [4] CPU wait        CPU reads with the scrubber running wait only a few cycles longer
//   [5] random stress   3000 random CPU reads/writes (full and partial) with single-bit errors
//                       injected on the way, scrubber running; every read must be correct
//
// Run: see README_scrubber.md. Vivado: simulation top = tb_scrubber, runtime = all.
// -----------------------------------------------------------------------------
module tb_scrubber;
    import mem_pkg::*;

    localparam int DEPTH = 64;
    localparam logic [31:0] BASE = 32'h2000_0000;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;                       // 50 MHz

    longint cyc = 0;
    always @(negedge clk) cyc = cyc + 1;

    // ---------------- DUT: data-RAM AXI port used, register port idle ----------------
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic  [3:0] wstrb;
    logic        awvalid = 0, awready, wvalid = 0, wready, bvalid, bready = 0;
    logic        arvalid = 0, arready, rvalid, rready = 0;
    logic  [1:0] bresp, rresp;

    logic [31:0] r_awaddr = 0, r_wdata = 0, r_araddr = 0, r_rdata;
    logic  [3:0] r_wstrb = 0;
    logic        r_awvalid = 0, r_awready, r_wvalid = 0, r_wready, r_bvalid, r_bready = 0;
    logic        r_arvalid = 0, r_arready, r_rvalid, r_rready = 0;
    logic  [1:0] r_bresp, r_rresp;
    logic        irq;

    mem_subsystem #(.DEPTH(DEPTH), .SCRUB_ENABLE(1), .SCRUB_INTERVAL(12), .SCRUB_PATIENCE(20)) dut (
        .clk, .rst_n,
        .s_mem_awaddr(awaddr), .s_mem_awvalid(awvalid), .s_mem_awready(awready),
        .s_mem_wdata(wdata), .s_mem_wstrb(wstrb), .s_mem_wvalid(wvalid), .s_mem_wready(wready),
        .s_mem_bresp(bresp), .s_mem_bvalid(bvalid), .s_mem_bready(bready),
        .s_mem_araddr(araddr), .s_mem_arvalid(arvalid), .s_mem_arready(arready),
        .s_mem_rdata(rdata), .s_mem_rresp(rresp), .s_mem_rvalid(rvalid), .s_mem_rready(rready),
        .s_reg_awaddr(r_awaddr), .s_reg_awvalid(r_awvalid), .s_reg_awready(r_awready),
        .s_reg_wdata(r_wdata), .s_reg_wstrb(r_wstrb), .s_reg_wvalid(r_wvalid), .s_reg_wready(r_wready),
        .s_reg_bresp(r_bresp), .s_reg_bvalid(r_bvalid), .s_reg_bready(r_bready),
        .s_reg_araddr(r_araddr), .s_reg_arvalid(r_arvalid), .s_reg_arready(r_arready),
        .s_reg_rdata(r_rdata), .s_reg_rresp(r_rresp), .s_reg_rvalid(r_rvalid), .s_reg_rready(r_rready),
        .hw_inj_single(1'b0), .hw_inj_double(1'b0),
        .irq_ue(irq), .irq_ce()
    );

    // is this stored word a valid codeword? (syndrome must be 0)
    logic [38:0] chk_cw = '0;
    logic  [6:0] chk_syn;
    ecc_syn u_chk (.cw_in(chk_cw), .syndrome(chk_syn));

    // ---------------- bookkeeping ----------------
    int errors = 0, checks = 0, sec_errors = 0;
    int ev_ce_cpu = 0, ev_ue_cpu = 0, ev_ce_scr = 0, ev_ue_scr = 0;   // events by who caused the access
    int lat_read = 0;

    always @(posedge clk) begin
        if (rst_n && dut.ev_valid) begin
            if (dut.ev_scrub) begin
                if (dut.ev_ce) ev_ce_scr = ev_ce_scr + 1;
                if (dut.ev_ue) ev_ue_scr = ev_ue_scr + 1;
            end else begin
                if (dut.ev_ce) ev_ce_cpu = ev_ce_cpu + 1;
                if (dut.ev_ue) ev_ue_cpu = ev_ue_cpu + 1;
            end
        end
    end

    task fail(input string msg);
        errors = errors + 1;
        sec_errors = sec_errors + 1;
        $display("    ** ERROR: %s", msg);
    endtask

    task section(input string title);
        sec_errors = 0;
        $display("");
        $display("------------------------------------------------------------------------");
        $display("%s", title);
        $display("------------------------------------------------------------------------");
    endtask

    task section_end(input string name);
        if (sec_errors == 0) $display("    %s: OK", name);
        else                 $display("    %s: FAILED (%0d errors)", name, sec_errors);
    endtask

    task idle(input int n);
        repeat (n) @(posedge clk);
    endtask

    // ---------------- AXI4-Lite master on the data-RAM port ----------------
    task axi_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s, output logic [1:0] resp);
        fork
            begin awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0; end
            begin wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0; end
        join
        bready <= 1;
        do @(posedge clk); while (!bvalid);
        resp = bresp;
        bready <= 0;
    endtask

    task axi_read(input logic [31:0] a, output logic [31:0] d, output logic [1:0] resp);
        longint t0;
        t0 = cyc;
        araddr <= a; arvalid <= 1;
        do @(posedge clk); while (!arready);
        arvalid <= 0;
        rready <= 1;
        do @(posedge clk); while (!rvalid);
        d = rdata;
        resp = rresp;
        rready <= 0;
        lat_read = int'(cyc - t0);
    endtask

    // ---------------- helpers ----------------
    logic [31:0] ref_mem [0:DEPTH-1];            // what the CPU believes is stored
    bit          corrupt [0:DEPTH-1];            // random test: a flipped bit may be in this word

    function logic [31:0] merge32(input logic [31:0] old_w, input logic [31:0] new_w, input logic [3:0] s);
        logic [31:0] r;
        r = old_w;
        for (int b = 0; b < 4; b++)
            if (s[b]) r[8*b +: 8] = new_w[8*b +: 8];
        merge32 = r;
    endfunction

    function logic [38:0] bitmask(input int b1, input int b2);   // b2 < 0: one bit only
        logic [38:0] m;
        m = 39'd0;
        m[b1] = 1'b1;
        if (b2 >= 0) m[b2] = 1'b1;
        bitmask = m;
    endfunction

    task flip_stored(input int word, input logic [38:0] m);
        dut.u_bram.mem[word] = dut.u_bram.mem[word] ^ m;
    endtask

    task pause_scrubber;
        force dut.scrub_enable = 1'b0;
        idle(12);                                // let a scrub operation that already started finish
    endtask

    task resume_scrubber;
        release dut.scrub_enable;
    endtask

    task wr_full(input int word, input logic [31:0] d);
        logic [1:0] resp;
        axi_write(BASE + word * 4, d, 4'b1111, resp);
        ref_mem[word] = d;
        checks = checks + 1;
        if (resp !== 2'b00) fail($sformatf("write word %0d: BRESP=%b", word, resp));
    endtask

    task rd_check(input int word, input logic [31:0] exp_data, input logic [1:0] exp_resp, input string what);
        logic [31:0] d;
        logic [1:0] resp;
        axi_read(BASE + word * 4, d, resp);
        checks = checks + 1;
        if (d !== exp_data || resp !== exp_resp)
            fail($sformatf("%s: word %0d read %h resp %b, expected %h resp %b", what, word, d, resp, exp_data, exp_resp));
    endtask

    task check_stored(input int word, input string what);
        chk_cw = dut.u_bram.mem[word];
        #1;
        checks = checks + 1;
        if (chk_syn !== 7'd0)
            fail($sformatf("%s: stored word %0d is not a valid codeword (syndrome %b)", what, word, chk_syn));
        checks = checks + 1;
        if (dut.u_bram.mem[word][31:0] !== ref_mem[word])
            fail($sformatf("%s: stored word %0d holds data %h, expected %h", what, word, dut.u_bram.mem[word][31:0], ref_mem[word]));
    endtask

    // wait until the scrubber has done n more scrub operations (with a timeout)
    task wait_scanned(input int n, input int timeout_cycles);
        int start, t;
        start = dut.scrub_scanned;
        t = 0;
        while ((dut.scrub_scanned - start) < n && t < timeout_cycles) begin
            @(posedge clk);
            t = t + 1;
        end
        if ((dut.scrub_scanned - start) < n) fail($sformatf("timeout: scrubber did only %0d of %0d operations", dut.scrub_scanned - start, n));
    endtask

    // wait until a stored word is a valid codeword again (the scrubber repaired it)
    task wait_valid(input int word, input int timeout_cycles);
        int t;
        t = 0;
        chk_cw = dut.u_bram.mem[word];
        #1;
        while (chk_syn !== 7'd0 && t < timeout_cycles) begin
            @(posedge clk);
            chk_cw = dut.u_bram.mem[word];
            #1;
            t = t + 1;
        end
        if (chk_syn !== 7'd0) fail($sformatf("timeout: word %0d was not repaired", word));
    endtask

    // ---------------- the tests ----------------
    initial begin
        logic [31:0] d, expd;
        logic [1:0]  resp;
        logic [38:0] pre;
        int w, n, kind, pos, k;
        int s0, r0, u0, ce_s0, ue_s0, ce_c0, ue_c0;
        int base_max, run_max, base_min, run_min, scanned_during;
        logic [3:0] s;
        int inj_word [0:7];
        int inj_bit  [0:7];

        force dut.scrub_enable = 1'b0;            // scrubber paused while the memory is set up

        $display("========================================================================");
        $display("tb_scrubber: %0d-word RAM, one scrub operation every 12 cycles, patience 20", DEPTH);
        $display("========================================================================");
        idle(3); rst_n = 1; idle(3);

        for (int i = 0; i < DEPTH; i++) begin
            d = $urandom;
            wr_full(i, d);
        end

        // ------------------------------------------------------------------ [1]
        section("[1] Repair: single errors are removed by the scrubber, with no CPU access at all");
        inj_word[0] = 3;  inj_bit[0] = 0;
        inj_word[1] = 12; inj_bit[1] = 31;
        inj_word[2] = 20; inj_bit[2] = 32;
        inj_word[3] = 31; inj_bit[3] = 38;
        inj_word[4] = 40; inj_bit[4] = 7;
        inj_word[5] = 47; inj_bit[5] = 19;
        inj_word[6] = 55; inj_bit[6] = 35;
        inj_word[7] = 62; inj_bit[7] = 25;
        for (int i = 0; i < 8; i++) flip_stored(inj_word[i], bitmask(inj_bit[i], -1));
        $display("    flipped one stored bit in each of 8 words (bits d0, d31, c0, c6, d7, d19, c3, d25)");
        for (int i = 0; i < 8; i++) begin
            chk_cw = dut.u_bram.mem[inj_word[i]]; #1;
            checks = checks + 1;
            if (chk_syn === 7'd0) fail($sformatf("injection into word %0d had no effect", inj_word[i]));
        end
        s0 = dut.scrub_scanned; r0 = dut.scrub_repaired; u0 = dut.scrub_ue; ce_s0 = ev_ce_scr;
        resume_scrubber;
        wait_scanned(DEPTH + 2, 5000);            // one full sweep (the pointer started at word 0)
        pause_scrubber;
        $display("    scrubber ran %0d scrub operations (one sweep = %0d words), the CPU read nothing",
                 dut.scrub_scanned - s0, DEPTH);
        for (int i = 0; i < DEPTH; i++) check_stored(i, "after one sweep");
        checks = checks + 1;
        if (dut.scrub_repaired - r0 != 8) fail($sformatf("scrubber repaired %0d words, expected 8", dut.scrub_repaired - r0));
        checks = checks + 1;
        if (dut.scrub_ue != u0) fail("scrubber reported an uncorrectable word");
        checks = checks + 1;
        if (ev_ce_scr - ce_s0 != 8) fail($sformatf("expected 8 'corrected by scrubber' events, saw %0d", ev_ce_scr - ce_s0));
        $display("    after the sweep all %0d stored words are valid codewords again; repaired = %0d, uncorrectable = %0d",
                 DEPTH, dut.scrub_repaired - r0, dut.scrub_ue - u0);
        section_end("[1]");

        // ------------------------------------------------------------------ [2]
        section("[2] Why scrubbing matters: a second error in the same word");
        // (a) scrubber paused: the two errors accumulate
        wr_full(5, 32'h89ABCDEF);
        flip_stored(5, bitmask(3, -1));
        idle(200);                                // time passes, nobody reads the word
        flip_stored(5, bitmask(20, -1));          // a second particle hits the same word
        expd = dut.u_bram.mem[5][31:0];
        rd_check(5, expd, 2'b10, "without scrubber");
        $display("    scrubber OFF: bit 3 flipped, later bit 20 flipped -> two errors in one word:");
        $display("                  CPU read returns %h (stored was 89abcdef) with SLVERR: the data is lost", expd);
        wr_full(5, 32'h89ABCDEF);                 // restore
        // (b) scrubber running: each error is repaired before the next one arrives
        flip_stored(5, bitmask(3, -1));
        u0 = dut.scrub_ue;
        resume_scrubber;
        wait_valid(5, 3000);
        $display("    scrubber ON : bit 3 flipped -> repaired by the scrubber (stored word valid again)");
        flip_stored(5, bitmask(20, -1));
        wait_valid(5, 3000);
        $display("                  bit 20 flipped later -> repaired as well");
        pause_scrubber;
        rd_check(5, 32'h89ABCDEF, 2'b00, "with scrubber");
        checks = checks + 1;
        if (dut.scrub_ue != u0) fail("scrubber found an uncorrectable word: errors accumulated");
        $display("                  CPU read returns 89abcdef with OKAY: the data survived both hits");
        section_end("[2]");

        // ------------------------------------------------------------------ [3]
        section("[3] An uncorrectable word: reported, left untouched, the sweep carries on");
        wr_full(9, 32'hDEADBEEF);
        flip_stored(9, bitmask(4, 36));           // d4 and c4 flipped: two errors in one word
        flip_stored(40, bitmask(10, -1));         // and an ordinary single error elsewhere
        pre = dut.u_bram.mem[9];
        s0 = dut.scrub_scanned; r0 = dut.scrub_repaired; u0 = dut.scrub_ue; ue_s0 = ev_ue_scr;
        resume_scrubber;
        wait_scanned(2 * DEPTH + 2, 8000);        // two sweeps
        pause_scrubber;
        checks = checks + 1;
        if (dut.u_bram.mem[9] !== pre) fail("the scrubber changed a word with an uncorrectable error");
        checks = checks + 1;
        if (dut.scrub_ue - u0 < 2) fail($sformatf("expected the uncorrectable word to be reported in each sweep, saw %0d", dut.scrub_ue - u0));
        checks = checks + 1;
        if (ev_ue_scr - ue_s0 != dut.scrub_ue - u0) fail("scrub error events and scrubber statistics disagree");
        check_stored(40, "single error in another word");
        $display("    word 9 (two flipped bits): left as it was (%h), reported %0d times in 2 sweeps", pre, dut.scrub_ue - u0);
        $display("    word 40 (one flipped bit): repaired in the same sweeps");
        wr_full(9, 32'hDEADBEEF);                 // a full write replaces the word and clears the problem
        check_stored(9, "after rewriting word 9");
        section_end("[3]");

        // ------------------------------------------------------------------ [4]
        section("[4] CPU wait: 200 back-to-back reads, scrubber off and on");
        base_max = 0; base_min = 1000;
        for (int i = 0; i < 200; i++) begin
            rd_check(i % DEPTH, ref_mem[i % DEPTH], 2'b00, "baseline read");
            if (lat_read > base_max) base_max = lat_read;
            if (lat_read < base_min) base_min = lat_read;
        end
        s0 = dut.scrub_scanned;
        resume_scrubber;
        run_max = 0; run_min = 1000;
        for (int i = 0; i < 200; i++) begin
            rd_check(i % DEPTH, ref_mem[i % DEPTH], 2'b00, "read with scrubber");
            if (lat_read > run_max) run_max = lat_read;
            if (lat_read < run_min) run_min = lat_read;
        end
        scanned_during = dut.scrub_scanned - s0;
        pause_scrubber;
        $display("    read latency, scrubber off : min %0d, max %0d cycles", base_min, base_max);
        $display("    read latency, scrubber on  : min %0d, max %0d cycles  (%0d scrub operations ran in the meantime)",
                 run_min, run_max, scanned_during);
        checks = checks + 1;
        if (run_max > base_max + 5) fail($sformatf("a CPU read waited %0d cycles longer than without the scrubber", run_max - base_max));
        checks = checks + 1;
        if (scanned_during < 1) fail("the scrubber made no progress while the CPU was reading");
        $display("    the CPU waits at most %0d extra cycles (one scrub operation) and every read was correct", run_max - base_max);
        section_end("[4]");

        // ------------------------------------------------------------------ [5]
        section("[5] Random stress: 3000 CPU operations with single-bit errors injected, scrubber running");
        for (int i = 0; i < DEPTH; i++) corrupt[i] = 1'b0;
        ce_c0 = ev_ce_cpu; ue_c0 = ev_ue_cpu; ce_s0 = ev_ce_scr; ue_s0 = ev_ue_scr; u0 = dut.scrub_ue;
        resume_scrubber;
        for (n = 1; n <= 3000; n++) begin
            w = $urandom_range(0, DEPTH - 1);
            // inject a single-bit error into a word that cannot hold another one right now
            if ($urandom_range(0, 3) == 0 && !corrupt[w]) begin
                flip_stored(w, bitmask($urandom_range(0, 38), -1));
                corrupt[w] = 1'b1;
            end
            kind = $urandom_range(0, 2);
            if (kind == 0) begin
                rd_check(w, ref_mem[w], 2'b00, "random read");
            end else if (kind == 1) begin
                wr_full(w, $urandom);
                corrupt[w] = 1'b0;
            end else begin
                d = $urandom;
                s = $urandom_range(1, 14);
                axi_write(BASE + w * 4, d, s, resp);
                checks = checks + 1;
                if (resp !== 2'b00) fail($sformatf("random partial write: BRESP=%b", resp));
                ref_mem[w] = merge32(ref_mem[w], d, s);
                corrupt[w] = 1'b0;
            end
            idle($urandom_range(0, 5));
            if (n % 1000 == 0)
                $display("    progress: %0d / 3000 operations, errors so far %0d", n, errors);
        end
        pause_scrubber;
        for (int i = 0; i < DEPTH; i++) rd_check(i, ref_mem[i], 2'b00, "final sweep");
        checks = checks + 1;
        if (ev_ue_cpu != ue_c0 || ev_ue_scr != ue_s0 || dut.scrub_ue != u0) fail("an uncorrectable error occurred: errors accumulated in a word");
        $display("    errors corrected on a CPU access: %0d, repaired by the scrubber: %0d, uncorrectable: 0",
                 ev_ce_cpu - ce_c0, ev_ce_scr - ce_s0);
        section_end("[5]");

        // ------------------------------------------------------------------ summary
        idle(5);
        $display("");
        $display("========================================================================");
        $display("SUMMARY");
        $display("  scrubber totals: %0d words scrubbed, %0d repaired, %0d uncorrectable reports, %0d full sweeps",
                 dut.scrub_scanned, dut.scrub_repaired, dut.scrub_ue, dut.scrub_sweeps);
        $display("------------------------------------------------------------------------");
        if (errors == 0) $display("PASS: %0d checks, 0 errors", checks);
        else             $display("FAIL: %0d errors in %0d checks", errors, checks);
        $display("========================================================================");
        $finish;
    end

    initial begin
        #200ms;
        $display("TIMEOUT");
        $finish;
    end
endmodule
