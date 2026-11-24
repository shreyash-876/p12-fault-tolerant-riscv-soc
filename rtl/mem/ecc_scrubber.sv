`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_scrubber: background memory scrubber.
//
// WHY: ECC corrects a single flipped bit per word, but only when the word is read.
// A word nobody reads can pick up a SECOND flip later, and two flips in one word can
// no longer be corrected. The scrubber walks through the whole RAM in the background,
// reads every word through the ECC decoder and writes back the corrected word if a
// single error was found, so single errors are removed before a second one can join them.
//
// HOW: a small state machine and an address counter.
//   SC_WAIT  count `interval` clock cycles (only while `enable` = 1)
//   SC_REQ   raise req_valid with OP_SCRUB for the current word, until the arbiter accepts
//   SC_BUSY  wait for the response, update the statistics, go to the next word
// One scrub operation = the memory controller reads the word, decodes it, and if (and only if)
// a single error was corrected, writes the corrected word back. The response carries
//   rsp_rdata[0] = a single error was corrected (and repaired)
//   rsp_rdata[1] = uncorrectable error found (rsp_err = 1, nothing was written)
//
// The scrubber never talks to the RAM directly: it is just another requester on the native
// request port (mem_pkg). The arbiter decides when it may run, and the controller executes
// a scrub operation as one uninterrupted sequence, so it cannot collide with a CPU write.
//
// Bandwidth: one word every `interval` cycles (a register, see ecc_regs). With 1000 at 50 MHz and 2048
// words a full sweep takes about 41 ms and uses well under 1 % of the memory.
//
// `enable` only gates the START of a scrub operation; one that has begun always finishes.
// -----------------------------------------------------------------------------
module ecc_scrubber
    import mem_pkg::*;
#(
    parameter int          DEPTH     = 2048,           // words in the RAM
    parameter logic [31:0] BASE_ADDR = 32'h2000_0000   // byte address of word 0 (aligned to the RAM size)
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,              // 1 = keep scrubbing
    input  logic [31:0] interval,            // clock cycles between two scrub operations (0 or 1 = back to back)

    // ---------------- native request port (master side) ----------------
    output logic        req_valid,
    input  logic        req_ready,
    output mem_op_t     req_op,
    output logic [31:0] req_addr,
    input  logic        rsp_valid,
    input  logic [31:0] rsp_rdata,
    input  logic        rsp_err,

    // ---------------- status (for the ILA now, for registers later) ----------------
    output logic [31:0] stat_scanned,        // words scrubbed so far
    output logic [31:0] stat_repaired,       // words in which a single error was corrected and written back
    output logic [31:0] stat_ue,             // words found with an uncorrectable error
    output logic [31:0] stat_sweeps,         // completed passes over the whole RAM
    output logic [31:0] stat_addr            // byte address of the word being / last scrubbed
);
    localparam int AW = $clog2(DEPTH);

    typedef enum logic [1:0] {SC_WAIT, SC_REQ, SC_BUSY} sc_state_t;
    sc_state_t state;

    logic [AW-1:0] addr_cnt;                 // word index of the next / current scrub operation
    logic [31:0]   timer;

    // request: scrub the current word
    assign req_valid = (state == SC_REQ);
    assign req_op    = OP_SCRUB;
    assign req_addr  = {BASE_ADDR[31:AW+2], addr_cnt, 2'b00};
    assign stat_addr = req_addr;

    wire fire = req_valid && req_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= SC_WAIT;
            addr_cnt <= '0;
            timer <= 32'd0;
            stat_scanned <= 32'd0; stat_repaired <= 32'd0; stat_ue <= 32'd0; stat_sweeps <= 32'd0;
        end else begin
            case (state)
                SC_WAIT: begin
                    if (!enable) begin
                        timer <= 32'd0;                       // paused: restart the interval when re-enabled
                    end else if (timer + 32'd1 >= interval) begin
                        state <= SC_REQ;
                    end else begin
                        timer <= timer + 32'd1;
                    end
                end

                SC_REQ: if (fire) state <= SC_BUSY;

                SC_BUSY: if (rsp_valid) begin
                    stat_scanned <= stat_scanned + 32'd1;
                    if (rsp_rdata[0])           stat_repaired <= stat_repaired + 32'd1;
                    if (rsp_err | rsp_rdata[1]) stat_ue       <= stat_ue + 32'd1;
                    if (addr_cnt == AW'(DEPTH - 1)) begin       // last word: wrap around
                        addr_cnt    <= '0;
                        stat_sweeps <= stat_sweeps + 32'd1;
                    end else begin
                        addr_cnt <= addr_cnt + 1'b1;
                    end
                    timer <= 32'd0;
                    state <= SC_WAIT;
                end

                default: state <= SC_WAIT;
            endcase
        end
    end
endmodule
