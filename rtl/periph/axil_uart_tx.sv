`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axil_uart_tx: transmit-only UART, 8N1, at 0x8000_1000.
//   0x00 TXDATA  W   write a byte (bits [7:0]) to send; ignored while busy
//   0x04 STATUS  R   bit 0 = busy (poll until 0 before writing TXDATA)
// CLKS_PER_BIT = f_clk / baud, e.g. 50 MHz / 115200 = 434.
// The Zybo Z7 USB-UART is wired to the PS, so route `tx` to a Pmod pin and use a
// Pmod USBUART or any 3.3 V USB-serial adapter.
// -----------------------------------------------------------------------------
module axil_uart_tx
    import mem_pkg::*;
#(
    parameter int CLKS_PER_BIT = 434
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] s_awaddr,  input  logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input  logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic  [1:0] s_bresp,   output logic s_bvalid,  input  logic s_bready,
    input  logic [31:0] s_araddr,  input  logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input  logic s_rready,

    output logic        tx
);
    logic        req_valid, req_ready, rsp_valid;
    mem_op_t     req_op;
    logic [31:0] req_addr, req_wdata, rdata_q;
    logic  [3:0] req_wstrb;

    axil_frontend u_fe (
        .clk, .rst_n,
        .s_awaddr, .s_awvalid, .s_awready, .s_wdata, .s_wstrb, .s_wvalid, .s_wready,
        .s_bresp, .s_bvalid, .s_bready, .s_araddr, .s_arvalid, .s_arready,
        .s_rdata, .s_rresp, .s_rvalid, .s_rready,
        .req_valid, .req_ready, .req_op, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata(rdata_q), .rsp_err(1'b0)
    );

    // ---------------- transmitter ----------------
    logic        busy;
    logic  [9:0] shreg;                       // {stop, data[7:0], start}
    logic  [3:0] bit_cnt;
    localparam int CNT_W = $clog2(CLKS_PER_BIT);
    logic [CNT_W-1:0] clk_cnt;

    wire start = req_valid && req_ready && (req_op == OP_WRITE) &&
                 (req_addr[3:2] == 2'd0) && req_wstrb[0] && !busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; shreg <= '1; bit_cnt <= '0; clk_cnt <= '0; tx <= 1'b1;
        end else if (start) begin
            busy <= 1'b1; shreg <= {1'b1, req_wdata[7:0], 1'b0};
            bit_cnt <= 4'd0; clk_cnt <= '0; tx <= 1'b0;          // start bit
        end else if (busy) begin
            if (clk_cnt == CNT_W'(CLKS_PER_BIT - 1)) begin
                clk_cnt <= '0;
                if (bit_cnt == 4'd9) begin
                    busy <= 1'b0; tx <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 4'd1;
                    tx      <= shreg[bit_cnt + 4'd1];
                end
            end else clk_cnt <= clk_cnt + 1'b1;
        end
    end

    // ---------------- register responses ----------------
    assign req_ready = !rsp_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0; rdata_q <= '0;
        end else begin
            rsp_valid <= req_valid && req_ready;
            if (req_valid && req_ready)
                rdata_q <= (req_op == OP_READ && req_addr[3:2] == 2'd1) ? {31'd0, busy} : 32'd0;
        end
    end
endmodule
