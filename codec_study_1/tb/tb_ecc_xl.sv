`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_ecc_xl: every XOR-limited, pipelined decoder configuration (ecc_dec_xl, CFG = 0 .. XL_NCFG-1)
// against the golden-model vectors in tb/vectors/ecc_vectors.hex.
//
//   PHASE 1  all vectors back-to-back, one per clock.
//   PHASE 2  all vectors again with random idle cycles (in_valid = 0, garbage on cw_in) between them,
//            to prove that out_valid follows in_valid exactly LAT clocks later and that no data of an idle
//            cycle leaks into a valid one.
//
// Latency of configuration k is ecc_xl_pkg::xl_lat(k). For every clock the testbench knows which input
// was applied LAT clocks earlier and checks all outputs of every configuration against the golden result:
//   out_valid, data_out, cw_out, syndrome, ce, ue, err_pos.
// Vector layout: [166:128] mask [127:89] cw_in [88:57] data_out [56:18] cw_out [17:11] syndrome
//                [10] ce [9] ue [8:3] err_pos
// -----------------------------------------------------------------------------
module tb_ecc_xl;
    import ecc_xl_pkg::*;

    localparam int VMAX  = 65536;
    localparam int HMAX  = 262144;     // clock history (phase 2 adds idle cycles)

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    logic [167:0] vec [0:VMAX-1];
    logic         in_valid;
    logic  [38:0] cw_in;

    logic [XL_NCFG-1:0] ov;
    logic  [31:0] dout  [0:XL_NCFG-1];
    logic  [38:0] cwout [0:XL_NCFG-1];
    logic   [6:0] syn   [0:XL_NCFG-1];
    logic [XL_NCFG-1:0] ce, ue;
    logic   [5:0] pos   [0:XL_NCFG-1];

    for (genvar k = 0; k < XL_NCFG; k++) begin : g_dut
        ecc_dec_xl #(.CFG(k)) dut (
            .clk, .rst_n, .in_valid, .cw_in,
            .out_valid(ov[k]), .data_out(dout[k]), .cw_out(cwout[k]), .syndrome(syn[k]),
            .ce(ce[k]), .ue(ue[k]), .err_pos(pos[k]));
    end

    // history: what was applied in clock t
    bit [HMAX-1:0] h_valid;
    int            h_idx [0:HMAX-1];

    int errs [0:XL_NCFG-1];
    int checks [0:XL_NCFG-1];
    int outs   [0:XL_NCFG-1];
    int nvec, t;

    task automatic compare(input int k, input int idx);
        logic [167:0] v;
        v = vec[idx];
        checks[k] += 6;
        if (dout[k]  !== v[88:57]) begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: data_out %h expected %h", k, idx, dout[k], v[88:57]); end
        if (cwout[k] !== v[56:18]) begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: cw_out %h expected %h", k, idx, cwout[k], v[56:18]); end
        if (syn[k]   !== v[17:11]) begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: syndrome %h expected %h", k, idx, syn[k], v[17:11]); end
        if (ce[k]    !== v[10])    begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: ce %b expected %b", k, idx, ce[k], v[10]); end
        if (ue[k]    !== v[9])     begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: ue %b expected %b", k, idx, ue[k], v[9]); end
        if (pos[k]   !== v[8:3])   begin errs[k]++; if (errs[k] < 4) $display("cfg%0d vec %0d: err_pos %h expected %h", k, idx, pos[k], v[8:3]); end
    endtask

    // sample all outputs for clock t (called at the falling edge, before the next input is applied)
    task automatic check_clock();
        int src;
        for (int k = 0; k < XL_NCFG; k++) begin
            src = t - xl_lat(k);
            checks[k] += 1;
            if (src < 0 || !h_valid[src]) begin
                if (ov[k] !== 1'b0) begin errs[k]++; if (errs[k] < 4) $display("cfg%0d clock %0d: out_valid should be 0", k, t); end
            end else begin
                if (ov[k] !== 1'b1) begin errs[k]++; if (errs[k] < 4) $display("cfg%0d clock %0d: out_valid should be 1", k, t); end
                else begin compare(k, h_idx[src]); outs[k]++; end
            end
        end
    endtask

    task automatic step(input bit valid, input int idx);
        @(negedge clk);
        check_clock();
        h_valid[t] = valid;
        h_idx[t]   = idx;
        in_valid   = valid;
        junk       = {rnd(), rnd()};
        cw_in      = valid ? vec[idx][127:89] : junk[38:0];
        t++;
    endtask

    // portable pseudo-random numbers (the seeded random system function is not supported by xsim)
    logic [31:0] rng;
    function automatic logic [31:0] rnd();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        return rng;
    endfunction

    int total_err, total_checks, seed, gaps;
    logic [63:0] junk;
    int expect_outs;

    initial begin
        for (int k = 0; k < XL_NCFG; k++) begin errs[k] = 0; checks[k] = 0; outs[k] = 0; end
        seed = 1; if ($value$plusargs("seed=%d", seed)) ;
        rng = 32'h1ACEB00C ^ seed;
        if (rng == 0) rng = 32'h1;
        $readmemh("ecc_vectors.hex", vec);
        nvec = 0;
        while (nvec < VMAX && !$isunknown(vec[nvec])) nvec++;
        if (nvec == 0) begin $display("FAIL: ecc_vectors.hex not found or empty"); $finish; end
        $display("tb_ecc_xl: %0d golden vectors, %0d configurations", nvec, XL_NCFG);
        for (int k = 0; k < XL_NCFG; k++)
            $display("  cfg%0d: <= %0d XORs/stage, <= %0d levels/stage, latency %0d clocks", k, xl_k(k), xl_c(k), xl_lat(k));

        t = 0; in_valid = 0; cw_in = '0; h_valid = '0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        // PHASE 1: back to back
        for (int i = 0; i < nvec; i++) step(1'b1, i);
        for (int i = 0; i < 16; i++) step(1'b0, 0);                       // flush (longest latency is 10)
        // PHASE 2: random idle cycles
        gaps = 0;
        for (int i = 0; i < nvec; i++) begin
            while ((rnd() & 3) == 0) begin step(1'b0, 0); gaps++; end   // about 1/3 of the clocks idle
            step(1'b1, i);
        end
        for (int i = 0; i < 16; i++) step(1'b0, 0);
        @(negedge clk); check_clock();

        total_err = 0; total_checks = 0; expect_outs = 2 * nvec;
        $display("");
        for (int k = 0; k < XL_NCFG; k++) begin
            if (outs[k] != expect_outs) begin errs[k]++; $display("cfg%0d: %0d valid outputs, expected %0d", k, outs[k], expect_outs); end
            $display("  cfg%0d (latency %2d): %0d valid outputs, %0d checks, %0d errors", k, xl_lat(k), outs[k], checks[k], errs[k]);
            total_err += errs[k]; total_checks += checks[k];
        end
        $display("  idle cycles inserted in phase 2: %0d", gaps);
        if (total_err == 0) $display("PASS: %0d checks, 0 errors", total_checks);
        else                $display("FAIL: %0d errors in %0d checks", total_err, total_checks);
        $finish;
    end
endmodule
