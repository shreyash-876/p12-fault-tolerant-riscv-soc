`timescale 1ns / 1ps
// =============================================================================
// tb_mega: MEGA TESTBENCH for the whole P12 data path
//
//   AXI4-Lite master (this testbench)
//        |
//   axil_frontend --- CPU requests ---> mem_arbiter <--- scrub requests --- ecc_scrubber
//                                            |
//                                      mem_ctrl_ecc : encoder on write, decoder/corrector on read,
//                                            |         read-modify-write, scrub operation
//                                      39-bit BRAM : 32 data bits + 7 check bits per word
//
// What the testbench contains
//   * its OWN model of the Hsiao (39,32) code (columns of H, as in the Python golden model),
//     so the hardware encoder/decoder is checked against an independent description
//   * a reference memory: what the CPU believes it has stored, word by word
//   * a "radiation" injector: flips bits of the STORED words directly inside the RAM array
//   * a scoreboard that predicts, for every read, the data and the response (OKAY / SLVERR)
//   * monitors: AXI response rules, the controller's error events, the scrubber's requests
//
// The tests are random (seeded; the seed is printed, re-run with +seed=N to repeat a run),
// but every part prints what it is doing, with the real numbers, so a run reads like a story.
//
//   PART 1  follow one word through the system (write, encode, store, flip, decode, read, RMW, scrub)
//   PART 2  AXI reads and writes: data patterns, address corners, sub-word writes, handshake variants
//   PART 3  error detection and correction: single, double, beyond-guarantee errors, errors + writes
//   PART 4  the scrubber: repair, visiting order and wrap-around, why it matters, CPU wait
//   PART 5  long random traffic with random errors injected, scrubber running
//
// Run with simulation runtime = all. Result lines start with "PASS"/"FAIL".
// =============================================================================
module tb_mega;
    import mem_pkg::*;

    parameter int DEPTH        = 256;      // RAM words in this test
    parameter int N_RANDOM_OPS = 3000;     // length of the random traffic in part 5
    parameter int SEED_DEFAULT = 1;

    localparam logic [31:0] BASE = 32'h2000_0000;
    localparam int LAST = DEPTH - 1;

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

    mem_subsystem #(.DEPTH(DEPTH), .SCRUB_ENABLE(1), .SCRUB_INTERVAL(16), .SCRUB_PATIENCE(24)) dut (
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

    // =========================================================================
    // The testbench's own model of the Hsiao (39,32) code
    //   codeword bit j (0..31 = data d0..d31, 32..38 = check bits c0..c6) has a 7-bit "column" of H.
    //   syndrome = XOR of the columns of all bits that are 1.  A single flipped bit j gives column j.
    // =========================================================================
    function automatic logic [6:0] hcol(input int j);
        case (j)
             0: hcol = 7'b0010011;   // d0
             1: hcol = 7'b0100011;   // d1
             2: hcol = 7'b1000011;   // d2
             3: hcol = 7'b0001101;   // d3
             4: hcol = 7'b0010101;   // d4
             5: hcol = 7'b0100101;   // d5
             6: hcol = 7'b1000101;   // d6
             7: hcol = 7'b0011001;   // d7
             8: hcol = 7'b0101001;   // d8
             9: hcol = 7'b1001001;   // d9
            10: hcol = 7'b0110001;   // d10
            11: hcol = 7'b1010001;   // d11
            12: hcol = 7'b1100001;   // d12
            13: hcol = 7'b0001110;   // d13
            14: hcol = 7'b0010110;   // d14
            15: hcol = 7'b0100110;   // d15
            16: hcol = 7'b1000110;   // d16
            17: hcol = 7'b0011010;   // d17
            18: hcol = 7'b0101010;   // d18
            19: hcol = 7'b1001010;   // d19
            20: hcol = 7'b0110010;   // d20
            21: hcol = 7'b1010010;   // d21
            22: hcol = 7'b1100010;   // d22
            23: hcol = 7'b0011100;   // d23
            24: hcol = 7'b0101100;   // d24
            25: hcol = 7'b1001100;   // d25
            26: hcol = 7'b0110100;   // d26
            27: hcol = 7'b1010100;   // d27
            28: hcol = 7'b1100100;   // d28
            29: hcol = 7'b0111000;   // d29
            30: hcol = 7'b1011000;   // d30
            31: hcol = 7'b1101000;   // d31
            32: hcol = 7'b0000001;   // c0
            33: hcol = 7'b0000010;   // c1
            34: hcol = 7'b0000100;   // c2
            35: hcol = 7'b0001000;   // c3
            36: hcol = 7'b0010000;   // c4
            37: hcol = 7'b0100000;   // c5
            38: hcol = 7'b1000000;   // c6
            default: hcol = 7'b0000000;
        endcase
    endfunction

    function automatic logic [38:0] g_encode(input logic [31:0] data);
        logic [6:0] chk;
        chk = 7'd0;
        for (int j = 0; j < 32; j++)
            if (data[j]) chk = chk ^ hcol(j);
        g_encode = {chk, data};
    endfunction

    function automatic logic [6:0] g_syndrome(input logic [38:0] cw);
        logic [6:0] s;
        s = 7'd0;
        for (int j = 0; j < 39; j++)
            if (cw[j]) s = s ^ hcol(j);
        g_syndrome = s;
    endfunction

    // golden decode: returns {ue, ce, pos[5:0], data[31:0]}
    function automatic logic [39:0] g_decode(input logic [38:0] cw);
        logic [6:0]  s;
        logic [38:0] c;
        int          jm;
        bit          found;
        s = g_syndrome(cw);
        c = cw;
        jm = 0;
        found = 1'b0;
        if (s != 7'd0)
            for (int j = 0; j < 39; j++)
                if (!found && hcol(j) == s) begin found = 1'b1; jm = j; end
        if (s == 7'd0) begin
            g_decode = {1'b0, 1'b0, 6'd0, cw[31:0]};
        end else if (found) begin
            c[jm] = ~c[jm];
            g_decode = {1'b0, 1'b1, 6'(jm), c[31:0]};
        end else begin
            g_decode = {1'b1, 1'b0, 6'd0, cw[31:0]};
        end
    endfunction
    function automatic logic [31:0] gd_data(input logic [39:0] v); gd_data = v[31:0];  endfunction
    function automatic int          gd_pos (input logic [39:0] v); gd_pos  = int'(v[37:32]); endfunction
    function automatic bit          gd_ce  (input logic [39:0] v); gd_ce   = v[38]; endfunction
    function automatic bit          gd_ue  (input logic [39:0] v); gd_ue   = v[39]; endfunction

    function automatic int popc7(input logic [6:0] x);
        int n;
        n = 0;
        for (int i = 0; i < 7; i++) if (x[i]) n = n + 1;
        popc7 = n;
    endfunction

    // =========================================================================
    // Small helpers
    // =========================================================================
    function automatic string pick(input bit c, input string a, input string b);
        if (c) return a;
        return b;
    endfunction

    function automatic string bitname(input int j);
        if (j < 32) return $sformatf("d%0d", j);
        return $sformatf("c%0d", j - 32);
    endfunction

    function automatic string resp_name(input logic [1:0] r);
        if (r === 2'b00) return "OKAY  ";
        if (r === 2'b10) return "SLVERR";
        return "other ";
    endfunction

    function automatic logic [31:0] addr_of(input int w, input int off);
        addr_of = BASE + w * 4 + off;
    endfunction

    function automatic logic [31:0] merge32(input logic [31:0] old_w, input logic [31:0] new_w, input logic [3:0] s);
        logic [31:0] r;
        r = old_w;
        for (int b = 0; b < 4; b++)
            if (s[b]) r[8*b +: 8] = new_w[8*b +: 8];
        merge32 = r;
    endfunction

    function automatic logic [38:0] bitmask(input int b1, input int b2, input int b3);   // -1 = unused
        logic [38:0] m;
        m = 39'd0;
        if (b1 >= 0) m[b1] = 1'b1;
        if (b2 >= 0) m[b2] = 1'b1;
        if (b3 >= 0) m[b3] = 1'b1;
        bitmask = m;
    endfunction

    // random bit position that is not already in the list
    function automatic int rbit(input int not1, input int not2);
        int b;
        b = $urandom_range(0, 38);
        while (b == not1 || b == not2) b = $urandom_range(0, 38);
        rbit = b;
    endfunction

    // =========================================================================
    // Scoreboard state
    //   ref_data[w]  what the CPU believes word w holds
    //   wstate[w]    0 clean   1 one flipped bit (the scrubber may or may not have repaired it yet)
    //                2 two flipped bits (injected at once)   3 arbitrary pattern (oracle = golden decode)
    // =========================================================================
    logic [31:0] ref_data [0:DEPTH-1];
    int          wstate   [0:DEPTH-1];

    function automatic logic [38:0] peek(input int w);
        peek = dut.u_bram.mem[w];
    endfunction

    // check counters, per part and in total
    int checks = 0, errors = 0;
    int part_checks [0:9];
    int part_errors [0:9];
    int cur_part = 0;

    task chk(input bit cond, input string what);
        checks = checks + 1;
        part_checks[cur_part] = part_checks[cur_part] + 1;
        if (!cond) begin
            errors = errors + 1;
            part_errors[cur_part] = part_errors[cur_part] + 1;
            $display("    ** FAIL: %s", what);
        end
    endtask

    task begin_part(input int n, input string title);
        cur_part = n;
        $display("");
        $display("==============================================================================");
        $display(" PART %0d: %s", n, title);
        $display("==============================================================================");
    endtask

    task end_part;
        $display("  -> part %0d: %0d checks, %0d failures  [%s]", cur_part, part_checks[cur_part], part_errors[cur_part],
                 pick(part_errors[cur_part] == 0, "OK", "FAILED"));
    endtask

    task idle(input int n);
        repeat (n) @(posedge clk);
    endtask

    // =========================================================================
    // Monitors
    // =========================================================================
    // --- error events reported by the ECC controller (one pulse per access that found an error) ---
    int ev_ce_cpu = 0, ev_ue_cpu = 0, ev_ce_scr = 0, ev_ue_scr = 0;
    logic [6:0]  last_ev_syn = 0;
    int          last_ev_pos = 0;
    logic [31:0] last_ev_addr = 0;
    always @(posedge clk) begin
        if (rst_n && dut.ev_valid) begin
            if (dut.ev_scrub) begin
                if (dut.ev_ce) ev_ce_scr = ev_ce_scr + 1;
                if (dut.ev_ue) ev_ue_scr = ev_ue_scr + 1;
            end else begin
                if (dut.ev_ce) ev_ce_cpu = ev_ce_cpu + 1;
                if (dut.ev_ue) ev_ue_cpu = ev_ue_cpu + 1;
            end
            last_ev_syn  = dut.ev_syn;
            last_ev_pos  = int'(dut.ev_pos);
            last_ev_addr = dut.ev_addr;
        end
    end

    // --- AXI response rules: VALID must stay high, with stable data, until READY ---
    logic        bvalid_d = 0, rvalid_d = 0, bready_d = 0, rready_d = 0;
    logic [31:0] rdata_d = 0;
    int          prot_viol = 0;
    always @(posedge clk) begin
        bvalid_d <= bvalid; rvalid_d <= rvalid; rdata_d <= rdata; bready_d <= bready; rready_d <= rready;
        if (rst_n) begin
            if (bvalid_d && !bready_d && !bvalid) prot_viol = prot_viol + 1;
            if (rvalid_d && !rready_d && !rvalid) prot_viol = prot_viol + 1;
            if (rvalid_d && !rready_d && rvalid && rdata !== rdata_d) prot_viol = prot_viol + 1;
        end
    end

    // --- addresses of the scrubber's requests (used in part 4) ---
    logic [31:0] scrub_log [0:4*DEPTH-1];
    int          scrub_log_n = 0;
    bit          scrub_log_on = 0;
    always @(posedge clk) begin
        if (rst_n && scrub_log_on && dut.sc_req_valid && dut.sc_req_ready) begin
            if (scrub_log_n < 4 * DEPTH) scrub_log[scrub_log_n] = dut.sc_req_addr;
            scrub_log_n = scrub_log_n + 1;
        end
    end

    // =========================================================================
    // AXI4-Lite master (random gaps and back-pressure when gap_max > 0)
    // =========================================================================
    int gap_max = 0;
    int lat_read = 0;

    task rgap;
        if (gap_max > 0) idle($urandom_range(0, gap_max));
    endtask

    // order: 0 AW and W together, 1 AW first, 2 W first, 3 random gaps on both
    task axi_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s, input int order, output logic [1:0] resp);
        case (order)
            0: fork
                   begin awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0; end
                   begin wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0; end
               join
            1: begin
                   awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0;
                   idle(2);
                   wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0;
               end
            2: begin
                   wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0;
                   idle(2);
                   awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0;
               end
            default: fork
                   begin rgap(); awaddr <= a; awvalid <= 1; do @(posedge clk); while (!awready); awvalid <= 0; end
                   begin rgap(); wdata <= d; wstrb <= s; wvalid <= 1; do @(posedge clk); while (!wready); wvalid <= 0; end
               join
        endcase
        rgap();
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
        rgap();
        rready <= 1;
        do @(posedge clk); while (!rvalid);
        d = rdata;
        resp = rresp;
        rready <= 0;
        lat_read = int'(cyc - t0);
    endtask

    // =========================================================================
    // Word-level operations that keep the scoreboard up to date
    // =========================================================================
    // full-word write (all four byte strobes)
    task wr_full(input int w, input logic [31:0] d, input int order);
        logic [1:0] resp;
        axi_write(addr_of(w, 0), d, 4'b1111, order, resp);
        ref_data[w] = d;
        wstate[w]   = 0;
        chk(resp === 2'b00, "a full-word write must answer OKAY");
    endtask

    // partial write = read-modify-write; `off` is added to the byte address (a CPU does that for sb/sh)
    task wr_part(input int w, input logic [31:0] d, input logic [3:0] s, input int off, input int order, output logic [1:0] resp);
        logic [39:0] gd;
        logic [31:0] base_data;
        bit abort;
        abort = 1'b0;
        base_data = ref_data[w];
        if (wstate[w] >= 2 && s != 4'b1111 && s != 4'b0000) begin
            gd = g_decode(peek(w));
            if (gd_ue(gd)) abort = 1'b1;               // the word cannot be corrected: the write is refused
            else           base_data = gd_data(gd);    // a wrong "correction" is what the read-modify-write sees
        end
        axi_write(addr_of(w, off), d, s, order, resp);
        if (s == 4'b0000) begin
            chk(resp === 2'b00, "a write with no byte strobe must answer OKAY and change nothing");
        end else if (abort) begin
            chk(resp === 2'b10, "a read-modify-write on an uncorrectable word must answer SLVERR");
        end else begin
            chk(resp === 2'b00, "a partial write must answer OKAY");
            ref_data[w] = merge32(base_data, d, s);
            wstate[w]   = 0;
        end
    endtask

    // read word w and compare with the scoreboard's prediction
    task rd_expect(input int w, input int off, output logic [31:0] got, output logic [1:0] resp,
                   output logic [31:0] exp_data, output logic [1:0] exp_resp);
        logic [39:0] gd;
        bit ok;
        if (wstate[w] >= 2) begin
            gd = g_decode(peek(w));                    // what the stored word decodes to
            exp_data = gd_data(gd);
            if (gd_ue(gd)) exp_resp = 2'b10;
            else           exp_resp = 2'b00;
        end else begin
            exp_data = ref_data[w];
            exp_resp = 2'b00;
        end
        axi_read(addr_of(w, off), got, resp);
        ok = (got === exp_data) && (resp === exp_resp);
        if (!ok) $display("    read of word %0d: got %h resp %s, expected %h resp %s", w, got, resp_name(resp), exp_data, resp_name(exp_resp));
        chk(ok, "a read must return the predicted data and response");
    endtask

    task rd_check(input int w);
        logic [31:0] g, e;
        logic [1:0]  r, er;
        rd_expect(w, 0, g, r, e, er);
    endtask

    // ---------------- the "radiation": flip stored bits directly in the RAM array ----------------
    task inject1(input int w, input int b);
        dut.u_bram.mem[w] = dut.u_bram.mem[w] ^ bitmask(b, -1, -1);
        wstate[w] = 1;
    endtask

    task inject2(input int w, input int b1, input int b2);          // both bits at the same instant
        dut.u_bram.mem[w] = dut.u_bram.mem[w] ^ bitmask(b1, b2, -1);
        wstate[w] = 2;
    endtask

    task inject_pattern(input int w, input logic [38:0] m);         // any pattern: oracle = golden decode
        dut.u_bram.mem[w] = dut.u_bram.mem[w] ^ m;
        wstate[w] = 3;
    endtask

    // ---------------- scrubber control ----------------
    task pause_scrubber;
        force dut.scrub_enable = 1'b0;
        idle(30);                                   // let an operation that already started finish
    endtask

    task resume_scrubber;
        release dut.scrub_enable;
    endtask

    function automatic bit is_valid(input int w);
        is_valid = (g_syndrome(peek(w)) == 7'd0);
    endfunction

    task wait_scanned(input int n, input int timeout_cycles);
        int start, t;
        start = dut.scrub_scanned;
        t = 0;
        while ((dut.scrub_scanned - start) < n && t < timeout_cycles) begin
            @(posedge clk);
            t = t + 1;
        end
        chk((dut.scrub_scanned - start) >= n, "the scrubber must complete the expected number of scrub operations in time");
    endtask

    // wait until word w is a valid codeword again; returns the cycles waited
    task wait_valid(input int w, input int timeout_cycles, output int waited);
        waited = 0;
        while (!is_valid(w) && waited < timeout_cycles) begin
            @(posedge clk);
            waited = waited + 1;
        end
        chk(is_valid(w), "the scrubber must repair the word in time");
    endtask

    // =========================================================================
    // PART 1: stories (scrubber paused, except story 1E)
    // =========================================================================
    task story_1a;
        int w;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] st, gold;
        w = $urandom_range(1, LAST - 1);
        d = $urandom;
        $display("  Story 1A: write a random word and read it back");
        $display("   [AXI WRITE ] byte address %h (word %0d), data %h, all four byte strobes on", addr_of(w, 0), w, d);
        wr_full(w, d, 0);
        st   = peek(w);
        gold = g_encode(d);
        $display("   [ENCODER   ] check bits added on the way in: %h   (the testbench's own model gives %h)", st[38:32], gold[38:32]);
        $display("   [BRAM      ] word %0d now holds the 39-bit codeword %h  =  check bits %h | data %h", w, st, st[38:32], st[31:0]);
        chk(st === gold, "the stored codeword must equal the model's codeword");
        rd_expect(w, 0, got, resp, e, er);
        $display("   [AXI READ  ] returned %h, response %s   -> identical to what was written", got, resp_name(resp));
    endtask

    task story_1b;
        int w, b;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        w = $urandom_range(1, LAST - 1);
        d = $urandom;
        b = $urandom_range(0, 38);
        wr_full(w, d, 0);
        $display("");
        $display("  Story 1B: one stored bit is flipped by radiation, then the word is read");
        $display("   [BRAM      ] word %0d holds %h (data %h)", w, peek(w), d);
        inject1(w, b);
        cor = peek(w);
        syn = g_syndrome(cor);
        $display("   [RADIATION ] a particle flips bit %s:  %h -> %h", bitname(b), peek(w) ^ bitmask(b, -1, -1), cor);
        rd_expect(w, 0, got, resp, e, er);
        $display("   [DECODER   ] recomputed check bits differ from the stored ones: syndrome = %b (0x%h), odd weight %0d", syn, syn, popc7(syn));
        $display("                the syndrome equals the H-column of bit %s -> single error at %s", bitname(b), bitname(b));
        $display("                (the hardware reported syndrome %b and bit %s)", last_ev_syn, bitname(last_ev_pos));
        $display("   [AXI READ  ] returned %h, response %s   -> original data, error corrected on the fly", got, resp_name(resp));
        $display("   [BRAM      ] the stored word is still %h: a read does not repair it, the scrubber does", peek(w));
        chk(last_ev_syn === syn, "the hardware syndrome must equal the model's syndrome");
        chk(last_ev_pos == b, "the hardware must point at the flipped bit");
        chk(got === d, "the corrected read must return the original data");
        chk(peek(w) === cor, "a read must not modify the stored word");
        wr_full(w, d, 0);                          // clean up: the next story starts with a healthy memory
    endtask

    task story_1c;
        int w, b1, b2;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        int ue0;
        w  = $urandom_range(1, LAST - 1);
        d  = $urandom;
        b1 = $urandom_range(0, 38);
        b2 = rbit(b1, -1);
        wr_full(w, d, 0);
        $display("");
        $display("  Story 1C: TWO stored bits are flipped in the same word, then the word is read");
        inject2(w, b1, b2);
        cor = peek(w);
        syn = g_syndrome(cor);
        ue0 = ev_ue_cpu;
        $display("   [RADIATION ] flips %s and %s of word %0d:  stored word is now %h (was %h)", bitname(b1), bitname(b2), w, cor, g_encode(d));
        rd_expect(w, 0, got, resp, e, er);
        $display("   [DECODER   ] syndrome = %b, weight %0d (even) and equal to no column of H -> two errors,", syn, popc7(syn));
        $display("                which the code can detect but not correct");
        $display("   [AXI READ  ] returned %h (the data bits as stored, NOT modified), response %s", got, resp_name(resp));
        $display("                the bus master is told: SLVERR = uncorrectable error");
        chk(resp === 2'b10, "a double error must be answered with SLVERR");
        chk(gd_ue(g_decode(cor)), "the model must also classify it as uncorrectable");
        chk(ev_ue_cpu == ue0 + 1, "the controller must report one uncorrectable event");
        chk(peek(w) === cor, "a read must not modify the stored word");
        wr_full(w, d, 0);                          // clean up: the next story starts with a healthy memory
    endtask

    task story_1d;
        int w, k;
        logic [31:0] oldd, nd, expd, got, e;
        logic [1:0]  resp, er, wresp;
        logic [3:0]  s;
        logic [7:0]  nb;
        logic [38:0] st;
        w = $urandom_range(1, LAST - 1);
        k = $urandom_range(0, 3);
        oldd = $urandom;
        nb   = $urandom;
        wr_full(w, oldd, 0);
        s  = 4'b0001 << k;
        nd = {4{nb}};                              // a CPU store-byte repeats the byte on all four lanes
        $display("");
        $display("  Story 1D: a byte write (sb), which needs a read-modify-write");
        $display("   [BRAM      ] word %0d holds data %h", w, oldd);
        $display("   [AXI WRITE ] byte address %h (byte lane %0d), write data %h, byte strobes %b", addr_of(w, k), k, nd, s);
        $display("   [CONTROLLER] cannot write 7 check bits for one byte alone, so it does:");
        $display("                read the old word -> decode (corrects if needed) -> replace byte %0d -> encode -> write", k);
        wr_part(w, nd, s, k, 0, wresp);
        st = peek(w);
        expd = merge32(oldd, nd, s);
        $display("   [BRAM      ] word %0d now holds data %h, check bits %h   (expected data %h)", w, st[31:0], st[38:32], expd);
        rd_expect(w, 0, got, resp, e, er);
        $display("   [AXI READ  ] returned %h, response %s", got, resp_name(resp));
        chk(st === g_encode(expd), "the stored word must be the model's codeword of the merged data");
    endtask

    task story_1e;
        int w, b, waited, rep0;
        logic [31:0] d;
        logic [38:0] before_w, after_w;
        w = $urandom_range(1, LAST - 1);
        b = $urandom_range(0, 38);
        d = $urandom;
        wr_full(w, d, 0);
        $display("");
        $display("  Story 1E: the scrubber repairs a flipped bit while the CPU never touches the word");
        inject1(w, b);
        before_w = peek(w);
        $display("   [RADIATION ] flips bit %s of word %0d: stored word %h (valid codeword was %h)", bitname(b), w, before_w, g_encode(d));
        rep0 = dut.scrub_repaired;
        $display("   [SCRUBBER  ] switched on; it checks one word every 16 cycles and wraps around at word %0d", LAST);
        resume_scrubber;
        wait_valid(w, 20000, waited);
        after_w = peek(w);
        pause_scrubber;
        $display("   [SCRUBBER  ] after %0d cycles the word is a valid codeword again: %h", waited, after_w);
        $display("                the scrubber found a single error, corrected it, and wrote the word back;");
        $display("                words repaired by it so far: %0d", dut.scrub_repaired - rep0);
        chk(after_w === g_encode(d), "the repaired word must equal the original codeword");
        chk(dut.scrub_repaired - rep0 == 1, "exactly one word must have been repaired");
        rd_check(w);
    endtask

    // =========================================================================
    // Predictions for a read (used when a write is in flight at the same time)
    // =========================================================================
    function automatic logic [31:0] exp_data(input int w);
        logic [39:0] gd;
        if (wstate[w] >= 2) begin
            gd = g_decode(peek(w));
            exp_data = gd_data(gd);
        end else begin
            exp_data = ref_data[w];
        end
    endfunction

    function automatic logic [1:0] exp_resp(input int w);
        logic [39:0] gd;
        exp_resp = 2'b00;
        if (wstate[w] >= 2) begin
            gd = g_decode(peek(w));
            if (gd_ue(gd)) exp_resp = 2'b10;
        end
    endfunction

    // =========================================================================
    // PART 2: AXI reads and writes
    // =========================================================================
    function automatic logic [31:0] pat(input int k);
        case (k)
            0: pat = 32'h00000000;
            1: pat = 32'hFFFFFFFF;
            2: pat = 32'h55555555;
            3: pat = 32'hAAAAAAAA;
            4: pat = 32'h80000001;
            5: pat = 32'h00000001;
            6: pat = 32'h80000000;
            7: pat = 32'h0000FFFF;
            default: pat = $urandom;
        endcase
    endfunction

    task part2_patterns;
        int w;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] st;
        $display("  2A. Data patterns (corner values first, then random): the encoder's output must match the model");
        $display("      data       check  stored codeword  read back  result");
        for (int k = 0; k < 11; k++) begin
            w = $urandom_range(2, LAST - 2);
            d = pat(k);
            wr_full(w, d, k % 3);
            st = peek(w);
            rd_expect(w, 0, got, resp, e, er);
            chk(st === g_encode(d), "stored codeword must equal the model's codeword");
            $display("      %h   %h     %h     %h   %s", d, st[38:32], st, got,
                     pick((st === g_encode(d)) && (got === d) && (resp === 2'b00), "ok", "MISMATCH"));
        end
    endtask

    function automatic int corner_word(input int i);
        case (i)
            0: corner_word = 0;
            1: corner_word = 1;
            2: corner_word = LAST / 2;
            3: corner_word = LAST - 1;
            default: corner_word = LAST;
        endcase
    endfunction

    task part2_addresses;
        int w, off;
        logic [31:0] got, e;
        logic [1:0]  resp, er;
        $display("");
        $display("  2B. Address corners: first word, last word, and their neighbours must not disturb each other");
        for (int i = 0; i < 5; i++) begin
            w = corner_word(i);
            wr_full(w, $urandom, 0);
        end
        $display("      word  byte address   data written  read back (at byte offset)  result");
        for (int i = 0; i < 5; i++) begin
            w   = corner_word(i);
            off = $urandom_range(0, 3);           // a load may use any byte of the word
            rd_expect(w, off, got, resp, e, er);
            $display("      %3d   %h     %h     %h (+%0d)              %s", w, addr_of(w, 0), ref_data[w], got, off,
                     pick((got === ref_data[w]) && (resp === 2'b00), "ok", "MISMATCH"));
        end
        $display("      reading at byte offsets 1..3 of a word returns the whole word; the top and bottom words are distinct");
    endtask

    function automatic logic [3:0] sw_strobe(input int k);
        case (k)
            0: sw_strobe = 4'b0001;
            1: sw_strobe = 4'b0010;
            2: sw_strobe = 4'b0100;
            3: sw_strobe = 4'b1000;
            4: sw_strobe = 4'b0011;
            5: sw_strobe = 4'b1100;
            6: sw_strobe = 4'b0111;
            7: sw_strobe = 4'b1110;
            8: sw_strobe = 4'b0101;
            9: sw_strobe = 4'b1010;
            10: sw_strobe = 4'b0000;
            default: sw_strobe = 4'b1111;
        endcase
    endfunction

    function automatic int sw_off(input int k);
        case (k)
            1: sw_off = 1;
            2: sw_off = 2;
            3: sw_off = 3;
            5: sw_off = 2;
            7: sw_off = 1;
            default: sw_off = 0;
        endcase
    endfunction

    task part2_subword;
        int w, off;
        logic [31:0] oldd, nd, expd, got, e;
        logic [1:0]  resp, er, wresp;
        logic [3:0]  s;
        logic [38:0] st;
        $display("");
        $display("  2C. Sub-word writes (sb, sh and odd strobe patterns): each needs a read-modify-write");
        $display("      strobe  +off  old data    write data  expected    stored word valid & = model  result");
        for (int k = 0; k < 12; k++) begin
            w    = $urandom_range(2, LAST - 2);
            oldd = $urandom;
            s    = sw_strobe(k);
            off  = sw_off(k);
            if (k < 4)       nd = {4{8'($urandom)}};          // sb: the byte is repeated on all lanes
            else if (k < 6)  nd = {2{16'($urandom)}};         // sh: the half-word is repeated
            else             nd = $urandom;
            wr_full(w, oldd, 0);
            wr_part(w, nd, s, off, k % 3, wresp);
            expd = merge32(oldd, nd, s);
            st   = peek(w);
            rd_expect(w, 0, got, resp, e, er);
            chk(st === g_encode(expd), "stored word must be the model's codeword of the merged data");
            $display("      %b    +%0d   %h    %h    %h    %s                       %s", s, off, oldd, nd, expd,
                     pick(st === g_encode(expd), "yes", "NO "), pick(got === expd, "ok", "MISMATCH"));
        end
        // four single-byte writes assemble one word
        begin : assemble
            logic [7:0] b0, b1, b2, b3;
            logic [31:0] tgt;
            int order [0:3];
            int t;
            w = $urandom_range(2, LAST - 2);
            b0 = $urandom; b1 = $urandom; b2 = $urandom; b3 = $urandom;
            wr_full(w, $urandom, 0);
            order[0] = 2; order[1] = 0; order[2] = 3; order[3] = 1;       // fixed shuffled byte order
            for (int i = 0; i < 4; i++) begin
                t = order[i];
                case (t)
                    0: wr_part(w, {4{b0}}, 4'b0001, 0, 0, wresp);
                    1: wr_part(w, {4{b1}}, 4'b0010, 1, 0, wresp);
                    2: wr_part(w, {4{b2}}, 4'b0100, 2, 0, wresp);
                    default: wr_part(w, {4{b3}}, 4'b1000, 3, 0, wresp);
                endcase
            end
            tgt = {b3, b2, b1, b0};
            rd_expect(w, 0, got, resp, e, er);
            $display("      four byte writes (lanes 2,0,3,1) into word %0d: bytes %h %h %h %h -> read %h   %s",
                     w, b3, b2, b1, b0, got, pick(got === tgt, "ok", "MISMATCH"));
            chk(got === tgt, "four byte writes must assemble the expected word");
        end
    endtask

    task part2_handshakes;
        int w, wa, wb, bad;
        logic [31:0] d, got, e, g2;
        logic [1:0]  resp, er, r2, wresp;
        int lat_max;
        $display("");
        $display("  2D. AXI handshake variants: the controller must accept the write address and data in any order");
        for (int order = 0; order < 3; order++) begin
            w = $urandom_range(2, LAST - 2);
            d = $urandom;
            wr_full(w, d, order);
            rd_expect(w, 0, got, resp, e, er);
            $display("      %s -> wrote %h, read %h   %s",
                     pick(order == 0, "AW and W together", pick(order == 1, "AW first, W 2 cycles later", "W first, AW 2 cycles later")),
                     d, got, pick(got === d, "ok", "MISMATCH"));
        end
        // random gaps and slow BREADY / RREADY
        gap_max = 8;
        bad = errors;
        lat_max = 0;
        for (int i = 0; i < 40; i++) begin
            w = $urandom_range(2, LAST - 2);
            if ($urandom_range(0, 1) == 0) wr_full(w, $urandom, 3);
            else                           wr_part(w, $urandom, 4'($urandom_range(1, 14)), 0, 3, wresp);
            rd_check(w);
            if (lat_read > lat_max) lat_max = lat_read;
        end
        gap_max = 0;
        $display("      40 write+read pairs with random idle gaps (0..8 cycles) before every VALID/READY: %0d failures, slowest read %0d cycles",
                 errors - bad, lat_max);
        // a read and a write presented in the same clock cycle, different words
        bad = errors;
        for (int i = 0; i < 10; i++) begin
            wa = $urandom_range(2, LAST / 2);
            wb = $urandom_range(LAST / 2 + 1, LAST - 2);
            d  = $urandom;
            fork
                axi_write(addr_of(wa, 0), d, 4'b1111, 0, wresp);
                axi_read(addr_of(wb, 0), g2, r2);
            join
            chk(wresp === 2'b00, "the write must complete");
            chk((g2 === ref_data[wb]) && (r2 === 2'b00), "the simultaneous read must return its word");
            ref_data[wa] = d;
            wstate[wa]   = 0;
            rd_check(wa);
        end
        $display("      10 times a read and a write started in the SAME clock cycle (different words): %0d failures", errors - bad);
    endtask

    task part2_dependencies;
        int w, bad;
        logic [31:0] d1, d2, got, e;
        logic [1:0]  resp, er;
        bad = errors;
        $display("");
        $display("  2E. Back-to-back accesses to the same word");
        for (int i = 0; i < 20; i++) begin
            w  = $urandom_range(2, LAST - 2);
            d1 = $urandom;
            d2 = $urandom;
            wr_full(w, d1, 0);
            wr_full(w, d2, 0);              // the second write must win
            rd_expect(w, 0, got, resp, e, er);
            chk(got === d2, "the last write must win");
            wr_full(w, d1, 0);              // read immediately after a write
            rd_expect(w, 0, got, resp, e, er);
            chk(got === d1, "a read right after a write must see the new data");
        end
        $display("      20 x (write, write, read) and (write, read): last write wins, read-after-write sees new data: %0d failures", errors - bad);
    endtask

    // =========================================================================
    // PART 3: error detection and correction (scrubber paused)
    // =========================================================================
    function automatic int corner_bit(input int i);
        case (i)
            0: corner_bit = 0;      // d0   first data bit
            1: corner_bit = 31;     // d31  last data bit
            2: corner_bit = 32;     // c0   first check bit
            3: corner_bit = 38;     // c6   last check bit
            default: corner_bit = $urandom_range(0, 38);
        endcase
    endfunction

    task part3_single;
        int w, b, ue0;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        $display("  3A. Single-bit errors: first/last data bit, first/last check bit, then random positions");
        $display("      flipped  stored (corrupted)  model syn  hw syn  hw bit  read data  resp    result");
        for (int i = 0; i < 12; i++) begin
            w = $urandom_range(2, LAST - 2);
            d = $urandom;
            b = corner_bit(i);
            wr_full(w, d, 0);
            inject1(w, b);
            cor = peek(w);
            syn = g_syndrome(cor);
            rd_expect(w, 0, got, resp, e, er);
            chk(last_ev_syn === syn, "hardware syndrome must equal the model's syndrome");
            chk(last_ev_pos == b, "hardware must point at the flipped bit");
            chk(peek(w) === cor, "the read must not change the stored word");
            chk(syn === hcol(b), "(model) a single flip must give exactly the column of that bit");
            $display("      %-4s     %h        %b    %b   %-4s    %h   %s  %s", bitname(b), cor, syn, last_ev_syn, bitname(last_ev_pos),
                     got, resp_name(resp), pick((got === d) && (resp === 2'b00) && (last_ev_pos == b), "ok", "MISMATCH"));
        end
    endtask

    task part3_double;
        int w, b1, b2, ue0, kind;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        $display("");
        $display("  3B. Double-bit errors: always detected (SLVERR), data returned as stored, never 'corrected'");
        $display("      kind          flipped    syndrome (weight)  returned data  resp    stored unchanged  result");
        for (int i = 0; i < 9; i++) begin
            w = $urandom_range(2, LAST - 2);
            d = $urandom;
            kind = i % 6;
            case (kind)
                0: begin b1 = $urandom_range(0, 31); b2 = $urandom_range(0, 31); while (b2 == b1) b2 = $urandom_range(0, 31); end
                1: begin b1 = $urandom_range(0, 31); b2 = $urandom_range(32, 38); end
                2: begin b1 = $urandom_range(32, 38); b2 = $urandom_range(32, 38); while (b2 == b1) b2 = $urandom_range(32, 38); end
                3: begin b1 = $urandom_range(0, 30); b2 = b1 + 1; end          // neighbouring data bits
                4: begin b1 = 31; b2 = 32; end                                  // across the data/check boundary
                default: begin b1 = rbit(-1, -1); b2 = rbit(b1, -1); end
            endcase
            wr_full(w, d, 0);
            inject2(w, b1, b2);
            cor = peek(w);
            syn = g_syndrome(cor);
            ue0 = ev_ue_cpu;
            rd_expect(w, 0, got, resp, e, er);
            chk(resp === 2'b10, "a double error must be answered with SLVERR");
            chk(gd_ue(g_decode(cor)), "the model must classify it as uncorrectable");
            chk(ev_ue_cpu == ue0 + 1, "the controller must report exactly one uncorrectable event");
            chk(got === cor[31:0], "the data must come back exactly as stored (not 'corrected')");
            chk(peek(w) === cor, "the read must not change the stored word");
            $display("      %-12s  %-3s %-3s    %b (%0d)         %h       %s  %s               %s",
                     pick(kind == 0, "data+data", pick(kind == 1, "data+check", pick(kind == 2, "check+check", pick(kind == 3, "adjacent", pick(kind == 4, "d31 + c0", "random"))))),
                     bitname(b1), bitname(b2), syn, popc7(syn), got, resp_name(resp),
                     pick(peek(w) === cor, "yes", "NO "), pick((resp === 2'b10) && (got === cor[31:0]), "ok", "MISMATCH"));
        end
    endtask

    task part3_triple;
        int w, b1, b2, b3;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [39:0] gd;
        int mis;
        $display("");
        $display("  3C. Three flipped bits: beyond what SEC-DED guarantees. The hardware must still do exactly what the");
        $display("      model predicts: either flag it (SLVERR) or - unavoidably - 'correct' a wrong bit (miscorrection)");
        $display("      flipped         model says                       hardware returned  resp    result");
        mis = 0;
        for (int i = 0; i < 8; i++) begin
            w = $urandom_range(2, LAST - 2);
            d = $urandom;
            b1 = rbit(-1, -1); b2 = rbit(b1, -1); b3 = rbit(b1, b2);
            wr_full(w, d, 0);
            inject_pattern(w, bitmask(b1, b2, b3));
            cor = peek(w);
            gd  = g_decode(cor);
            rd_expect(w, 0, got, resp, e, er);
            if (gd_ce(gd)) mis = mis + 1;
            $display("      %-4s %-4s %-4s  %-32s %h   %s  %s", bitname(b1), bitname(b2), bitname(b3),
                     pick(gd_ue(gd), "uncorrectable (flagged)", $sformatf("looks like a single error at %s", bitname(gd_pos(gd)))),
                     got, resp_name(resp), pick((got === gd_data(gd)) && (resp === er), "ok (= model)", "MISMATCH"));
            wr_full(w, d, 0);                        // heal
        end
        $display("      %0d of 8 were silently miscorrected: that is the limit of SEC-DED, the model predicted every one", mis);
    endtask

    task part3_errors_and_writes;
        int w, b, b1, b2, k;
        logic [31:0] d, nd, expd, got, e;
        logic [1:0]  resp, er, wresp;
        logic [38:0] cor;
        logic [3:0]  s;
        $display("");
        $display("  3D. Errors meeting writes");
        // (i) single error, then a byte write
        w = $urandom_range(2, LAST - 2); d = $urandom; b = $urandom_range(0, 38); k = $urandom_range(0, 3);
        wr_full(w, d, 0);
        inject1(w, b);
        s = 4'b0001 << k;
        nd = {4{8'($urandom)}};
        wr_part(w, nd, s, k, 0, wresp);
        expd = merge32(d, nd, s);
        chk(peek(w) === g_encode(expd), "RMW on a single-error word must store the model's codeword of the corrected+merged data");
        rd_expect(w, 0, got, resp, e, er);
        $display("      (i)   bit %s of word %0d flipped, then byte %0d written: the read-modify-write corrects while it reads,", bitname(b), w, k);
        $display("            merges the new byte and re-encodes -> stored word %h is valid again, read %h   %s",
                 peek(w), got, pick(got === expd, "ok", "MISMATCH"));
        // (ii) double error, then a byte write
        w = $urandom_range(2, LAST - 2); d = $urandom; b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); k = $urandom_range(0, 3);
        wr_full(w, d, 0);
        inject2(w, b1, b2);
        cor = peek(w);
        s = 4'b0001 << k;
        wr_part(w, {4{8'($urandom)}}, s, k, 0, wresp);
        chk(peek(w) === cor, "a refused read-modify-write must leave the stored word untouched");
        $display("      (ii)  %s and %s of word %0d flipped, then a byte write: refused with %s, stored word unchanged (%h):",
                 bitname(b1), bitname(b2), w, resp_name(wresp), peek(w));
        $display("            writing new check bits over data that cannot be trusted would hide the error");
        // (iii) a full-word write heals it
        nd = $urandom;
        wr_full(w, nd, 0);
        rd_expect(w, 0, got, resp, e, er);
        chk(is_valid(w), "a full-word write must leave a valid codeword");
        $display("      (iii) a full-word write to the same word replaces everything: stored %h valid, read %h %s",
                 peek(w), got, resp_name(resp));
    endtask

    task part3_soup;
        int w, nflips, b1, b2, b3, r, healed;
        int n_case [0:3];
        int n_ok [0:3];
        int n_ce [0:3];
        int n_ue [0:3];
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        logic [38:0] m;
        logic [39:0] gd;
        for (int i = 0; i < 4; i++) begin n_case[i] = 0; n_ok[i] = 0; n_ce[i] = 0; n_ue[i] = 0; end
        $display("");
        $display("  3E. 300 random cases: random word, random data, 0..3 random flipped bits; oracle = the model");
        for (int i = 0; i < 300; i++) begin
            w = $urandom_range(0, LAST);
            d = $urandom;
            r = $urandom_range(0, 99);
            if (r < 10) nflips = 0; else if (r < 50) nflips = 1; else if (r < 80) nflips = 2; else nflips = 3;
            b1 = rbit(-1, -1); b2 = rbit(b1, -1); b3 = rbit(b1, b2);
            wr_full(w, d, $urandom_range(0, 2));
            if (nflips == 1) m = bitmask(b1, -1, -1);
            else if (nflips == 2) m = bitmask(b1, b2, -1);
            else if (nflips == 3) m = bitmask(b1, b2, b3);
            else m = 39'd0;
            if (nflips > 0) inject_pattern(w, m);
            gd = g_decode(peek(w));
            rd_expect(w, $urandom_range(0, 3), got, resp, e, er);
            n_case[nflips] = n_case[nflips] + 1;
            if ((got === gd_data(gd)) && (resp === er)) n_ok[nflips] = n_ok[nflips] + 1;
            if (gd_ce(gd)) n_ce[nflips] = n_ce[nflips] + 1;
            if (gd_ue(gd)) n_ue[nflips] = n_ue[nflips] + 1;
            if (nflips == 1) chk(got === d, "a single error must always be corrected");
            if (nflips == 2) chk(resp === 2'b10, "a double error must always be flagged");
        end
        $display("      flipped bits   cases   model: corrected  flagged   hardware agreed with the model");
        for (int i = 0; i < 4; i++)
            $display("           %0d          %3d            %3d       %3d        %3d of %3d", i, n_case[i], n_ce[i], n_ue[i], n_ok[i], n_case[i]);
        $display("      (for 3 flips 'corrected' means a WRONG correction: the miscorrections of the 3C discussion)");
        healed = 0;
        for (int w2 = 0; w2 < DEPTH; w2++)
            if (wstate[w2] != 0) begin wr_full(w2, $urandom, 0); healed = healed + 1; end
        $display("      all %0d damaged words rewritten afterwards, the memory is clean again", healed);
    endtask

    // =========================================================================
    // PART 4: the scrubber
    // =========================================================================
    task part4_repair;
        int ws [0:9];
        int bs [0:9];
        logic [38:0] before_w [0:9];
        int w, b, r0, u0, ce0, scan0;
        $display("  4A. Ten single-bit errors in ten random words (including the first and last word); the CPU reads nothing");
        pause_scrubber;
        for (int i = 0; i < 10; i++) begin
            if (i == 0) w = 0;
            else if (i == 1) w = LAST;
            else begin
                w = $urandom_range(1, LAST - 1);
                while (wstate[w] != 0) w = $urandom_range(1, LAST - 1);
            end
            b = corner_bit(i);
            ws[i] = w; bs[i] = b;
            inject1(w, b);
            before_w[i] = peek(w);
        end
        r0 = dut.scrub_repaired; u0 = dut.scrub_ue; ce0 = ev_ce_cpu; scan0 = dut.scrub_scanned;
        $display("      scrubber switched on: one scrub operation every 16 cycles, %0d words, so a sweep takes about %0d cycles",
                 DEPTH, DEPTH * 21);
        resume_scrubber;
        wait_scanned(DEPTH + 4, 60000);
        pause_scrubber;
        $display("      after %0d scrub operations (one full sweep plus a few):", dut.scrub_scanned - scan0);
        $display("        word  flipped  before (corrupted)  after the sweep      valid codeword?");
        for (int i = 0; i < 10; i++)
            $display("        %3d   %-4s     %h          %h        %s", ws[i], bitname(bs[i]), before_w[i], peek(ws[i]),
                     pick(peek(ws[i]) === g_encode(ref_data[ws[i]]), "yes, original", "NO"));
        for (int w2 = 0; w2 < DEPTH; w2++) chk(is_valid(w2), "after a full sweep every stored word must be a valid codeword");
        chk(dut.scrub_repaired - r0 == 10, "the scrubber must have repaired exactly the ten damaged words");
        chk(dut.scrub_ue == u0, "no uncorrectable word may be reported");
        chk(ev_ce_cpu == ce0, "the CPU must not have seen any error: it never accessed those words");
        for (int i = 0; i < 10; i++) begin
            chk(peek(ws[i]) === g_encode(ref_data[ws[i]]), "a repaired word must be the original codeword");
            wstate[ws[i]] = 0;
        end
        $display("      repaired by the scrubber: %0d   uncorrectable: %0d   errors seen by the CPU: 0", dut.scrub_repaired - r0, dut.scrub_ue - u0);
    endtask

    task part4_order;
        int p0, bad, wraps;
        logic [31:0] expect_a;
        $display("");
        $display("  4B. Visiting order: the scrubber must visit every word, in order, and wrap around after the last one");
        pause_scrubber;
        p0 = dut.u_scrub.addr_cnt;
        scrub_log_n = 0;
        scrub_log_on = 1'b1;
        resume_scrubber;
        wait_scanned(DEPTH + 3, 60000);
        pause_scrubber;
        scrub_log_on = 1'b0;
        bad = 0; wraps = 0;
        for (int k = 0; k < DEPTH + 3; k++) begin
            expect_a = BASE + ((p0 + k) % DEPTH) * 4;
            if (scrub_log[k] !== expect_a) bad = bad + 1;
            if (k > 0 && scrub_log[k] === BASE && scrub_log[k - 1] === addr_of(LAST, 0)) wraps = wraps + 1;
        end
        $display("      started at word %0d; first requests: %h %h %h ...; around the wrap: ... %h %h",
                 p0, scrub_log[0], scrub_log[1], scrub_log[2], addr_of(LAST, 0), BASE);
        $display("      %0d requests checked: %0d out of order, wrap-around from word %0d to word 0 seen %0d time(s)",
                 DEPTH + 3, bad, LAST, wraps);
        chk(bad == 0, "the scrubber must request consecutive words");
        chk(wraps >= 1, "the scrubber must wrap from the last word to the first");
    endtask

    task part4_accumulate;
        int w, b1, b2, t1, t2;
        logic [31:0] d, got, e;
        logic [1:0]  resp, er;
        w  = $urandom_range(2, LAST - 2);
        d  = $urandom;
        b1 = $urandom_range(0, 38);
        b2 = rbit(b1, -1);
        $display("");
        $display("  4C. Why scrubbing matters: two separate hits on the same word (%s, later %s) - word %0d holds %h", bitname(b1), bitname(b2), w, d);
        // scrubber off: the errors accumulate into an uncorrectable word
        pause_scrubber;
        wr_full(w, d, 0);
        inject1(w, b1);
        idle(500);                                  // time passes, nobody reads the word
        dut.u_bram.mem[w] = dut.u_bram.mem[w] ^ bitmask(b2, -1, -1);
        wstate[w] = 2;
        rd_expect(w, 0, got, resp, e, er);
        $display("      scrubber OFF: after the second hit the word has TWO errors -> read returns %h, response %s (data lost)", got, resp_name(resp));
        chk(resp === 2'b10, "without the scrubber the two errors must accumulate into an uncorrectable word");
        wr_full(w, d, 0);
        // scrubber on: each hit is repaired before the next one arrives
        inject1(w, b1);
        resume_scrubber;
        wait_valid(w, 40000, t1);
        wstate[w] = 0;
        inject1(w, b2);
        wait_valid(w, 40000, t2);
        pause_scrubber;
        wstate[w] = 0;
        rd_expect(w, 0, got, resp, e, er);
        $display("      scrubber ON : first hit repaired after %0d cycles, second hit repaired after %0d cycles -> read returns %h, response %s",
                 t1, t2, got, resp_name(resp));
        chk((got === d) && (resp === 2'b00), "with the scrubber the data must survive both hits");
    endtask

    task part4_uncorrectable;
        int w9, w40, b1, b2, b, u0, ue_s0, scan0;
        logic [31:0] d9, d40;
        logic [38:0] pre;
        w9 = $urandom_range(2, LAST / 2);
        w40 = $urandom_range(LAST / 2 + 1, LAST - 2);
        d9 = $urandom; d40 = $urandom;
        b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); b = $urandom_range(0, 38);
        $display("");
        $display("  4D. An uncorrectable word (two flips in word %0d) and an ordinary single error (word %0d) in the same sweeps", w9, w40);
        pause_scrubber;
        wr_full(w9, d9, 0);
        wr_full(w40, d40, 0);
        inject2(w9, b1, b2);
        inject1(w40, b);
        pre = peek(w9);
        u0 = dut.scrub_ue; ue_s0 = ev_ue_scr; scan0 = dut.scrub_scanned;
        resume_scrubber;
        wait_scanned(2 * DEPTH + 4, 120000);
        pause_scrubber;
        chk(peek(w9) === pre, "the scrubber must not touch a word with an uncorrectable error");
        chk(dut.scrub_ue - u0 >= 2, "the uncorrectable word must be reported in every sweep");
        chk(ev_ue_scr - ue_s0 == dut.scrub_ue - u0, "events and scrubber statistics must agree");
        chk(is_valid(w40), "the sweep must carry on and repair the other word");
        $display("      word %0d (flips %s, %s): left exactly as it was (%h), reported %0d times in 2 sweeps", w9, bitname(b1), bitname(b2), pre, dut.scrub_ue - u0);
        $display("      word %0d (flip %s): repaired in the same sweeps -> %h   (%0d scrub operations in total)", w40, bitname(b), peek(w40), dut.scrub_scanned - scan0);
        wr_full(w9, d9, 0);
        wstate[w40] = 0;
        chk(is_valid(w9), "rewriting the word must clear the problem");
        $display("      a full-word write to word %0d replaces it: valid again", w9);
    endtask

    task part4_cpu_wait;
        int base_max, base_min, run_max, run_min, scan0, w;
        logic [31:0] g, e;
        logic [1:0]  r, er;
        $display("");
        $display("  4E. Does the scrubber slow the CPU down? 200 back-to-back reads, scrubber off and on");
        pause_scrubber;
        base_max = 0; base_min = 1000;
        for (int i = 0; i < 200; i++) begin
            w = $urandom_range(0, LAST);
            rd_expect(w, 0, g, r, e, er);
            if (lat_read > base_max) base_max = lat_read;
            if (lat_read < base_min) base_min = lat_read;
        end
        scan0 = dut.scrub_scanned;
        resume_scrubber;
        run_max = 0; run_min = 1000;
        for (int i = 0; i < 200; i++) begin
            w = $urandom_range(0, LAST);
            rd_expect(w, 0, g, r, e, er);
            if (lat_read > run_max) run_max = lat_read;
            if (lat_read < run_min) run_min = lat_read;
        end
        pause_scrubber;
        $display("      read latency (request to response seen by the master): scrubber off %0d..%0d cycles, on %0d..%0d cycles",
                 base_min, base_max, run_min, run_max);
        $display("      %0d scrub operations ran during the second batch; the worst extra wait was %0d cycle(s)", dut.scrub_scanned - scan0, run_max - base_max);
        chk(run_max <= base_max + 5, "a CPU read may wait at most about one scrub operation longer");
        chk(dut.scrub_scanned - scan0 > 0, "the scrubber must keep making progress while the CPU is busy");
    endtask

    // =========================================================================
    // PART 5: long random traffic with random errors, scrubber running
    // =========================================================================
    function automatic int low_lane(input logic [3:0] s);
        low_lane = 0;
        if (s[0]) low_lane = 0;
        else if (s[1]) low_lane = 1;
        else if (s[2]) low_lane = 2;
        else if (s[3]) low_lane = 3;
    endfunction

    task part5_random;
        int n, w, w2, r, op, b, b2, order, healed, n_double_words;
        int n_rd, n_wf, n_wp, n_nop, n_i1, n_i2, n_sim, n_idle, n_slv_rd, n_slv_wr;
        int ce_c0, ce_s0, ue_c0, ue_s0, rep0, scan0, sw0;
        logic [31:0] d, g, g2, e;
        logic [1:0]  resp, r2, er, wresp;
        logic [3:0]  s;
        n_rd = 0; n_wf = 0; n_wp = 0; n_nop = 0; n_i1 = 0; n_i2 = 0; n_sim = 0; n_idle = 0; n_slv_rd = 0; n_slv_wr = 0;
        for (int i = 0; i < DEPTH; i++) wstate[i] = 0;
        ce_c0 = ev_ce_cpu; ce_s0 = ev_ce_scr; ue_c0 = ev_ue_cpu; ue_s0 = ev_ue_scr;
        rep0 = dut.scrub_repaired; scan0 = dut.scrub_scanned; sw0 = dut.scrub_sweeps;
        $display("  %0d random operations, chosen at random every time:", N_RANDOM_OPS);
        $display("    reads 30%%, full writes 18%%, partial writes 22%% (random byte strobes, including none and all),");
        $display("    single-bit error injection 10%%, double-bit injection 3%%, read+write in the same cycle 7%%, idle bursts 10%%.");
        $display("    70%% of the accesses hit 24 'hot' words (many collisions), the rest the whole RAM, the first and the last word.");
        $display("    The AXI timing is random too (random order of AW/W, idle gaps, slow BREADY/RREADY). The scrubber runs all the time.");
        $display("    Every response is checked against the scoreboard; word states: clean / one flipped bit / two flipped bits.");
        resume_scrubber;
        for (n = 1; n <= N_RANDOM_OPS; n++) begin
            r = $urandom_range(0, 99);
            if (r < 70)       w = $urandom_range(0, 23);
            else if (r < 95)  w = $urandom_range(0, LAST);
            else if (r < 98)  w = 0;
            else              w = LAST;
            if ($urandom_range(0, 3) == 0) gap_max = 6; else gap_max = 0;
            order = $urandom_range(0, 3);
            op = $urandom_range(0, 99);
            if (op < 30) begin
                rd_expect(w, $urandom_range(0, 3), g, resp, e, er);
                n_rd = n_rd + 1;
                if (er === 2'b10) n_slv_rd = n_slv_rd + 1;
            end else if (op < 48) begin
                wr_full(w, $urandom, order);
                n_wf = n_wf + 1;
            end else if (op < 70) begin
                s = $urandom_range(0, 15);
                d = $urandom;
                wr_part(w, d, s, low_lane(s), order, wresp);
                if (s == 4'b0000) n_nop = n_nop + 1;
                else if (s == 4'b1111) n_wf = n_wf + 1;
                else n_wp = n_wp + 1;
                if (wresp === 2'b10) n_slv_wr = n_slv_wr + 1;
            end else if (op < 80) begin
                if (wstate[w] == 0) begin inject1(w, $urandom_range(0, 38)); n_i1 = n_i1 + 1; end
            end else if (op < 83) begin
                if (wstate[w] == 0) begin
                    b = $urandom_range(0, 38); b2 = rbit(b, -1);
                    inject2(w, b, b2);
                    n_i2 = n_i2 + 1;
                end
            end else if (op < 90) begin
                w2 = $urandom_range(0, LAST);
                while (w2 == w) w2 = $urandom_range(0, LAST);
                d = $urandom;
                e = exp_data(w2);
                er = exp_resp(w2);
                fork
                    axi_write(addr_of(w, 0), d, 4'b1111, 0, wresp);
                    axi_read(addr_of(w2, 0), g2, r2);
                join
                ref_data[w] = d;
                wstate[w]   = 0;
                chk(wresp === 2'b00, "the write of a simultaneous pair must answer OKAY");
                chk((g2 === e) && (r2 === er), "the read of a simultaneous pair must match the scoreboard");
                n_sim = n_sim + 1;
            end else begin
                idle($urandom_range(20, 200));
                n_idle = n_idle + 1;
            end
            if (n % (N_RANDOM_OPS / 6) == 0)
                $display("    ... %5d / %0d operations done, failures so far %0d, errors injected so far %0d single + %0d double",
                         n, N_RANDOM_OPS, part_errors[5], n_i1, n_i2);
        end
        gap_max = 0;

        // ---- final consistency check ----
        n_double_words = 0;
        for (int i = 0; i < DEPTH; i++) begin
            if (wstate[i] == 2) n_double_words = n_double_words + 1;
            rd_check(i);
        end
        healed = 0;
        for (int i = 0; i < DEPTH; i++)
            if (wstate[i] == 2) begin wr_full(i, $urandom, 0); healed = healed + 1; end
        wait_scanned(DEPTH + 4, 80000);              // one more full sweep so every single error is gone
        pause_scrubber;
        for (int i = 0; i < DEPTH; i++) begin
            wstate[i] = 0;
            chk(peek(i) === g_encode(ref_data[i]), "after the last sweep every word must be the model's codeword of the expected data");
        end

        $display("");
        $display("    traffic summary");
        $display("      CPU operations : %0d reads (%0d answered SLVERR), %0d full writes, %0d partial writes (%0d refused with SLVERR),", n_rd, n_slv_rd, n_wf, n_wp, n_slv_wr);
        $display("                       %0d writes with no byte strobe, %0d simultaneous read+write pairs, %0d idle bursts", n_nop, n_sim, n_idle);
        $display("      errors injected: %0d single-bit, %0d double-bit (%0d words still held two flipped bits at the end)", n_i1, n_i2, n_double_words);
        $display("      corrected on a CPU access: %0d   repaired by the scrubber: %0d   uncorrectable seen: %0d by the CPU, %0d by the scrubber",
                 ev_ce_cpu - ce_c0, dut.scrub_repaired - rep0, ev_ue_cpu - ue_c0, ev_ue_scr - ue_s0);
        $display("      scrubber: %0d words scrubbed, %0d full sweeps", dut.scrub_scanned - scan0, dut.scrub_sweeps - sw0);
        $display("      final check: every word read back as predicted; after one more sweep all %0d stored words equal the model's", DEPTH);
        $display("                   codeword of the expected data (%0d damaged words were rewritten first)", healed);
        chk(n_i1 > 50 && n_i2 > 5, "the random run must have injected a meaningful number of errors");
        chk(ev_ce_cpu - ce_c0 + dut.scrub_repaired - rep0 > 0, "single errors must have been corrected");
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    integer seed;
    integer seed_used;
    integer seed_dummy;
    task part_row(input int n, input string text);
        $display("   %0d    %-60s %6d   %6d     %s", n, text, part_checks[n], part_errors[n], pick(part_errors[n] == 0, "PASS", "FAIL"));
    endtask

    initial begin
        for (int i = 0; i < 10; i++) begin part_checks[i] = 0; part_errors[i] = 0; end
        for (int i = 0; i < DEPTH; i++) begin ref_data[i] = 32'h0; wstate[i] = 0; end
        seed = SEED_DEFAULT;
        if ($value$plusargs("seed=%d", seed)) begin
            $display("(seed given on the command line)");
        end
        seed_used = seed;                            // remember it: $urandom(seed) may advance the variable
        seed_dummy = $urandom(seed);
        force dut.scrub_enable = 1'b0;               // the scrubber stays paused until a test wants it

        $display("==============================================================================");
        $display(" MEGA TESTBENCH - P12 ECC memory subsystem (AXI4-Lite + arbiter + scrubber + ECC + 39-bit RAM)");
        $display("==============================================================================");
        $display(" random seed = %0d   (re-run with +seed=<n> to repeat exactly)   RAM = %0d words", seed_used, DEPTH);
        $display("");
        $display(" Data flow under test:");
        $display("   AXI master --> axil_frontend --> mem_arbiter <-- ecc_scrubber (background, 1 word / 16 cycles)");
        $display("                                        |");
        $display("                                   mem_ctrl_ecc: write = encode, read = decode + correct,");
        $display("                                        |        partial write = read-modify-write, scrub = read + repair");
        $display("                              39-bit RAM word = { 7 check bits c6..c0 | 32 data bits d31..d0 }");
        $display("");
        $display(" How to read the output:  [AXI ...] = what the bus master does,  [ENCODER]/[DECODER] = what the ECC does,");
        $display("   [RADIATION] = the testbench flips stored bits behind the controller's back,  [SCRUBBER] = background repair.");
        $display(" d0..d31 are data bits, c0..c6 check bits. 'model' = the testbench's own copy of the code (same as the Python model).");

        // ---------------- reset and initial fill ----------------
        begin_part(0, "Reset and initial fill");
        idle(3); rst_n = 1; idle(3);
        for (int w = 0; w < DEPTH; w++) wr_full(w, $urandom, 3);
        for (int w = 0; w < DEPTH; w++) rd_check(w);
        $display("  all %0d words written with random data and read back", DEPTH);
        end_part();

        // ---------------- part 1 ----------------
        begin_part(1, "Follow one word through the system (random word, data and bit every run)");
        story_1a();
        story_1b();
        story_1c();
        story_1d();
        story_1e();
        end_part();

        // ---------------- part 2 ----------------
        begin_part(2, "AXI reads and writes (scrubber running in the background)");
        resume_scrubber;
        part2_patterns();
        part2_addresses();
        part2_subword();
        part2_handshakes();
        part2_dependencies();
        end_part();

        // ---------------- part 3 ----------------
        begin_part(3, "Error detection and correction (scrubber paused so nothing is repaired behind our back)");
        pause_scrubber;
        part3_single();
        part3_double();
        part3_triple();
        part3_errors_and_writes();
        part3_soup();
        end_part();

        // ---------------- part 4 ----------------
        begin_part(4, "The scrubber");
        part4_repair();
        part4_order();
        part4_accumulate();
        part4_uncorrectable();
        part4_cpu_wait();
        end_part();

        // ---------------- part 5 ----------------
        begin_part(5, "Long random traffic with random errors, scrubber running");
        part5_random();
        end_part();

        // ---------------- summary ----------------
        idle(5);
        $display("");
        $display("==============================================================================");
        $display(" SUMMARY");
        $display("==============================================================================");
        $display("  part  what                                                            checks  failures  result");
        part_row(0, "reset, initial fill of the whole RAM");
        part_row(1, "one word through the system (5 stories)");
        part_row(2, "AXI reads/writes, patterns, corners, sub-word, handshakes");
        part_row(3, "single / double / triple errors, errors meeting writes");
        part_row(4, "scrubber: repair, order, accumulation, uncorrectable, CPU wait");
        part_row(5, "long random traffic with random errors");
        $display("  -----------------------------------------------------------------------------------------");
        $display("  AXI response-rule violations seen by the monitor : %0d", prot_viol);
        chk(prot_viol == 0, "BVALID/RVALID must stay asserted with stable data until READY");
        $display("  error events from the controller: corrected %0d on CPU accesses + %0d by the scrubber, uncorrectable %0d + %0d",
                 ev_ce_cpu, ev_ce_scr, ev_ue_cpu, ev_ue_scr);
        $display("  scrubber totals: %0d words scrubbed, %0d repaired, %0d uncorrectable reports, %0d full sweeps",
                 dut.scrub_scanned, dut.scrub_repaired, dut.scrub_ue, dut.scrub_sweeps);
        $display("");
        if (errors == 0) begin
            $display("PASS: %0d checks, 0 failures  (seed %0d)", checks, seed_used);
            $display("  What this run showed: data written through AXI is encoded and stored as the model's codeword; single-bit");
            $display("  errors anywhere in the 39 bits are corrected on read and by the scrubber; double errors are always detected");
            $display("  (SLVERR) and never silently changed; sub-word writes keep the rest of the word and the check bits right;");
            $display("  the scrubber visits every word in order, repairs without the CPU, and costs the CPU one or two cycles at most.");
        end else begin
            $display("FAIL: %0d failures in %0d checks  (seed %0d)", errors, checks, seed_used);
        end
        $display("==============================================================================");
        $finish;
    end

    initial begin
        #500ms;
        $display("TIMEOUT");
        $finish;
    end
endmodule
