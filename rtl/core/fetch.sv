`timescale 1ns / 1ps

module fetch_stage (
    input  logic        clk,
    input  logic        rst_n,
    
    // Control Signals (from Hazard Unit & EX Stage)
    input  logic        stall,         
    input  logic        flush,         
    input  logic        pc_src,        
    input  logic [31:0] branch_target, 
    
    // ITCM Interface
    output logic [31:0] itcm_addr,
    input  logic [31:0] itcm_rdata,
    
    // IF/ID Pipeline Register Outputs
    output logic [31:0] if_id_pc,
    output logic [31:0] if_id_instr,
    output logic        if_id_valid    // 0 while the instruction is a NOP that replaced a squashed fetch
);

    // Internal PC registers
    logic [31:0] pc_reg;
    logic [31:0] pc_next;
    logic        flush_latch; // Tracks if we need to squash speculative BRAM output

    // RISC-V NOP Instruction (addi x0, x0, 0)
    localparam logic [31:0] NOP_INSTR = 32'h00000013;

    // -------------------------------------------------------------------------
    // 1. Program Counter Logic
    // -------------------------------------------------------------------------
    assign pc_next = pc_src ? branch_target : (pc_reg + 32'd4);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= 32'h0000_0000;
        end else if (!stall) begin
            pc_reg <= pc_next;
        end
    end

    // ITCM address presents current PC directly to RAM
    assign itcm_addr = pc_reg;

    // -------------------------------------------------------------------------
    // 2. IF/ID Pipeline Register (Absorbing the 1-Cycle BRAM Delay)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'h0000_0000;
            flush_latch <= 1'b1; // Force a NOP on the very first cycle after reset
        end else if (!stall) begin
            if_id_pc    <= pc_reg; // PC is delayed by 1 cycle to align with BRAM data
            flush_latch <= flush;  // Remember flush to squash BRAM output next cycle
        end
    end

    // The instruction is the direct BRAM output.
    // If we flushed last cycle, the data arriving now is speculative, so squash it to NOP.
    assign if_id_instr = flush_latch ? NOP_INSTR : itcm_rdata;
    assign if_id_valid = ~flush_latch;          // a real instruction (needed to take interrupts at a precise point)

endmodule
