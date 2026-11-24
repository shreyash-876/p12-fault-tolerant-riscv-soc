`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axil_frontend: AXI4-Lite slave  ->  native request port (see mem_pkg).
// Written once in Stage 1 and never changed afterwards.
//
//  * AW, W and AR are captured independently into holding registers, so the
//    master may present them in any order or all at once (AXI4-Lite legal).
//  * A captured write (AW + W both present) has priority over a captured read.
//  * Exactly one native request is in flight at a time.
//  * rsp_err -> SLVERR (2'b10) on BRESP / RRESP, otherwise OKAY.
// -----------------------------------------------------------------------------
module axil_frontend
    import mem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------- AXI4-Lite slave ----------------
    input  logic [31:0] s_awaddr,
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_wdata,
    input  logic  [3:0] s_wstrb,
    input  logic        s_wvalid,
    output logic        s_wready,
    output logic  [1:0] s_bresp,
    output logic        s_bvalid,
    input  logic        s_bready,
    input  logic [31:0] s_araddr,
    input  logic        s_arvalid,
    output logic        s_arready,
    output logic [31:0] s_rdata,
    output logic  [1:0] s_rresp,
    output logic        s_rvalid,
    input  logic        s_rready,

    // ---------------- native request port ----------------
    output logic        req_valid,
    input  logic        req_ready,
    output mem_op_t     req_op,
    output logic [31:0] req_addr,
    output logic [31:0] req_wdata,
    output logic  [3:0] req_wstrb,
    input  logic        rsp_valid,
    input  logic [31:0] rsp_rdata,
    input  logic        rsp_err
);
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // Holding registers
    logic        aw_got, w_got, ar_got;
    logic [31:0] aw_addr_q, w_data_q, ar_addr_q;
    logic  [3:0] w_strb_q;

    typedef enum logic [1:0] {S_IDLE, S_WAIT, S_RESP} st_t;
    st_t         state;
    logic        cur_is_write;
    logic [31:0] rdata_q;
    logic        err_q;

    // Ready = holding register empty (independent of the transaction in flight)
    assign s_awready = !aw_got;
    assign s_wready  = !w_got;
    assign s_arready = !ar_got;

    wire issue_write = (state == S_IDLE) && aw_got && w_got;
    wire issue_read  = (state == S_IDLE) && ar_got && !(aw_got && w_got);

    assign req_valid = issue_write || issue_read;
    assign req_op    = mem_op_t'(issue_write ? OP_WRITE : OP_READ);
    assign req_addr  = issue_write ? aw_addr_q : ar_addr_q;
    assign req_wdata = w_data_q;
    assign req_wstrb = issue_write ? w_strb_q : 4'b0000;

    wire req_fire = req_valid && req_ready;

    // Response channels
    assign s_bvalid = (state == S_RESP) &&  cur_is_write;
    assign s_rvalid = (state == S_RESP) && !cur_is_write;
    assign s_bresp  = err_q ? RESP_SLVERR : RESP_OKAY;
    assign s_rresp  = err_q ? RESP_SLVERR : RESP_OKAY;
    assign s_rdata  = rdata_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 1'b0; w_got <= 1'b0; ar_got <= 1'b0;
            aw_addr_q <= '0; w_data_q <= '0; w_strb_q <= '0; ar_addr_q <= '0;
            state <= S_IDLE; cur_is_write <= 1'b0; rdata_q <= '0; err_q <= 1'b0;
        end else begin
            // ---- capture ----
            if (s_awvalid && s_awready) begin aw_got <= 1'b1; aw_addr_q <= s_awaddr; end
            if (s_wvalid  && s_wready)  begin w_got  <= 1'b1; w_data_q  <= s_wdata; w_strb_q <= s_wstrb; end
            if (s_arvalid && s_arready) begin ar_got <= 1'b1; ar_addr_q <= s_araddr; end

            // ---- transaction FSM ----
            case (state)
                S_IDLE: if (req_fire) begin
                    cur_is_write <= issue_write;
                    if (issue_write) begin aw_got <= 1'b0; w_got <= 1'b0; end
                    else                     ar_got <= 1'b0;
                    state <= S_WAIT;
                end
                S_WAIT: if (rsp_valid) begin
                    rdata_q <= rsp_rdata;
                    err_q   <= rsp_err;
                    state   <= S_RESP;
                end
                S_RESP: if ((cur_is_write && s_bready) || (!cur_is_write && s_rready))
                    state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
