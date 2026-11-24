`timescale 1ns / 1ps

module decode_stage (
    input  logic        clk,
    input  logic        rst_n,
    
    // Pipeline control
    input  logic        stall,
    input  logic        flush,
    
    // Inputs from IF/ID Register
    input  logic [31:0] if_id_pc,
    input  logic [31:0] if_id_instr,
    input  logic        if_id_valid,
    
    // Outputs to Register File (Read Addresses)
    output logic  [4:0] rs1_addr,
    output logic  [4:0] rs2_addr,
    
    // Inputs FROM Register File (Read Data)
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    
    // Outputs to ID/EX Pipeline Register
    output logic [31:0] id_ex_pc,
    output logic [31:0] id_ex_imm,
    output logic [31:0] id_ex_rs1_data, // NEW: Latched data
    output logic [31:0] id_ex_rs2_data, // NEW: Latched data
    output logic  [4:0] id_ex_rs1_addr,
    output logic  [4:0] id_ex_rs2_addr,
    output logic  [4:0] id_ex_rd_addr,
    
    // Control Signals to ID/EX
    output logic        id_ex_reg_write,
    output logic        id_ex_mem_read,
    output logic        id_ex_mem_write,
    output logic        id_ex_branch,
    output logic        id_ex_jump,
    output logic        id_ex_is_jalr,
    output logic        id_ex_alu_src, 
    output logic  [1:0] id_ex_result_src, 
    output logic  [3:0] id_ex_alu_ctrl,
    output logic        id_ex_alu_a_pc,   // FIX: AUIPC uses PC as ALU operand A
    output logic  [2:0] id_ex_funct3,     // FIX: load/store size + sign (LB/LH/LW/LBU/LHU, SB/SH/SW)
    output logic        id_ex_valid,      // a real instruction (not a bubble): needed for precise interrupts
    output logic        id_ex_is_csr,     // CSRRW/CSRRS/CSRRC and immediate forms (CSR address is in id_ex_imm[11:0])
    output logic        id_ex_is_mret
);

    // Internal Combinational Signals
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [31:0] imm_ext;
    
    // Internal Control Signals
    logic ctrl_reg_write, ctrl_mem_read, ctrl_mem_write;
    logic ctrl_branch, ctrl_jump, ctrl_is_jalr, ctrl_alu_src, ctrl_alu_a_pc;
    logic ctrl_is_csr, ctrl_is_mret;
    logic [1:0] ctrl_result_src;
    logic [3:0] ctrl_alu_ctrl;
    

    // Decode fields
    assign opcode = if_id_instr[6:0];
    assign funct3 = if_id_instr[14:12];
    assign funct7 = if_id_instr[31:25];
    
    logic [4:0] rs1_addr_int;
    logic [4:0] rs2_addr_int;
    logic [4:0] rd_addr_int;

    always_comb begin
        // If U-Type (LUI, AUIPC) or J-Type (JAL), force rs1 to 0
        if (opcode == 7'b0110111 || opcode == 7'b0010111 || opcode == 7'b1101111) begin
            rs1_addr_int = 5'd0;
        end else begin
            rs1_addr_int = if_id_instr[19:15];
        end
        
        // If U-Type, J-Type, I-Type, or Load, force rs2 to 0
        if (opcode == 7'b0110111 || opcode == 7'b0010111 || opcode == 7'b1101111 || 
            opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1110011) begin
            rs2_addr_int = 5'd0;
        end else begin
            rs2_addr_int = if_id_instr[24:20];
        end
    end

    assign rs1_addr = rs1_addr_int;
    assign rs2_addr = rs2_addr_int;
    assign rd_addr_int = if_id_instr[11:7];

    // Immediate Generation
    always_comb begin
        case(opcode)
            7'b0010011, 7'b0000011, 7'b1100111: // I-Type
                imm_ext = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
            7'b0100011: // S-Type
                imm_ext = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
            7'b1100011: // B-Type
                imm_ext = {{20{if_id_instr[31]}}, if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
            7'b0110111, 7'b0010111: // U-Type 
                imm_ext = {if_id_instr[31:12], 12'b0};
            7'b1101111: // J-Type
                imm_ext = {{12{if_id_instr[31]}}, if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};
            7'b1110011: // SYSTEM: the 12-bit CSR address, zero-extended
                imm_ext = {20'b0, if_id_instr[31:20]};
            default: 
                imm_ext = 32'b0;
        endcase
    end

    // Main Control Unit
    always_comb begin
        ctrl_reg_write = 0; ctrl_mem_read = 0; ctrl_mem_write = 0;
        ctrl_branch = 0; ctrl_jump = 0; ctrl_is_jalr = 0; ctrl_alu_src = 0;
        ctrl_result_src = 2'b00; ctrl_alu_ctrl = 4'b0000;
        ctrl_alu_a_pc = 0;
        ctrl_is_csr = 0; ctrl_is_mret = 0;

        case(opcode)
            7'b0110011: begin // R-Type
                ctrl_reg_write = 1;
                ctrl_alu_ctrl = {funct7[5], funct3}; 
            end
            7'b0010011: begin // I-Type ALU
                ctrl_reg_write = 1; ctrl_alu_src = 1;
                ctrl_alu_ctrl = {(funct3 == 3'b101 ? funct7[5] : 1'b0), funct3}; 
            end
            7'b0000011: begin // Load
                ctrl_reg_write = 1; ctrl_alu_src = 1; ctrl_mem_read = 1;
                ctrl_result_src = 2'b01; 
            end
            7'b0100011: begin // Store
                ctrl_alu_src = 1; ctrl_mem_write = 1;
            end
            7'b1100011: begin // Branch
                ctrl_branch = 1; ctrl_alu_ctrl = {1'b0, funct3}; 
            end
            7'b1101111: begin // JAL
                ctrl_reg_write = 1; ctrl_jump = 1;
                ctrl_result_src = 2'b10; 
            end
            7'b1100111: begin // JALR
                ctrl_reg_write = 1; ctrl_jump = 1; ctrl_is_jalr = 1; // Flag it!
                ctrl_result_src = 2'b10; 
            end
            7'b0110111: begin // LUI  (rs1 forced to x0, so ALU computes 0 + imm)
                ctrl_reg_write = 1; ctrl_alu_src = 1; 
            end
            7'b0010111: begin // AUIPC (FIX: was missing -> executed as NOP)
                ctrl_reg_write = 1; ctrl_alu_src = 1; ctrl_alu_a_pc = 1;
            end
            7'b1110011: begin // SYSTEM
                if (funct3 != 3'b000) begin               // CSRRW / CSRRS / CSRRC / CSRRWI / CSRRSI / CSRRCI
                    ctrl_reg_write = 1; ctrl_is_csr = 1; ctrl_result_src = 2'b00;
                end else if (if_id_instr[31:20] == 12'h302) begin
                    ctrl_is_mret = 1;                     // MRET
                end                                       // ECALL / EBREAK / WFI: no operation
            end
            // FENCE (0001111) falls through to default = NOP
            default: ; 
        endcase
    end

    // ID/EX Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc <= 0; id_ex_imm <= 0;
            id_ex_rs1_data <= 0; id_ex_rs2_data <= 0;
            id_ex_rs1_addr <= 0; id_ex_rs2_addr <= 0; id_ex_rd_addr <= 0;
            id_ex_reg_write <= 0; id_ex_mem_read <= 0; id_ex_mem_write <= 0;
            id_ex_branch <= 0; id_ex_jump <= 0; id_ex_is_jalr <= 0; id_ex_alu_src <= 0;
            id_ex_result_src <= 0; id_ex_alu_ctrl <= 0; id_ex_alu_a_pc <= 0; id_ex_funct3 <= 0;
            id_ex_valid <= 0; id_ex_is_csr <= 0; id_ex_is_mret <= 0;
        end else if (!stall) begin
            if (flush) begin
                id_ex_reg_write <= 0; id_ex_mem_read <= 0; id_ex_mem_write <= 0;
                id_ex_branch <= 0; id_ex_jump <= 0; id_ex_is_jalr <= 0;
                id_ex_valid <= 0; id_ex_is_csr <= 0; id_ex_is_mret <= 0;
            end else begin
                id_ex_valid <= if_id_valid;
                id_ex_is_csr <= ctrl_is_csr;
                id_ex_is_mret <= ctrl_is_mret;
                id_ex_pc <= if_id_pc;
                id_ex_imm <= imm_ext;
                id_ex_rs1_data <= rs1_data_in; // Latch RF data
                id_ex_rs2_data <= rs2_data_in; // Latch RF data
                id_ex_rs1_addr <= rs1_addr;
                id_ex_rs2_addr <= rs2_addr;
                id_ex_rd_addr <= rd_addr_int;
                
                id_ex_reg_write <= ctrl_reg_write;
                id_ex_mem_read <= ctrl_mem_read;
                id_ex_mem_write <= ctrl_mem_write;
                id_ex_branch <= ctrl_branch;
                id_ex_jump <= ctrl_jump;
                id_ex_is_jalr <= ctrl_is_jalr;
                id_ex_alu_src <= ctrl_alu_src;
                id_ex_result_src <= ctrl_result_src;
                id_ex_alu_ctrl <= ctrl_alu_ctrl;
                id_ex_alu_a_pc <= ctrl_alu_a_pc;
                id_ex_funct3 <= funct3;
            end
        end
    end

endmodule
