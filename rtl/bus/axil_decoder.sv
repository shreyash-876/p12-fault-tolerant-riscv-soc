`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axil_decoder: one AXI4-Lite master -> N_SLV slaves. Replaces rv_addr_decoder.
//
// Differences from rv_addr_decoder:
//  * the selected slave is LATCHED at the AW / AR handshake and used to route
//    W, B and R, so routing no longer depends on the master holding its address;
//  * at most one write and one read outstanding (matches the core);
//  * unmapped addresses are answered by an internal DECERR responder that
//    obeys the handshake rules (response only after the address handshake);
//  * WSTRB is carried.
//
// System memory map (frozen in Stage 1):
//   slave 0  ITCM data-side read port  0x0000_0000 - 0x0000_FFFF  (.rodata, .data init)
//   slave 1  data RAM (ECC from St. 2) 0x2000_0000 - 0x2000_FFFF
//   slave 2  ECC registers             0x4000_0000 - 0x4000_FFFF
//   slave 3  GPIO (LEDs, switches)     0x8000_0000 - 0x8000_0FFF
//   slave 4  UART                      0x8000_1000 - 0x8000_1FFF
// -----------------------------------------------------------------------------
module axil_decoder #(
    parameter int N_SLV = 5
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---------------- from master ----------------
    input  logic [31:0]           s_awaddr,
    input  logic                  s_awvalid,
    output logic                  s_awready,
    input  logic [31:0]           s_wdata,
    input  logic  [3:0]           s_wstrb,
    input  logic                  s_wvalid,
    output logic                  s_wready,
    output logic  [1:0]           s_bresp,
    output logic                  s_bvalid,
    input  logic                  s_bready,
    input  logic [31:0]           s_araddr,
    input  logic                  s_arvalid,
    output logic                  s_arready,
    output logic [31:0]           s_rdata,
    output logic  [1:0]           s_rresp,
    output logic                  s_rvalid,
    input  logic                  s_rready,

    // ---------------- to slaves (addr/data broadcast, valid/ready per slave) ----
    output logic [31:0]           m_awaddr,
    output logic [N_SLV-1:0]      m_awvalid,
    input  logic [N_SLV-1:0]      m_awready,
    output logic [31:0]           m_wdata,
    output logic  [3:0]           m_wstrb,
    output logic [N_SLV-1:0]      m_wvalid,
    input  logic [N_SLV-1:0]      m_wready,
    input  logic [N_SLV-1:0][1:0] m_bresp,
    input  logic [N_SLV-1:0]      m_bvalid,
    output logic [N_SLV-1:0]      m_bready,
    output logic [31:0]           m_araddr,
    output logic [N_SLV-1:0]      m_arvalid,
    input  logic [N_SLV-1:0]      m_arready,
    input  logic [N_SLV-1:0][31:0] m_rdata,
    input  logic [N_SLV-1:0][1:0] m_rresp,
    input  logic [N_SLV-1:0]      m_rvalid,
    output logic [N_SLV-1:0]      m_rready
);
    localparam logic [1:0] DECERR = 2'b11;

    // ---------------- address map ----------------
    function automatic logic [N_SLV-1:0] decode(input logic [31:0] a);
        logic [N_SLV-1:0] hit;
        hit    = '0;
        hit[0] = (a[31:16] == 16'h0000);
        hit[1] = (a[31:16] == 16'h2000);
        hit[2] = (a[31:16] == 16'h4000);
        hit[3] = (a[31:12] == 20'h80000);
        hit[4] = (a[31:12] == 20'h80001);
        return hit;
    endfunction

    // ================= write path =================
    logic             w_busy;              // AW accepted, B not yet done
    logic [N_SLV-1:0] w_sel_q;
    logic             w_err_q;             // current write goes to the DECERR responder
    logic             w_data_done;         // W handshake done for the current write
    logic             err_bvalid;

    wire [N_SLV-1:0] aw_hit  = decode(s_awaddr);
    wire             aw_miss = (aw_hit == '0);

    // AW routing (only when idle)
    assign m_awaddr  = s_awaddr;
    assign m_awvalid = (!w_busy && s_awvalid) ? aw_hit : '0;
    assign s_awready = !w_busy && s_awvalid && (aw_miss ? 1'b1 : |(aw_hit & m_awready));

    // W routing: only after AW is accepted (W cannot be routed before its address)
    assign m_wdata  = s_wdata;
    assign m_wstrb  = s_wstrb;
    assign m_wvalid = (w_busy && !w_data_done && !w_err_q && s_wvalid) ? w_sel_q : '0;
    assign s_wready = w_busy && !w_data_done && (w_err_q ? 1'b1 : |(w_sel_q & m_wready));

    // B routing
    assign m_bready = (w_busy && !w_err_q) ? (w_sel_q & {N_SLV{s_bready}}) : '0;
    always_comb begin
        s_bvalid = 1'b0; s_bresp = 2'b00;
        if (w_busy) begin
            if (w_err_q) begin s_bvalid = err_bvalid; s_bresp = DECERR; end
            else for (int i = 0; i < N_SLV; i++)
                if (w_sel_q[i]) begin s_bvalid = m_bvalid[i]; s_bresp = m_bresp[i]; end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_busy <= 1'b0; w_sel_q <= '0; w_err_q <= 1'b0; w_data_done <= 1'b0; err_bvalid <= 1'b0;
        end else begin
            if (s_awvalid && s_awready) begin
                w_busy <= 1'b1; w_sel_q <= aw_hit; w_err_q <= aw_miss; w_data_done <= 1'b0;
            end
            if (s_wvalid && s_wready) begin
                w_data_done <= 1'b1;
                if (w_err_q) err_bvalid <= 1'b1;      // DECERR response after W
            end
            if (s_bvalid && s_bready) begin
                w_busy <= 1'b0; err_bvalid <= 1'b0; w_data_done <= 1'b0;
            end
        end
    end

    // ================= read path =================
    logic             r_busy;
    logic [N_SLV-1:0] r_sel_q;
    logic             r_err_q;

    wire [N_SLV-1:0] ar_hit  = decode(s_araddr);
    wire             ar_miss = (ar_hit == '0);

    assign m_araddr  = s_araddr;
    assign m_arvalid = (!r_busy && s_arvalid) ? ar_hit : '0;
    assign s_arready = !r_busy && s_arvalid && (ar_miss ? 1'b1 : |(ar_hit & m_arready));

    assign m_rready = (r_busy && !r_err_q) ? (r_sel_q & {N_SLV{s_rready}}) : '0;
    always_comb begin
        s_rvalid = 1'b0; s_rdata = 32'h0; s_rresp = 2'b00;
        if (r_busy) begin
            if (r_err_q) begin s_rvalid = 1'b1; s_rdata = 32'hDEAD_FA01; s_rresp = DECERR; end
            else for (int i = 0; i < N_SLV; i++)
                if (r_sel_q[i]) begin s_rvalid = m_rvalid[i]; s_rdata = m_rdata[i]; s_rresp = m_rresp[i]; end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_busy <= 1'b0; r_sel_q <= '0; r_err_q <= 1'b0;
        end else begin
            if (s_arvalid && s_arready) begin r_busy <= 1'b1; r_sel_q <= ar_hit; r_err_q <= ar_miss; end
            if (s_rvalid && s_rready)   r_busy <= 1'b0;
        end
    end
endmodule
