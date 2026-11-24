`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mem_ctrl_ecc: memory controller with SEC-DED ECC and read-modify-write.
// Sits between the AXI4-Lite front-end (native request port, see mem_pkg) and a
// 39-bit block RAM that stores {check bits[6:0], data[31:0]}.
//
//   READ            read the 39-bit word -> ecc_dec -> return the corrected data.
//                   Uncorrectable error (ue) -> raw data + rsp_err (SLVERR on the bus).
//                   A corrected single error is NOT written back (the scrubber will do
//                   that in Stage 3); the stored word stays as it is.
//   WRITE, wstrb = 1111   ecc_enc(wdata) -> write the 39-bit word.
//   WRITE, partial wstrb  read-modify-write, one uninterrupted sequence:
//                   read -> decode/correct -> merge the strobed bytes -> encode -> write.
//                   If the stored word is uncorrectable (ue) nothing is written and the
//                   write response is an error: fresh check bits on bad data would hide it.
//   WRITE, wstrb = 0000   nothing to write: OKAY response, no memory access.
//   SCRUB           read the word -> decode; if a single error was corrected, write the corrected
//                   word back (re-encoded); if uncorrectable, write nothing. One uninterrupted
//                   sequence. The response data carries the status: bit 0 = corrected and
//                   repaired, bit 1 = uncorrectable (rsp_err is set as well).
//   INJECT          error injection (a test / demo feature): read the raw 39-bit word, write it back
//                   XOR `inj_mask` WITHOUT re-encoding, so the stored word really is damaged. No decode
//                   result is used and no error event is generated for it.
//
// One request at a time (req_ready is low until the response has been given), so the
// read-modify-write cannot be interleaved with any other access to the same word.
//
// Timing (clock cycles from the cycle the request is accepted; rsp_valid is a one-cycle pulse)
//   READ                accept (BRAM read) -> DEC -> RESP          rsp_valid in cycle 2
//   SCRUB, clean word   accept (BRAM read) -> DEC -> RESP          rsp_valid in cycle 2
//   SCRUB, repair       accept (BRAM read) -> DEC -> WR -> RESP    rsp_valid in cycle 3
//   full-word WRITE     accept             -> WR  -> RESP          rsp_valid in cycle 2
//   partial WRITE (RMW) accept (BRAM read) -> DEC -> WR -> RESP    rsp_valid in cycle 3
// The decoder result is registered in DEC, so the path BRAM output -> decoder ends in a
// register, and the encoder always works from registers.
//
// ev_* : one-cycle pulse after a decode that found an error (corrected or not). The register
//        block (ecc_regs) counts and logs these. Injection operations never produce an event.
// -----------------------------------------------------------------------------
module mem_ctrl_ecc
    import mem_pkg::*;
#(
    parameter int DEPTH = 2048                   // words in the RAM
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ---------------- native request port (mem_pkg) ----------------
    input  logic                     req_valid,
    output logic                     req_ready,
    input  mem_op_t                  req_op,
    input  logic [31:0]              req_addr,
    input  logic [31:0]              req_wdata,
    input  logic  [3:0]              req_wstrb,
    output logic                     rsp_valid,
    output logic [31:0]              rsp_rdata,
    output logic                     rsp_err,

    // ---------------- 39-bit BRAM port ----------------
    output logic                     bram_en,
    output logic                     bram_we,
    output logic [$clog2(DEPTH)-1:0] bram_addr,
    output logic [38:0]              bram_din,
    input  logic [38:0]              bram_dout,

    // ---------------- error-injection mask (used only for OP_INJECT) ----------------
    // Held stable by the injector while its request is in flight; sampled when the request is accepted.
    input  logic [38:0]              inj_mask,

    // ---------------- error events (for the next step) ----------------
    output logic                     ev_valid,   // 1-cycle pulse: this access saw an error
    output logic                     ev_scrub,   // ...and it was a scrub operation (0 = CPU access)
    output logic                     ev_ce,      // a single error was corrected
    output logic                     ev_ue,      // an uncorrectable error was detected
    output logic [31:0]              ev_addr,    // byte address of the word
    output logic  [6:0]              ev_syn,     // syndrome
    output logic  [5:0]              ev_pos      // corrected codeword bit (when ev_ce)
);
    localparam int AW = $clog2(DEPTH);

    typedef enum logic [1:0] {S_IDLE, S_DEC, S_WR, S_RESP} state_t;
    state_t state;

    // ---------------- request latched at accept ----------------
    mem_op_t     op_q;
    logic [31:0] addr_q, wdata_q;
    logic  [3:0] wstrb_q;
    logic [38:0] raw_q, inj_mask_q;      // raw stored word and injection mask (OP_INJECT)
    logic        err_q;                  // error flag for the response
    logic        st_ce_q, st_ue_q;       // decode status, registered in S_DEC (scrub response)
    wire         is_inject_q = (op_q == OP_INJECT);

    wire is_read  = (req_op == OP_READ);
    wire is_write = (req_op == OP_WRITE);
    wire is_scrub = (req_op == OP_SCRUB);
    wire is_inject = (req_op == OP_INJECT);
    wire full_wr  = &req_wstrb;          // all four bytes
    wire no_wr    = ~|req_wstrb;         // no byte
    wire fire     = req_valid && req_ready;

    assign req_ready = (state == S_IDLE);

    // ---------------- decoder on the BRAM output ----------------
    logic [31:0] dec_data;
    logic [38:0] dec_cw_unused;
    logic  [6:0] dec_syn;
    logic        dec_ce, dec_ue;
    logic  [5:0] dec_pos;

    ecc_dec u_dec (
        .cw_in    (bram_dout),
        .data_out (dec_data),
        .cw_out   (dec_cw_unused),
        .syndrome (dec_syn),
        .ce       (dec_ce),
        .ue       (dec_ue),
        .err_pos  (dec_pos)
    );

    logic [31:0] dec_data_q;             // corrected data, registered in S_DEC

    // ---------------- merge + encoder on the write path ----------------
    // merged = corrected stored word with the strobed bytes replaced by the new data.
    // For a full-word write (wstrb = 1111) every byte is replaced, so dec_data_q is ignored.
    logic [31:0] merged;
    always_comb begin
        merged = dec_data_q;
        for (int b = 0; b < 4; b++)
            if (wstrb_q[b]) merged[8*b +: 8] = wdata_q[8*b +: 8];
    end

    logic [38:0] enc_cw;
    ecc_enc u_enc (.data_in(merged), .cw_out(enc_cw));

    // normal writes store the freshly encoded word; an injection stores the RAW word with bits flipped
    assign bram_din = (op_q == OP_INJECT) ? (raw_q ^ inj_mask_q) : enc_cw;

    // ---------------- BRAM control ----------------
    always_comb begin
        bram_en   = 1'b0;
        bram_we   = 1'b0;
        bram_addr = addr_q[AW+1:2];
        case (state)
            S_IDLE: begin
                // read the word for a READ or for the first half of a read-modify-write
                bram_addr = req_addr[AW+1:2];
                bram_en   = fire && (is_read || is_scrub || is_inject || (is_write && !full_wr && !no_wr));
            end
            S_WR: begin
                bram_en = 1'b1;
                bram_we = 1'b1;
            end
            default: ;
        endcase
    end

    // ---------------- response ----------------
    assign rsp_valid = (state == S_RESP);
    always_comb begin
        rsp_rdata = 32'h0000_0000;
        if (op_q == OP_READ)       rsp_rdata = dec_data_q;
        else if (op_q == OP_SCRUB) rsp_rdata = {30'd0, st_ue_q, st_ce_q};
    end
    assign rsp_err   = err_q;

    // ---------------- state machine ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            op_q <= OP_READ; addr_q <= '0; wdata_q <= '0; wstrb_q <= '0;
            err_q <= 1'b0;
            raw_q <= '0; inj_mask_q <= '0;
            st_ce_q <= 1'b0; st_ue_q <= 1'b0;
            dec_data_q <= '0;
            ev_valid <= 1'b0; ev_scrub <= 1'b0; ev_ce <= 1'b0; ev_ue <= 1'b0;
            ev_addr <= '0; ev_syn <= '0; ev_pos <= '0;
        end else begin
            ev_valid <= 1'b0;                        // pulse, default low

            case (state)
                S_IDLE: if (fire) begin
                    op_q    <= req_op;
                    addr_q  <= req_addr;
                    wdata_q <= req_wdata;
                    wstrb_q <= req_wstrb;
                    err_q   <= 1'b0;
                    if (is_read) begin
                        state <= S_DEC;
                    end else if (is_scrub) begin
                        wstrb_q <= 4'b0000;                  // no byte replaced: write-back re-encodes the corrected data
                        state   <= S_DEC;
                    end else if (is_inject) begin
                        inj_mask_q <= inj_mask;              // take the mask now
                        wstrb_q    <= 4'b0000;
                        state      <= S_DEC;                 // read the raw word first
                    end else if (is_write) begin
                        if (full_wr)      state <= S_WR;     // encode and write directly
                        else if (no_wr)   state <= S_RESP;   // nothing to write
                        else              state <= S_DEC;    // read-modify-write: read first
                    end else begin
                        err_q <= 1'b1;                       // unknown operation
                        state <= S_RESP;
                    end
                end

                S_DEC: begin
                    // the BRAM output is valid now: register the decoder result
                    dec_data_q <= dec_data;
                    raw_q      <= bram_dout;                 // raw stored word (used by OP_INJECT)
                    st_ce_q    <= dec_ce;
                    st_ue_q    <= dec_ue;
                    ev_scrub   <= (op_q == OP_SCRUB);
                    ev_valid   <= (dec_ce | dec_ue) & ~is_inject_q;   // an injection is not an "error found"
                    ev_ce      <= dec_ce;
                    ev_ue      <= dec_ue;
                    ev_addr    <= addr_q;
                    ev_syn     <= dec_syn;
                    ev_pos     <= dec_pos;
                    if (op_q == OP_READ) begin
                        err_q <= dec_ue;                     // uncorrectable -> SLVERR
                        state <= S_RESP;
                    end else if (op_q == OP_INJECT) begin
                        state <= S_WR;                       // write back raw ^ mask
                    end else if (op_q == OP_SCRUB) begin
                        err_q <= dec_ue;                     // uncorrectable: report, do not write
                        state <= dec_ce ? S_WR : S_RESP;     // repair only a corrected single error
                    end else if (dec_ue) begin
                        err_q <= 1'b1;                       // read-modify-write aborted, no write
                        state <= S_RESP;
                    end else begin
                        state <= S_WR;                       // merge + encode + write
                    end
                end

                S_WR:   state <= S_RESP;

                S_RESP: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
