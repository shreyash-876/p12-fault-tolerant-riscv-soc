`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mem_pkg: the FROZEN internal request interface of the memory subsystem.
// Every block behind the AXI4-Lite front-end (mem_ctrl now; arbiter, scrubber,
// injection later) speaks this protocol. Do not change it in later stages.
//
//   Request : req_valid/req_ready handshake. While req_valid=1 the requester
//             holds req_op/addr/wdata/wstrb/mask stable. One request in flight.
//   Response: rsp_valid is a ONE-CYCLE pulse carrying rsp_rdata / rsp_err.
//             The requester must be able to take it in that cycle.
// -----------------------------------------------------------------------------
package mem_pkg;
    typedef enum logic [1:0] {
        OP_READ   = 2'b00,
        OP_WRITE  = 2'b01,
        OP_SCRUB  = 2'b10,   // Stage 3: read, correct, write back if needed
        OP_INJECT = 2'b11    // Stage 2: XOR req_mask into the stored codeword
    } mem_op_t;

    localparam int CW_W = 39;  // codeword width from Stage 2 on: Hsiao (39,32)
endpackage
