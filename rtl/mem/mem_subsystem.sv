`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mem_subsystem: everything behind the two AXI4-Lite windows of the controller.
//
//   s_mem_*  : protected data RAM     (CPU 0x2000_0000)
//   s_reg_*  : ECC control registers  (CPU 0x4000_0000)
//
// DATA RAM PATH (ECC + scrubber + injector)
//
//   s_mem -> axil_frontend --(CPU)--> mem_arbiter --> mem_ctrl_ecc -> bram_sp (39 bit)
//                                      ^   ^             ecc_enc / ecc_dec, read-modify-write,
//                                      |   |             scrub operation, injection
//                          ecc_scrubber    ecc_injector  (background requesters)
//
// REGISTER PATH
//
//   s_reg -> axil_frontend -> ecc_regs : counters, error log, scrubber control, injection control,
//                                        interrupt lines. Fed by the ev_* events of mem_ctrl_ecc.
// -----------------------------------------------------------------------------
module mem_subsystem
    import mem_pkg::*;
#(
    parameter int DEPTH          = 2048,   // data RAM words (8 KB)
    parameter     DMEM_INIT      = "",     // optional preload (39-bit codewords, not raw data)
    parameter int SCRUB_ENABLE   = 1,      // 1 = the scrubber may run (the CTRL.SCRUB_EN register bit also has to be 1)
    parameter int SCRUB_INTERVAL = 1000,   // reset value of the SCRUB_INTERVAL register (cycles between scrub operations)
    parameter int SCRUB_PATIENCE = 256     // cycles the scrubber may wait before it wins against the CPU
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------- AXI4-Lite slave: data RAM ----------------
    input  logic [31:0] s_mem_awaddr,
    input  logic        s_mem_awvalid,
    output logic        s_mem_awready,
    input  logic [31:0] s_mem_wdata,
    input  logic  [3:0] s_mem_wstrb,
    input  logic        s_mem_wvalid,
    output logic        s_mem_wready,
    output logic  [1:0] s_mem_bresp,
    output logic        s_mem_bvalid,
    input  logic        s_mem_bready,
    input  logic [31:0] s_mem_araddr,
    input  logic        s_mem_arvalid,
    output logic        s_mem_arready,
    output logic [31:0] s_mem_rdata,
    output logic  [1:0] s_mem_rresp,
    output logic        s_mem_rvalid,
    input  logic        s_mem_rready,

    // ---------------- AXI4-Lite slave: registers ----------------
    input  logic [31:0] s_reg_awaddr,
    input  logic        s_reg_awvalid,
    output logic        s_reg_awready,
    input  logic [31:0] s_reg_wdata,
    input  logic  [3:0] s_reg_wstrb,
    input  logic        s_reg_wvalid,
    output logic        s_reg_wready,
    output logic  [1:0] s_reg_bresp,
    output logic        s_reg_bvalid,
    input  logic        s_reg_bready,
    input  logic [31:0] s_reg_araddr,
    input  logic        s_reg_arvalid,
    output logic        s_reg_arready,
    output logic [31:0] s_reg_rdata,
    output logic  [1:0] s_reg_rresp,
    output logic        s_reg_rvalid,
    input  logic        s_reg_rready,

    // ---------------- hardware injection triggers: ONE-CYCLE PULSES (e.g. debounced board buttons) ----------------
    input  logic        hw_inj_single,    // flip one random bit of the word at INJ_ADDR
    input  logic        hw_inj_double,    // flip two random bits of the word at INJ_ADDR

    // ---------------- interrupt lines (levels) ----------------
    output logic        irq_ue,           // uncorrectable error seen and CTRL.IRQ_UE_EN set
    output logic        irq_ce            // corrected error seen and CTRL.IRQ_CE_EN set
);
    localparam int AW = $clog2(DEPTH);

    // ================= data RAM path =================
    (* mark_debug = "true" *) logic        m_req_valid;
    (* mark_debug = "true" *) logic        m_req_ready;
    (* mark_debug = "true" *) mem_op_t     m_req_op;
    (* mark_debug = "true" *) logic [31:0] m_req_addr;
    (* mark_debug = "true" *) logic [31:0] m_req_wdata;
    (* mark_debug = "true" *) logic  [3:0] m_req_wstrb;
    (* mark_debug = "true" *) logic        m_rsp_valid;
    (* mark_debug = "true" *) logic [31:0] m_rsp_rdata;
    (* mark_debug = "true" *) logic        m_rsp_err;

    axil_frontend u_fe_mem (
        .clk, .rst_n,
        .s_awaddr (s_mem_awaddr),  .s_awvalid(s_mem_awvalid), .s_awready(s_mem_awready),
        .s_wdata  (s_mem_wdata),   .s_wstrb  (s_mem_wstrb),   .s_wvalid (s_mem_wvalid),
        .s_wready (s_mem_wready),  .s_bresp  (s_mem_bresp),   .s_bvalid (s_mem_bvalid),
        .s_bready (s_mem_bready),  .s_araddr (s_mem_araddr),  .s_arvalid(s_mem_arvalid),
        .s_arready(s_mem_arready), .s_rdata  (s_mem_rdata),   .s_rresp  (s_mem_rresp),
        .s_rvalid (s_mem_rvalid),  .s_rready (s_mem_rready),
        .req_valid(m_req_valid), .req_ready(m_req_ready), .req_op(m_req_op),
        .req_addr (m_req_addr),  .req_wdata(m_req_wdata), .req_wstrb(m_req_wstrb),
        .rsp_valid(m_rsp_valid), .rsp_rdata(m_rsp_rdata), .rsp_err(m_rsp_err)
    );

    // ---------------- memory controller side of the arbiter ----------------
    (* mark_debug = "true" *) logic        c_req_valid;
    (* mark_debug = "true" *) logic        c_req_ready;
    (* mark_debug = "true" *) mem_op_t     c_req_op;
    (* mark_debug = "true" *) logic [31:0] c_req_addr;
    logic [31:0] c_req_wdata;
    logic  [3:0] c_req_wstrb;
    (* mark_debug = "true" *) logic        c_rsp_valid;
    logic [31:0] c_rsp_rdata;
    (* mark_debug = "true" *) logic        c_rsp_err;

    // ---------------- scrubber side of the arbiter ----------------
    logic        sc_req_valid, sc_req_ready, sc_rsp_valid, sc_rsp_err;
    mem_op_t     sc_req_op;
    logic [31:0] sc_req_addr, sc_rsp_rdata;
    logic        reg_scrub_en;                         // CTRL.SCRUB_EN
    logic [31:0] reg_scrub_interval;                   // SCRUB_INTERVAL register
    wire         scrub_enable = (SCRUB_ENABLE != 0) && reg_scrub_en;   // a wire, so a testbench can force it

    (* mark_debug = "true" *) logic [31:0] scrub_scanned, scrub_repaired, scrub_ue, scrub_sweeps, scrub_addr;

    // ---------------- injector side of the arbiter ----------------
    logic        ij_req_valid, ij_req_ready, ij_rsp_valid, ij_rsp_err;
    mem_op_t     ij_req_op;
    logic [31:0] ij_req_addr, ij_rsp_rdata;
    logic [38:0] ij_mask;                              // side-band mask for the memory controller
    logic        ij_busy;
    (* mark_debug = "true" *) logic [31:0] ij_count;

    mem_arbiter #(.PATIENCE(SCRUB_PATIENCE)) u_arb (
        .clk, .rst_n,
        .cpu_req_valid(m_req_valid), .cpu_req_ready(m_req_ready), .cpu_req_op(m_req_op),
        .cpu_req_addr (m_req_addr),  .cpu_req_wdata(m_req_wdata), .cpu_req_wstrb(m_req_wstrb),
        .cpu_rsp_valid(m_rsp_valid), .cpu_rsp_rdata(m_rsp_rdata), .cpu_rsp_err(m_rsp_err),
        .scr_req_valid(sc_req_valid), .scr_req_ready(sc_req_ready), .scr_req_op(sc_req_op),
        .scr_req_addr (sc_req_addr),
        .scr_rsp_valid(sc_rsp_valid), .scr_rsp_rdata(sc_rsp_rdata), .scr_rsp_err(sc_rsp_err),
        .inj_req_valid(ij_req_valid), .inj_req_ready(ij_req_ready), .inj_req_op(ij_req_op),
        .inj_req_addr (ij_req_addr),
        .inj_rsp_valid(ij_rsp_valid), .inj_rsp_rdata(ij_rsp_rdata), .inj_rsp_err(ij_rsp_err),
        .c_req_valid, .c_req_ready, .c_req_op, .c_req_addr, .c_req_wdata, .c_req_wstrb,
        .c_rsp_valid, .c_rsp_rdata, .c_rsp_err
    );

    ecc_scrubber #(.DEPTH(DEPTH), .BASE_ADDR(32'h2000_0000)) u_scrub (
        .clk, .rst_n,
        .enable(scrub_enable), .interval(reg_scrub_interval),
        .req_valid(sc_req_valid), .req_ready(sc_req_ready), .req_op(sc_req_op), .req_addr(sc_req_addr),
        .rsp_valid(sc_rsp_valid), .rsp_rdata(sc_rsp_rdata), .rsp_err(sc_rsp_err),
        .stat_scanned(scrub_scanned), .stat_repaired(scrub_repaired), .stat_ue(scrub_ue),
        .stat_sweeps(scrub_sweeps), .stat_addr(scrub_addr)
    );

    logic          bram_en;
    logic          bram_we;                     // one write enable for the whole 39-bit word
    logic [AW-1:0] bram_addr;
    logic [38:0]   bram_din, bram_dout;         // stored word = {7 check bits, 32 data bits}

    // error events from the ECC controller (counted and logged by ecc_regs)
    (* mark_debug = "true" *) logic        ev_valid, ev_scrub, ev_ce, ev_ue;
    (* mark_debug = "true" *) logic [31:0] ev_addr;
    (* mark_debug = "true" *) logic  [6:0] ev_syn;
    (* mark_debug = "true" *) logic  [5:0] ev_pos;

    mem_ctrl_ecc #(.DEPTH(DEPTH)) u_ctrl (
        .clk, .rst_n,
        .req_valid(c_req_valid), .req_ready(c_req_ready), .req_op(c_req_op),
        .req_addr (c_req_addr),  .req_wdata(c_req_wdata), .req_wstrb(c_req_wstrb),
        .rsp_valid(c_rsp_valid), .rsp_rdata(c_rsp_rdata), .rsp_err(c_rsp_err),
        .bram_en, .bram_we, .bram_addr, .bram_din, .bram_dout,
        .inj_mask(ij_mask),
        .ev_valid, .ev_scrub, .ev_ce, .ev_ue, .ev_addr, .ev_syn, .ev_pos
    );

    // 39-bit RAM, one write enable. Contents start at zero, and an all-zero word is a valid
    // codeword, so no initialisation pass is needed. If DMEM_INIT is used, the file must hold
    // 39-bit CODEWORDS (data + check bits), not raw data words.
    bram_sp #(.DEPTH(DEPTH), .WIDTH(39), .NLANES(1), .INIT_FILE(DMEM_INIT)) u_bram (
        .clk, .en(bram_en), .we(bram_we), .addr(bram_addr), .din(bram_din), .dout(bram_dout)
    );

    // ================= register path =================
    logic        r_req_valid, r_req_ready, r_rsp_valid, r_rsp_err;
    mem_op_t     r_req_op;
    logic [31:0] r_req_addr, r_req_wdata, r_rsp_rdata;
    logic  [3:0] r_req_wstrb;

    axil_frontend u_fe_reg (
        .clk, .rst_n,
        .s_awaddr (s_reg_awaddr),  .s_awvalid(s_reg_awvalid), .s_awready(s_reg_awready),
        .s_wdata  (s_reg_wdata),   .s_wstrb  (s_reg_wstrb),   .s_wvalid (s_reg_wvalid),
        .s_wready (s_reg_wready),  .s_bresp  (s_reg_bresp),   .s_bvalid (s_reg_bvalid),
        .s_bready (s_reg_bready),  .s_araddr (s_reg_araddr),  .s_arvalid(s_reg_arvalid),
        .s_arready(s_reg_arready), .s_rdata  (s_reg_rdata),   .s_rresp  (s_reg_rresp),
        .s_rvalid (s_reg_rvalid),  .s_rready (s_reg_rready),
        .req_valid(r_req_valid), .req_ready(r_req_ready), .req_op(r_req_op),
        .req_addr (r_req_addr),  .req_wdata(r_req_wdata), .req_wstrb(r_req_wstrb),
        .rsp_valid(r_rsp_valid), .rsp_rdata(r_rsp_rdata), .rsp_err(r_rsp_err)
    );

    // ---------------- injection settings from the registers ----------------
    logic        rg_inj_go, rg_inj_random, rg_inj_double;
    logic [31:0] rg_inj_addr;
    logic [38:0] rg_inj_mask;

    ecc_regs #(.SCRUB_INTERVAL_DEFAULT(SCRUB_INTERVAL)) u_regs (
        .clk, .rst_n,
        .req_valid(r_req_valid), .req_ready(r_req_ready), .req_op(r_req_op),
        .req_addr (r_req_addr),  .req_wdata(r_req_wdata), .req_wstrb(r_req_wstrb),
        .rsp_valid(r_rsp_valid), .rsp_rdata(r_rsp_rdata), .rsp_err(r_rsp_err),
        .ev_valid, .ev_scrub, .ev_ce, .ev_ue, .ev_addr, .ev_syn, .ev_pos,
        .scrub_repaired, .scrub_sweeps,
        .scrub_enable(reg_scrub_en), .scrub_interval(reg_scrub_interval),
        .inj_go(rg_inj_go), .inj_random(rg_inj_random), .inj_double(rg_inj_double),
        .inj_addr(rg_inj_addr), .inj_mask(rg_inj_mask),
        .inj_busy(ij_busy), .inj_count(ij_count),
        .irq_ue, .irq_ce
    );

    ecc_injector u_inj (
        .clk, .rst_n,
        .go_reg(rg_inj_go), .use_random(rg_inj_random), .random_double(rg_inj_double),
        .hw_single(hw_inj_single), .hw_double(hw_inj_double),
        .inj_addr(rg_inj_addr), .inj_mask_reg(rg_inj_mask),
        .req_valid(ij_req_valid), .req_ready(ij_req_ready), .req_op(ij_req_op), .req_addr(ij_req_addr),
        .rsp_valid(ij_rsp_valid),
        .inj_mask(ij_mask), .busy(ij_busy), .inj_count(ij_count)
    );
endmodule
