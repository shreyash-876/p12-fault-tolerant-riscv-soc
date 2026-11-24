`timescale 1ns / 1ps
// =============================================================================
// tb_regs: testbench for the register block, the error counters, the error log, the interrupt lines
// and the error-injection port of the P12 ECC memory system (module mem_subsystem).
//
//   R1  reset values, plain registers, byte strobes, read-only and unmapped registers
//   R2  counters, flags, log and interrupt gating for errors found by CPU accesses
//   R3  errors found by the scrubber; scrubber control (enable bit, interval register, statistics)
//   R4  the error-injection port: register-driven masks, random single/double flips, board-button pulses
//   R5  the uncorrectable-error interrupt, end to end
//   R6  random consistency stress: the hardware counters must equal an independent count of the events
//
// The testbench has its own model of the code, a reference memory (scoreboard), and a "radiation"
// backdoor that flips stored bits directly in the RAM array. Random choices are seeded; the seed is
// printed (re-run with +seed=N). Run with simulation runtime = all.
// =============================================================================
module tb_regs;
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
    logic        irq_ue, irq_ce;
    logic        hw_single = 0, hw_double = 0;      // board-button pulses for the injector

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
        .hw_inj_single(hw_single), .hw_inj_double(hw_double),
        .irq_ue(irq_ue), .irq_ce(irq_ce)
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


    // =========================================================================
    // Register-port master and helpers
    // =========================================================================
    localparam logic [31:0] REGBASE = 32'h4000_0000;
    localparam logic [31:0] R_ID   = 32'h00, R_S0   = 32'h04, R_S1   = 32'h08, R_S2   = 32'h0C,
                            R_CTRL = 32'h10, R_STAT = 32'h14, R_CE   = 32'h18, R_UE   = 32'h1C,
                            R_LOGA = 32'h20, R_LOGI = 32'h24, R_SINT = 32'h28, R_SREP = 32'h2C,
                            R_SSWP = 32'h30, R_IADR = 32'h34, R_IMLO = 32'h38, R_IMHI = 32'h3C,
                            R_ICTL = 32'h40, R_ICNT = 32'h44;

    logic [1:0] last_bresp = 2'b00;

    task reg_write(input logic [31:0] off, input logic [31:0] d, input logic [3:0] s);
        fork
            begin r_awaddr <= REGBASE + off; r_awvalid <= 1; do @(posedge clk); while (!r_awready); r_awvalid <= 0; end
            begin r_wdata <= d; r_wstrb <= s; r_wvalid <= 1; do @(posedge clk); while (!r_wready); r_wvalid <= 0; end
        join
        r_bready <= 1;
        do @(posedge clk); while (!r_bvalid);
        last_bresp = r_bresp;
        r_bready <= 0;
    endtask

    task reg_read(input logic [31:0] off, output logic [31:0] d);
        r_araddr <= REGBASE + off; r_arvalid <= 1;
        do @(posedge clk); while (!r_arready);
        r_arvalid <= 0;
        r_rready <= 1;
        do @(posedge clk); while (!r_rvalid);
        d = r_rdata;
        r_rready <= 0;
    endtask

    task rw(input logic [31:0] off, input logic [31:0] d);
        reg_write(off, d, 4'hF);
    endtask

    logic [31:0] ctrl_sh = 32'h1;                     // what the testbench last wrote to CTRL (bits 2:0)

    task set_ctrl(input logic [31:0] v);
        ctrl_sh = v & 32'h7;
        rw(R_CTRL, ctrl_sh);
    endtask
    task scrub_off;
        set_ctrl(ctrl_sh & ~32'h1);
        idle(40);                                     // let a scrub operation that already started finish
    endtask
    task scrub_on;
        set_ctrl(ctrl_sh | 32'h1);
    endtask
    task clear_counters;
        rw(R_CTRL, ctrl_sh | 32'h10);                 // CLEAR: counters and log
    endtask
    task clear_flags;
        rw(R_STAT, 32'h7);                            // write 1 to clear CE_SEEN, UE_SEEN, LOG_OVERRUN
    endtask
    task clear_all;
        clear_counters();
        clear_flags();
    endtask

    task heal_all;                                    // rewrite every damaged word: the memory is clean again
        for (int w = 0; w < DEPTH; w++)
            if (wstate[w] != 0) wr_full(w, $urandom, 0);
    endtask

    task wait_scanned(input int n, input int timeout_cycles);
        int start, t;
        start = dut.scrub_scanned;
        t = 0;
        while ((dut.scrub_scanned - start) < n && t < timeout_cycles) begin
            @(posedge clk);
            t = t + 1;
        end
        chk((dut.scrub_scanned - start) >= n, "the scrubber must complete the expected number of operations in time");
    endtask

    task wait_valid(input int w, input int timeout_cycles, output int waited);
        waited = 0;
        while (!is_valid(w) && waited < timeout_cycles) begin
            @(posedge clk);
            waited = waited + 1;
        end
        chk(is_valid(w), "the scrubber must repair the word in time");
    endtask

    function automatic bit is_valid(input int w);
        is_valid = (g_syndrome(peek(w)) == 7'd0);
    endfunction

    task wait_inj_idle;
        logic [31:0] d;
        int n;
        n = 0;
        d = 32'h100;
        while (d[8] && n < 400) begin
            reg_read(R_ICTL, d);
            n = n + 1;
        end
        chk(!d[8], "the injection must finish (INJ_CTRL.BUSY back to 0)");
    endtask

    function automatic int popc39(input logic [38:0] x);
        int n;
        n = 0;
        for (int i = 0; i < 39; i++) if (x[i]) n = n + 1;
        popc39 = n;
    endfunction

    function automatic string info_str(input logic [31:0] li);
        string kind;
        if (li[16]) kind = "UNCORRECTABLE";
        else        kind = $sformatf("corrected bit %s", bitname(int'(li[13:8])));
        info_str = $sformatf("syndrome %b, %s, found by the %s", li[6:0], kind, pick(li[17], "scrubber", "CPU"));
    endfunction

    function automatic int rand_word(input int dummy);
        int w;
        w = $urandom_range(2, LAST - 2);
        while (wstate[w] != 0) w = $urandom_range(2, LAST - 2);
        rand_word = w;
    endfunction

    task show_reg(input string name, input logic [31:0] off, input logic [31:0] expv);
        logic [31:0] d;
        reg_read(off, d);
        $display("      %-16s 0x%02h    %h    %h   %s", name, off[7:0], d, expv, pick(d === expv, "ok", "MISMATCH"));
        chk(d === expv, "register reset value");
    endtask

    // =========================================================================
    // R1: reset values and plain registers
    // =========================================================================
    task r1;
        logic [31:0] d, big;
        $display("  R1a. Reset values, read through the AXI register port");
        $display("      register         offset  value       expected    result");
        show_reg("ID",              R_ID,   32'h5031_2001);
        show_reg("SCRATCH0",        R_S0,   32'h0);
        show_reg("CTRL",            R_CTRL, 32'h1);          // scrubber on, interrupts off
        show_reg("STATUS",          R_STAT, 32'h0);
        show_reg("CE_COUNT",        R_CE,   32'h0);
        show_reg("UE_COUNT",        R_UE,   32'h0);
        show_reg("LOG_ADDR",        R_LOGA, 32'h0);
        show_reg("LOG_INFO",        R_LOGI, 32'h0);
        show_reg("SCRUB_INTERVAL",  R_SINT, 32'd16);         // the SCRUB_INTERVAL parameter
        show_reg("SCRUB_REPAIRED",  R_SREP, 32'h0);
        show_reg("INJ_ADDR",        R_IADR, 32'h0);
        show_reg("INJ_MASK_LO",     R_IMLO, 32'h0);
        show_reg("INJ_MASK_HI",     R_IMHI, 32'h0);
        show_reg("INJ_CTRL",        R_ICTL, 32'h0);
        show_reg("INJ_COUNT",       R_ICNT, 32'h0);
        scrub_off;                                           // from here the testbench decides when the scrubber runs

        $display("");
        $display("  R1b. Scratch registers and byte strobes");
        rw(R_S0, 32'hDEADBEEF);
        reg_read(R_S0, d);
        $display("      write DEADBEEF -> read %h", d);
        chk(d === 32'hDEADBEEF, "scratch register must hold the written value");
        reg_write(R_S0, 32'h0000_AA00, 4'b0010);
        reg_read(R_S0, d);
        $display("      write 0000AA00 with strobe 0010 (byte 1 only) -> read %h   (expected DEADAAEF)", d);
        chk(d === 32'hDEADAAEF, "a byte-strobed write must change only that byte");
        reg_write(R_S0, 32'h1122_3344, 4'b1001);
        reg_read(R_S0, d);
        $display("      write 11223344 with strobe 1001 (bytes 3 and 0) -> read %h   (expected 11ADAA44)", d);
        chk(d === 32'h11ADAA44, "strobes 1001 must change bytes 3 and 0 only");

        $display("");
        $display("  R1c. Read-only and unmapped registers ignore writes");
        rw(R_ID, 32'h0);          rw(R_CE, 32'h12345678);   rw(R_UE, 32'h1);   rw(R_LOGA, 32'h7);
        rw(R_SREP, 32'h5);        rw(R_SSWP, 32'h9);        rw(R_ICNT, 32'h3);
        reg_read(R_ID, d);   chk(d === 32'h5031_2001, "ID must be read-only");
        reg_read(R_CE, d);   chk(d === 32'h0, "CE_COUNT must be read-only");
        reg_read(R_UE, d);   chk(d === 32'h0, "UE_COUNT must be read-only");
        reg_read(R_SREP, d); chk(d === 32'h0, "SCRUB_REPAIRED must be read-only");
        reg_read(R_ICNT, d); chk(d === 32'h0, "INJ_COUNT must be read-only");
        $display("      writes to ID, CE_COUNT, UE_COUNT, LOG_ADDR, SCRUB_REPAIRED, SCRUB_SWEEPS, INJ_COUNT changed nothing");
        rw(32'h48, 32'hFFFFFFFF);
        chk(last_bresp === 2'b00, "a write to an unmapped offset must still answer OKAY");
        reg_read(32'h48, d); chk(d === 32'h0, "an unmapped register must read 0");
        reg_read(32'h7C, d); chk(d === 32'h0, "an unmapped register must read 0");
        reg_read(32'hFC, d); chk(d === 32'h0, "an unmapped register must read 0");
        $display("      offsets 0x48, 0x7C, 0xFC (unmapped): read 0, writes answered OKAY and ignored");

        $display("");
        $display("  R1d. Read/write registers keep only their implemented bits");
        rw(R_CTRL, 32'hFFFF_FFFF);
        reg_read(R_CTRL, d);
        $display("      CTRL: wrote FFFFFFFF -> reads %h  (only SCRUB_EN, IRQ_UE_EN, IRQ_CE_EN are stored; CLEAR is a command)", d);
        chk(d === 32'h7, "CTRL must keep bits 2:0 only");
        set_ctrl(32'h1);
        rw(R_IMHI, 32'hFFFF_FFFF);
        reg_read(R_IMHI, d);
        $display("      INJ_MASK_HI: wrote FFFFFFFF -> reads %h  (only the 7 check-bit positions)", d);
        chk(d === 32'h7F, "INJ_MASK_HI must keep 7 bits");
        rw(R_IMHI, 32'h0);
        rw(R_ICTL, 32'h6);                                   // RANDOM | DOUBLE, but not GO
        reg_read(R_ICTL, d);
        $display("      INJ_CTRL: wrote 6 (RANDOM|DOUBLE) -> reads %h", d);
        chk(d === 32'h6, "INJ_CTRL must keep RANDOM and DOUBLE");
        rw(R_ICTL, 32'h0);
        rw(R_SINT, 32'd1234);
        reg_read(R_SINT, d);
        chk(d === 32'd1234, "SCRUB_INTERVAL must be writable");
        rw(R_SINT, 32'd16);
        $display("      SCRUB_INTERVAL written and read back (1234), then restored to 16");
    endtask

    // =========================================================================
    // R2: counters, flags, log and interrupt gating for errors found by CPU accesses
    // =========================================================================
    task read_counts(output int ce, output int ue);
        logic [31:0] d;
        reg_read(R_CE, d); ce = int'(d);
        reg_read(R_UE, d); ue = int'(d);
    endtask

    task r2a;
        int w, b, ce, ue, wt;
        logic [31:0] d, got, e, st, la, li;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        scrub_off; heal_all; clear_all;
        w = rand_word(0); b = $urandom_range(0, 38); d = $urandom;
        wr_full(w, d, 0);
        inject1(w, b);
        cor = peek(w);
        syn = g_syndrome(cor);
        $display("  R2a. A single-bit error found by a CPU read (scrubber off)");
        $display("   [RADIATION ] flips %s of word %0d: stored word %h", bitname(b), w, cor);
        rd_expect(w, 0, got, resp, e, er);
        $display("   [AXI READ  ] returned %h (corrected), response %s", got, resp_name(resp));
        read_counts(ce, ue);
        reg_read(R_STAT, st); reg_read(R_LOGA, la); reg_read(R_LOGI, li);
        $display("   [REGISTERS ] CE_COUNT = %0d, UE_COUNT = %0d, STATUS = %h (CE_SEEN %0d, UE_SEEN %0d, log level %0d)", ce, ue, st, st[0], st[1], st[11:8]);
        $display("                LOG_ADDR = %h (word %0d is at %h)", la, w, addr_of(w, 0));
        $display("                LOG_INFO = %h : %s", li, info_str(li));
        chk(ce == 1 && ue == 0, "one corrected error must be counted");
        chk(st[0] && !st[1] && !st[2] && st[11:8] == 4'd1, "STATUS must show CE_SEEN and one log entry");
        chk(la === addr_of(w, 0), "the log must hold the byte address of the word");
        chk(li[6:0] === syn && li[13:8] == b && !li[16] && !li[17], "the log must hold syndrome, bit, 'corrected' and 'CPU'");
        // interrupt gating: irq_ce follows CE_SEEN only when IRQ_CE_EN is set
        chk(!irq_ce, "irq_ce must stay low while IRQ_CE_EN = 0");
        set_ctrl(ctrl_sh | 32'h4);
        idle(3);
        chk(irq_ce, "irq_ce must go high when IRQ_CE_EN is set and CE_SEEN = 1");
        $display("   [INTERRUPT ] IRQ_CE_EN set -> irq_ce = %0d; writing 1 to STATUS.CE_SEEN clears the flag:", irq_ce);
        rw(R_STAT, 32'h1);
        idle(3);
        reg_read(R_STAT, st);
        $display("                CE_SEEN = %0d, irq_ce = %0d   (the counter keeps its value: CE_COUNT = %0d)", st[0], irq_ce, ce);
        chk(!irq_ce && !st[0], "writing 1 to CE_SEEN must clear the flag and the interrupt");
        set_ctrl(ctrl_sh & ~32'h4);
        // pop the entry
        rw(R_LOGI, 32'h0);
        reg_read(R_STAT, st); reg_read(R_LOGA, la);
        $display("   [LOG       ] any write to LOG_INFO pops the entry: level %0d, LOG_ADDR %h", st[11:8], la);
        chk(st[11:8] == 4'd0 && la === 32'h0, "the log must be empty after the pop");
    endtask

    task r2b;
        int w, b1, b2, ce, ue;
        logic [31:0] d, got, e, st, la, li;
        logic [1:0]  resp, er;
        logic [38:0] cor;
        logic [6:0]  syn;
        scrub_off; heal_all; clear_all;
        w = rand_word(0); b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); d = $urandom;
        wr_full(w, d, 0);
        inject2(w, b1, b2);
        cor = peek(w);
        syn = g_syndrome(cor);
        $display("");
        $display("  R2b. A double-bit error found by a CPU read");
        $display("   [RADIATION ] flips %s and %s of word %0d: stored word %h", bitname(b1), bitname(b2), w, cor);
        rd_expect(w, 0, got, resp, e, er);
        read_counts(ce, ue);
        reg_read(R_STAT, st); reg_read(R_LOGA, la); reg_read(R_LOGI, li);
        $display("   [AXI READ  ] returned %h with response %s", got, resp_name(resp));
        $display("   [REGISTERS ] CE_COUNT = %0d, UE_COUNT = %0d, STATUS = %h (UE_SEEN %0d)", ce, ue, st, st[1]);
        $display("                LOG_INFO = %h : %s", li, info_str(li));
        chk(ce == 0 && ue == 1, "one uncorrectable error must be counted");
        chk(!st[0] && st[1], "STATUS must show UE_SEEN only");
        chk(li[16] && li[6:0] === syn && la === addr_of(w, 0), "the log entry must say 'uncorrectable' with the right syndrome and address");
        chk(!irq_ue, "irq_ue must stay low while IRQ_UE_EN = 0");
        set_ctrl(ctrl_sh | 32'h2);
        idle(3);
        chk(irq_ue, "irq_ue must go high when IRQ_UE_EN is set and UE_SEEN = 1");
        $display("   [INTERRUPT ] IRQ_UE_EN set -> irq_ue = %0d (a level: it stays high until the firmware clears UE_SEEN)", irq_ue);
        idle(50);
        chk(irq_ue, "irq_ue must stay high");
        rw(R_STAT, 32'h2);
        idle(3);
        chk(!irq_ue, "clearing UE_SEEN must drop irq_ue");
        $display("                after writing 1 to STATUS.UE_SEEN: irq_ue = %0d", irq_ue);
        set_ctrl(ctrl_sh & ~32'h2);
        rw(R_LOGI, 32'h0);
    endtask

    task r2c;
        int ws [0:9];
        int ce, ue, n_ok;
        logic [31:0] got, e, st, la, li;
        logic [1:0]  resp, er;
        scrub_off; heal_all; clear_all;
        $display("");
        $display("  R2c. Ten errors in a row: the log holds 8 entries (oldest first), the overrun flag is set, the counter keeps counting");
        for (int i = 0; i < 10; i++) begin
            ws[i] = rand_word(0);
            wr_full(ws[i], $urandom, 0);
            inject1(ws[i], $urandom_range(0, 38));
        end
        for (int i = 0; i < 10; i++) rd_expect(ws[i], 0, got, resp, e, er);
        read_counts(ce, ue);
        reg_read(R_STAT, st);
        $display("   CE_COUNT = %0d, log level = %0d, LOG_OVERRUN = %0d", ce, st[11:8], st[2]);
        chk(ce == 10, "all ten corrected errors must be counted");
        chk(st[11:8] == 4'd8 && st[2], "the log must be full (8) with LOG_OVERRUN set");
        n_ok = 0;
        for (int i = 0; i < 8; i++) begin
            reg_read(R_LOGA, la);
            if (la === addr_of(ws[i], 0)) n_ok = n_ok + 1;
            rw(R_LOGI, 32'h0);
        end
        reg_read(R_STAT, st);
        $display("   popped 8 entries: %0d of 8 had exactly the address of the matching error, in order; level now %0d", n_ok, st[11:8]);
        chk(n_ok == 8, "the log must keep the OLDEST 8 events in order");
        chk(st[11:8] == 4'd0, "the log must be empty after 8 pops");
        rw(R_STAT, 32'h4);
        reg_read(R_STAT, st);
        chk(!st[2], "writing 1 to LOG_OVERRUN must clear it");
        read_counts(ce, ue);
        chk(ce == 10, "popping must not change the counter");
        rw(R_STAT, 32'h7);
    endtask

    task r2d;
        int ce, ue, w;
        logic [31:0] got, e, st;
        logic [1:0]  resp, er;
        scrub_off; heal_all; clear_all;
        $display("");
        $display("  R2d. The CLEAR command (CTRL bit 4) restarts the counters and the log, but not the sticky flags");
        for (int i = 0; i < 3; i++) begin
            w = rand_word(0);
            wr_full(w, $urandom, 0);
            inject1(w, $urandom_range(0, 38));
            rd_expect(w, 0, got, resp, e, er);
        end
        read_counts(ce, ue);
        reg_read(R_STAT, st);
        $display("   before: CE_COUNT = %0d, log level %0d, CE_SEEN %0d", ce, st[11:8], st[0]);
        clear_counters();
        read_counts(ce, ue);
        reg_read(R_STAT, st);
        $display("   after CLEAR: CE_COUNT = %0d, log level %0d, CE_SEEN %0d (flag untouched)", ce, st[11:8], st[0]);
        chk(ce == 0 && ue == 0 && st[11:8] == 4'd0, "CLEAR must zero the counters and empty the log");
        chk(st[0], "CLEAR must not clear the sticky flags");
        clear_flags();
    endtask

    // =========================================================================
    // R3: errors found by the scrubber, and scrubber control
    // =========================================================================
    task r3a;
        int w, b, ce, ue, waited, rep0;
        logic [31:0] d, st, la, li, v;
        logic [38:0] cor;
        logic [6:0]  syn;
        scrub_off; heal_all; clear_all;
        reg_read(R_SREP, v); rep0 = int'(v);
        w = rand_word(0); b = $urandom_range(0, 38); d = $urandom;
        wr_full(w, d, 0);
        inject1(w, b);
        cor = peek(w);
        syn = g_syndrome(cor);
        $display("  R3a. A single-bit error repaired by the scrubber (the CPU never touches the word)");
        $display("   [RADIATION ] flips %s of word %0d: stored word %h", bitname(b), w, cor);
        scrub_on;
        wait_valid(w, 20000, waited);
        scrub_off;
        wstate[w] = 0;
        read_counts(ce, ue);
        reg_read(R_STAT, st); reg_read(R_LOGA, la); reg_read(R_LOGI, li); reg_read(R_SREP, v);
        $display("   [SCRUBBER  ] repaired the word after %0d cycles; stored word is %h again", waited, peek(w));
        $display("   [REGISTERS ] CE_COUNT = %0d, SCRUB_REPAIRED = %0d (+%0d), log level %0d", ce, v, int'(v) - rep0, st[11:8]);
        $display("                LOG_ADDR = %h, LOG_INFO = %h : %s", la, li, info_str(li));
        chk(ce == 1 && ue == 0, "the scrubber's correction must be counted once");
        chk(int'(v) - rep0 == 1, "SCRUB_REPAIRED must count the repaired word");
        chk(st[11:8] == 4'd1 && la === addr_of(w, 0), "the scrubber's event must be in the log with the word's address");
        chk(li[17] && !li[16] && li[6:0] === syn && li[13:8] == b, "the log entry must say 'found by the scrubber, corrected', with the right syndrome and bit");
        rw(R_LOGI, 32'h0);
        clear_flags();
    endtask

    task r3b;
        int w, b1, b2, ce, ue, t, waited;
        logic [31:0] d, st, la, li;
        scrub_off; heal_all; clear_all;
        set_ctrl(ctrl_sh | 32'h2);                              // IRQ_UE_EN
        w = rand_word(0); b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); d = $urandom;
        wr_full(w, d, 0);
        inject2(w, b1, b2);
        $display("");
        $display("  R3b. A word with TWO flipped bits (%s, %s) stays uncorrectable: the scrubber finds it again in every sweep", bitname(b1), bitname(b2));
        scrub_on;
        wait_scanned(2 * DEPTH + 8, 80000);
        scrub_off;
        read_counts(ce, ue);
        reg_read(R_STAT, st); reg_read(R_LOGA, la); reg_read(R_LOGI, li);
        $display("   after two sweeps: UE_COUNT = %0d (found once per sweep), but the log holds %0d entry (repeats are not logged)", ue, st[11:8]);
        $display("   LOG_ADDR = %h, LOG_INFO : %s", la, info_str(li));
        chk(ue >= 2, "the scrubber must report the uncorrectable word in every sweep");
        chk(st[11:8] == 4'd1, "the repeated report must be logged only once");
        chk(la === addr_of(w, 0) && li[16] && li[17], "the entry must be an uncorrectable word found by the scrubber");
        chk(st[1] && irq_ue, "UE_SEEN and irq_ue must be set");
        // acknowledge: pop the entry and clear the flag -> the next sweep reports it again
        rw(R_LOGI, 32'h0);
        rw(R_STAT, 32'h2);
        idle(3);
        chk(!irq_ue, "irq_ue must drop after the flag is cleared");
        scrub_on;
        t = 0;
        while (!irq_ue && t < 30000) begin @(posedge clk); t = t + 1; end
        scrub_off;
        reg_read(R_STAT, st);
        $display("   after the firmware cleared the flag and popped the entry: irq_ue rose again %0d cycles later (next sweep), log level %0d", t, st[11:8]);
        chk(irq_ue && st[11:8] == 4'd1, "an acknowledged but unrepaired word must be reported again in the next sweep");
        // repair it by rewriting
        wr_full(w, d, 0);
        rw(R_LOGI, 32'h0); rw(R_STAT, 32'h7);
        set_ctrl(ctrl_sh & ~32'h2);
        clear_counters();
    endtask

    task r3c;
        int s0, fast, slow;
        scrub_off; heal_all; clear_all;
        $display("");
        $display("  R3c. SCRUB_INTERVAL and CTRL.SCRUB_EN control the scrubber (scrub operations counted over 2000 cycles)");
        scrub_on;
        s0 = dut.scrub_scanned; idle(2000); fast = dut.scrub_scanned - s0;
        rw(R_SINT, 32'd30000);
        idle(100);
        s0 = dut.scrub_scanned; idle(2000); slow = dut.scrub_scanned - s0;
        rw(R_SINT, 32'd16);
        idle(100);
        $display("      interval 16: %0d operations;  interval 30000: %0d operations", fast, slow);
        chk(fast >= 80, "with interval 16 the scrubber must run about one operation per 20 cycles");
        chk(slow <= 1, "with interval 30000 the scrubber must be almost idle");
        scrub_off;
        s0 = dut.scrub_scanned; idle(1000); fast = dut.scrub_scanned - s0;
        $display("      SCRUB_EN = 0: %0d operations in 1000 cycles", fast);
        chk(fast == 0, "with SCRUB_EN = 0 the scrubber must not start new operations");
        scrub_on;
        s0 = dut.scrub_scanned; idle(1000); fast = dut.scrub_scanned - s0;
        $display("      SCRUB_EN = 1 again: %0d operations in 1000 cycles", fast);
        chk(fast > 20, "setting SCRUB_EN must restart the scrubber");
        wait_scanned(DEPTH + 4, 20000);
        scrub_off;
        begin
            logic [31:0] sw, sr;
            reg_read(R_SSWP, sw); reg_read(R_SREP, sr);
            $display("      SCRUB_SWEEPS register = %0d (the scrubber's own count: %0d), SCRUB_REPAIRED = %0d", sw, dut.scrub_sweeps, sr);
            chk(sw === dut.scrub_sweeps && sw >= 1, "SCRUB_SWEEPS must show the completed sweeps");
            chk(sr === dut.scrub_repaired, "SCRUB_REPAIRED must equal the scrubber's own count");
        end
    endtask

    // =========================================================================
    // R4: the error-injection port
    // =========================================================================
    task r4a;
        int w, off, kind, ce0, ue0, ce1, ue1, ic0, ic1, nshow;
        logic [31:0] d, v, got, e;
        logic [1:0]  resp, er;
        logic [38:0] before_w, after_w, m;
        int b1, b2, b3;
        scrub_off; heal_all; clear_all;
        $display("  R4a. Register-driven injection: INJ_ADDR, INJ_MASK_LO/HI, then INJ_CTRL.GO (random masks, 12 words)");
        $display("      word  addr offset   mask (39 bits)   stored before  stored after   exactly mask flipped?   read result");
        nshow = 0;
        for (int i = 0; i < 12; i++) begin
            w = rand_word(0);
            wr_full(w, $urandom, 0);
            off = $urandom_range(0, 3);                       // the low address bits must be ignored
            kind = $urandom_range(0, 4);
            b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); b3 = rbit(b1, b2);
            case (kind)
                0: m = bitmask(b1, -1, -1);
                1: m = bitmask($urandom_range(0, 31), -1, -1);          // a data bit
                2: m = bitmask($urandom_range(32, 38), -1, -1);         // a check bit
                3: m = bitmask(b1, b2, -1);
                default: m = bitmask(b1, b2, b3);
            endcase
            before_w = peek(w);
            read_counts(ce0, ue0);
            reg_read(R_ICNT, v); ic0 = int'(v);
            rw(R_IADR, addr_of(w, off));
            rw(R_IMLO, m[31:0]);
            rw(R_IMHI, {25'd0, m[38:32]});
            rw(R_ICTL, 32'h1);                                  // GO
            wait_inj_idle();
            after_w = peek(w);
            wstate[w] = 3;
            read_counts(ce1, ue1);
            reg_read(R_ICNT, v); ic1 = int'(v);
            chk((before_w ^ after_w) === m, "the injection must flip exactly the bits of the mask");
            chk(ce1 == ce0 && ue1 == ue0, "an injection must not count as an error event");
            chk(ic1 == ic0 + 1, "INJ_COUNT must count the injection");
            rd_expect(w, 0, got, resp, e, er);
            if (nshow < 6) begin
                $display("      %3d   +%0d    %h     %h     %h      %s              %s", w, off, m, before_w, after_w,
                         pick((before_w ^ after_w) === m, "yes", "NO "),
                         pick(er === 2'b10, "uncorrectable (SLVERR)",
                              pick(popc39(m) == 1, $sformatf("single error, corrected at %s", bitname(gd_pos(g_decode(after_w)))),
                                   $sformatf("3 flips look like one: wrongly 'corrected' at %s", bitname(gd_pos(g_decode(after_w)))))));
                nshow = nshow + 1;
            end
        end
        $display("      all 12 injections flipped exactly the mask, ignored the low address bits and were not counted as errors");
        heal_all;
    endtask

    task r4b;
        int w, ones, ok1, ok2, nshow;
        logic [31:0] v;
        logic [38:0] before_w, after_w;
        int c1, c2;
        scrub_off; heal_all; clear_all;
        $display("");
        $display("  R4b. Random injection (INJ_CTRL.RANDOM): one random bit, or two distinct random bits with DOUBLE");
        ok1 = 0; ok2 = 0; nshow = 0;
        for (int i = 0; i < 40; i++) begin
            w = rand_word(0);
            wr_full(w, $urandom, 0);
            before_w = peek(w);
            rw(R_IADR, addr_of(w, 0));
            if (i < 20) rw(R_ICTL, 32'h3);                       // GO | RANDOM
            else        rw(R_ICTL, 32'h7);                       // GO | RANDOM | DOUBLE
            wait_inj_idle();
            after_w = peek(w);
            ones = popc39(before_w ^ after_w);
            if (i < 20) begin if (ones == 1) ok1 = ok1 + 1; end
            else        begin if (ones == 2) ok2 = ok2 + 1; end
            if (nshow < 6 && (i < 3 || (i >= 20 && i < 23))) begin
                $display("      %s: mask %h  (%0d bit%s flipped)", pick(i < 20, "single", "double"), before_w ^ after_w, ones, pick(ones == 1, "", "s"));
                nshow = nshow + 1;
            end
            wstate[w] = 3;
            heal_all;
        end
        rw(R_ICTL, 32'h0);
        $display("      20 random single injections: %0d flipped exactly one bit;  20 random double injections: %0d flipped exactly two", ok1, ok2);
        chk(ok1 == 20, "a random single injection must flip exactly one bit");
        chk(ok2 == 20, "a random double injection must flip exactly two distinct bits");
    endtask

    task r4c;
        int w, ic0, ic1;
        logic [31:0] v;
        logic [38:0] before_w, after_w;
        scrub_off; heal_all; clear_all;
        $display("");
        $display("  R4c. Board buttons (one-cycle pulses hw_inj_single / hw_inj_double) inject at INJ_ADDR");
        w = rand_word(0);
        wr_full(w, $urandom, 0);
        rw(R_IADR, addr_of(w, 0));
        before_w = peek(w);
        @(posedge clk); hw_single <= 1; @(posedge clk); hw_single <= 0;
        wait_inj_idle();
        after_w = peek(w);
        $display("      BTN single : word %0d mask %h (%0d bit)", w, before_w ^ after_w, popc39(before_w ^ after_w));
        chk(popc39(before_w ^ after_w) == 1, "the single-flip button must flip one bit");
        wr_full(w, $urandom, 0);
        before_w = peek(w);
        @(posedge clk); hw_double <= 1; @(posedge clk); hw_double <= 0;
        wait_inj_idle();
        after_w = peek(w);
        $display("      BTN double : word %0d mask %h (%0d bits)", w, before_w ^ after_w, popc39(before_w ^ after_w));
        chk(popc39(before_w ^ after_w) == 2, "the double-flip button must flip two bits");
        // a second pulse while an injection is running is ignored
        wr_full(w, $urandom, 0);
        reg_read(R_ICNT, v); ic0 = int'(v);
        before_w = peek(w);
        @(posedge clk); hw_single <= 1; @(posedge clk); hw_single <= 1; @(posedge clk); hw_single <= 0;
        wait_inj_idle();
        reg_read(R_ICNT, v); ic1 = int'(v);
        after_w = peek(w);
        $display("      two pulses on consecutive cycles: INJ_COUNT went up by %0d, %0d bit(s) flipped (the second was ignored: one injection at a time)", ic1 - ic0, popc39(before_w ^ after_w));
        chk(ic1 - ic0 == 1 && popc39(before_w ^ after_w) == 1, "a trigger during an injection must be ignored");
        wstate[w] = 3;
        heal_all;
    endtask

    task r4d;
        int wx, n_flips;
        logic [38:0] exp_w, m, before_w;
        logic [31:0] got, e, v;
        logic [1:0]  resp, er;
        bit done_inj;
        scrub_off; heal_all; clear_all;
        wx = rand_word(0);
        wr_full(wx, $urandom, 0);
        exp_w = peek(wx);
        $display("");
        $display("  R4d. Injections while the CPU is busy: 20 injections into word %0d during 150 CPU reads and writes of other words", wx);
        done_inj = 0;
        rw(R_IADR, addr_of(wx, 0));
        fork
            begin : injector_thread
                for (int i = 0; i < 20; i++) begin
                    m = bitmask($urandom_range(0, 38), -1, -1);
                    rw(R_IMLO, m[31:0]);
                    rw(R_IMHI, {25'd0, m[38:32]});
                    rw(R_ICTL, 32'h1);
                    wait_inj_idle();
                    exp_w = exp_w ^ m;
                end
                done_inj = 1;
            end
            begin : cpu_thread
                for (int i = 0; i < 150; i++) begin
                    int w;
                    w = rand_word(0);
                    while (w == wx) w = rand_word(0);
                    if ($urandom_range(0, 2) == 0) wr_full(w, $urandom, 0);
                    else if ($urandom_range(0, 1) == 0) wr_part(w, $urandom, 4'($urandom_range(1, 14)), 0, 0, resp);
                    else rd_check(w);
                end
            end
        join
        wstate[wx] = 3;
        chk(peek(wx) === exp_w, "the 20 injections must add up exactly (no injection lost or torn)");
        $display("      word %0d holds %h = the original XOR all 20 masks; every CPU access was correct meanwhile", wx, peek(wx));
        heal_all;
    endtask


    task inject_via_regs(input int w, input logic [38:0] m);
        rw(R_IADR, addr_of(w, 0));
        rw(R_IMLO, m[31:0]);
        rw(R_IMHI, {25'd0, m[38:32]});
        rw(R_ICTL, 32'h1);
        wait_inj_idle();
    endtask

    task r4e;
        int w, b1, b2, ce0, ue0, ce1, ue1, ce2, ue2, ce3, ue3;
        logic [38:0] before_w, m1, m2;
        logic [31:0] got, e;
        logic [1:0]  resp, er;
        scrub_off; heal_all; clear_all;
        w = rand_word(0);
        wr_full(w, $urandom, 0);
        before_w = peek(w);
        b1 = $urandom_range(0, 38); b2 = rbit(b1, -1);
        m1 = bitmask(b1, -1, -1); m2 = bitmask(b2, -1, -1);
        $display("");
        $display("  R4e. Injecting into a word that ALREADY has an error is not an error event either (word %0d, bits %s then %s)", w, bitname(b1), bitname(b2));
        read_counts(ce0, ue0);
        inject_via_regs(w, m1);
        read_counts(ce1, ue1);
        inject_via_regs(w, m2);                              // the controller reads a word that decodes with an error
        read_counts(ce2, ue2);
        wstate[w] = 2;
        $display("      counters before / after the 1st injection / after the 2nd injection: CE %0d/%0d/%0d, UE %0d/%0d/%0d",
                 ce0, ce1, ce2, ue0, ue1, ue2);
        chk(ce1 == ce0 && ue1 == ue0 && ce2 == ce0 && ue2 == ue0, "the injector reading a damaged word must not count as an error event");
        chk((peek(w) ^ before_w) === (m1 | m2), "two injections into the same word must add up");
        rd_expect(w, 0, got, resp, e, er);
        read_counts(ce3, ue3);
        $display("      a CPU read of the doubly damaged word: response %s, UE_COUNT %0d (+%0d)", resp_name(resp), ue3, ue3 - ue2);
        chk(resp === 2'b10 && ue3 == ue2 + 1 && ce3 == ce2, "the CPU read must be counted as exactly one uncorrectable error");
        heal_all;
    endtask

    // =========================================================================
    // R5: the uncorrectable-error interrupt, end to end
    // =========================================================================
    task r5;
        int w, b1, b2, t, ce, ue;
        logic [31:0] d, got, e, st;
        logic [1:0]  resp, er;
        scrub_off; heal_all; clear_all;
        set_ctrl(ctrl_sh | 32'h2);
        w = rand_word(0); b1 = $urandom_range(0, 38); b2 = rbit(b1, -1); d = $urandom;
        wr_full(w, d, 0);
        $display("  R5. Interrupt sequence (CTRL.IRQ_UE_EN = 1), the way firmware would use it");
        chk(!irq_ue, "no interrupt without an error");
        $display("   1. no error yet: irq_ue = %0d", irq_ue);
        inject2(w, b1, b2);
        $display("   2. radiation flips %s and %s of word %0d", bitname(b1), bitname(b2), w);
        rd_expect(w, 0, got, resp, e, er);
        t = 0;
        while (!irq_ue && t < 10) begin @(posedge clk); t = t + 1; end
        $display("   3. the CPU reads the word: response %s, and irq_ue = %0d (%0d cycle(s) after the response)", resp_name(resp), irq_ue, t);
        chk(irq_ue && resp === 2'b10, "an uncorrectable read must raise irq_ue together with the SLVERR response");
        reg_read(R_STAT, st);
        $display("   4. handler reads STATUS = %h (UE_SEEN = %0d), LOG_ADDR/LOG_INFO say which word, then acknowledges:", st, st[1]);
        rw(R_LOGI, 32'h0);
        rw(R_STAT, 32'h2);
        idle(2);
        $display("   5. UE_SEEN cleared -> irq_ue = %0d", irq_ue);
        chk(!irq_ue, "acknowledging must drop the interrupt");
        rd_expect(w, 0, got, resp, e, er);
        idle(3);
        $display("   6. the word is still damaged: reading it again raises the interrupt again (irq_ue = %0d)", irq_ue);
        chk(irq_ue, "a still-damaged word must raise the interrupt again");
        rw(R_LOGI, 32'h0); rw(R_STAT, 32'h7);
        wr_full(w, d, 0);
        rd_expect(w, 0, got, resp, e, er);
        idle(3);
        $display("   7. firmware rewrites the word (full write): it reads back clean, irq_ue = %0d", irq_ue);
        chk(!irq_ue && resp === 2'b00, "after the repair no interrupt may be raised");
        chk(!irq_ce, "irq_ce must not react to uncorrectable errors");
        read_counts(ce, ue);
        $display("      UE_COUNT = %0d, CE_COUNT = %0d", ue, ce);
        set_ctrl(ctrl_sh & ~32'h2);
    endtask

    // =========================================================================
    // R6: random consistency stress
    // =========================================================================
    task r6;
        int n, w, r, op, b, mon_ce0, mon_ue0, hw_ce, hw_ue, n_inj1, n_inj2, n_pop, n_ack, n_rd, n_wr, n_slv;
        logic [31:0] d, got, e, st, v, ce_v, ue_v;
        logic [1:0]  resp, er, wresp;
        logic [3:0]  s;
        scrub_off; heal_all; clear_all;
        mon_ce0 = ev_ce_cpu + ev_ce_scr;
        mon_ue0 = ev_ue_cpu + ev_ue_scr;
        n_inj1 = 0; n_inj2 = 0; n_pop = 0; n_ack = 0; n_rd = 0; n_wr = 0; n_slv = 0;
        $display("  %0d random operations: CPU reads and writes (full and partial), random single/double injections through the", 2500);
        $display("  injection registers, a 'firmware' that pops the log and acknowledges flags at random times, scrubber running fast.");
        $display("  At the end the hardware counters must equal an independent count of the events seen at the controller.");
        scrub_on;
        for (n = 1; n <= 2500; n++) begin
            r = $urandom_range(0, 99);
            if (r < 70) w = $urandom_range(0, 23); else w = $urandom_range(0, LAST);
            op = $urandom_range(0, 99);
            if (op < 30) begin
                rd_check(w); n_rd = n_rd + 1;
            end else if (op < 45) begin
                wr_full(w, $urandom, $urandom_range(0, 3)); n_wr = n_wr + 1;
            end else if (op < 60) begin
                s = $urandom_range(1, 14);
                wr_part(w, $urandom, s, 0, $urandom_range(0, 3), wresp);
                if (wresp === 2'b10) n_slv = n_slv + 1;
                n_wr = n_wr + 1;
            end else if (op < 74) begin
                if (wstate[w] == 0) begin
                    rw(R_IADR, addr_of(w, 0)); rw(R_ICTL, 32'h3);        // GO | RANDOM: one random bit
                    wait_inj_idle();
                    wstate[w] = 1; n_inj1 = n_inj1 + 1;
                end
            end else if (op < 77) begin
                if (wstate[w] == 0) begin
                    rw(R_IADR, addr_of(w, 0)); rw(R_ICTL, 32'h7);        // GO | RANDOM | DOUBLE
                    wait_inj_idle();
                    wstate[w] = 2; n_inj2 = n_inj2 + 1;
                end
            end else if (op < 88) begin
                reg_read(R_STAT, st);                                   // the "firmware"
                if (st[11:8] != 0) begin rw(R_LOGI, 32'h0); n_pop = n_pop + 1; end
                if (st[2:0] != 0) begin rw(R_STAT, st & 32'h7); n_ack = n_ack + 1; end
            end else begin
                idle($urandom_range(20, 150));
            end
            if (n % 500 == 0)
                $display("    ... %4d / 2500 operations done, failures so far %0d, injected so far %0d single + %0d double", n, part_errors[6], n_inj1, n_inj2);
        end
        rw(R_ICTL, 32'h0);
        // repair what the CPU cannot: rewrite the double-error words, then let one more sweep clear the singles
        for (int i = 0; i < DEPTH; i++) if (wstate[i] == 2) wr_full(i, $urandom, 0);
        wait_scanned(DEPTH + 4, 80000);
        scrub_off;
        idle(60);
        reg_read(R_CE, ce_v); reg_read(R_UE, ue_v);
        hw_ce = int'(ce_v); hw_ue = int'(ue_v);
        $display("");
        $display("    operations: %0d reads, %0d writes (%0d refused with SLVERR), injections %0d single + %0d double, %0d log pops, %0d flag acknowledgements",
                 n_rd, n_wr, n_slv, n_inj1, n_inj2, n_pop, n_ack);
        $display("    hardware counters: CE_COUNT = %0d, UE_COUNT = %0d", hw_ce, hw_ue);
        $display("    independent count of the controller's events: corrected = %0d, uncorrectable = %0d", ev_ce_cpu + ev_ce_scr - mon_ce0, ev_ue_cpu + ev_ue_scr - mon_ue0);
        chk(hw_ce == ev_ce_cpu + ev_ce_scr - mon_ce0, "CE_COUNT must equal the number of corrected-error events");
        chk(hw_ue == ev_ue_cpu + ev_ue_scr - mon_ue0, "UE_COUNT must equal the number of uncorrectable-error events");
        for (int i = 0; i < DEPTH; i++) begin
            wstate[i] = 0;
            chk(peek(i) === g_encode(ref_data[i]), "after the last sweep every word must be the model's codeword of the expected data");
        end
        $display("    final check: all %0d words equal the model's codeword of the expected data", DEPTH);
        chk(n_inj1 > 40 && n_inj2 > 5, "the random run must have injected a meaningful number of errors");
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    integer seed;
    integer seed_used;
    integer seed_dummy;
    task part_row(input int n, input string text);
        $display("   %0d    %-62s %6d   %6d     %s", n, text, part_checks[n], part_errors[n], pick(part_errors[n] == 0, "PASS", "FAIL"));
    endtask

    initial begin
        for (int i = 0; i < 10; i++) begin part_checks[i] = 0; part_errors[i] = 0; end
        for (int i = 0; i < DEPTH; i++) begin ref_data[i] = 32'h0; wstate[i] = 0; end
        seed = SEED_DEFAULT;
        if ($value$plusargs("seed=%d", seed)) begin
            $display("(seed given on the command line)");
        end
        seed_used = seed;
        seed_dummy = $urandom(seed);

        $display("==============================================================================");
        $display(" REGISTER / COUNTER / LOG / INTERRUPT / INJECTION TESTBENCH - P12 ECC memory system");
        $display("==============================================================================");
        $display(" random seed = %0d   (re-run with +seed=<n> to repeat exactly)   RAM = %0d words", seed_used, DEPTH);
        $display("");
        $display(" What is tested: mem_subsystem's register window (0x4000_0000) next to the ECC data path.");
        $display("   error events --> CE/UE counters, sticky flags, error log (8 entries), interrupt lines irq_ue / irq_ce");
        $display("   registers    --> scrubber enable and interval, error injection (address, mask, random, buttons)");
        $display(" [RADIATION] = the testbench flips stored bits behind the controller's back;  [REGISTERS] = values read back");
        $display(" through the AXI register port;  [INTERRUPT] = the irq lines;  [LOG] = the error-log FIFO.");

        idle(3); rst_n = 1; idle(3);

        begin_part(1, "Reset values and plain registers");
        r1();
        end_part();

        begin_part(2, "Counters, flags, log and interrupt gating for errors found by the CPU");
        r2a(); r2b(); r2c(); r2d();
        end_part();

        begin_part(3, "Errors found by the scrubber, and scrubber control");
        r3a(); r3b(); r3c();
        end_part();

        begin_part(4, "The error-injection port");
        r4a(); r4b(); r4c(); r4d(); r4e();
        end_part();

        begin_part(5, "The uncorrectable-error interrupt");
        r5();
        end_part();

        begin_part(6, "Random consistency stress");
        r6();
        end_part();

        idle(5);
        $display("");
        $display("==============================================================================");
        $display(" SUMMARY");
        $display("==============================================================================");
        $display("  part  what                                                              checks  failures  result");
        part_row(1, "reset values, scratch registers, strobes, read-only/unmapped registers");
        part_row(2, "counters, sticky flags, log FIFO, overrun, CLEAR, interrupt gating");
        part_row(3, "scrubber events in the log, repeat reports, interval and enable");
        part_row(4, "injection: exact masks, random single/double, buttons, concurrency");
        part_row(5, "uncorrectable-error interrupt sequence");
        part_row(6, "random stress: counters equal the independent event count");
        $display("  -----------------------------------------------------------------------------------------");
        $display("  AXI response-rule violations seen by the monitor : %0d", prot_viol);
        chk(prot_viol == 0, "BVALID/RVALID must stay asserted with stable data until READY");
        $display("");
        if (errors == 0) begin
            $display("PASS: %0d checks, 0 failures  (seed %0d)", checks, seed_used);
            $display("  What this run showed: errors found by CPU reads and by the scrubber are counted and logged with address,");
            $display("  syndrome and bit; the interrupt line follows the flag and its enable; the injection port flips exactly the");
            $display("  requested (or random) bits without counting as an error; the scrubber is controlled by the registers.");
        end else begin
            $display("FAIL: %0d failures in %0d checks  (seed %0d)", errors, checks, seed_used);
        end
        $display("==============================================================================");
        $finish;
    end

    initial begin
        #800ms;
        $display("TIMEOUT");
        $finish;
    end
endmodule
