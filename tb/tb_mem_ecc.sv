`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_mem_ecc: ECC encoder/decoder and read-modify-write behind the AXI4-Lite slave.
//
// Only the data-RAM AXI port is used. The testbench drives it like the CPU would, and
// it plays the part of the radiation: it flips bits of the STORED 39-bit words directly
// in the RAM array (dut.u_bram.mem[...]), behind the controller's back.
//
//   [1] encoder in the write path   stored words equal the golden-model codewords
//   [2] single-bit errors           every one of the 39 bit positions is corrected on read
//   [3] double-bit errors           detected: SLVERR on the bus, raw data, nothing "fixed"
//   [4] partial writes (RMW)        every byte-strobe pattern on a clean word
//   [5] RMW on a word with one flipped bit   corrected, merged, stored word valid again
//   [6] RMW on a word with two flipped bits  aborted: SLVERR and the word is left untouched
//   [7] random stress               random reads/writes (full and partial) with single-bit
//                                   errors injected on the way; every read must be correct
//
// Run: iverilog -g2012 ... (see README_integration.md)   or Vivado xsim, top = tb_mem_ecc,
// runtime = all.
// -----------------------------------------------------------------------------
module tb_mem_ecc;
    import mem_pkg::*;

    localparam int DEPTH = 2048;
    localparam logic [31:0] BASE = 32'h2000_0000;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;                       // 50 MHz

    // cycle counter for the latency report (counts at the falling edge, so reads at the
    // rising edge never race with the increment)
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

    mem_subsystem #(.DEPTH(DEPTH), .SCRUB_ENABLE(0)) dut (   // scrubber off: this test checks the controller alone
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

    // a checker for "is this stored word a valid codeword?" (syndrome must be 0)
    logic [38:0] chk_cw = '0;
    logic  [6:0] chk_syn;
    ecc_syn u_chk (.cw_in(chk_cw), .syndrome(chk_syn));

    // ---------------- bookkeeping ----------------
    int errors = 0, checks = 0;
    int sec_errors = 0;
    int ev_ce_cnt = 0, ev_ue_cnt = 0;            // error events seen from the controller
    int last_ev_pos = 0;
    int lat_read = 0, lat_wr_full = 0, lat_rmw = 0;

    always @(posedge clk) begin
        if (rst_n && dut.ev_valid) begin
            if (dut.ev_ce) ev_ce_cnt = ev_ce_cnt + 1;
            if (dut.ev_ue) ev_ue_cnt = ev_ue_cnt + 1;
            last_ev_pos = dut.ev_pos;
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
        longint t0;
        t0 = cyc;
        fork
            begin awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0; end
            begin wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0; end
        join
        bready <= 1;
        do @(posedge clk); while (!bvalid);
        resp = bresp;
        bready <= 0;
        if (s == 4'b1111) lat_wr_full = int'(cyc - t0);
        else if (s != 4'b0000) lat_rmw = int'(cyc - t0);
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
    function logic [31:0] merge32(input logic [31:0] old_w, input logic [31:0] new_w, input logic [3:0] s);
        logic [31:0] r;
        r = old_w;
        for (int b = 0; b < 4; b++)
            if (s[b]) r[8*b +: 8] = new_w[8*b +: 8];
        merge32 = r;
    endfunction

    function logic [38:0] bitmask(input int b1, input int b2);   // b2 < 0: only one bit
        logic [38:0] m;
        m = 39'd0;
        m[b1] = 1'b1;
        if (b2 >= 0) m[b2] = 1'b1;
        bitmask = m;
    endfunction

    // flip stored bits behind the controller's back
    task flip_stored(input int word, input logic [38:0] m);
        dut.u_bram.mem[word] = dut.u_bram.mem[word] ^ m;
    endtask

    // write a full word and check the OKAY response
    task wr_full(input int word, input logic [31:0] d);
        logic [1:0] resp;
        axi_write(BASE + word * 4, d, 4'b1111, resp);
        checks = checks + 1;
        if (resp !== 2'b00) fail($sformatf("full write word %0d: BRESP=%b", word, resp));
    endtask

    // read and compare data and response code
    task rd_check(input int word, input logic [31:0] exp_data, input logic [1:0] exp_resp, input string what);
        logic [31:0] d;
        logic [1:0] resp;
        axi_read(BASE + word * 4, d, resp);
        checks = checks + 1;
        if (d !== exp_data || resp !== exp_resp)
            fail($sformatf("%s: word %0d read %h resp %b, expected %h resp %b", what, word, d, resp, exp_data, exp_resp));
    endtask

    // stored word must be a valid codeword
    task stored_valid(input int word, input string what);
        chk_cw = dut.u_bram.mem[word];
        #1;
        checks = checks + 1;
        if (chk_syn !== 7'd0)
            fail($sformatf("%s: stored word %0d is not a valid codeword (syndrome %b)", what, word, chk_syn));
    endtask

    // ---------------- reference model for the random test ----------------
    logic [31:0] ref_mem [0:63];
    bit          corrupt [0:63];

    // ---------------- the tests ----------------
    initial begin
        logic [31:0] data_a [0:4];
        logic [38:0] cw_a   [0:4];
        logic [31:0] d, base_w, newd, expd, r;
        logic [1:0]  resp;
        logic [38:0] pre;
        int ce0, ue0, w, pos, n, kind, pa, pb;
        logic [3:0] s;

        $display("========================================================================");
        $display("tb_mem_ecc: AXI4-Lite -> mem_subsystem (ECC + read-modify-write) -> 39-bit BRAM");
        $display("========================================================================");
        idle(3); rst_n = 1; idle(3);

        // ------------------------------------------------------------------ [1]
        section("[1] Encoder in the write path: stored words must equal the golden-model codewords");
        data_a[0] = 32'h00000000; cw_a[0] = 39'h00_0000_0000;
        data_a[1] = 32'h89ABCDEF; cw_a[1] = 39'h36_89AB_CDEF;
        data_a[2] = 32'h00080000; cw_a[2] = 39'h4A_0008_0000;
        data_a[3] = 32'hFFFFFFFF; cw_a[3] = 39'h03_FFFF_FFFF;
        data_a[4] = 32'h55555555; cw_a[4] = 39'h77_5555_5555;
        for (int i = 0; i < 5; i++) begin
            wr_full(i, data_a[i]);
            checks = checks + 1;
            if (dut.u_bram.mem[i] !== cw_a[i]) fail($sformatf("word %0d stored %h, golden codeword %h", i, dut.u_bram.mem[i], cw_a[i]));
            rd_check(i, data_a[i], 2'b00, "read back");
            $display("    write %h -> RAM holds %h (check bits %h) -> read back %h", data_a[i], dut.u_bram.mem[i], dut.u_bram.mem[i][38:32], data_a[i]);
        end
        section_end("[1]");

        // ------------------------------------------------------------------ [2]
        section("[2] Single-bit error in each of the 39 stored bits: corrected on read, SLVERR never");
        base_w = 32'h89ABCDEF;
        ce0 = ev_ce_cnt;
        for (pos = 0; pos < 39; pos++) begin
            wr_full(10, base_w);
            flip_stored(10, bitmask(pos, -1));
            pre = dut.u_bram.mem[10];
            rd_check(10, base_w, 2'b00, "single error");
            idle(3);
            checks = checks + 1;
            if (last_ev_pos != pos) fail($sformatf("error event reported bit %0d, expected %0d", last_ev_pos, pos));
            checks = checks + 1;
            if (dut.u_bram.mem[10] !== pre) fail("a read must not modify the stored word");
        end
        checks = checks + 1;
        if (ev_ce_cnt - ce0 != 39) fail($sformatf("expected 39 corrected-error events, saw %0d", ev_ce_cnt - ce0));
        $display("    all 39 positions (d0..d31, c0..c6) corrected; 39 'corrected' events seen; reads leave the");
        $display("    stored word as it is (the scrubber of Stage 3 will rewrite it)");
        section_end("[2]");

        // ------------------------------------------------------------------ [3]
        section("[3] Double-bit errors: detected (SLVERR), data returned unmodified");
        ue0 = ev_ue_cnt;
        for (int k = 0; k < 8; k++) begin
            case (k)
                0: begin pa = 0;  pb = 4;  end      // d0  d4
                1: begin pa = 3;  pb = 35; end      // d3  c3
                2: begin pa = 33; pb = 36; end      // c1  c4
                3: begin pa = 31; pb = 32; end      // d31 c0
                4: begin pa = 0;  pb = 38; end      // d0  c6
                5: begin pa = 15; pb = 16; end      // d15 d16
                6: begin pa = 1;  pb = 2;  end      // d1  d2
                default: begin pa = 37; pb = 38; end  // c5  c6
            endcase
            wr_full(11, base_w);
            flip_stored(11, bitmask(pa, pb));
            expd = dut.u_bram.mem[11][31:0];          // data bits exactly as stored (flips included)
            rd_check(11, expd, 2'b10, "double error");
            $display("    flipped bits %0d and %0d -> read returns %h with RRESP=SLVERR", pa, pb, expd);
        end
        idle(3);
        checks = checks + 1;
        if (ev_ue_cnt - ue0 != 8) fail($sformatf("expected 8 uncorrectable events, saw %0d", ev_ue_cnt - ue0));
        section_end("[3]");

        // ------------------------------------------------------------------ [4]
        section("[4] Partial writes (read-modify-write): every byte-strobe pattern on a clean word");
        base_w = 32'h89ABCDEF;
        newd   = 32'h11223344;
        for (int sv = 0; sv < 16; sv++) begin
            s = sv[3:0];
            wr_full(20, base_w);
            axi_write(BASE + 20 * 4, newd, s, resp);
            checks = checks + 1;
            if (resp !== 2'b00) fail($sformatf("partial write strobe %b: BRESP=%b", s, resp));
            expd = merge32(base_w, newd, s);
            rd_check(20, expd, 2'b00, "after partial write");
            stored_valid(20, "after partial write");
            if (sv != 0 && sv != 15)
                $display("    strobe %b: %h with %h -> %h", s, base_w, newd, expd);
        end
        section_end("[4]");

        // ------------------------------------------------------------------ [5]
        section("[5] Partial write onto a word that has ONE flipped bit: corrected, merged, valid again");
        ce0 = ev_ce_cnt;
        for (int k = 0; k < 4; k++) begin
            case (k)
                0: pos = 0;       // d0  (inside the byte that is NOT written)
                1: pos = 12;      // d12 (inside the byte that IS written)
                2: pos = 35;      // c3  (a check bit)
                default: pos = 31;
            endcase
            wr_full(21, base_w);
            flip_stored(21, bitmask(pos, -1));
            axi_write(BASE + 21 * 4, 32'h0000AA00, 4'b0010, resp);      // byte 1 only
            checks = checks + 1;
            if (resp !== 2'b00) fail($sformatf("RMW on single-error word: BRESP=%b", resp));
            expd = merge32(base_w, 32'h0000AA00, 4'b0010);
            rd_check(21, expd, 2'b00, "after RMW on single-error word");
            stored_valid(21, "after RMW on single-error word");
            $display("    flipped bit %0d, wrote byte 1 = AA -> read %h (stored word is a valid codeword again)", pos, expd);
        end
        checks = checks + 1;
        if (ev_ce_cnt - ce0 != 4) fail($sformatf("expected 4 corrected events, saw %0d", ev_ce_cnt - ce0));
        section_end("[5]");

        // ------------------------------------------------------------------ [6]
        section("[6] Partial write onto a word with TWO flipped bits: aborted, word untouched");
        ue0 = ev_ue_cnt;
        wr_full(22, base_w);
        flip_stored(22, bitmask(3, 20));
        pre = dut.u_bram.mem[22];
        axi_write(BASE + 22 * 4, 32'h000000FF, 4'b0001, resp);
        checks = checks + 1;
        if (resp !== 2'b10) fail($sformatf("RMW on double-error word: BRESP=%b, expected SLVERR (10)", resp));
        checks = checks + 1;
        if (dut.u_bram.mem[22] !== pre) fail("an aborted read-modify-write must not change the stored word");
        idle(3);
        checks = checks + 1;
        if (ev_ue_cnt - ue0 != 1) fail("expected one uncorrectable event");
        $display("    BRESP = SLVERR and the stored word is unchanged (%h)", pre);
        // a FULL-word write replaces everything and repairs the word
        wr_full(22, 32'hCAFEBABE);
        rd_check(22, 32'hCAFEBABE, 2'b00, "full write after double error");
        stored_valid(22, "full write after double error");
        $display("    a full-word write afterwards replaces the word and clears the problem");
        section_end("[6]");

        // ------------------------------------------------------------------ [7]
        section("[7] Random stress: 3000 operations on 64 words, single-bit errors injected on the way");
        for (int i = 0; i < 64; i++) begin
            ref_mem[i] = 32'h0;
            corrupt[i] = 1'b0;
            wr_full(100 + i, 32'h0);
        end
        ce0 = ev_ce_cnt;
        for (n = 1; n <= 3000; n++) begin
            w = $urandom_range(0, 63);
            // inject a single-bit error into a word that is clean right now
            if ($urandom_range(0, 3) == 0 && !corrupt[w]) begin
                flip_stored(100 + w, bitmask($urandom_range(0, 38), -1));
                corrupt[w] = 1'b1;
            end
            kind = $urandom_range(0, 2);
            if (kind == 0) begin                                          // read
                rd_check(100 + w, ref_mem[w], 2'b00, "random read");
            end else if (kind == 1) begin                                 // full write
                r = $urandom;
                wr_full(100 + w, r);
                ref_mem[w] = r;
                corrupt[w] = 1'b0;                                        // overwritten: clean
            end else begin                                                // partial write
                r = $urandom;
                s = $urandom_range(1, 14);                                // not 0, not 15
                axi_write(BASE + (100 + w) * 4, r, s, resp);
                checks = checks + 1;
                if (resp !== 2'b00) fail($sformatf("random RMW: BRESP=%b", resp));
                ref_mem[w] = merge32(ref_mem[w], r, s);
                corrupt[w] = 1'b0;                                        // corrected and rewritten
            end
            if (n % 1000 == 0)
                $display("    progress: %0d / 3000 operations, errors so far %0d, errors corrected so far %0d",
                         n, errors, ev_ce_cnt - ce0);
        end
        // final sweep: every word must read back as the model says
        for (int i = 0; i < 64; i++) rd_check(100 + i, ref_mem[i], 2'b00, "final sweep");
        section_end("[7]");

        // ------------------------------------------------------------------ [8]
        section("[8] Access latency with an idle bus (information only, not a pass/fail check)");
        idle(10); wr_full(30, 32'h12345678);
        idle(10); axi_write(BASE + 30 * 4, 32'h000000AA, 4'b0001, resp);
        idle(10); axi_read(BASE + 30 * 4, d, resp);
        $display("    cycles from AWVALID/ARVALID to the response being seen by the master:");
        $display("      read %0d, full-word write %0d, partial write (read-modify-write) %0d", lat_read, lat_wr_full, lat_rmw);
        $display("    (the Stage 1 controller without ECC measures 4, 4 and 4: ECC costs +1 cycle on a read or a");
        $display("     full-word write and +2 on a partial write; the CPU simply stalls longer)");
        section_end("[8]");

        // ------------------------------------------------------------------ summary
        idle(5);
        $display("");
        $display("========================================================================");
        $display("SUMMARY");
        $display("  error events from the controller: %0d corrected, %0d uncorrectable", ev_ce_cnt, ev_ue_cnt);
        $display("------------------------------------------------------------------------");
        if (errors == 0) $display("PASS: %0d checks, 0 errors", checks);
        else             $display("FAIL: %0d errors in %0d checks", errors, checks);
        $display("========================================================================");
        $finish;
    end

    initial begin
        #50ms;
        $display("TIMEOUT");
        $finish;
    end
endmodule
