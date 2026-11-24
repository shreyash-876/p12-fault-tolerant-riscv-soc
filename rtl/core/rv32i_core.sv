`timescale 1ns / 1ps

module rv32i_core (
    input  logic        clk,
    input  logic        rst_n,

    // Machine external interrupt request (level). Taken when mstatus.MIE and mie.MEIE are set.
    input  logic        ext_irq,

    // Instruction Memory Interface (ITCM)
    output logic [31:0] itcm_addr,
    output logic        itcm_en,      // FIX: BRAM read enable (= !fetch stall); replaces the
                                      // hierarchical reference u_core0.global_stall in core_top
    input  logic [31:0] itcm_rdata,

    // AXI4 Master Interface (Data Memory)
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic  [3:0] m_axi_wstrb,  // FIX: byte lanes for SB/SH (was missing)
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic  [1:0] m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic  [1:0] m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // -------------------------------------------------------------------------
    // Global Stall & Flush Signals
    // -------------------------------------------------------------------------
    (* mark_debug = "true" *) logic mem_stall;        // Asserted by MEM stage during AXI transactions
    logic hazard_stall_if;  // Asserted by Hazard Unit (Load-Use)
    logic branch_flush_if;  // Asserted by Hazard Unit (Branch mispredict)
    logic hazard_flush_id;  // Asserted by Hazard Unit (Load-Use or Branch)
    logic branch_taken_ex;  // Asserted by EX stage
    
    (* mark_debug = "true" *) logic global_stall;
    assign global_stall = mem_stall | hazard_stall_if;
    assign itcm_en      = ~global_stall;

    // Combined flushes (Gated with !mem_stall so memory stalls never flush valid pipeline state)
    logic decode_flush;
    logic fetch_flush;
    assign fetch_flush  = branch_flush_if & ~mem_stall;
    assign decode_flush = (hazard_flush_id | branch_flush_if) & ~mem_stall;

    // -------------------------------------------------------------------------
    // Inter-Stage Wires
    // -------------------------------------------------------------------------
    // IF/ID
    (* mark_debug = "true" *) logic [31:0] if_id_pc;
    (* mark_debug = "true" *) logic [31:0] if_id_instr;

    // ID/EX
    logic [31:0] id_ex_pc, id_ex_imm, id_ex_rs1_data, id_ex_rs2_data;
    logic [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    logic        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write;
    logic        id_ex_branch, id_ex_jump, id_ex_is_jalr, id_ex_alu_src;
    logic [1:0]  id_ex_result_src;
    logic [3:0]  id_ex_alu_ctrl;
    logic        id_ex_alu_a_pc;
    logic [2:0]  id_ex_funct3;
    logic        id_ex_valid, id_ex_is_csr, id_ex_is_mret;
    logic        if_id_valid;

    // EX/MEM
    logic [31:0] ex_mem_alu_res, ex_mem_rs2_data, ex_mem_pc_plus4;
    logic [4:0]  ex_mem_rd_addr;
    logic        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write;
    logic [1:0]  ex_mem_result_src;
    logic [2:0]  ex_mem_funct3;
    logic [31:0] ex_branch_target;

    // MEM/WB (Generated locally)
    logic [31:0] mem_wb_alu_res, mem_wb_mem_data, mem_wb_pc_plus4;
    (* mark_debug = "true" *) logic [4:0]  mem_wb_rd_addr;
    (* mark_debug = "true" *) logic        mem_wb_reg_write;
    logic        mem_wb_mem_read;
    logic [1:0]  mem_wb_result_src;
    logic [2:0]  mem_wb_funct3;

    // Writeback Result
    (* mark_debug = "true" *) logic [31:0] wb_final_data;

    // -------------------------------------------------------------------------
    // 1. INSTRUCTION FETCH (IF)
    // -------------------------------------------------------------------------
    fetch_stage if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(global_stall),
        .flush(fetch_flush),
        .pc_src(branch_taken_ex),
        .branch_target(ex_branch_target),
        .itcm_addr(itcm_addr),
        .itcm_rdata(itcm_rdata),
        .if_id_pc(if_id_pc),
        .if_id_instr(if_id_instr),
        .if_id_valid(if_id_valid)
    );

    // -------------------------------------------------------------------------
    // 2. DECODE (ID) & REGISTER FILE
    // -------------------------------------------------------------------------
    logic [4:0] id_rs1_addr, id_rs2_addr;
    logic [31:0] id_rs1_data, id_rs2_data;

    logic [31:0] id_rs1_data_bypassed;
    logic [31:0] id_rs2_data_bypassed;

    regfile_ram32m register_file (
        .clk(clk),
        .rs1_addr(id_rs1_addr),   .rs1_data(id_rs1_data),
        .rs2_addr(id_rs2_addr),   .rs2_data(id_rs2_data),
        .we(mem_wb_reg_write),
        .rd_addr(mem_wb_rd_addr), .rd_data(wb_final_data)
    );

    assign id_rs1_data_bypassed = (mem_wb_reg_write && (mem_wb_rd_addr == id_rs1_addr) && (id_rs1_addr != 5'd0)) ? wb_final_data : id_rs1_data;
    assign id_rs2_data_bypassed = (mem_wb_reg_write && (mem_wb_rd_addr == id_rs2_addr) && (id_rs2_addr != 5'd0)) ? wb_final_data : id_rs2_data;

    decode_stage id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(mem_stall),
        .flush(decode_flush),
        .if_id_pc(if_id_pc),
        .if_id_instr(if_id_instr),
        .if_id_valid(if_id_valid),
        
        .rs1_addr(id_rs1_addr),
        .rs2_addr(id_rs2_addr),
        .rs1_data_in(id_rs1_data_bypassed),
        .rs2_data_in(id_rs2_data_bypassed),
        
        .id_ex_pc(id_ex_pc),
        .id_ex_imm(id_ex_imm),
        .id_ex_rs1_data(id_ex_rs1_data),
        .id_ex_rs2_data(id_ex_rs2_data),
        .id_ex_rs1_addr(id_ex_rs1_addr),
        .id_ex_rs2_addr(id_ex_rs2_addr),
        .id_ex_rd_addr(id_ex_rd_addr),
        
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_mem_write(id_ex_mem_write),
        .id_ex_branch(id_ex_branch),
        .id_ex_jump(id_ex_jump),
        .id_ex_is_jalr(id_ex_is_jalr),
        .id_ex_alu_src(id_ex_alu_src),
        .id_ex_result_src(id_ex_result_src),
        .id_ex_alu_ctrl(id_ex_alu_ctrl),
        .id_ex_alu_a_pc(id_ex_alu_a_pc),
        .id_ex_funct3(id_ex_funct3),
        .id_ex_valid(id_ex_valid),
        .id_ex_is_csr(id_ex_is_csr),
        .id_ex_is_mret(id_ex_is_mret)
    );

    hazard_unit hazard_det (
        .rs1_addr(id_rs1_addr),
        .rs2_addr(id_rs2_addr),
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd_addr(id_ex_rd_addr),
        .ex_pc_src(branch_taken_ex),
        .stall_if(hazard_stall_if),
        .flush_if(branch_flush_if),
        .flush_id(hazard_flush_id)
    );

    // -------------------------------------------------------------------------
    // 3. EXECUTE (EX)
    // -------------------------------------------------------------------------
    logic [1:0] forward_a, forward_b;

    // ---- interrupts / CSRs: the trap and MRET redirect the PC exactly like a taken branch from EX ----
    logic        ex_pc_src_raw;                 // branch / jump decided by the execute stage
    logic [31:0] ex_target_raw;
    logic [31:0] ex_operand_a;
    logic [31:0] csr_rdata;
    logic        trap_take, mret_take;
    logic [31:0] trap_target, mret_target;

    assign branch_taken_ex  = ex_pc_src_raw | trap_take | mret_take;
    assign ex_branch_target = trap_take ? trap_target : (mret_take ? mret_target : ex_target_raw);

    csr_unit csr (
        .clk(clk), .rst_n(rst_n),
        .ext_irq(ext_irq),
        .ex_valid(id_ex_valid), .ex_pc(id_ex_pc), .ex_stall(mem_stall),
        .ex_is_csr(id_ex_is_csr), .ex_is_mret(id_ex_is_mret),
        .ex_funct3(id_ex_funct3), .ex_csr_addr(id_ex_imm[11:0]),
        .ex_rs1_val(ex_operand_a), .ex_zimm(id_ex_rs1_addr),
        .csr_rdata(csr_rdata),
        .trap_take(trap_take), .trap_target(trap_target),
        .mret_take(mret_take), .mret_target(mret_target)
    );

    forwarding_unit fwd_unit (
        .id_ex_rs1_addr(id_ex_rs1_addr),
        .id_ex_rs2_addr(id_ex_rs2_addr),
        .ex_mem_rd_addr(ex_mem_rd_addr),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd_addr(mem_wb_rd_addr),
        .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    execute_stage ex_unit (
        .clk(clk),
        .rst_n(rst_n),
        .stall(mem_stall),
        .id_ex_pc(id_ex_pc),
        .id_ex_imm(id_ex_imm),
        .id_ex_rs1_data(id_ex_rs1_data),
        .id_ex_rs2_data(id_ex_rs2_data),
        .id_ex_rs1_addr(id_ex_rs1_addr),
        .id_ex_rs2_addr(id_ex_rs2_addr),
        .id_ex_rd_addr(id_ex_rd_addr),
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_mem_write(id_ex_mem_write),
        .id_ex_branch(id_ex_branch),
        .id_ex_jump(id_ex_jump),
        .id_ex_is_jalr(id_ex_is_jalr),
        .id_ex_alu_src(id_ex_alu_src),
        .id_ex_result_src(id_ex_result_src),
        .id_ex_alu_ctrl(id_ex_alu_ctrl),
        .id_ex_alu_a_pc(id_ex_alu_a_pc),
        .id_ex_funct3(id_ex_funct3),
        .id_ex_is_csr(id_ex_is_csr),
        .csr_rdata(csr_rdata),
        .ex_squash(trap_take),
        
        .ex_mem_alu_res_fwd(ex_mem_alu_res),
        .mem_wb_result_fwd(wb_final_data),
        .forward_a(forward_a),
        .forward_b(forward_b),
        
        .ex_pc_src(ex_pc_src_raw),
        .branch_target(ex_target_raw),
        .ex_operand_a(ex_operand_a),
        
        .ex_mem_alu_res(ex_mem_alu_res),
        .ex_mem_rs2_data(ex_mem_rs2_data),
        .ex_mem_rd_addr(ex_mem_rd_addr),
        .ex_mem_pc_plus4(ex_mem_pc_plus4),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_mem_read(ex_mem_mem_read),
        .ex_mem_mem_write(ex_mem_mem_write),
        .ex_mem_result_src(ex_mem_result_src),
        .ex_mem_funct3(ex_mem_funct3)
    );

    // -------------------------------------------------------------------------
    // 4. MEMORY (MEM) STAGE (AXI4 State Machine)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {ST_IDLE, ST_READ_WAIT, ST_WRITE_WAIT} axi_state_t;
    (* mark_debug = "true" *) axi_state_t axi_state;

    // FIX: store byte-lane formatting (SB/SH/SW). Address low bits pick the lane.
    logic [3:0]  st_wstrb;
    logic [31:0] st_wdata;
    always_comb begin
        case (ex_mem_funct3[1:0])
            2'b00:   begin st_wstrb = 4'b0001 << ex_mem_alu_res[1:0];          st_wdata = {4{ex_mem_rs2_data[7:0]}};  end // SB
            2'b01:   begin st_wstrb = 4'b0011 << {ex_mem_alu_res[1], 1'b0};    st_wdata = {2{ex_mem_rs2_data[15:0]}}; end // SH
            default: begin st_wstrb = 4'b1111;                                 st_wdata = ex_mem_rs2_data;            end // SW
        endcase
    end

    // --- Combinational Stall Logic ---
    always_comb begin
        mem_stall = 1'b0;
        
        case (axi_state)
            ST_IDLE: begin
                if (ex_mem_mem_read || ex_mem_mem_write) begin
                    mem_stall = 1'b1;
                end
            end
            
            ST_READ_WAIT: begin
                mem_stall = 1'b1;
                if (m_axi_rvalid && m_axi_rready) begin
                    mem_stall = 1'b0; 
                end
            end
            
            ST_WRITE_WAIT: begin
                mem_stall = 1'b1;
                if ((!m_axi_awvalid || m_axi_awready) && 
                    (!m_axi_wvalid || m_axi_wready) && 
                    (!m_axi_bready || m_axi_bvalid)) begin
                    mem_stall = 1'b0;
                end
            end
            
            default: mem_stall = 1'b0;
        endcase
    end

    // --- AXI State Machine ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_state     <= ST_IDLE;
            m_axi_arvalid <= 1'b0; m_axi_araddr <= 32'd0; m_axi_rready <= 1'b0;
            m_axi_awvalid <= 1'b0; m_axi_awaddr <= 32'd0;
            m_axi_wvalid  <= 1'b0; m_axi_wdata  <= 32'd0; m_axi_wstrb <= 4'b0; m_axi_bready <= 1'b0;
        end else begin
            case (axi_state)
                ST_IDLE: begin
                    if (ex_mem_mem_read) begin
                        m_axi_arvalid <= 1'b1;
                        m_axi_araddr  <= ex_mem_alu_res;
                        m_axi_rready  <= 1'b1;
                        axi_state     <= ST_READ_WAIT;
                    end else if (ex_mem_mem_write) begin
                        m_axi_awvalid <= 1'b1;
                        m_axi_awaddr  <= ex_mem_alu_res;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wdata   <= st_wdata;
                        m_axi_wstrb   <= st_wstrb;
                        m_axi_bready  <= 1'b1;
                        axi_state     <= ST_WRITE_WAIT;
                    end
                end

                ST_READ_WAIT: begin
                    if (m_axi_arvalid && m_axi_arready) m_axi_arvalid <= 1'b0;
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready      <= 1'b0;
                        axi_state         <= ST_IDLE;
                    end
                end

                ST_WRITE_WAIT: begin
                    if (m_axi_awvalid && m_axi_awready) m_axi_awvalid <= 1'b0;
                    if (m_axi_wvalid && m_axi_wready)   m_axi_wvalid  <= 1'b0;
                    
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                    end

                    if ((!m_axi_awvalid || m_axi_awready) && 
                        (!m_axi_wvalid || m_axi_wready) && 
                        (!m_axi_bready || m_axi_bvalid)) begin
                        axi_state <= ST_IDLE;
                    end
                end

                default: axi_state <= ST_IDLE;
            endcase
        end
    end

// -------------------------------------------------------------------------
    // MEM/WB Pipeline Register (Corrected Stall & Retirement Logic)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_alu_res    <= 32'd0;
            mem_wb_mem_data   <= 32'd0;
            mem_wb_pc_plus4   <= 32'd0;
            mem_wb_rd_addr    <= 5'd0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_read   <= 1'b0;
            mem_wb_result_src <= 2'b00;
            mem_wb_funct3     <= 3'b000;
        end else if (!mem_stall) begin
            // FIX 1: during an AXI stall MEM/WB is now simply HELD. The old code cleared
            //        mem_wb_reg_write, which killed MEM/WB->EX forwarding for the instruction
            //        frozen in EX, so it resumed with a stale operand. Re-writing the same
            //        value to the same register every stalled cycle is harmless.
            // FIX 2: load data is taken straight from RDATA in the completion cycle (the only
            //        cycle a read releases the stall). The old code sampled a register that was
            //        being updated on the same edge, so every load returned the PREVIOUS load.
            mem_wb_alu_res    <= ex_mem_alu_res;
            mem_wb_mem_data   <= m_axi_rdata;
            mem_wb_pc_plus4   <= ex_mem_pc_plus4;
            mem_wb_rd_addr    <= ex_mem_rd_addr;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_read   <= ex_mem_mem_read;
            mem_wb_result_src <= ex_mem_result_src;
            mem_wb_funct3     <= ex_mem_funct3;
        end
    end

    // FIX: load extraction (LB/LH/LW/LBU/LHU). mem_wb_alu_res holds the byte address.
    logic [31:0] ld_shifted, ld_data;
    assign ld_shifted = mem_wb_mem_data >> {mem_wb_alu_res[1:0], 3'b000};
    always_comb begin
        case (mem_wb_funct3)
            3'b000:  ld_data = {{24{ld_shifted[7]}},  ld_shifted[7:0]};   // LB
            3'b001:  ld_data = {{16{ld_shifted[15]}}, ld_shifted[15:0]};  // LH
            3'b100:  ld_data = {24'b0, ld_shifted[7:0]};                  // LBU
            3'b101:  ld_data = {16'b0, ld_shifted[15:0]};                 // LHU
            default: ld_data = mem_wb_mem_data;                           // LW
        endcase
    end
    // -------------------------------------------------------------------------
    // 5. WRITE-BACK (WB) STAGE

    always_comb begin
        case(mem_wb_result_src)
            2'b00: wb_final_data = mem_wb_alu_res;
            2'b01: wb_final_data = ld_data;
            2'b10: wb_final_data = mem_wb_pc_plus4;
            default: wb_final_data = mem_wb_alu_res;
        endcase
    end

endmodule
