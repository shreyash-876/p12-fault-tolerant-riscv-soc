`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// csr_unit: machine-mode CSRs and the interrupt (trap) logic of the RV32I core.
//
// Implemented (all others read as 0 and ignore writes; there are no illegal-instruction traps):
//   0x300 mstatus   MIE (bit 3), MPIE (bit 7); MPP (bits 12:11) reads as 11
//   0x301 misa      0x4000_0100 (RV32, I)
//   0x304 mie       MEIE (bit 11) = machine external interrupt enable
//   0x305 mtvec     trap vector, direct mode (bits 1:0 read as 0)
//   0x340 mscratch  scratch register for the handler
//   0x341 mepc      PC to return to (bits 1:0 read as 0)
//   0x342 mcause    0x8000_000B after an external interrupt
//   0x344 mip       MEIP (bit 11) = the interrupt input, read-only
//   0xB00 / 0xC00   mcycle / cycle: free-running 32-bit cycle counter (read-only here)
//
// The CSR instructions (csrrw, csrrs, csrrc and their immediate forms) execute in the EX stage.
// A CSR instruction writes its CSR only in the cycle in which it leaves EX (EX not stalled) and is not
// squashed by an interrupt. csrrs/csrrc with rs1 = x0 (or a zero immediate) do not write.
//
// INTERRUPT (machine external): taken in the EX stage when
//     ext_irq && mstatus.MIE && mie.MEIE,  EX holds a REAL instruction,  and the pipeline is not stalled
//     by a memory access (ex_stall = 0).
// The instruction in EX is squashed (it has not executed), mepc = its PC, mcause = 0x8000000B,
// MPIE <= MIE, MIE <= 0, and the PC is redirected to mtvec. The core then flushes IF and ID as for a
// taken branch. Instructions older than EX (in MEM and WB) complete normally, so the interrupt is precise:
// after `mret` the squashed instruction runs for the first time.
// MRET (in EX, not stalled, not interrupted) redirects to mepc, MIE <= MPIE, MPIE <= 1.
// -----------------------------------------------------------------------------
module csr_unit (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        ext_irq,             // level interrupt request (machine external)

    // ---------------- the instruction in EX ----------------
    input  logic        ex_valid,            // EX holds a real (not a bubble) instruction
    input  logic [31:0] ex_pc,
    input  logic        ex_stall,            // EX is frozen by a memory access
    input  logic        ex_is_csr,
    input  logic        ex_is_mret,
    input  logic  [2:0] ex_funct3,
    input  logic [11:0] ex_csr_addr,
    input  logic [31:0] ex_rs1_val,          // forwarded value of rs1
    input  logic  [4:0] ex_zimm,             // the rs1 field: register number, or the immediate of csrr*i

    output logic [31:0] csr_rdata,           // old value of the addressed CSR (the result of a CSR instruction)

    // ---------------- redirects ----------------
    output logic        trap_take,           // take the interrupt now: squash EX, jump to trap_target
    output logic [31:0] trap_target,
    output logic        mret_take,           // MRET executes now: jump to mret_target
    output logic [31:0] mret_target
);
    // ---------------- CSR state ----------------
    logic        mstatus_mie, mstatus_mpie, mie_meie;
    logic [31:2] mtvec_r, mepc_r;
    logic [31:0] mscratch_r, mcause_r, cycle_r;

    wire irq_pending = ext_irq & mstatus_mie & mie_meie;

    assign trap_take   = ex_valid & ~ex_stall & irq_pending;
    assign trap_target = {mtvec_r, 2'b00};
    assign mret_take   = ex_valid & ex_is_mret & ~ex_stall & ~trap_take;
    assign mret_target = {mepc_r, 2'b00};

    // ---------------- read ----------------
    always_comb begin
        case (ex_csr_addr)
            12'h300: csr_rdata = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
            12'h301: csr_rdata = 32'h4000_0100;
            12'h304: csr_rdata = {20'd0, mie_meie, 11'd0};
            12'h305: csr_rdata = {mtvec_r, 2'b00};
            12'h340: csr_rdata = mscratch_r;
            12'h341: csr_rdata = {mepc_r, 2'b00};
            12'h342: csr_rdata = mcause_r;
            12'h344: csr_rdata = {20'd0, ext_irq, 11'd0};
            12'hB00, 12'hC00: csr_rdata = cycle_r;
            default: csr_rdata = 32'd0;
        endcase
    end

    // ---------------- write ----------------
    wire        csr_commit = ex_valid & ex_is_csr & ~ex_stall & ~trap_take;
    wire        use_imm    = ex_funct3[2];
    wire [31:0] src        = use_imm ? {27'd0, ex_zimm} : ex_rs1_val;
    wire        src_zero   = (ex_zimm == 5'd0);          // rs1 = x0, or a zero immediate
    wire        do_write   = csr_commit & ((ex_funct3[1:0] == 2'b01) | ~src_zero);

    logic [31:0] wnew;                                    // the CSR value after the instruction
    always_comb begin
        case (ex_funct3[1:0])
            2'b01:   wnew = src;                          // csrrw / csrrwi
            2'b10:   wnew = csr_rdata | src;              // csrrs / csrrsi
            2'b11:   wnew = csr_rdata & ~src;             // csrrc / csrrci
            default: wnew = csr_rdata;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie <= 1'b0; mstatus_mpie <= 1'b0; mie_meie <= 1'b0;
            mtvec_r <= '0; mepc_r <= '0; mscratch_r <= '0; mcause_r <= '0; cycle_r <= '0;
        end else begin
            cycle_r <= cycle_r + 32'd1;
            if (trap_take) begin
                mepc_r       <= ex_pc[31:2];
                mcause_r     <= 32'h8000_000B;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
            end else if (mret_take) begin
                mstatus_mie  <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
            end else if (do_write) begin
                case (ex_csr_addr)
                    12'h300: begin mstatus_mie <= wnew[3]; mstatus_mpie <= wnew[7]; end
                    12'h304: mie_meie   <= wnew[11];
                    12'h305: mtvec_r    <= wnew[31:2];
                    12'h340: mscratch_r <= wnew;
                    12'h341: mepc_r     <= wnew[31:2];
                    12'h342: mcause_r   <= wnew;
                    default: ;
                endcase
            end
        end
    end
endmodule
