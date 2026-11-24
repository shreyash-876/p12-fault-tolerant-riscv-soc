`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axil_gpio: Zybo LEDs / switches / buttons on the bus at 0x8000_0000.
//   0x00 LED  RW  bits [3:0] drive LD0..LD3
//   0x04 SW   RO  bits [3:0] = SW0..SW3   (2-FF synchronised)
//   0x08 BTN  RO  bits [3:0] = BTN0..BTN3 (2-FF synchronised, not debounced)
// -----------------------------------------------------------------------------
module axil_gpio
    import mem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] s_awaddr,  input  logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input  logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic  [1:0] s_bresp,   output logic s_bvalid,  input  logic s_bready,
    input  logic [31:0] s_araddr,  input  logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input  logic s_rready,

    output logic  [3:0] led,
    input  logic  [3:0] sw,
    input  logic  [3:0] btn
);
    logic        req_valid, req_ready, rsp_valid;
    mem_op_t     req_op;
    logic [31:0] req_addr, req_wdata, rdata_q;
    logic  [3:0] req_wstrb;

    axil_frontend u_fe (
        .clk, .rst_n,
        .s_awaddr, .s_awvalid, .s_awready, .s_wdata, .s_wstrb, .s_wvalid, .s_wready,
        .s_bresp, .s_bvalid, .s_bready, .s_araddr, .s_arvalid, .s_arready,
        .s_rdata, .s_rresp, .s_rvalid, .s_rready,
        .req_valid, .req_ready, .req_op, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata(rdata_q), .rsp_err(1'b0)
    );

    logic [3:0] sw_s1, sw_s2, btn_s1, btn_s2;
    always_ff @(posedge clk) begin
        sw_s1  <= sw;  sw_s2  <= sw_s1;
        btn_s1 <= btn; btn_s2 <= btn_s1;
    end

    assign req_ready = !rsp_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0; rdata_q <= '0; led <= '0;
        end else begin
            rsp_valid <= req_valid && req_ready;
            if (req_valid && req_ready) begin
                if (req_op == OP_WRITE) begin
                    if (req_addr[3:2] == 2'd0 && req_wstrb[0]) led <= req_wdata[3:0];
                    rdata_q <= '0;
                end else begin
                    case (req_addr[3:2])
                        2'd0:    rdata_q <= {28'd0, led};
                        2'd1:    rdata_q <= {28'd0, sw_s2};
                        2'd2:    rdata_q <= {28'd0, btn_s2};
                        default: rdata_q <= '0;
                    endcase
                end
            end
        end
    end
endmodule
