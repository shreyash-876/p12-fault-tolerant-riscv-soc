`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mem_arbiter: lets the CPU path and two background requesters (the scrubber and the
// error injector) share the one memory controller. All sides speak the native
// request/response protocol of mem_pkg.
//
// Policy:
//   * CPU priority: when the CPU and a background requester ask in the same cycle, the CPU wins.
//   * Between the two background requesters the injector goes first (its requests are rare
//     and short), unless only the scrubber has already waited PATIENCE cycles.
//   * Once an operation has been accepted it OWNS the controller until its response comes back.
//     Nothing can interrupt it, so a scrub write-back or an injection can never land in the
//     middle of a CPU read-modify-write, or the other way round.
//   * The CPU therefore waits for at most one background operation (a few cycles) and can never
//     be starved: background requests are rare, and each waits for its response before the next.
//   * Neither background requester can be starved either: each one has its own wait counter, and once
//     a background request has waited PATIENCE cycles it wins the next arbitration even against a
//     waiting CPU request (and, for the scrubber, against the injector). PATIENCE must be < 65535.
//
// State:  A_IDLE  nobody owns the controller; decide on the requests of this cycle
//         A_CPU / A_SCR / A_INJ   an operation of that requester was accepted, wait for its response
// -----------------------------------------------------------------------------
module mem_arbiter
    import mem_pkg::*;
#(
    parameter int PATIENCE = 256
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------- CPU side (from axil_frontend) ----------------
    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  mem_op_t     cpu_req_op,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic  [3:0] cpu_req_wstrb,
    output logic        cpu_rsp_valid,
    output logic [31:0] cpu_rsp_rdata,
    output logic        cpu_rsp_err,

    // ---------------- scrubber side ----------------
    input  logic        scr_req_valid,
    output logic        scr_req_ready,
    input  mem_op_t     scr_req_op,
    input  logic [31:0] scr_req_addr,
    output logic        scr_rsp_valid,
    output logic [31:0] scr_rsp_rdata,
    output logic        scr_rsp_err,

    // ---------------- error-injector side ----------------
    input  logic        inj_req_valid,
    output logic        inj_req_ready,
    input  mem_op_t     inj_req_op,
    input  logic [31:0] inj_req_addr,
    output logic        inj_rsp_valid,
    output logic [31:0] inj_rsp_rdata,
    output logic        inj_rsp_err,

    // ---------------- to the memory controller ----------------
    output logic        c_req_valid,
    input  logic        c_req_ready,
    output mem_op_t     c_req_op,
    output logic [31:0] c_req_addr,
    output logic [31:0] c_req_wdata,
    output logic  [3:0] c_req_wstrb,
    input  logic        c_rsp_valid,
    input  logic [31:0] c_rsp_rdata,
    input  logic        c_rsp_err
);
    typedef enum logic [1:0] {A_IDLE, A_CPU, A_SCR, A_INJ} a_state_t;
    a_state_t state;

    logic [15:0] scr_wait_cnt, inj_wait_cnt;     // cycles each background request has been waiting for a grant
    wire bg_req    = scr_req_valid | inj_req_valid;
    wire scr_aged  = scr_req_valid && (scr_wait_cnt >= 16'(PATIENCE));
    wire inj_aged  = inj_req_valid && (inj_wait_cnt >= 16'(PATIENCE));

    // which background requester would be served: the injector, unless only the scrubber is "aged"
    wire pick_scr  = scr_req_valid && (!inj_req_valid || (scr_aged && !inj_aged));
    wire pick_inj  = inj_req_valid && !pick_scr;

    // who gets the controller in this cycle (only decided in A_IDLE)
    wire grant_bg  = (state == A_IDLE) && bg_req && (!cpu_req_valid || scr_aged || inj_aged);
    wire grant_inj = grant_bg && pick_inj;
    wire grant_scr = grant_bg && pick_scr;
    wire grant_cpu = (state == A_IDLE) && cpu_req_valid && !grant_bg;

    // request mux
    always_comb begin
        c_req_valid = 1'b0;
        c_req_op    = OP_READ;
        c_req_addr  = 32'h0;
        c_req_wdata = 32'h0;
        c_req_wstrb = 4'h0;
        if (grant_cpu) begin
            c_req_valid = 1'b1;
            c_req_op    = cpu_req_op;
            c_req_addr  = cpu_req_addr;
            c_req_wdata = cpu_req_wdata;
            c_req_wstrb = cpu_req_wstrb;
        end else if (grant_inj) begin
            c_req_valid = 1'b1;
            c_req_op    = inj_req_op;
            c_req_addr  = inj_req_addr;
        end else if (grant_scr) begin
            c_req_valid = 1'b1;
            c_req_op    = scr_req_op;
            c_req_addr  = scr_req_addr;
        end
    end

    assign cpu_req_ready = grant_cpu && c_req_ready;
    assign inj_req_ready = grant_inj && c_req_ready;
    assign scr_req_ready = grant_scr && c_req_ready;

    // response routing: the owner gets the response
    assign cpu_rsp_valid = (state == A_CPU) && c_rsp_valid;
    assign scr_rsp_valid = (state == A_SCR) && c_rsp_valid;
    assign inj_rsp_valid = (state == A_INJ) && c_rsp_valid;
    assign cpu_rsp_rdata = c_rsp_rdata;
    assign scr_rsp_rdata = c_rsp_rdata;
    assign inj_rsp_rdata = c_rsp_rdata;
    assign cpu_rsp_err   = c_rsp_err;
    assign scr_rsp_err   = c_rsp_err;
    assign inj_rsp_err   = c_rsp_err;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= A_IDLE;
            scr_wait_cnt <= 16'd0;
            inj_wait_cnt <= 16'd0;
        end else begin
            case (state)
                A_IDLE: begin
                    if (cpu_req_ready)      state <= A_CPU;
                    else if (inj_req_ready) state <= A_INJ;
                    else if (scr_req_ready) state <= A_SCR;
                end
                A_CPU, A_SCR, A_INJ: if (c_rsp_valid) state <= A_IDLE;
                default: state <= A_IDLE;
            endcase

            // how long has each background request been waiting?
            if (!scr_req_valid || scr_req_ready)    scr_wait_cnt <= 16'd0;
            else if (scr_wait_cnt != 16'hFFFF)      scr_wait_cnt <= scr_wait_cnt + 16'd1;
            if (!inj_req_valid || inj_req_ready)    inj_wait_cnt <= 16'd0;
            else if (inj_wait_cnt != 16'hFFFF)      inj_wait_cnt <= inj_wait_cnt + 16'd1;
        end
    end
endmodule
