`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// soc_top: single-core system for P12. Replaces the dual-core core_top.
//
//   rv32i_core --fetch--> itcm port A
//       |
//       +-- AXI4-Lite --> axil_decoder --+-- 0 ITCM read port  (frontend + mem_ctrl RO -> itcm port B)
//                                        +-- 1 data RAM        (mem_subsystem s_mem)
//                                        +-- 2 ECC registers   (mem_subsystem s_reg)
//                                        +-- 3 GPIO
//                                        +-- 4 UART TX
//
// rst_n must already be synchronised to clk (see zybo_top).
// Board buttons BTN1 / BTN2 trigger error injection (debounced, see btn_pulse).
// Signals marked (* mark_debug *) are the Stage-1 ILA probe set.
// -----------------------------------------------------------------------------
module soc_top
    import mem_pkg::*;
#(
    parameter int ITCM_DEPTH   = 4096,               // 16 KB
    parameter int DMEM_DEPTH   = 2048,               // 8 KB
    parameter     ITCM_INIT    = "firmware.hex",
    parameter     DMEM_INIT    = "",
    parameter int CLKS_PER_BIT = 434,                // 50 MHz / 115200
    parameter int BTN_DEBOUNCE = 500000              // button debounce time in clock cycles (10 ms at 50 MHz)
)(
    input  logic       clk,
    input  logic       rst_n,
    output logic [3:0] led,
    input  logic [3:0] sw,
    input  logic [3:0] btn,
    output logic       uart_tx,
    output logic       irq_ue,               // uncorrectable error seen (level; also the core's interrupt together with irq_ce)
    output logic       irq_ce                // corrected error seen (level, optional)
);
    localparam int N = 5;
    localparam int IAW = $clog2(ITCM_DEPTH);

    // ---------------- core ----------------
    logic [31:0] itcm_addr, itcm_rdata;
    logic        itcm_en;

    (* mark_debug = "true" *) logic [31:0] c_awaddr;
    (* mark_debug = "true" *) logic        c_awvalid, c_awready;
    (* mark_debug = "true" *) logic [31:0] c_wdata;
    (* mark_debug = "true" *) logic  [3:0] c_wstrb;
    (* mark_debug = "true" *) logic        c_wvalid, c_wready;
    (* mark_debug = "true" *) logic  [1:0] c_bresp;
    (* mark_debug = "true" *) logic        c_bvalid, c_bready;
    (* mark_debug = "true" *) logic [31:0] c_araddr;
    (* mark_debug = "true" *) logic        c_arvalid, c_arready;
    (* mark_debug = "true" *) logic [31:0] c_rdata;
    (* mark_debug = "true" *) logic  [1:0] c_rresp;
    (* mark_debug = "true" *) logic        c_rvalid, c_rready;

    // The two interrupt lines of the ECC system are the core's machine external interrupt (level).
    // They only matter if the firmware sets CTRL.IRQ_UE_EN / IRQ_CE_EN in the ECC block AND mie.MEIE and mstatus.MIE in the core.
    // (A wire, so that a testbench can force it to produce interrupts at chosen moments.)
    wire core_irq = irq_ue | irq_ce;

    rv32i_core u_core (
        .clk, .rst_n,
        .ext_irq(core_irq),
        .itcm_addr, .itcm_en, .itcm_rdata,
        .m_axi_awaddr(c_awaddr), .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
        .m_axi_wdata(c_wdata), .m_axi_wstrb(c_wstrb), .m_axi_wvalid(c_wvalid), .m_axi_wready(c_wready),
        .m_axi_bresp(c_bresp), .m_axi_bvalid(c_bvalid), .m_axi_bready(c_bready),
        .m_axi_araddr(c_araddr), .m_axi_arvalid(c_arvalid), .m_axi_arready(c_arready),
        .m_axi_rdata(c_rdata), .m_axi_rresp(c_rresp), .m_axi_rvalid(c_rvalid), .m_axi_rready(c_rready)
    );

    // ---------------- ITCM ----------------
    logic           itcm_b_en;
    logic [IAW-1:0] itcm_b_addr;
    logic [31:0]    itcm_b_dout;

    itcm #(.DEPTH(ITCM_DEPTH), .INIT_FILE(ITCM_INIT)) u_itcm (
        .clk,
        .en_a(itcm_en), .addr_a(itcm_addr[IAW+1:2]), .dout_a(itcm_rdata),
        .en_b(itcm_b_en), .addr_b(itcm_b_addr), .dout_b(itcm_b_dout)
    );

    // ---------------- decoder ----------------
    logic [31:0]        m_awaddr, m_wdata, m_araddr;
    logic  [3:0]        m_wstrb;
    logic [N-1:0]       m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    logic [N-1:0]       m_arvalid, m_arready, m_rvalid, m_rready;
    logic [N-1:0][1:0]  m_bresp, m_rresp;
    logic [N-1:0][31:0] m_rdata;

    axil_decoder #(.N_SLV(N)) u_dec (
        .clk, .rst_n,
        .s_awaddr(c_awaddr), .s_awvalid(c_awvalid), .s_awready(c_awready),
        .s_wdata(c_wdata), .s_wstrb(c_wstrb), .s_wvalid(c_wvalid), .s_wready(c_wready),
        .s_bresp(c_bresp), .s_bvalid(c_bvalid), .s_bready(c_bready),
        .s_araddr(c_araddr), .s_arvalid(c_arvalid), .s_arready(c_arready),
        .s_rdata(c_rdata), .s_rresp(c_rresp), .s_rvalid(c_rvalid), .s_rready(c_rready),
        .m_awaddr, .m_awvalid, .m_awready, .m_wdata, .m_wstrb, .m_wvalid, .m_wready,
        .m_bresp, .m_bvalid, .m_bready, .m_araddr, .m_arvalid, .m_arready,
        .m_rdata, .m_rresp, .m_rvalid, .m_rready
    );

    // ---------------- slave 0: ITCM read port ----------------
    logic        i_req_valid, i_req_ready, i_rsp_valid, i_rsp_err;
    mem_op_t     i_req_op;
    logic [31:0] i_req_addr, i_req_wdata, i_rsp_rdata;
    logic  [3:0] i_req_wstrb, i_bram_we_unused;
    logic [31:0] i_bram_din_unused;

    axil_frontend u_fe_itcm (
        .clk, .rst_n,
        .s_awaddr(m_awaddr), .s_awvalid(m_awvalid[0]), .s_awready(m_awready[0]),
        .s_wdata(m_wdata), .s_wstrb(m_wstrb), .s_wvalid(m_wvalid[0]), .s_wready(m_wready[0]),
        .s_bresp(m_bresp[0]), .s_bvalid(m_bvalid[0]), .s_bready(m_bready[0]),
        .s_araddr(m_araddr), .s_arvalid(m_arvalid[0]), .s_arready(m_arready[0]),
        .s_rdata(m_rdata[0]), .s_rresp(m_rresp[0]), .s_rvalid(m_rvalid[0]), .s_rready(m_rready[0]),
        .req_valid(i_req_valid), .req_ready(i_req_ready), .req_op(i_req_op),
        .req_addr(i_req_addr), .req_wdata(i_req_wdata), .req_wstrb(i_req_wstrb),
        .rsp_valid(i_rsp_valid), .rsp_rdata(i_rsp_rdata), .rsp_err(i_rsp_err)
    );

    mem_ctrl #(.DEPTH(ITCM_DEPTH), .READ_ONLY(1'b1)) u_itcm_ctrl (
        .clk, .rst_n,
        .req_valid(i_req_valid), .req_ready(i_req_ready), .req_op(i_req_op),
        .req_addr(i_req_addr), .req_wdata(i_req_wdata), .req_wstrb(i_req_wstrb),
        .rsp_valid(i_rsp_valid), .rsp_rdata(i_rsp_rdata), .rsp_err(i_rsp_err),
        .bram_en(itcm_b_en), .bram_we(i_bram_we_unused), .bram_addr(itcm_b_addr),
        .bram_din(i_bram_din_unused), .bram_dout(itcm_b_dout)
    );

    // ---------------- slaves 1, 2: memory subsystem ----------------
    // ---------------- error-injection buttons: BTN1 = one random bit flip, BTN2 = two random bit flips ----------------
    // (the target word is the INJ_ADDR register; the same buttons can still be read through the GPIO block)
    logic hw_inj_single, hw_inj_double;
    btn_pulse #(.DEBOUNCE_CYCLES(BTN_DEBOUNCE)) u_btn_single (.clk, .rst_n, .btn(btn[1]), .pulse(hw_inj_single));
    btn_pulse #(.DEBOUNCE_CYCLES(BTN_DEBOUNCE)) u_btn_double (.clk, .rst_n, .btn(btn[2]), .pulse(hw_inj_double));

    mem_subsystem #(.DEPTH(DMEM_DEPTH), .DMEM_INIT(DMEM_INIT)) u_mem (
        .clk, .rst_n,
        .s_mem_awaddr(m_awaddr), .s_mem_awvalid(m_awvalid[1]), .s_mem_awready(m_awready[1]),
        .s_mem_wdata(m_wdata), .s_mem_wstrb(m_wstrb), .s_mem_wvalid(m_wvalid[1]), .s_mem_wready(m_wready[1]),
        .s_mem_bresp(m_bresp[1]), .s_mem_bvalid(m_bvalid[1]), .s_mem_bready(m_bready[1]),
        .s_mem_araddr(m_araddr), .s_mem_arvalid(m_arvalid[1]), .s_mem_arready(m_arready[1]),
        .s_mem_rdata(m_rdata[1]), .s_mem_rresp(m_rresp[1]), .s_mem_rvalid(m_rvalid[1]), .s_mem_rready(m_rready[1]),
        .s_reg_awaddr(m_awaddr), .s_reg_awvalid(m_awvalid[2]), .s_reg_awready(m_awready[2]),
        .s_reg_wdata(m_wdata), .s_reg_wstrb(m_wstrb), .s_reg_wvalid(m_wvalid[2]), .s_reg_wready(m_wready[2]),
        .s_reg_bresp(m_bresp[2]), .s_reg_bvalid(m_bvalid[2]), .s_reg_bready(m_bready[2]),
        .s_reg_araddr(m_araddr), .s_reg_arvalid(m_arvalid[2]), .s_reg_arready(m_arready[2]),
        .s_reg_rdata(m_rdata[2]), .s_reg_rresp(m_rresp[2]), .s_reg_rvalid(m_rvalid[2]), .s_reg_rready(m_rready[2]),
        .hw_inj_single, .hw_inj_double,
        .irq_ue, .irq_ce
    );

    // ---------------- slave 3: GPIO ----------------
    axil_gpio u_gpio (
        .clk, .rst_n,
        .s_awaddr(m_awaddr), .s_awvalid(m_awvalid[3]), .s_awready(m_awready[3]),
        .s_wdata(m_wdata), .s_wstrb(m_wstrb), .s_wvalid(m_wvalid[3]), .s_wready(m_wready[3]),
        .s_bresp(m_bresp[3]), .s_bvalid(m_bvalid[3]), .s_bready(m_bready[3]),
        .s_araddr(m_araddr), .s_arvalid(m_arvalid[3]), .s_arready(m_arready[3]),
        .s_rdata(m_rdata[3]), .s_rresp(m_rresp[3]), .s_rvalid(m_rvalid[3]), .s_rready(m_rready[3]),
        .led, .sw, .btn
    );

    // ---------------- slave 4: UART ----------------
    axil_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk, .rst_n,
        .s_awaddr(m_awaddr), .s_awvalid(m_awvalid[4]), .s_awready(m_awready[4]),
        .s_wdata(m_wdata), .s_wstrb(m_wstrb), .s_wvalid(m_wvalid[4]), .s_wready(m_wready[4]),
        .s_bresp(m_bresp[4]), .s_bvalid(m_bvalid[4]), .s_bready(m_bready[4]),
        .s_araddr(m_araddr), .s_arvalid(m_arvalid[4]), .s_arready(m_arready[4]),
        .s_rdata(m_rdata[4]), .s_rresp(m_rresp[4]), .s_rvalid(m_rvalid[4]), .s_rready(m_rready[4]),
        .tx(uart_tx)
    );
endmodule
