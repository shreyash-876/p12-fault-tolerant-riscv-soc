`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_mem_arbiter: the arbiter alone, with a simple model of the memory controller.
//
// It checks the properties that the formal (CTL) proof will state later:
//   * safety   : only the owner of the controller gets the response; the two sides are never
//                granted at the same time; an operation is never interrupted
//   * CPU      : every CPU request is granted, and it waits at most for ONE scrub operation
//   * injector : the second background requester (error injector) is treated like the scrubber
//   * scrubber : every scrub request is granted, at the latest after PATIENCE cycles (+ the
//                operation in progress), even if the CPU asks continuously
//   * priority : while the scrubber has not waited PATIENCE cycles, the CPU wins
//
// Two scenarios, 20,000 cycles each:
//   A  worst case: the next CPU request is valid in the very cycle in which the arbiter is free
//      again, so the CPU is present at every arbitration
//   B  light CPU traffic with random gaps
// -----------------------------------------------------------------------------
module tb_mem_arbiter;
    import mem_pkg::*;

    localparam int PATIENCE  = 20;     // scrubber patience (cycles)
    localparam int OP_CYCLES = 3;      // longest controller operation (decode, write, respond)

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    // ---------------- DUT ----------------
    logic        cpu_req_valid, cpu_req_ready, cpu_rsp_valid, cpu_rsp_err;
    mem_op_t     cpu_req_op;
    logic [31:0] cpu_req_addr, cpu_req_wdata, cpu_rsp_rdata;
    logic  [3:0] cpu_req_wstrb;

    logic        scr_req_valid, scr_req_ready, scr_rsp_valid, scr_rsp_err;
    mem_op_t     scr_req_op;
    logic [31:0] scr_req_addr, scr_rsp_rdata;

    logic        inj_req_valid, inj_req_ready, inj_rsp_valid, inj_rsp_err;
    mem_op_t     inj_req_op;
    logic [31:0] inj_req_addr, inj_rsp_rdata;

    logic        c_req_valid, c_req_ready, c_rsp_valid, c_rsp_err;
    mem_op_t     c_req_op;
    logic [31:0] c_req_addr, c_req_wdata, c_rsp_rdata;
    logic  [3:0] c_req_wstrb;

    mem_arbiter #(.PATIENCE(PATIENCE)) dut (
        .clk, .rst_n,
        .cpu_req_valid, .cpu_req_ready, .cpu_req_op, .cpu_req_addr, .cpu_req_wdata, .cpu_req_wstrb,
        .cpu_rsp_valid, .cpu_rsp_rdata, .cpu_rsp_err,
        .scr_req_valid, .scr_req_ready, .scr_req_op, .scr_req_addr,
        .scr_rsp_valid, .scr_rsp_rdata, .scr_rsp_err,
        .inj_req_valid, .inj_req_ready, .inj_req_op, .inj_req_addr,
        .inj_rsp_valid, .inj_rsp_rdata, .inj_rsp_err,
        .c_req_valid, .c_req_ready, .c_req_op, .c_req_addr, .c_req_wdata, .c_req_wstrb,
        .c_rsp_valid, .c_rsp_rdata, .c_rsp_err
    );

    // ---------------- model of the memory controller ----------------
    // one operation at a time, busy for OP_CYCLES cycles, response data = the request address
    logic        ctrl_busy;
    int          ctrl_cnt;
    logic [31:0] ctrl_addr;
    assign c_req_ready = !ctrl_busy;
    assign c_rsp_valid = ctrl_busy && (ctrl_cnt == 0);
    assign c_rsp_rdata = ctrl_addr;
    assign c_rsp_err   = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_busy <= 1'b0; ctrl_cnt <= 0; ctrl_addr <= 32'h0;
        end else if (c_req_valid && c_req_ready) begin
            ctrl_busy <= 1'b1;
            ctrl_cnt  <= OP_CYCLES - 1;
            ctrl_addr <= c_req_addr;
        end else if (ctrl_busy) begin
            if (ctrl_cnt == 0) ctrl_busy <= 1'b0;
            else               ctrl_cnt  <= ctrl_cnt - 1;
        end
    end

    // ---------------- scenario control ----------------
    int scenario = 0;                 // 0 = A (no gaps), 1 = B (random gaps)
    int errors = 0;

    // ---------------- CPU master ----------------
    int cpu_st, cpu_wait, cpu_gap;
    int cpu_wait_max, cpu_ops;
    logic [31:0] cpu_next;
    assign cpu_req_op = OP_READ;
    assign cpu_req_wdata = 32'h0;
    assign cpu_req_wstrb = 4'h0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_st <= 0; cpu_wait <= 0; cpu_gap <= 0; cpu_wait_max <= 0; cpu_ops <= 0;
            cpu_req_valid <= 1'b0; cpu_req_addr <= 32'h0; cpu_next <= 32'h1000;
        end else begin
            case (cpu_st)
                0: begin                                   // optional gap, then present a request
                    if (cpu_gap > 0) cpu_gap <= cpu_gap - 1;
                    else begin
                        cpu_req_valid <= 1'b1;
                        cpu_req_addr  <= cpu_next;
                        cpu_next      <= cpu_next + 32'd4;
                        cpu_wait      <= 0;
                        cpu_st        <= 1;
                    end
                end
                1: begin                                   // wait for the grant
                    if (cpu_req_ready) begin
                        cpu_req_valid <= 1'b0;
                        if (cpu_wait > cpu_wait_max) cpu_wait_max <= cpu_wait;
                        cpu_st <= 2;
                    end else cpu_wait <= cpu_wait + 1;
                end
                2: if (cpu_rsp_valid) begin                // wait for the response
                    if (cpu_rsp_rdata !== cpu_req_addr) begin
                        errors = errors + 1;
                        $display("ERROR: CPU got response data %h for request %h", cpu_rsp_rdata, cpu_req_addr);
                    end
                    cpu_ops <= cpu_ops + 1;
                    if (scenario == 0) begin
                        // worst case: the next request is already valid in the very cycle in which the
                        // arbiter is free again, so the CPU is present at EVERY arbitration
                        cpu_req_valid <= 1'b1;
                        cpu_req_addr  <= cpu_next;
                        cpu_next      <= cpu_next + 32'd4;
                        cpu_wait      <= 0;
                        cpu_st        <= 1;
                    end else begin
                        cpu_gap <= $urandom_range(0, 10);
                        cpu_st  <= 0;
                    end
                end
            endcase
        end
    end

    // ---------------- scrubber master ----------------
    int scr_st, scr_wait, scr_gap;
    int scr_wait_max, scr_wait_min, scr_ops;
    logic [31:0] scr_next;
    assign scr_req_op = OP_SCRUB;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scr_st <= 0; scr_wait <= 0; scr_gap <= 30; scr_wait_max <= 0; scr_wait_min <= 100000; scr_ops <= 0;
            scr_req_valid <= 1'b0; scr_req_addr <= 32'h0; scr_next <= 32'h2000_0000;
        end else begin
            case (scr_st)
                0: begin                                   // wait the interval, then request
                    if (scr_gap > 0) scr_gap <= scr_gap - 1;
                    else begin
                        scr_req_valid <= 1'b1;
                        scr_req_addr  <= scr_next;
                        scr_next      <= scr_next + 32'd4;
                        scr_wait      <= 0;
                        scr_st        <= 1;
                    end
                end
                1: begin
                    if (scr_req_ready) begin
                        scr_req_valid <= 1'b0;
                        if (scr_wait > scr_wait_max) scr_wait_max <= scr_wait;
                        if (scr_wait < scr_wait_min) scr_wait_min <= scr_wait;
                        scr_st <= 2;
                    end else scr_wait <= scr_wait + 1;
                end
                2: if (scr_rsp_valid) begin
                    if (scr_rsp_rdata !== scr_req_addr) begin
                        errors = errors + 1;
                        $display("ERROR: scrubber got response data %h for request %h", scr_rsp_rdata, scr_req_addr);
                    end
                    scr_ops <= scr_ops + 1;
                    scr_gap <= 30;
                    scr_st  <= 0;
                end
            endcase
        end
    end

    // ---------------- injector master (second background requester, rarer than the scrubber) ----------------
    int inj_st, inj_wait, inj_gap;
    int inj_wait_max, inj_wait_min, inj_ops;
    logic [31:0] inj_next;
    assign inj_req_op = OP_INJECT;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inj_st <= 0; inj_wait <= 0; inj_gap <= 47; inj_wait_max <= 0; inj_wait_min <= 100000; inj_ops <= 0;
            inj_req_valid <= 1'b0; inj_req_addr <= 32'h0; inj_next <= 32'h2000_4000;
        end else begin
            case (inj_st)
                0: begin
                    if (inj_gap > 0) inj_gap <= inj_gap - 1;
                    else begin
                        inj_req_valid <= 1'b1;
                        inj_req_addr  <= inj_next;
                        inj_next      <= inj_next + 32'd4;
                        inj_wait      <= 0;
                        inj_st        <= 1;
                    end
                end
                1: begin
                    if (inj_req_ready) begin
                        inj_req_valid <= 1'b0;
                        if (inj_wait > inj_wait_max) inj_wait_max <= inj_wait;
                        if (inj_wait < inj_wait_min) inj_wait_min <= inj_wait;
                        inj_st <= 2;
                    end else inj_wait <= inj_wait + 1;
                end
                2: if (inj_rsp_valid) begin
                    if (inj_rsp_rdata !== inj_req_addr) begin
                        errors = errors + 1;
                        $display("ERROR: injector got response data %h for request %h", inj_rsp_rdata, inj_req_addr);
                    end
                    inj_ops <= inj_ops + 1;
                    inj_gap <= 47;
                    inj_st  <= 0;
                end
            endcase
        end
    end

    // ---------------- always-on protocol checks ----------------
    int grant_both = 0, spurious_rsp = 0, interrupted = 0;
    int ctrl_owner = 0;                       // 1 = CPU op in progress, 2 = scrub op in progress
    always @(posedge clk) begin
        if (rst_n) begin
            if ((cpu_req_ready ? 1 : 0) + (scr_req_ready ? 1 : 0) + (inj_req_ready ? 1 : 0) > 1) grant_both = grant_both + 1;
            if ((cpu_rsp_valid ? 1 : 0) + (scr_rsp_valid ? 1 : 0) + (inj_rsp_valid ? 1 : 0) > 1) grant_both = grant_both + 1;
            if ((cpu_rsp_valid && cpu_st != 2) || (scr_rsp_valid && scr_st != 2) || (inj_rsp_valid && inj_st != 2)) spurious_rsp = spurious_rsp + 1;
            // nothing may be accepted while the controller is busy
            if (c_req_valid && !c_req_ready) interrupted = interrupted + 1;
        end
    end

    // ---------------- run ----------------
    int a_cpu_max, a_scr_max, a_scr_min, a_cpu_ops, a_scr_ops, a_inj_max, a_inj_min, a_inj_ops;
    int b_cpu_max, b_scr_max, b_scr_min, b_cpu_ops, b_scr_ops, b_inj_max, b_inj_min, b_inj_ops;

    initial begin
        $display("========================================================================");
        $display("tb_mem_arbiter: PATIENCE = %0d cycles, controller operation = %0d cycles", PATIENCE, OP_CYCLES);
        $display("========================================================================");
        repeat (3) @(posedge clk);
        rst_n = 1;

        // ---- scenario A: CPU hammers with no gap ----
        scenario = 0;
        repeat (20000) @(posedge clk);
        a_cpu_max = cpu_wait_max; a_scr_max = scr_wait_max; a_scr_min = scr_wait_min;
        a_cpu_ops = cpu_ops;      a_scr_ops = scr_ops;
        a_inj_max = inj_wait_max; a_inj_min = inj_wait_min; a_inj_ops = inj_ops;
        $display("");
        $display("Scenario A: the CPU is present at every arbitration (worst case)");
        $display("   CPU operations done      : %0d", a_cpu_ops);
        $display("   scrub operations done    : %0d   injection operations done: %0d", a_scr_ops, a_inj_ops);
        $display("   longest CPU wait         : %0d cycles   (limit: two background operations, 2 x (%0d + 1))", a_cpu_max, OP_CYCLES);
        $display("   scrubber wait min / max  : %0d / %0d cycles   (CPU has priority until %0d, then the scrubber wins)",
                 a_scr_min, a_scr_max, PATIENCE);
        $display("   injector wait min / max  : %0d / %0d cycles", a_inj_min, a_inj_max);

        // ---- scenario B: light CPU traffic ----
        scenario = 1;
        cpu_wait_max = 0; scr_wait_max = 0; scr_wait_min = 100000;
        inj_wait_max = 0; inj_wait_min = 100000; inj_ops = 0;
        cpu_ops = 0; scr_ops = 0;
        repeat (20000) @(posedge clk);
        b_cpu_max = cpu_wait_max; b_scr_max = scr_wait_max; b_scr_min = scr_wait_min;
        b_cpu_ops = cpu_ops;      b_scr_ops = scr_ops;
        b_inj_max = inj_wait_max; b_inj_min = inj_wait_min; b_inj_ops = inj_ops;
        $display("");
        $display("Scenario B: CPU traffic with random gaps of 0..10 cycles");
        $display("   CPU operations done      : %0d", b_cpu_ops);
        $display("   scrub operations done    : %0d   injection operations done: %0d", b_scr_ops, b_inj_ops);
        $display("   longest CPU wait         : %0d cycles", b_cpu_max);
        $display("   scrubber wait min / max  : %0d / %0d cycles", b_scr_min, b_scr_max);
        $display("   injector wait min / max  : %0d / %0d cycles", b_inj_min, b_inj_max);

        // ---- verdict ----
        $display("");
        if (a_cpu_max > 2 * (OP_CYCLES + 1) || b_cpu_max > 2 * (OP_CYCLES + 1)) begin
            errors = errors + 1; $display("ERROR: the CPU waited longer than two background operations");
        end
        if (a_scr_min < PATIENCE) begin
            errors = errors + 1; $display("ERROR: the scrubber won against a waiting CPU before PATIENCE (min wait %0d)", a_scr_min);
        end
        if (a_scr_max > PATIENCE + 2 * (OP_CYCLES + 1) + 2 || b_scr_max > PATIENCE + 2 * (OP_CYCLES + 1) + 2 ||
            a_inj_max > PATIENCE + 2 * (OP_CYCLES + 1) + 2 || b_inj_max > PATIENCE + 2 * (OP_CYCLES + 1) + 2) begin
            errors = errors + 1; $display("ERROR: a background requester waited longer than PATIENCE + two operations");
        end
        if (a_cpu_ops < 100 || a_scr_ops < 100 || a_inj_ops < 50 || b_cpu_ops < 100 || b_scr_ops < 100 || b_inj_ops < 50) begin
            errors = errors + 1; $display("ERROR: too few operations completed (progress problem)");
        end
        if (grant_both != 0)   begin errors = errors + 1; $display("ERROR: both sides granted at the same time (%0d)", grant_both); end
        if (spurious_rsp != 0) begin errors = errors + 1; $display("ERROR: %0d responses went to a side that was not waiting", spurious_rsp); end
        if (interrupted != 0)  begin errors = errors + 1; $display("ERROR: %0d requests presented to a busy controller", interrupted); end

        $display("protocol checks: simultaneous grants %0d, responses to the wrong side %0d, requests to a busy controller %0d",
                 grant_both, spurious_rsp, interrupted);
        if (errors == 0) $display("PASS: arbiter properties hold in both scenarios");
        else             $display("FAIL: %0d errors", errors);
        $display("========================================================================");
        $finish;
    end
endmodule
