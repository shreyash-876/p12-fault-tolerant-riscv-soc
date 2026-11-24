`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_mem_subsystem (STAGE 1a): mem_subsystem alone, driven by an AXI4-Lite
// master BFM. No CPU involved. Prints every step it performs.
//
//   [1] directed word and sub-word writes, each read back and compared
//   [2] AW/W channel ordering: together, AW first, W first
//   [3] a read and a write started in the same clock cycle
//   [4] 3000 random ops (random address/data/strobe/order, random VALID gaps,
//       random BREADY/RREADY back-pressure) checked against a reference model
//   [5] register window: ID register, scratch register with byte strobes
//   always-on protocol monitors on the B and R channels
//
// Plusargs:  +seed=N        random seed (default 7)
//            +verbose=0|1|2 0 = sections and summary only
//                           1 = also every directed transaction (default)
//                           2 = also every random transaction
// Run (Icarus): iverilog -g2012 -o sim_mem ../rtl/mem/mem_pkg.sv tb_mem_subsystem.sv \
//                 ../rtl/mem/bram_sp.sv ../rtl/mem/axil_frontend.sv ../rtl/mem/mem_ctrl.sv \
//                 ../rtl/mem/ecc_regs.sv ../rtl/mem/mem_subsystem.sv && vvp sim_mem
// Run (Vivado): simulation top = tb_mem_subsystem, runtime = all
// -----------------------------------------------------------------------------
module tb_mem_subsystem;
    import mem_pkg::*;

    localparam int DEPTH = 2048;
    localparam logic [31:0] BASE = 32'h2000_0000;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;            // 50 MHz

    // cycle counter (for latency measurements)
    longint cyc = 0;
    always @(posedge clk) cyc++;

    // ---------------- DUT signals ----------------
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic  [3:0] wstrb;
    logic        awvalid = 0, awready, wvalid = 0, wready, bvalid, bready = 0;
    logic        arvalid = 0, arready, rvalid, rready = 0;
    logic  [1:0] bresp, rresp;

    logic [31:0] r_awaddr, r_wdata, r_araddr, r_rdata;
    logic  [3:0] r_wstrb;
    logic        r_awvalid = 0, r_awready, r_wvalid = 0, r_wready, r_bvalid, r_bready = 0;
    logic        r_arvalid = 0, r_arready, r_rvalid, r_rready = 0;
    logic  [1:0] r_bresp, r_rresp;
    logic        irq;

    mem_subsystem #(.DEPTH(DEPTH)) dut (
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

    // ---------------- reference model ----------------
    logic [31:0] model [0:DEPTH-1];
    logic        written [0:DEPTH-1];
    initial for (int i = 0; i < DEPTH; i++) begin model[i] = 32'h0; written[i] = 1'b0; end

    // ---------------- bookkeeping ----------------
    int errors = 0, checks = 0;               // totals
    int sec_errors = 0, sec_checks = 0;       // current section
    int gap_max = 3;                          // random idle cycles before VALID / READY
    int verbose = 1;
    bit quiet = 0;                            // set during the random section (unless verbose >= 2)
    integer seed;
    int unsigned seed_dummy;

    // coverage counters
    int n_wr = 0, n_rd = 0, n_rd_written = 0;
    int strobe_hits [0:15];
    int order_hits  [0:3];
    longint wr_lat_sum = 0, rd_lat_sum = 0;
    int     wr_lat_max = 0, rd_lat_max = 0, wr_lat_min = 999, rd_lat_min = 999;
    int b_wait_cycles = 0, r_wait_cycles = 0;  // cycles a response was held waiting for READY
    int prot_viol = 0;                         // protocol-monitor violations
    initial begin for (int i = 0; i < 16; i++) strobe_hits[i] = 0; for (int i = 0; i < 4; i++) order_hits[i] = 0; end

    function automatic logic [31:0] merge(logic [31:0] old, logic [31:0] nw, logic [3:0] st);
        for (int b = 0; b < 4; b++) if (st[b]) old[8*b +: 8] = nw[8*b +: 8];
        return old;
    endfunction

    function automatic string order_name(int o);
        case (o)
            0: return "AW+W together";
            1: return "AW first     ";
            2: return "W first      ";
            default: return "random gaps  ";
        endcase
    endfunction

    function automatic string resp_name(logic [1:0] r);
        case (r)
            2'b00: return "OKAY";
            2'b01: return "EXOKAY";
            2'b10: return "SLVERR";
            default: return "DECERR";
        endcase
    endfunction

    task automatic fail(input string msg);
        errors++; sec_errors++;
        $display("    ** ERROR: %s", msg);
    endtask

    task automatic section(input string title);
        sec_errors = 0; sec_checks = 0;
        $display("");
        $display("------------------------------------------------------------------------");
        $display("%s", title);
        $display("------------------------------------------------------------------------");
    endtask

    task automatic section_end(input string name);
        string verdict;
        verdict = (sec_errors == 0) ? "OK" : "FAILED";
        $display("    %s: %0d checks, %0d errors -> %s", name, sec_checks, sec_errors, verdict);
    endtask

    task automatic idle(int n); repeat (n) @(posedge clk); endtask
    task automatic rgap(); if (gap_max > 0) idle($urandom_range(0, gap_max)); endtask

    // ---------------- BFM: AW / W / B ----------------
    task automatic send_aw(input logic [31:0] a);
        awaddr <= a; awvalid <= 1;
        do @(posedge clk); while (!awready);
        awvalid <= 0;
    endtask
    task automatic send_w(input logic [31:0] d, input logic [3:0] s);
        wdata <= d; wstrb <= s; wvalid <= 1;
        do @(posedge clk); while (!wready);
        wvalid <= 0;
    endtask
    task automatic get_b(output logic [1:0] resp);
        rgap(); bready <= 1;
        do @(posedge clk); while (!bvalid);
        resp = bresp; bready <= 0;
    endtask

    // order: 0 = together, 1 = AW first, 2 = W first, 3 = random gaps on both
    task automatic axi_write(input logic [31:0] a, input logic [31:0] d,
                             input logic [3:0] s, input int order = 0);
        logic [1:0] resp;
        longint t0;
        int lat;
        logic [31:0] old_word;
        t0 = cyc;
        old_word = model[a[12:2]];
        case (order)
            0: fork send_aw(a); send_w(d, s); join
            1: begin send_aw(a); idle(2); send_w(d, s); end
            2: begin send_w(d, s); idle(2); send_aw(a); end
            default: fork begin rgap(); send_aw(a); end begin rgap(); send_w(d, s); end join
        endcase
        get_b(resp);
        lat = int'(cyc - t0);
        checks++; sec_checks++;
        model[a[12:2]] = merge(model[a[12:2]], d, s);
        written[a[12:2]] = 1'b1;
        n_wr++; strobe_hits[s]++; order_hits[order]++;
        wr_lat_sum += lat; if (lat > wr_lat_max) wr_lat_max = lat; if (lat < wr_lat_min) wr_lat_min = lat;
        if (!quiet)
            $display("    WRITE addr=%h data=%h strb=%b (%s) -> %s  %2d cycles  word %h -> %h",
                     a, d, s, order_name(order), resp_name(resp), lat, old_word, model[a[12:2]]);
        if (resp !== 2'b00) fail($sformatf("write %h returned BRESP=%s", a, resp_name(resp)));
    endtask

    // ---------------- BFM: AR / R ----------------
    task automatic axi_read(input logic [31:0] a, output logic [31:0] d, output int lat);
        longint t0;
        t0 = cyc;
        araddr <= a; arvalid <= 1;
        do @(posedge clk); while (!arready);
        arvalid <= 0;
        rgap(); rready <= 1;
        do @(posedge clk); while (!rvalid);
        d = rdata; rready <= 0;
        lat = int'(cyc - t0);
        checks++; sec_checks++;
        n_rd++;
        rd_lat_sum += lat; if (lat > rd_lat_max) rd_lat_max = lat; if (lat < rd_lat_min) rd_lat_min = lat;
        if (rresp !== 2'b00) fail($sformatf("read %h returned RRESP=%s", a, resp_name(rresp)));
    endtask

    task automatic check_read(input logic [31:0] a);
        logic [31:0] d;
        int lat;
        if (written[a[12:2]]) n_rd_written++;
        axi_read(a, d, lat);
        if (!quiet)
            $display("    READ  addr=%h got =%h expected=%h  %2d cycles  %s",
                     a, d, model[a[12:2]], lat, (d === model[a[12:2]]) ? "match" : "MISMATCH");
        if (d !== model[a[12:2]])
            fail($sformatf("read %h: got %h expected %h", a, d, model[a[12:2]]));
    endtask

    // ---------------- register-port BFM ----------------
    task automatic reg_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s);
        fork
            begin r_awaddr <= a; r_awvalid <= 1; do @(posedge clk); while (!r_awready); r_awvalid <= 0; end
            begin r_wdata <= d; r_wstrb <= s; r_wvalid <= 1; do @(posedge clk); while (!r_wready); r_wvalid <= 0; end
        join
        r_bready <= 1; do @(posedge clk); while (!r_bvalid); r_bready <= 0;
        if (!quiet) $display("    REG WRITE addr=%h data=%h strb=%b -> %s", a, d, s, resp_name(r_bresp));
    endtask
    task automatic reg_read(input logic [31:0] a, output logic [31:0] d);
        r_araddr <= a; r_arvalid <= 1; do @(posedge clk); while (!r_arready); r_arvalid <= 0;
        r_rready <= 1; do @(posedge clk); while (!r_rvalid); d = r_rdata; r_rready <= 0;
    endtask
    task automatic reg_check(input logic [31:0] a, input logic [31:0] exp, input string what);
        logic [31:0] d;
        reg_read(a, d);
        checks++; sec_checks++;
        if (!quiet) $display("    REG READ  addr=%h got =%h expected=%h  %s  (%s)", a, d, exp,
                 (d === exp) ? "match" : "MISMATCH", what);
        if (d !== exp) fail($sformatf("register %h: got %h expected %h", a, d, exp));
    endtask

    // ---------------- protocol monitors (always on) ----------------
    logic        bvalid_d, rvalid_d, bready_d, rready_d;
    logic [31:0] rdata_d;
    always @(posedge clk) begin
        bvalid_d <= bvalid; rvalid_d <= rvalid; rdata_d <= rdata;
        bready_d <= bready; rready_d <= rready;
        if (rst_n) begin
            if (bvalid && !bready) b_wait_cycles++;
            if (rvalid && !rready) r_wait_cycles++;
            if (bvalid_d && !bready_d && !bvalid) fail("PROTOCOL: BVALID dropped old_word BREADY");
            if (rvalid_d && !rready_d && !rvalid) fail("PROTOCOL: RVALID dropped old_word RREADY");
            if (rvalid_d && !rready_d && rvalid && rdata !== rdata_d) fail("PROTOCOL: RDATA changed while RVALID held");
        end
    end

    // ---------------- test sequence ----------------
    initial begin
        logic [31:0] a;
        logic [31:0] last_addr;
        last_addr = BASE + 32'((DEPTH - 1) * 4);

        seed = 7;
        if ($value$plusargs("seed=%d", seed)) ;
        if ($value$plusargs("verbose=%d", verbose)) ;
        $display("========================================================================");
        $display("tb_mem_subsystem: AXI4-Lite -> mem_subsystem -> BRAM (%0d words), seed=%0d, verbose=%0d",
                 DEPTH, seed, verbose);
        seed_dummy = $urandom(seed);          // seeds the generator (function form: xsim-compatible)
        $display("========================================================================");
        quiet = (verbose == 0);
        idle(3); rst_n = 1; idle(3);
        $display("reset released at cycle %0d", cyc);

        // ---------------------------------------------------------------- [1]
        section("[1] Directed accesses: full words, every strobe pattern, first/last word");
        gap_max = 0;
        $display("  1a. full-word write then read back");
        axi_write(BASE + 32'h0, 32'hDEADBEEF, 4'b1111); check_read(BASE + 32'h0);
        $display("  1b. all 15 non-zero WSTRB patterns on one word (only strobed bytes may change)");
        for (int s = 1; s < 16; s++) begin
            axi_write(BASE + 32'h10, 32'h11223344 * s, 4'(s)); check_read(BASE + 32'h10);
        end
        $display("  1c. single bytes and half-words as SB / SH would produce them");
        axi_write(BASE + 32'h20, 32'hA5A5A5A5, 4'b0001); check_read(BASE + 32'h20);
        axi_write(BASE + 32'h20, 32'h5A5A5A5A, 4'b1000); check_read(BASE + 32'h20);
        axi_write(BASE + 32'h20, 32'hCAFEF00D, 4'b1100); check_read(BASE + 32'h20);
        $display("  1d. last word of the RAM (top address bits decode correctly)");
        axi_write(last_addr, 32'h0BADC0DE, 4'b1111); check_read(last_addr);
        section_end("[1]");

        // ---------------------------------------------------------------- [2]
        section("[2] Channel ordering: the slave must accept AW and W in any order");
        axi_write(BASE + 32'h40, 32'h01010101, 4'b1111, 0); check_read(BASE + 32'h40);
        axi_write(BASE + 32'h44, 32'h02020202, 4'b1111, 1); check_read(BASE + 32'h44);
        axi_write(BASE + 32'h48, 32'h03030303, 4'b1111, 2); check_read(BASE + 32'h48);
        section_end("[2]");

        // ---------------------------------------------------------------- [3]
        section("[3] Read and write started in the same cycle (write has priority)");
        fork
            axi_write(BASE + 32'h80, 32'h12345678, 4'b1111, 0);
            check_read(BASE + 32'h40);
        join
        check_read(BASE + 32'h80);
        section_end("[3]");

        // ---------------------------------------------------------------- [4]
        section("[4] Random: 3000 ops over 64 hot words, random gaps and back-pressure");
        gap_max = 4;
        quiet = (verbose < 2);
        if (verbose < 2) $display("  (individual transactions hidden; run with +verbose=2 to see them)");
        for (int n = 1; n <= 3000; n++) begin
            a = BASE + {19'd0, 11'($urandom_range(0, 63)), 2'b00};
            if ($urandom_range(0, 1)) axi_write(a, $urandom, 4'($urandom_range(1, 15)), $urandom_range(0, 3));
            else                      check_read(a);
            if (n % 500 == 0)
                $display("  progress: %4d / 3000 ops   writes=%0d reads=%0d   errors so far=%0d   cycle=%0d",
                         n, n_wr, n_rd, errors, cyc);
        end
        quiet = (verbose == 0);
        section_end("[4]");

        // ---------------------------------------------------------------- [5]
        section("[5] Register window (0x4000_0000): ID and scratch registers");
        reg_check(32'h4000_0000, 32'h5031_2001, "ID register, read-only");
        reg_write(32'h4000_0004, 32'hAABBCCDD, 4'b1111);
        reg_check(32'h4000_0004, 32'hAABBCCDD, "SCRATCH0 after full write");
        reg_write(32'h4000_0004, 32'h00001100, 4'b0010);
        reg_check(32'h4000_0004, 32'hAABB11DD, "SCRATCH0 after byte-1 write");
        section_end("[5]");

        // ---------------------------------------------------------------- summary
        idle(5);
        $display("");
        $display("========================================================================");
        $display("SUMMARY");
        $display("  transactions : %0d writes, %0d reads (%0d reads of previously written words)",
                 n_wr, n_rd, n_rd_written);
        $display("  write latency: min %0d / avg %0d / max %0d cycles (AW/W issue -> B handshake)",
                 wr_lat_min, int'(wr_lat_sum / n_wr), wr_lat_max);
        $display("  read latency : min %0d / avg %0d / max %0d cycles (AR issue -> R handshake)",
                 rd_lat_min, int'(rd_lat_sum / n_rd), rd_lat_max);
        $display("  AW/W order   : together=%0d  AW-first=%0d  W-first=%0d  random-gaps=%0d",
                 order_hits[0], order_hits[1], order_hits[2], order_hits[3]);
        $write  ("  WSTRB hits   :");
        for (int s = 1; s < 16; s++) $write(" %b:%0d", 4'(s), strobe_hits[s]);
        $display("");
        $display("  back-pressure: BVALID held waiting %0d cycles, RVALID held waiting %0d cycles",
                 b_wait_cycles, r_wait_cycles);
        $display("  protocol     : %0d violations (BVALID/RVALID held until READY, RDATA stable)", prot_viol);
        $display("------------------------------------------------------------------------");
        if (errors == 0) $display("PASS: %0d checks, 0 errors", checks);
        else             $display("FAIL: %0d errors in %0d checks", errors, checks);
        $display("========================================================================");
        $finish;
    end

    initial begin #20ms; $display("TIMEOUT"); $finish; end
endmodule
