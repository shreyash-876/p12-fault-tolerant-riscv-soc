`timescale 1ns / 1ps

module execute_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,
    
    // Inputs from ID/EX Pipeline Register
    input  logic [31:0] id_ex_pc,
    input  logic [31:0] id_ex_imm,
    input  logic [31:0] id_ex_rs1_data,
    input  logic [31:0] id_ex_rs2_data,
    input  logic  [4:0] id_ex_rs1_addr,
    input  logic  [4:0] id_ex_rs2_addr,
    input  logic  [4:0] id_ex_rd_addr,
    
    // Control Signals from ID/EX
    input  logic        id_ex_reg_write,
    input  logic        id_ex_mem_read,
    input  logic        id_ex_mem_write,
    input  logic        id_ex_branch,
    input  logic        id_ex_jump,
    input  logic        id_ex_is_jalr,
    input  logic        id_ex_alu_src, 
    input  logic  [1:0] id_ex_result_src, 
    input  logic  [3:0] id_ex_alu_ctrl,
    input  logic        id_ex_alu_a_pc,
    input  logic  [2:0] id_ex_funct3,
    input  logic        id_ex_is_csr,       // CSR instruction: its result is the old CSR value
    input  logic [31:0] csr_rdata,
    input  logic        ex_squash,          // an interrupt is taken: the instruction in EX must not proceed
    
    // Forwarding Unit Data Inputs
    input  logic [31:0] ex_mem_alu_res_fwd, // Bypassed from EX/MEM stage
    input  logic [31:0] mem_wb_result_fwd,  // Bypassed from MEM/WB stage
    input  logic  [1:0] forward_a,          // Control from FU
    input  logic  [1:0] forward_b,          // Control from FU
    
    // Outputs back to Fetch Stage (For branching)
    output logic        ex_pc_src,
    output logic [31:0] branch_target,
    output logic [31:0] ex_operand_a,       // forwarded rs1 value (the write source of CSR instructions)
    
    // Outputs to EX/MEM Pipeline Register
    output logic [31:0] ex_mem_alu_res,
    output logic [31:0] ex_mem_rs2_data,    // Saved for Store Instructions
    output logic  [4:0] ex_mem_rd_addr,
    output logic [31:0] ex_mem_pc_plus4,    // Saved for JAL/JALR
    
    // Control Signals to EX/MEM
    output logic        ex_mem_reg_write,
    output logic        ex_mem_mem_read,
    output logic        ex_mem_mem_write,
    output logic  [1:0] ex_mem_result_src,
    output logic  [2:0] ex_mem_funct3
);

    // Internal Signals
    logic [31:0] operand_a;
    logic [31:0] operand_b_fwd;
    logic [31:0] operand_b_alu;
    logic [31:0] alu_in_a;
    logic [31:0] alu_result;
    logic        zero, less_than, less_than_u;
    logic        branch_taken;

    // -------------------------------------------------------------------------
    // 1. Operand Multiplexing (Forwarding)
    // -------------------------------------------------------------------------
    always_comb begin
        case (forward_a)
            2'b00: operand_a = id_ex_rs1_data;
            2'b10: operand_a = ex_mem_alu_res_fwd;
            2'b01: operand_a = mem_wb_result_fwd;
            default: operand_a = id_ex_rs1_data;
        endcase

        case (forward_b)
            2'b00: operand_b_fwd = id_ex_rs2_data;
            2'b10: operand_b_fwd = ex_mem_alu_res_fwd;
            2'b01: operand_b_fwd = mem_wb_result_fwd;
            default: operand_b_fwd = id_ex_rs2_data;
        endcase
    end

    // ALU Input B Selection (Register Data vs Immediate)
    assign operand_b_alu = id_ex_alu_src ? id_ex_imm : operand_b_fwd;
    // ALU Input A Selection (FIX: AUIPC needs PC; branches/JALR still use forwarded rs1)
    assign alu_in_a = id_ex_alu_a_pc ? id_ex_pc : operand_a;

    // -------------------------------------------------------------------------
    // 2. Arithmetic Logic Unit (ALU)
    // -------------------------------------------------------------------------
    // Pre-compute condition flags for branches and SLT instructions
    assign zero = (operand_a == operand_b_fwd);
    assign less_than = ($signed(operand_a) < $signed(operand_b_fwd));
    assign less_than_u = (operand_a < operand_b_fwd);

    always_comb begin
        case (id_ex_alu_ctrl)
            4'b0000: alu_result = alu_in_a + operand_b_alu;                 // ADD
            4'b1000: alu_result = alu_in_a - operand_b_alu;                 // SUB
            4'b0001: alu_result = alu_in_a << operand_b_alu[4:0];           // SLL
            // FIX: SLT/SLTU must compare against operand_b_alu, otherwise SLTI/SLTIU
            // compare rs1 against x0 instead of the immediate (breaks 'seqz' = sltiu rd,rs,1)
            4'b0010: alu_result = {31'b0, ($signed(operand_a) < $signed(operand_b_alu))}; // SLT/SLTI
            4'b0011: alu_result = {31'b0, (operand_a < operand_b_alu)};                    // SLTU/SLTIU
            4'b0100: alu_result = alu_in_a ^ operand_b_alu;                 // XOR
            4'b0101: alu_result = alu_in_a >> operand_b_alu[4:0];           // SRL
            4'b1101: alu_result = $signed(alu_in_a) >>> operand_b_alu[4:0]; // SRA
            4'b0110: alu_result = alu_in_a | operand_b_alu;                 // OR
            4'b0111: alu_result = alu_in_a & operand_b_alu;                 // AND
            default: alu_result = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 3. Branch & Jump Evaluation
    // -------------------------------------------------------------------------
    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_alu_ctrl[2:0])
                3'b000: branch_taken = zero;           // BEQ
                3'b001: branch_taken = !zero;          // BNE
                3'b100: branch_taken = less_than;      // BLT
                3'b101: branch_taken = !less_than;     // BGE
                3'b110: branch_taken = less_than_u;    // BLTU
                3'b111: branch_taken = !less_than_u;   // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    assign ex_operand_a = operand_a;
    assign ex_pc_src = branch_taken | id_ex_jump;
    
    // Target Adder Multiplexer
    // JALR uses: (rs1 + imm) with LSB cleared to 0. 
    // JAL/Branch uses: (PC + imm)
    assign branch_target = id_ex_is_jalr ? ((operand_a + id_ex_imm) & ~32'h1) : 
                                           (id_ex_pc + id_ex_imm);

    // -------------------------------------------------------------------------
    // 4. EX/MEM Pipeline Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_alu_res <= 0; ex_mem_rs2_data <= 0;
            ex_mem_rd_addr <= 0; ex_mem_pc_plus4 <= 0;
            ex_mem_reg_write <= 0; ex_mem_mem_read <= 0;
            ex_mem_mem_write <= 0; ex_mem_result_src <= 0; ex_mem_funct3 <= 0;
        end else if(!stall) begin
            ex_mem_alu_res <= id_ex_is_csr ? csr_rdata : alu_result;
            ex_mem_rs2_data <= operand_b_fwd; // Captures forwarded data for Store instructions
            ex_mem_rd_addr <= id_ex_rd_addr;
            ex_mem_pc_plus4 <= id_ex_pc + 32'd4;
            
            // an interrupt taken in this cycle squashes the instruction in EX: it enters MEM as a bubble
            ex_mem_reg_write <= id_ex_reg_write & ~ex_squash;
            ex_mem_mem_read  <= id_ex_mem_read  & ~ex_squash;
            ex_mem_mem_write <= id_ex_mem_write & ~ex_squash;
            ex_mem_result_src <= id_ex_result_src;
            ex_mem_funct3 <= id_ex_funct3;
        end
    end

endmodule
