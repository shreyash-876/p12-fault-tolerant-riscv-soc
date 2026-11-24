`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_daec_codec: every SEC-DED-DAEC encoder and decoder variant against the golden-model vectors in
// tb/vectors/daec_vectors.hex (made by model/gen_daec.py from model/daec.py).
//
//   encoders  IMPL 0 (reference), 1 flat, 2 CSE, 3 tree          (combinational)
//   decoders  k = 0..3 : IMPL k, PIPE 0                          (combinational)
//             k = 4    : IMPL 2, PIPE 1                          (one register stage, latency 1)
//
// Vector layout: [166:128] mask  [127:89] cw_in  [88:57] data_out  [56:18] cw_out  [17:11] syndrome
//                [10] ce  [9] ue  [8:3] err_pos  [2] ae         (original codeword = cw_in XOR mask)
//
//   PHASE 1  all vectors back-to-back, one per clock.
//   PHASE 2  all vectors again with random idle cycles (in_valid = 0, garbage inputs) in between, to prove that
//            out_valid follows in_valid and that nothing leaks from an idle cycle into a valid one.
// Checked for each decoder: out_valid, data_out, cw_out, syndrome, ce, ae, ue, err_pos. For each encoder: cw_out.
// Option: +seed=N changes the random idle pattern.
// -----------------------------------------------------------------------------
module tb_daec_codec;
    localparam int VMAX = 65536;
    localparam int NENC = 4;
    localparam int NDEC = 5;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    function automatic int dimpl(input int k);
        case (k) 0: return 0; 1: return 1; 2: return 2; 3: return 3; default: return 2; endcase
    endfunction
    function automatic int dpipe(input int k);
        return (k == 4) ? 1 : 0;
    endfunction

    logic [167:0] vec [0:VMAX-1];

    logic         in_valid;
    logic  [38:0] cw_in;
    logic  [31:0] data_in;

    // encoders
    logic  [38:0] enc_out [0:NENC-1];
    for (genvar k = 0; k < NENC; k++) begin : g_enc
        daec_enc #(.IMPL(k)) u_enc (.data_in(data_in), .cw_out(enc_out[k]));
    end

    // decoders
    logic [NDEC-1:0] ov, ce, ae, ue;
    logic  [31:0] dout  [0:NDEC-1];
    logic  [38:0] cwout [0:NDEC-1];
    logic   [6:0] syn   [0:NDEC-1];
    logic   [5:0] pos   [0:NDEC-1];
    for (genvar k = 0; k < NDEC; k++) begin : g_dec
        daec_dec #(.IMPL(dimpl(k)), .PIPE(dpipe(k))) u_dec (
            .clk, .rst_n, .in_valid, .cw_in,
            .out_valid(ov[k]), .data_out(dout[k]), .cw_out(cwout[k]), .syndrome(syn[k]),
            .ce(ce[k]), .ae(ae[k]), .ue(ue[k]), .err_pos(pos[k]));
    end

    // portable pseudo-random numbers (the seeded random system function is not supported by xsim)
    logic [31:0] rng;
    function automatic logic [31:0] rnd();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    int enc_err [0:NENC-1];
    int dec_err [0:NDEC-1];
    int enc_chk [0:NENC-1];
    int dec_chk [0:NDEC-1];
    int dec_outs [0:NDEC-1];
    int nvec, seed, gaps;
    int total_err, total_checks;
    logic [63:0] junk;

    // previous clock's input (for the one-stage pipelined decoder)
    bit prev_valid;
    int prev_idx;

    task automatic compare_dec(input int k, input int idx);
        logic [167:0] v;
        v = vec[idx];
        dec_chk[k] += 7;
        if (dout[k]  !== v[88:57]) begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: data_out %h expected %h", k, idx, dout[k], v[88:57]); end
        if (cwout[k] !== v[56:18]) begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: cw_out %h expected %h", k, idx, cwout[k], v[56:18]); end
        if (syn[k]   !== v[17:11]) begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: syndrome %h expected %h", k, idx, syn[k], v[17:11]); end
        if (ce[k]    !== v[10])    begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: ce %b expected %b", k, idx, ce[k], v[10]); end
        if (ue[k]    !== v[9])     begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: ue %b expected %b", k, idx, ue[k], v[9]); end
        if (pos[k]   !== v[8:3])   begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: err_pos %h expected %h", k, idx, pos[k], v[8:3]); end
        if (ae[k]    !== v[2])     begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d vec %0d: ae %b expected %b", k, idx, ae[k], v[2]); end
    endtask

    // combinational blocks: check right after a new input has been applied
    task automatic check_comb(input bit valid, input int idx);
        logic [38:0] clean;
        if (valid) begin
            clean = vec[idx][127:89] ^ vec[idx][166:128];
            for (int k = 0; k < NENC; k++) begin
                enc_chk[k]++;
                if (enc_out[k] !== clean) begin enc_err[k]++; if (enc_err[k] < 4) $display("enc%0d vec %0d: cw %h expected %h", k, idx, enc_out[k], clean); end
            end
        end
        for (int k = 0; k < NDEC; k++) begin
            if (dpipe(k) == 0) begin
                dec_chk[k] += 1;
                if (ov[k] !== valid) begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d: out_valid %b expected %b", k, ov[k], valid); end
                else if (valid) begin compare_dec(k, idx); dec_outs[k]++; end
            end
        end
    endtask

    // registered decoder: at the falling edge, the output belongs to the input applied one clock earlier
    task automatic check_seq();
        for (int k = 0; k < NDEC; k++) begin
            if (dpipe(k) == 1) begin
                dec_chk[k] += 1;
                if (ov[k] !== prev_valid) begin dec_err[k]++; if (dec_err[k] < 4) $display("dec%0d: out_valid %b expected %b", k, ov[k], prev_valid); end
                else if (prev_valid) begin compare_dec(k, prev_idx); dec_outs[k]++; end
            end
        end
    endtask

    task automatic step(input bit valid, input int idx);
        @(negedge clk);
        check_seq();
        in_valid = valid;
        junk     = {rnd(), rnd()};
        cw_in    = valid ? vec[idx][127:89] : junk[38:0];
        data_in  = valid ? (vec[idx][127:89] ^ vec[idx][166:128]) : junk[63:32];
        #1;
        check_comb(valid, idx);
        prev_valid = valid;
        prev_idx   = idx;
    endtask

    initial begin
        for (int k = 0; k < NENC; k++) begin enc_err[k] = 0; enc_chk[k] = 0; end
        for (int k = 0; k < NDEC; k++) begin dec_err[k] = 0; dec_chk[k] = 0; dec_outs[k] = 0; end
        seed = 1; if ($value$plusargs("seed=%d", seed)) ;
        rng = 32'h2BADCAFE ^ seed;
        if (rng == 0) rng = 32'h1;
        $readmemh("daec_vectors.hex", vec);
        nvec = 0;
        while (nvec < VMAX && !$isunknown(vec[nvec])) nvec++;
        if (nvec == 0) begin $display("FAIL: daec_vectors.hex not found or empty"); $finish; end
        $display("tb_daec_codec: %0d golden vectors (SEC-DED-DAEC, Dutta and Touba)", nvec);
        $display("  encoders: IMPL 0 ref, 1 flat, 2 CSE, 3 tree");
        $display("  decoders: IMPL 0-3 (PIPE 0), IMPL 2 PIPE 1");

        in_valid = 0; cw_in = '0; data_in = '0; prev_valid = 0; prev_idx = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        // PHASE 1: back to back
        for (int i = 0; i < nvec; i++) step(1'b1, i);
        step(1'b0, 0); step(1'b0, 0);
        // PHASE 2: random idle cycles
        gaps = 0;
        for (int i = 0; i < nvec; i++) begin
            while ((rnd() & 3) == 0) begin step(1'b0, 0); gaps++; end
            step(1'b1, i);
        end
        step(1'b0, 0); step(1'b0, 0);

        total_err = 0; total_checks = 0;
        $display("");
        for (int k = 0; k < NENC; k++) begin
            $display("  encoder IMPL %0d          : %0d checks, %0d errors", k, enc_chk[k], enc_err[k]);
            total_err += enc_err[k]; total_checks += enc_chk[k];
        end
        for (int k = 0; k < NDEC; k++) begin
            if (dec_outs[k] != 2 * nvec) begin dec_err[k]++; $display("dec%0d: %0d valid outputs, expected %0d", k, dec_outs[k], 2 * nvec); end
            $display("  decoder IMPL %0d, PIPE %0d : %0d valid outputs, %0d checks, %0d errors", dimpl(k), dpipe(k), dec_outs[k], dec_chk[k], dec_err[k]);
            total_err += dec_err[k]; total_checks += dec_chk[k];
        end
        $display("  idle cycles inserted in phase 2: %0d", gaps);
        if (total_err == 0) $display("PASS: %0d checks, 0 errors", total_checks);
        else                $display("FAIL: %0d errors in %0d checks", total_err, total_checks);
        $finish;
    end
endmodule
