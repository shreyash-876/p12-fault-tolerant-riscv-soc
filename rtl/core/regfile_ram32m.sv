`timescale 1ns / 1ps

module regfile_ram32m (
    input  logic        clk,
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,
    input  logic        we,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);

    // Xilinx synthesis attribute forcing distributed RAM (LUTRAM)
    (* ram_style = "distributed" *) logic [31:0] registers [1:31]; 

    // -------------------------------------------------------------------------
    // Asynchronous Read Ports with WB-to-ID Write-Through Bypass
    // -------------------------------------------------------------------------

    // Synchronous Write Port with Telemetry Probe
    always_ff @(posedge clk) begin
        if (we && rd_addr != 5'd0) begin
            registers[rd_addr] <= rd_data;
`ifdef REGFILE_TRACE
            $display("[REGFILE] t=%0t | %m | Reg x%0d <= 0x%08h", $time, rd_addr, rd_data);
`endif
        end
    end

    // Initialize registers for simulation
    initial begin
        for (int i = 1; i < 32; i++) begin
            registers[i] = 32'h0000_0000;
        end
    end
    
    assign rs1_data = (rs1_addr == 5'd0) ? 32'h0000_0000 :
                      (we && (rd_addr == rs1_addr)) ? rd_data : registers[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'h0000_0000 :
                      (we && (rd_addr == rs2_addr)) ? rd_data : registers[rs2_addr];

    // -------------------------------------------------------------------------
    // Synchronous Write Port
    // -----------------------------------------------------------------------
endmodule
