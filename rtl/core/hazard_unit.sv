`timescale 1ns / 1ps

module hazard_unit (
    // Inputs from Decode Stage (ID)
    input  logic [4:0] rs1_addr,
    input  logic [4:0] rs2_addr,
    
    // Inputs from Execute Stage (EX)
    input  logic       id_ex_mem_read, // 1 if EX stage is a Load instruction
    input  logic [4:0] id_ex_rd_addr,  // Destination register of EX stage
    input  logic       ex_pc_src,      // 1 if a branch/jump is taken in EX
    
    // Outputs to Pipeline Registers
    output logic       stall_if,       // Stalls the PC and IF/ID register
    output logic       flush_if,       // Flushes IF/ID register (Branch taken)
    output logic       flush_id        // Flushes ID/EX register (Load-Use or Branch)
);

    logic lw_stall;

    // -------------------------------------------------------------------------
    // 1. Load-Use Hazard Detection
    // -------------------------------------------------------------------------
    // A Load-Use hazard occurs if:
    // a) The instruction in the EX stage is a memory read (Load)
    // b) The destination register is not x0
    // c) The destination register matches either source register in the ID stage
    always_comb begin
        if (id_ex_mem_read && (id_ex_rd_addr != 5'd0) && 
           ((id_ex_rd_addr == rs1_addr) || (id_ex_rd_addr == rs2_addr))) begin
            lw_stall = 1'b1;
        end else begin
            lw_stall = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Control Signal Generation
    // -------------------------------------------------------------------------
    always_comb begin
        // Default assignments
        stall_if = 1'b0;
        flush_if = 1'b0;
        flush_id = 1'b0;

        if (ex_pc_src) begin
            // BRANCH TAKEN: 
            // We mispredicted. Flush the wrong instructions in Fetch and Decode.
            // No need to stall, we want the new PC to start fetching immediately.
            flush_if = 1'b1;
            flush_id = 1'b1;
        end 
        else if (lw_stall) begin
            // LOAD-USE HAZARD:
            // Freeze the PC and the IF/ID register so they don't lose their data.
            // Flush the ID/EX register to insert a bubble (NOP) into the EX stage.
            stall_if = 1'b1;
            flush_id = 1'b1;
        end
    end

endmodule
