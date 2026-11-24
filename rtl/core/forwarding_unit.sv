`timescale 1ns / 1ps

module forwarding_unit (
    input  logic [4:0] id_ex_rs1_addr,
    input  logic [4:0] id_ex_rs2_addr,
    
    // Data from EX/MEM boundary
    input  logic [4:0] ex_mem_rd_addr,
    input  logic       ex_mem_reg_write,
    
    // Data from MEM/WB boundary
    input  logic [4:0] mem_wb_rd_addr,
    input  logic       mem_wb_reg_write,
    
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // Forwarding Control Encodings:
    // 2'b00 = Default (Use data from ID/EX pipeline register)
    // 2'b10 = EX Hazard (Forward directly from EX/MEM pipeline register)
    // 2'b01 = MEM Hazard (Forward directly from MEM/WB pipeline register)

    // RS1 Forwarding Logic
    always_comb begin
        forward_a = 2'b00;
        if (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b01;
    end

    // RS2 Forwarding Logic
    always_comb begin
        forward_b = 2'b00;
        if (ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b01;
    end

endmodule
