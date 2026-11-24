`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mem_ctrl (STAGE 1): native request port -> BRAM port. Plain read/write with
// byte enables, no ECC yet.
//
// Stage 2 replaces the INSIDE of this module (encode on write, decode/correct on
// read, read-modify-write for partial writes, OP_INJECT) but keeps every port
// except the BRAM data width, which becomes CW_W (39).
//
// Timing (BRAM read latency = 1):
//   write : cycle 0 request accepted + BRAM written, cycle 1 rsp_valid
//   read  : cycle 0 request accepted + BRAM read,    cycle 1 rsp_valid with data
//
// READ_ONLY=1 rejects writes with rsp_err (used for the ITCM data-side port).
// Unsupported ops (SCRUB / INJECT) return rsp_err in Stage 1.
// -----------------------------------------------------------------------------
module mem_ctrl
    import mem_pkg::*;
#(
    parameter int DEPTH     = 2048,          // words
    parameter bit READ_ONLY = 1'b0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // native request port
    input  logic                     req_valid,
    output logic                     req_ready,
    input  mem_op_t                  req_op,
    input  logic [31:0]              req_addr,
    input  logic [31:0]              req_wdata,
    input  logic  [3:0]              req_wstrb,
    output logic                     rsp_valid,
    output logic [31:0]              rsp_rdata,
    output logic                     rsp_err,

    // BRAM port
    output logic                     bram_en,
    output logic  [3:0]              bram_we,
    output logic [$clog2(DEPTH)-1:0] bram_addr,
    output logic [31:0]              bram_din,
    input  logic [31:0]              bram_dout
);
    localparam int AW = $clog2(DEPTH);

    typedef enum logic [1:0] {C_IDLE, C_RD, C_ACK} cst_t;
    cst_t state;
    logic err_q;

    assign req_ready = (state == C_IDLE);
    wire   fire      = req_valid && req_ready;

    wire is_write = (req_op == OP_WRITE) && !READ_ONLY;
    wire is_read  = (req_op == OP_READ);

    // BRAM driven combinationally in the accept cycle
    assign bram_en   = fire && (is_write || is_read);
    assign bram_we   = (fire && is_write) ? req_wstrb : 4'b0000;
    assign bram_addr = req_addr[AW+1:2];
    assign bram_din  = req_wdata;

    // Response
    assign rsp_valid = (state == C_RD) || (state == C_ACK);
    assign rsp_rdata = (state == C_RD) ? bram_dout : 32'h0;
    assign rsp_err   = err_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= C_IDLE; err_q <= 1'b0;
        end else begin
            case (state)
                C_IDLE: if (fire) begin
                    if (is_read) begin state <= C_RD;  err_q <= 1'b0; end
                    else         begin state <= C_ACK; err_q <= !is_write; end
                end
                default: state <= C_IDLE;   // C_RD and C_ACK last exactly one cycle
            endcase
        end
    end
endmodule
