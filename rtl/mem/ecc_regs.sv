`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_regs: register block of the ECC memory system, behind the 0x4000_0000 window.
// It counts and logs the error events of the memory controller, controls the scrubber and the
// error injector, and raises the interrupt lines.
//
// Register map (byte offsets; every register is 32 bits, byte strobes are honoured on writes)
//
//  0x00 ID            RO   0x5031_2001
//  0x04 SCRATCH0      RW   scratch
//  0x08 SCRATCH1      RW   scratch
//  0x0C SCRATCH2      RW   scratch (the simulation testbenches use it as a result signature)
//  0x10 CTRL          RW   [0] SCRUB_EN   scrubber on (reset: 1)
//                          [1] IRQ_UE_EN  interrupt line irq_ue follows UE_SEEN (reset: 0)
//                          [2] IRQ_CE_EN  interrupt line irq_ce follows CE_SEEN (reset: 0)
//                          [4] CLEAR      write 1: clear CE_COUNT, UE_COUNT and the log (reads 0)
//  0x14 STATUS        R/W1C [0] CE_SEEN     a corrected error has been seen since the flag was cleared
//                          [1] UE_SEEN     an uncorrectable error has been seen (this drives irq_ue)
//                          [2] LOG_OVERRUN an error could not be logged because the log was full
//                          [3] INJ_BUSY    (RO) an injection is in progress
//                          [11:8] LOG_LEVEL (RO) number of entries in the log
//                          write 1 to bits 0..2 to clear them
//  0x18 CE_COUNT      RO   corrected single-bit errors seen (CPU accesses and scrubber), saturating
//  0x1C UE_COUNT      RO   uncorrectable errors seen (CPU accesses and scrubber), saturating
//  0x20 LOG_ADDR      RO   byte address of the oldest log entry (0 when the log is empty)
//  0x24 LOG_INFO      R/W  oldest log entry: [6:0] syndrome, [13:8] corrected bit (valid if not UE),
//                          [16] 1 = uncorrectable, [17] 1 = found by the scrubber.  ANY WRITE = pop it
//  0x28 SCRUB_INTERVAL RW  clock cycles between two scrub operations (reset: the parameter)
//  0x2C SCRUB_REPAIRED RO  words repaired by the scrubber
//  0x30 SCRUB_SWEEPS  RO   completed sweeps over the whole RAM
//  0x34 INJ_ADDR      RW   byte address of the word to damage
//  0x38 INJ_MASK_LO   RW   mask bits 31..0   (1 = flip that stored bit; bit n = codeword bit n)
//  0x3C INJ_MASK_HI   RW   mask bits 38..32  (check bits c0..c6)
//  0x40 INJ_CTRL      RW   [0] GO (write 1 to inject, reads 0)  [1] RANDOM  [2] DOUBLE  [8] BUSY (RO)
//  0x44 INJ_COUNT     RO   injections completed
//
// Error log: a FIFO of LOG_DEPTH entries. Every event found by the controller is logged, except
// that an uncorrectable word found AGAIN by the scrubber in every sweep is logged once until the
// firmware pops an entry (otherwise the log would fill with repeats). When the log is full the new
// entry is dropped and LOG_OVERRUN is set; the counters still count it.
// An event in the very clock cycle of a CLEAR write is counted but not logged.
//
// Interrupts: irq_ue = UE_SEEN & IRQ_UE_EN, irq_ce = CE_SEEN & IRQ_CE_EN. Both are LEVELS: they stay
// high until the firmware clears the flag in STATUS. A persistent uncorrectable word is found again in
// every scrubber sweep, so the flag (and the interrupt) comes back until the word is rewritten.
// -----------------------------------------------------------------------------
module ecc_regs
    import mem_pkg::*;
#(
    parameter int SCRUB_INTERVAL_DEFAULT = 1000,
    parameter int LOG_DEPTH              = 8          // power of two, at most 8 (LOG_LEVEL is 4 bits)
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------- native request port (slave side) ----------------
    input  logic        req_valid,
    output logic        req_ready,
    input  mem_op_t     req_op,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic  [3:0] req_wstrb,
    output logic        rsp_valid,
    output logic [31:0] rsp_rdata,
    output logic        rsp_err,

    // ---------------- error events from the memory controller ----------------
    input  logic        ev_valid,
    input  logic        ev_scrub,
    input  logic        ev_ce,
    input  logic        ev_ue,
    input  logic [31:0] ev_addr,
    input  logic  [6:0] ev_syn,
    input  logic  [5:0] ev_pos,

    // ---------------- scrubber ----------------
    input  logic [31:0] scrub_repaired,
    input  logic [31:0] scrub_sweeps,
    output logic        scrub_enable,
    output logic [31:0] scrub_interval,

    // ---------------- injector ----------------
    output logic        inj_go,                 // 1-cycle pulse, one cycle after the GO write
    output logic        inj_random,
    output logic        inj_double,
    output logic [31:0] inj_addr,
    output logic [38:0] inj_mask,
    input  logic        inj_busy,
    input  logic [31:0] inj_count,

    // ---------------- interrupts ----------------
    output logic        irq_ue,
    output logic        irq_ce
);
    localparam logic [31:0] ID_VALUE = 32'h5031_2001;
    localparam int PW = $clog2(LOG_DEPTH);

    // ================= native request handling =================
    logic        busy;
    logic [31:0] rdata_q;
    assign req_ready = !busy;
    assign rsp_valid = busy;
    assign rsp_rdata = rdata_q;
    assign rsp_err   = 1'b0;

    wire        fire  = req_valid && req_ready;
    wire        is_wr = (req_op == OP_WRITE);
    wire  [5:0] idx   = req_addr[7:2];          // register number (offset / 4)

    function automatic logic [31:0] wmerge(input logic [31:0] old_v, input logic [31:0] new_v, input logic [3:0] st);
        logic [31:0] r;
        r = old_v;
        for (int b = 0; b < 4; b++)
            if (st[b]) r[8*b +: 8] = new_v[8*b +: 8];
        wmerge = r;
    endfunction

    // ================= register storage =================
    logic [31:0] scratch [0:2];                      // an array: the Stage 1 testbenches read scratch[2] by name
    logic        ctrl_scrub_en, ctrl_irq_ue_en, ctrl_irq_ce_en;
    logic [31:0] scrub_interval_r;
    logic [31:0] inj_addr_r, inj_mask_lo;
    logic  [6:0] inj_mask_hi;
    logic        inj_random_r, inj_double_r;
    logic        go_q;

    assign scrub_enable   = ctrl_scrub_en;
    assign scrub_interval = scrub_interval_r;
    assign inj_go         = go_q;
    assign inj_random     = inj_random_r;
    assign inj_double     = inj_double_r;
    assign inj_addr       = inj_addr_r;
    assign inj_mask       = {inj_mask_hi, inj_mask_lo};

    // ================= commands decoded from register writes =================
    wire wr_ctrl   = fire && is_wr && (idx == 6'd4)  && req_wstrb[0];
    wire wr_status = fire && is_wr && (idx == 6'd5)  && req_wstrb[0];
    wire wr_log    = fire && is_wr && (idx == 6'd9);
    wire wr_injctl = fire && is_wr && (idx == 6'd16) && req_wstrb[0];

    wire clr_cmd   = wr_ctrl && req_wdata[4];
    wire clr_ce    = wr_status && req_wdata[0];
    wire clr_ue    = wr_status && req_wdata[1];
    wire clr_ovr   = wr_status && req_wdata[2];
    wire pop_cmd   = wr_log;
    wire go_cmd    = wr_injctl && req_wdata[0];

    // ================= event counters and sticky flags =================
    (* mark_debug = "true" *) logic [31:0] ce_count, ue_count;
    logic        ce_seen, ue_seen, overrun;

    wire ev_ce_p = ev_valid & ev_ce;
    wire ev_ue_p = ev_valid & ev_ue;

    // ================= error log FIFO =================
    logic [31:0]   log_addr_mem [0:LOG_DEPTH-1];
    logic [31:0]   log_info_mem [0:LOG_DEPTH-1];
    logic [PW-1:0] rd_ptr, wr_ptr;
    logic [PW:0]   level;
    logic          scrub_ue_logged;       // a scrubber-found uncorrectable word is already in the log

    wire dedupe_skip = ev_valid && ev_scrub && ev_ue && scrub_ue_logged;
    wire want_push   = ev_valid && !dedupe_skip;
    wire can_push    = (level != (PW+1)'(LOG_DEPTH));
    wire do_push     = want_push && can_push && !clr_cmd;
    wire do_pop      = pop_cmd && (level != '0);
    wire overrun_ev  = want_push && !can_push;

    logic [31:0] info_in;
    always_comb begin
        info_in        = 32'd0;
        info_in[6:0]   = ev_syn;
        info_in[13:8]  = ev_pos;
        info_in[16]    = ev_ue;
        info_in[17]    = ev_scrub;
    end

    wire [31:0] head_addr = (level != '0) ? log_addr_mem[rd_ptr] : 32'd0;
    wire [31:0] head_info = (level != '0) ? log_info_mem[rd_ptr] : 32'd0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ce_count <= 32'd0; ue_count <= 32'd0;
            ce_seen <= 1'b0; ue_seen <= 1'b0; overrun <= 1'b0;
            rd_ptr <= '0; wr_ptr <= '0; level <= '0; scrub_ue_logged <= 1'b0;
        end else begin
            // --- counters: a CLEAR write restarts them, an event in the same cycle is still counted ---
            if (clr_cmd) begin
                ce_count <= ev_ce_p ? 32'd1 : 32'd0;
                ue_count <= ev_ue_p ? 32'd1 : 32'd0;
            end else begin
                if (ev_ce_p && ce_count != 32'hFFFF_FFFF) ce_count <= ce_count + 32'd1;
                if (ev_ue_p && ue_count != 32'hFFFF_FFFF) ue_count <= ue_count + 32'd1;
            end
            // --- sticky flags: write-1-to-clear; a new event wins over a simultaneous clear ---
            ce_seen <= (ce_seen & ~clr_ce) | ev_ce_p;
            ue_seen <= (ue_seen & ~clr_ue) | ev_ue_p;
            overrun <= (overrun & ~clr_ovr) | overrun_ev;

            // --- log FIFO ---
            if (clr_cmd) begin
                rd_ptr <= '0; wr_ptr <= '0; level <= '0; scrub_ue_logged <= 1'b0;
            end else begin
                if (do_push) begin
                    log_addr_mem[wr_ptr] <= ev_addr;
                    log_info_mem[wr_ptr] <= info_in;
                    wr_ptr <= wr_ptr + 1'b1;
                    if (ev_scrub && ev_ue) scrub_ue_logged <= 1'b1;
                end
                if (do_pop) begin
                    rd_ptr <= rd_ptr + 1'b1;
                    scrub_ue_logged <= 1'b0;                 // acknowledged: report it again if it persists
                end
                level <= level + (PW+1)'(do_push) - (PW+1)'(do_pop);
            end
        end
    end

    assign irq_ue = ue_seen & ctrl_irq_ue_en;
    assign irq_ce = ce_seen & ctrl_irq_ce_en;

    // ================= register reads and writes =================
    logic [31:0] status_val;
    always_comb begin
        status_val        = 32'd0;
        status_val[0]     = ce_seen;
        status_val[1]     = ue_seen;
        status_val[2]     = overrun;
        status_val[3]     = inj_busy;
        status_val[11:8]  = 4'(level);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; rdata_q <= '0;
            scratch[0] <= '0; scratch[1] <= '0; scratch[2] <= '0;
            ctrl_scrub_en <= 1'b1; ctrl_irq_ue_en <= 1'b0; ctrl_irq_ce_en <= 1'b0;
            scrub_interval_r <= 32'(SCRUB_INTERVAL_DEFAULT);
            inj_addr_r <= '0; inj_mask_lo <= '0; inj_mask_hi <= '0;
            inj_random_r <= 1'b0; inj_double_r <= 1'b0;
            go_q <= 1'b0;
        end else begin
            busy <= fire;                               // respond one cycle after accepting
            go_q <= go_cmd;                             // GO takes effect after the other fields are updated

            if (fire) begin
                if (is_wr) begin
                    rdata_q <= 32'd0;
                    case (idx)
                        6'd1:  scratch[0] <= wmerge(scratch[0], req_wdata, req_wstrb);
                        6'd2:  scratch[1] <= wmerge(scratch[1], req_wdata, req_wstrb);
                        6'd3:  scratch[2] <= wmerge(scratch[2], req_wdata, req_wstrb);
                        6'd4:  if (req_wstrb[0]) begin
                                   ctrl_scrub_en  <= req_wdata[0];
                                   ctrl_irq_ue_en <= req_wdata[1];
                                   ctrl_irq_ce_en <= req_wdata[2];
                               end
                        6'd10: scrub_interval_r <= wmerge(scrub_interval_r, req_wdata, req_wstrb);
                        6'd13: inj_addr_r       <= wmerge(inj_addr_r, req_wdata, req_wstrb);
                        6'd14: inj_mask_lo      <= wmerge(inj_mask_lo, req_wdata, req_wstrb);
                        6'd15: if (req_wstrb[0]) inj_mask_hi <= req_wdata[6:0];
                        6'd16: if (req_wstrb[0]) begin
                                   inj_random_r <= req_wdata[1];
                                   inj_double_r <= req_wdata[2];
                               end
                        default: ;                      // read-only / unmapped: ignored
                    endcase
                end else begin
                    case (idx)
                        6'd0:  rdata_q <= ID_VALUE;
                        6'd1:  rdata_q <= scratch[0];
                        6'd2:  rdata_q <= scratch[1];
                        6'd3:  rdata_q <= scratch[2];
                        6'd4:  rdata_q <= {29'd0, ctrl_irq_ce_en, ctrl_irq_ue_en, ctrl_scrub_en};
                        6'd5:  rdata_q <= status_val;
                        6'd6:  rdata_q <= ce_count;
                        6'd7:  rdata_q <= ue_count;
                        6'd8:  rdata_q <= head_addr;
                        6'd9:  rdata_q <= head_info;
                        6'd10: rdata_q <= scrub_interval_r;
                        6'd11: rdata_q <= scrub_repaired;
                        6'd12: rdata_q <= scrub_sweeps;
                        6'd13: rdata_q <= inj_addr_r;
                        6'd14: rdata_q <= inj_mask_lo;
                        6'd15: rdata_q <= {25'd0, inj_mask_hi};
                        6'd16: rdata_q <= {23'd0, inj_busy, 5'd0, inj_double_r, inj_random_r, 1'b0};
                        6'd17: rdata_q <= inj_count;
                        default: rdata_q <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
