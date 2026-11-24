`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ecc_injector: error-injection port. Flips bits of a STORED word, on request, so that the
// ECC, the scrubber, the counters, the log and the interrupt can be demonstrated and tested.
//
// Triggers (one injection at a time; a trigger that arrives while one is running is ignored):
//   go_reg      a write of 1 to INJ_CTRL.GO. Mask = the INJ_MASK registers, or - if INJ_CTRL.RANDOM
//               is set - one random bit (two random distinct bits if INJ_CTRL.DOUBLE is set).
//   hw_single   a board button: flip ONE random bit of the word at INJ_ADDR
//   hw_double   a board button: flip TWO random distinct bits of the word at INJ_ADDR
// The target address is always the INJ_ADDR register (a word address; the two low bits are ignored).
// It must lie inside the data RAM: the controller only uses the low address bits, so an address
// outside the RAM would wrap around.
//
// The injection itself is an OP_INJECT request on the native port, scheduled by the arbiter like any
// other access: the controller reads the raw 39-bit word and writes it back XOR the mask,
// WITHOUT re-encoding. The mask travels on the side-band output `inj_mask` (held stable while busy).
//
// Random bits come from a free-running 32-bit LFSR, folded onto bit numbers 0..38. The folding
// favours bit numbers 0..24 slightly; that is fine for a demonstration.
// -----------------------------------------------------------------------------
module ecc_injector
    import mem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // ---------------- triggers and settings ----------------
    input  logic        go_reg,              // 1-cycle pulse from the register block
    input  logic        use_random,          // register: GO uses a random mask
    input  logic        random_double,       // register: ... with two bits
    input  logic        hw_single,           // 1-cycle pulse (button)
    input  logic        hw_double,           // 1-cycle pulse (button)
    input  logic [31:0] inj_addr,            // byte address of the target word
    input  logic [38:0] inj_mask_reg,        // mask used by GO when use_random = 0

    // ---------------- native request port (master side) ----------------
    output logic        req_valid,
    input  logic        req_ready,
    output mem_op_t     req_op,
    output logic [31:0] req_addr,
    input  logic        rsp_valid,

    // ---------------- side-band and status ----------------
    output logic [38:0] inj_mask,            // mask for the memory controller
    output logic        busy,
    output logic [31:0] inj_count            // injections completed
);
    typedef enum logic [1:0] {I_IDLE, I_REQ, I_BUSY} i_state_t;
    i_state_t state;

    logic [31:0] lfsr;                       // free-running random source
    logic [38:0] mask_q;
    logic [31:0] addr_q;

    function automatic logic [5:0] fold39(input logic [5:0] v);
        if (v >= 6'd39) fold39 = v - 6'd39;
        else            fold39 = v;
    endfunction

    // one random bit, or two random distinct bits
    function automatic logic [38:0] rnd_mask(input logic [31:0] r, input logic dbl);
        logic [5:0]  i1, i2;
        logic [38:0] m;
        i1 = fold39(r[5:0]);
        i2 = fold39(r[11:6]);
        if (i2 == i1) begin
            if (i1 == 6'd38) i2 = 6'd0;
            else             i2 = i1 + 6'd1;
        end
        m = 39'd0;
        m[i1] = 1'b1;
        if (dbl) m[i2] = 1'b1;
        rnd_mask = m;
    endfunction

    assign req_valid = (state == I_REQ);
    assign req_op    = OP_INJECT;
    assign req_addr  = addr_q;
    assign inj_mask  = mask_q;
    assign busy      = (state != I_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= I_IDLE;
            lfsr <= 32'hACE1_2345;
            mask_q <= '0;
            addr_q <= '0;
            inj_count <= 32'd0;
        end else begin
            // x^32 + x^22 + x^2 + x + 1
            lfsr <= {lfsr[30:0], 1'b0} ^ (lfsr[31] ? 32'h0040_0007 : 32'h0000_0000);

            case (state)
                I_IDLE: begin
                    if (go_reg) begin
                        mask_q <= use_random ? rnd_mask(lfsr, random_double) : inj_mask_reg;
                        addr_q <= {inj_addr[31:2], 2'b00};
                        state  <= I_REQ;
                    end else if (hw_single) begin
                        mask_q <= rnd_mask(lfsr, 1'b0);
                        addr_q <= {inj_addr[31:2], 2'b00};
                        state  <= I_REQ;
                    end else if (hw_double) begin
                        mask_q <= rnd_mask(lfsr, 1'b1);
                        addr_q <= {inj_addr[31:2], 2'b00};
                        state  <= I_REQ;
                    end
                end
                I_REQ:  if (req_ready) state <= I_BUSY;          // accepted by the arbiter
                I_BUSY: if (rsp_valid) begin
                    inj_count <= inj_count + 32'd1;
                    state     <= I_IDLE;
                end
                default: state <= I_IDLE;
            endcase
        end
    end
endmodule
