`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_ecc_codec: every encoder and decoder variant against the golden-model vectors,
// with a readable console trace.
//
// Each vector in tb/vectors/ecc_vectors.hex describes one test:
//     data word -> ENCODE -> stored codeword -> INJECT error mask -> READ back -> DECODE
// (the file stores the mask, the corrupted codeword and the golden-model results).
//
// PHASE A  "show me"   a few vectors of every kind (clean, single data/check bit,
//          double error data+data / data+check / check+check, triple) are applied one at
//          a time. For each one the console prints the input data, the encoder result,
//          the injected error, the codeword read back, and the decoder outputs
//          (RTL vs golden, field by field). All 4 encoders and 6 decoders are compared.
//          One machine-readable line per vector goes to the log file, so that
//          model/compare_log.py can recompute everything in Python and print it side by side.
// PHASE B  "prove it"  all vectors are streamed back-to-back (one per clock, silently)
//          through all 4 encoders and 6 decoders, including the pipelined decoders.
//
// Options (edit the parameters below, or pass plusargs to xsim / vvp):
//   SHOW_PER_KIND / +show=N     vectors shown per kind in phase A (default 3; 0 = skip phase A;
//                               a huge number such as 100000 = every vector, use with +console=0)
//   SHOW_DUT      / +dut=K      decoder shown in detail: 0..3 = IMPL 0..3 (PIPE 0),
//                               4 = IMPL 2 PIPE 1, 5 = IMPL 3 PIPE 1       (default 2)
//   CONSOLE       / +console=0  1 = print the cards on the console, 0 = log file only
//   LOG_FILE                    log file name (relative to the simulator's run folder,
//                               or give a full path with forward slashes)
// Vivado: Simulation Settings -> xsim.simulate.xsim.more_options -> -testplusarg show=5
// -----------------------------------------------------------------------------
module tb_ecc_codec;
    parameter int SHOW_PER_KIND = 3;
    parameter int SHOW_DUT      = 2;
    parameter int CONSOLE       = 1;
    parameter     LOG_FILE      = "ecc_tb_log.txt";

    localparam int VMAX = 65536;
    localparam int NDEC = 6;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    // decoder instance k -> IMPL / PIPE
    function automatic int dimpl(input int k);
        case (k) 0: return 0; 1: return 1; 2: return 2; 3: return 3; 4: return 2; default: return 3; endcase
    endfunction
    function automatic int dpipe(input int k);
        return (k >= 4) ? 1 : 0;
    endfunction
    function automatic string dec_name(input int k);
        return $sformatf("IMPL %0d, PIPE %0d", dimpl(k), dpipe(k));
    endfunction

    // ---------------- vectors ----------------
    // [166:128] error mask  [127:89] cw_in  [88:57] data_out  [56:18] cw_out
    // [17:11] syndrome  [10] ce  [9] ue  [8:3] err_pos
    logic [167:0] vec [0:VMAX-1];
    function automatic logic [38:0] f_mask (input logic [167:0] v); return v[166:128]; endfunction
    function automatic logic [38:0] f_cwin (input logic [167:0] v); return v[127:89];  endfunction
    function automatic logic [31:0] f_dout (input logic [167:0] v); return v[88:57];   endfunction
    function automatic logic [38:0] f_cwout(input logic [167:0] v); return v[56:18];   endfunction
    function automatic logic  [6:0] f_syn  (input logic [167:0] v); return v[17:11];   endfunction
    function automatic logic        f_ce   (input logic [167:0] v); return v[10];      endfunction
    function automatic logic        f_ue   (input logic [167:0] v); return v[9];       endfunction
    function automatic logic  [5:0] f_pos  (input logic [167:0] v); return v[8:3];     endfunction

    // ---------------- helpers: kinds, labels, text ----------------
    function automatic int popc(input logic [38:0] x);
        int n;
        n = 0;
        for (int i = 0; i < 39; i++) n += int'(x[i]);
        return n;
    endfunction

    // 0 clean, 1 single data, 2 single check, 3 double d+d, 4 double d+c, 5 double c+c, 6 triple, 7 other
    function automatic int kind_of(input logic [38:0] m);
        int n, nd;
        n  = popc(m);
        nd = popc({7'b0, m[31:0]});
        if (n == 0) return 0;
        if (n == 1) return (nd == 1) ? 1 : 2;
        if (n == 2) return (nd == 2) ? 3 : ((nd == 1) ? 4 : 5);
        if (n == 3) return 6;
        return 7;
    endfunction
    function automatic string kind_name(input int k);
        case (k)
            0: return "clean (no error)";
            1: return "single error, data bit";
            2: return "single error, check bit";
            3: return "double error, data+data";
            4: return "double error, data+check";
            5: return "double error, check+check";
            6: return "triple error";
            default: return "other";
        endcase
    endfunction
    function automatic string kind_tag(input int k);
        case (k)
            0: return "clean";
            1: return "single-data";
            2: return "single-check";
            3: return "double-dd";
            4: return "double-dc";
            5: return "double-cc";
            6: return "triple";
            default: return "other";
        endcase
    endfunction

    function automatic string bit_label(input int j);
        if (j < 32) return $sformatf("d%0d", j);
        return $sformatf("c%0d", j - 32);
    endfunction
    function automatic string flipped_list(input logic [38:0] m);
        string s;
        bit first;
        s = "";
        first = 1'b1;
        for (int j = 0; j < 39; j++) begin
            if (m[j]) begin
                if (first) s = bit_label(j);
                else       s = $sformatf("%s %s", s, bit_label(j));
                first = 1'b0;
            end
        end
        if (first) s = "none";
        return s;
    endfunction
    function automatic string decision_text(input logic [38:0] m, input logic ce, input logic ue,
                                            input logic [5:0] pos, input logic [6:0] syn);
        if (!ce && !ue) return "no error detected: data passed through unchanged";
        if (ce) begin
            if (popc(m) >= 3)
                return $sformatf("single error at %s (codeword bit %0d) corrected: syndrome equals that bit's column of H  ** MISCORRECTION: %0d errors were injected, decoder believes 1 **",
                                 bit_label(int'(pos)), pos, popc(m));
            return $sformatf("single error at %s (codeword bit %0d) corrected: syndrome equals that bit's column of H",
                             bit_label(int'(pos)), pos);
        end
        if ((popc({32'b0, syn}) % 2) == 0)
            return "even-weight syndrome => 2 errors: detected, NOT correctable, data left unchanged";
        return "odd-weight syndrome matching no column => 3+ errors: detected, NOT correctable, data left unchanged";
    endfunction

    // string selector without a literal ternary (a ternary pads the shorter literal)
    function automatic string pick(input bit c, input string a, input string b);
        if (c) return a;
        return b;
    endfunction

    // ---------------- DUTs ----------------
    logic [31:0] enc_data = '0;
    logic [38:0] cw_in    = '0;
    logic        in_valid = 0;

    logic [38:0] enc_cw [0:3];
    genvar g;
    generate
        for (g = 0; g < 4; g++) begin : g_enc
            ecc_enc #(.IMPL(g)) u_enc (.data_in(enc_data), .cw_out(enc_cw[g]));
        end
    endgenerate

    logic        d_valid [0:NDEC-1];
    logic        d_ce    [0:NDEC-1];
    logic        d_ue    [0:NDEC-1];
    logic [31:0] d_data  [0:NDEC-1];
    logic [38:0] d_cw    [0:NDEC-1];
    logic  [6:0] d_syn   [0:NDEC-1];
    logic  [5:0] d_pos   [0:NDEC-1];

    // explicit instances (instance k uses dimpl(k) / dpipe(k))
    ecc_dec #(.IMPL(0), .PIPE(0)) u_dec0 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[0]), .data_out(d_data[0]), .cw_out(d_cw[0]),
        .syndrome(d_syn[0]), .ce(d_ce[0]), .ue(d_ue[0]), .err_pos(d_pos[0]));
    ecc_dec #(.IMPL(1), .PIPE(0)) u_dec1 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[1]), .data_out(d_data[1]), .cw_out(d_cw[1]),
        .syndrome(d_syn[1]), .ce(d_ce[1]), .ue(d_ue[1]), .err_pos(d_pos[1]));
    ecc_dec #(.IMPL(2), .PIPE(0)) u_dec2 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[2]), .data_out(d_data[2]), .cw_out(d_cw[2]),
        .syndrome(d_syn[2]), .ce(d_ce[2]), .ue(d_ue[2]), .err_pos(d_pos[2]));
    ecc_dec #(.IMPL(3), .PIPE(0)) u_dec3 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[3]), .data_out(d_data[3]), .cw_out(d_cw[3]),
        .syndrome(d_syn[3]), .ce(d_ce[3]), .ue(d_ue[3]), .err_pos(d_pos[3]));
    ecc_dec #(.IMPL(2), .PIPE(1)) u_dec4 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[4]), .data_out(d_data[4]), .cw_out(d_cw[4]),
        .syndrome(d_syn[4]), .ce(d_ce[4]), .ue(d_ue[4]), .err_pos(d_pos[4]));
    ecc_dec #(.IMPL(3), .PIPE(1)) u_dec5 (
        .clk, .rst_n, .in_valid, .cw_in,
        .out_valid(d_valid[5]), .data_out(d_data[5]), .cw_out(d_cw[5]),
        .syndrome(d_syn[5]), .ce(d_ce[5]), .ue(d_ue[5]), .err_pos(d_pos[5]));

    // ---------------- pure comparison functions ----------------
    // Phase A: the encoder gets the ORIGINAL data; its output must equal the stored codeword.
    // Phase B: the encoder gets the RECEIVED data; check bits XOR received check bits = syndrome.
    function automatic bit enc_match(input int k, input logic [167:0] v, input bit phase_a);
        logic [38:0] orig, cwi, e;
        cwi  = f_cwin(v);
        orig = cwi ^ f_mask(v);
        e    = enc_cw[k];
        if (phase_a) return (e === orig);
        return (e[31:0] === cwi[31:0]) && ((e[38:32] ^ cwi[38:32]) === f_syn(v));
    endfunction

    function automatic bit dec_match(input int k, input logic [167:0] v);
        return (d_valid[k] === 1'b1) && (d_data[k] === f_dout(v)) && (d_cw[k] === f_cwout(v)) &&
               (d_syn[k] === f_syn(v)) && (d_ce[k] === f_ce(v)) && (d_ue[k] === f_ue(v)) &&
               (d_pos[k] === f_pos(v));
    endfunction

    function automatic string dec_line(input int k);
        return $sformatf("valid=%b syn=%b ce=%b ue=%b pos=%0d data_out=%h cw_out=%h",
                         d_valid[k], d_syn[k], d_ce[k], d_ue[k], d_pos[k], d_data[k], d_cw[k]);
    endfunction

    // ---------------- bookkeeping ----------------
    int enc_err [0:3];
    int dec_err [0:NDEC-1];
    int checks_a, checks_b, vec_a;
    int show_n, show_dut, show_enc, console_on;
    int cnt [0:7];
    int seen [0:7];
    int shown [0:7];
    int stride [0:7];
    int lf;

    task automatic count_enc(input int k, input logic [167:0] v, input bit phase_a, input int idx);
        if (!enc_match(k, v, phase_a)) begin
            if (enc_err[k] < 3)
                $display("  ERROR vector #%0d: encoder IMPL %0d gave %h for data %h (cw_in %h)",
                         idx, k, enc_cw[k], enc_data, f_cwin(v));
            enc_err[k] = enc_err[k] + 1;
        end
    endtask

    task automatic count_dec(input int k, input logic [167:0] v, input int idx);
        if (!dec_match(k, v)) begin
            if (dec_err[k] < 3)
                $display("  ERROR vector #%0d: decoder %s\n         got      %s\n         expected syn=%b ce=%b ue=%b pos=%0d data_out=%h cw_out=%h",
                         idx, dec_name(k), dec_line(k), f_syn(v), f_ce(v), f_ue(v), f_pos(v), f_dout(v), f_cwout(v));
            dec_err[k] = dec_err[k] + 1;
        end
    endtask

    // one "card" row: label, RTL value, golden value
    task automatic row(input string label, input string rtl, input string gold, input bit ok);
        if (console_on != 0)
            $display("          %-18s: %-24s %-24s %s", label, rtl, gold, pick(ok, "ok", "<-- MISMATCH"));
    endtask

    // ---------------- PHASE A: apply one vector, show everything ----------------
    task automatic run_one(input int idx);
        logic [167:0] v;
        logic [38:0]  cwi, orig, msk;
        logic [3:0]   enc_ok;
        logic [5:0]   dec_ok;
        int kd;
        string es, ds;
        v = vec[idx];
        cwi = f_cwin(v); msk = f_mask(v); orig = cwi ^ msk;
        kd = kind_of(msk);

        @(negedge clk);
        enc_data = orig[31:0];
        cw_in    = cwi;
        in_valid = 1'b1;
        @(negedge clk);                       // one clock so the pipelined decoders have their result

        for (int k = 0; k < 4; k++) begin
            enc_ok[k] = enc_match(k, v, 1'b1);
            count_enc(k, v, 1'b1, idx);
        end
        for (int k = 0; k < NDEC; k++) begin
            dec_ok[k] = dec_match(k, v);
            count_dec(k, v, idx);
        end
        checks_a = checks_a + 4 + NDEC;
        vec_a = vec_a + 1;

        es = ""; ds = "";
        for (int k = 0; k < 4; k++)    es = $sformatf("%s %s", es, pick(enc_ok[k], "OK", "BAD"));
        for (int k = 0; k < NDEC; k++) ds = $sformatf("%s %s", ds, pick(dec_ok[k], "OK", "BAD"));

        if (console_on != 0) begin
            $display("");
            $display("=== vector #%0d: %s =================================", idx, kind_name(kd));
            $display("  INPUT   data to store      : %h", orig[31:0]);
            $display("  ENCODE  stored codeword    : %h   (check bits %h)   encoders IMPL 0..3 vs golden:%s", orig, orig[38:32], es);
            $display("  INJECT  error mask         : %h   flipped bits: %s", msk, flipped_list(msk));
            $display("  READ    codeword read back : %h", cwi);
            $display("  DECODE  decoder %s%s", dec_name(show_dut), "              RTL (DUT)                golden");
        end
        row("syndrome (bin/hex)", $sformatf("%b / %h", d_syn[show_dut], d_syn[show_dut]),
                                  $sformatf("%b / %h", f_syn(v), f_syn(v)), d_syn[show_dut] === f_syn(v));
        row("ce / ue", $sformatf("%b / %b", d_ce[show_dut], d_ue[show_dut]),
                       $sformatf("%b / %b", f_ce(v), f_ue(v)),
                       (d_ce[show_dut] === f_ce(v)) && (d_ue[show_dut] === f_ue(v)));
        row("err_pos", $sformatf("%0d", d_pos[show_dut]), $sformatf("%0d", f_pos(v)), d_pos[show_dut] === f_pos(v));
        row("data_out", $sformatf("%h", d_data[show_dut]), $sformatf("%h", f_dout(v)), d_data[show_dut] === f_dout(v));
        row("cw_out", $sformatf("%h", d_cw[show_dut]), $sformatf("%h", f_cwout(v)), d_cw[show_dut] === f_cwout(v));
        if (console_on != 0) begin
            $display("  DECISION: %s", decision_text(msk, f_ce(v), f_ue(v), f_pos(v), f_syn(v)));
            $display("  data_out %s the stored data   |   all 6 decoders vs golden:%s   => %s",
                     pick(f_dout(v) === orig[31:0], "EQUALS", "DIFFERS FROM"), ds,
                     pick(enc_ok === 4'hF && dec_ok === 6'h3F, "PASS", "FAIL"));
        end

        if (lf != 0)
            $fdisplay(lf, "VEC idx=%0d kind=%s data=%h mask=%h cw_in=%h enc=%h syn=%h ce=%b ue=%b pos=%0d dout=%h cwout=%h",
                      idx, kind_tag(kd), orig[31:0], msk, cwi, enc_cw[show_enc],
                      d_syn[show_dut], d_ce[show_dut], d_ue[show_dut], d_pos[show_dut],
                      d_data[show_dut], d_cw[show_dut]);
    endtask

    // ---------------- main ----------------
    initial begin
        int n, old_fmt, kd, occ, total_err, total_checks;
        logic [167:0] prev;
        logic [38:0] cwi;

        for (int k = 0; k < 4; k++) enc_err[k] = 0;
        for (int k = 0; k < NDEC; k++) dec_err[k] = 0;
        for (int k = 0; k < 8; k++) begin cnt[k] = 0; seen[k] = 0; shown[k] = 0; stride[k] = 1; end
        checks_a = 0; checks_b = 0; vec_a = 0;
        show_n = SHOW_PER_KIND; show_dut = SHOW_DUT; console_on = CONSOLE;
        if ($value$plusargs("show=%d", show_n))       ;
        if ($value$plusargs("dut=%d", show_dut))      ;
        if ($value$plusargs("console=%d", console_on)) ;
        if (show_dut < 0 || show_dut >= NDEC) show_dut = 2;
        show_enc = dimpl(show_dut);

        $readmemh("ecc_vectors.hex", vec);
        n = 0;
        while (n < VMAX && !$isunknown(vec[n])) n++;
        if (n == 0) begin
            $display("FAIL: ecc_vectors.hex not found or empty");
            $finish;
        end

        // pass 1: count vectors per kind; detect the old 128-bit vector format (no mask stored)
        old_fmt = 0;
        for (int i = 0; i < n; i++) begin
            cnt[kind_of(f_mask(vec[i]))] = cnt[kind_of(f_mask(vec[i]))] + 1;
            if (f_mask(vec[i]) == 0 && (f_ce(vec[i]) || f_ue(vec[i]))) old_fmt = old_fmt + 1;
        end
        if (old_fmt > 0) begin
            $display("FAIL: ecc_vectors.hex is in the OLD format (no error mask stored).");
            $display("      Replace it with the new file, or run:  python model/gen.py --vectors-only");
            $finish;
        end

        lf = $fopen(LOG_FILE, "w");
        if (lf == 0) $display("WARNING: could not open log file %0s (no log will be written)", LOG_FILE);
        else begin
            $fdisplay(lf, "# tb_ecc_codec log: one line per vector shown in phase A");
            $fdisplay(lf, "# decoder shown = %0s, encoder shown = IMPL %0d", dec_name(show_dut), show_enc);
        end

        $display("========================================================================");
        $display("tb_ecc_codec: %0d golden-model vectors loaded", n);
        $display("  every vector = data word -> ENCODE -> INJECT error mask -> READ -> DECODE");
        $display("  encoders: IMPL 0 ref, 1 flat, 2 CSE, 3 tree");
        $display("  decoders: IMPL 0-3 (PIPE 0), IMPL 2 and 3 (PIPE 1)");
        $display("  detail shown for decoder %s; log file: %0s", dec_name(show_dut), LOG_FILE);
        $display("========================================================================");
        $display("Vectors in the file, by kind (shown in phase A = up to %0d per kind):", show_n);
        for (int k = 0; k < 7; k++) begin
            stride[k] = (show_n > 0 && cnt[k] > show_n) ? (cnt[k] / show_n) : 1;
            $display("  %-27s %6d vectors", kind_name(k), cnt[k]);
        end

        repeat (2) @(posedge clk);
        rst_n = 1;

        // ---------------- PHASE A ----------------
        $display("");
        $display("########################  PHASE A: selected vectors, step by step  ########################");
        if (show_n > 0) begin
            for (int i = 0; i < n; i++) begin
                kd  = kind_of(f_mask(vec[i]));
                occ = seen[kd];
                seen[kd] = seen[kd] + 1;
                if (shown[kd] < show_n && (occ % stride[kd]) == (stride[kd] / 2)) begin
                    shown[kd] = shown[kd] + 1;
                    run_one(i);
                end
            end
        end
        $display("");
        $display("Phase A: %0d vectors applied one at a time, %0d checks.", vec_a, checks_a);

        // ---------------- PHASE B ----------------
        $display("");
        $display("########################  PHASE B: all %0d vectors streamed, one per clock  ###########", n);
        for (int i = 0; i <= n; i++) begin
            @(negedge clk);
            // pipelined decoders now show the result for the previous vector
            if (i > 0) begin
                for (int k = 0; k < NDEC; k++)
                    if (dpipe(k) == 1) begin count_dec(k, prev, i - 1); checks_b = checks_b + 1; end
            end
            if (i < n) begin
                cwi = f_cwin(vec[i]);
                enc_data = cwi[31:0];                  // encoders see the received data
                cw_in    = cwi;
                in_valid = 1'b1;
                #1;
                for (int k = 0; k < 4; k++) begin count_enc(k, vec[i], 1'b0, i); checks_b = checks_b + 1; end
                for (int k = 0; k < NDEC; k++)
                    if (dpipe(k) == 0) begin count_dec(k, vec[i], i); checks_b = checks_b + 1; end
                prev = vec[i];
                if ((i + 1) % 10000 == 0) $display("  progress: %0d / %0d vectors", i + 1, n);
            end
        end

        total_err = 0;
        $display("");
        $display("------------------------------------------------------------------------");
        for (int k = 0; k < 4; k++) begin
            $display("  encoder IMPL %0d          : %0d errors", k, enc_err[k]);
            total_err = total_err + enc_err[k];
        end
        for (int k = 0; k < NDEC; k++) begin
            $display("  decoder IMPL %0d PIPE %0d   : %0d errors", dimpl(k), dpipe(k), dec_err[k]);
            total_err = total_err + dec_err[k];
        end
        total_checks = checks_a + checks_b;
        $display("------------------------------------------------------------------------");
        $display("  phase A %0d checks + phase B %0d checks", checks_a, checks_b);
        if (total_err == 0) $display("PASS: %0d checks, 0 errors", total_checks);
        else                $display("FAIL: %0d errors in %0d checks", total_err, total_checks);
        $display("========================================================================");
        if (lf != 0) $fclose(lf);
        $finish;
    end
endmodule
