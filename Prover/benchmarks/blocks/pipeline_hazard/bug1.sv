// BUG (seeded): the WB->ID bypass network was omitted — a register-file
// read issued on the same edge as the WB write returns the stale value,
// and by EX time the producer has left the WB stage.
// ============================================================================
// pipeline_hazard — 3-stage pipelined datapath with operand forwarding
//
// A tiny 4-register, 32-bit machine with a 3-stage pipeline:
//   IN (issue) -> S1 (decode/regfile read) -> EX/WB (execute, then write back)
// Two bypass networks are required for correctness:
//   * WB -> ID bypass (register file write is not visible to a same-edge read)
//   * WB -> EX forwarding (back-to-back dependent instructions)
//
// A lock-step architectural model commits each instruction when it reaches
// EX. Property: the (forwarded) operands seen by EX always equal the
// architectural register values — i.e. forwarding reproduces the ISA view.
// 32-bit datapath: BMC has real work to do (scalability stressor).
// ============================================================================
module pipeline_hazard (
    input  logic clk,
    input  logic rst,
    input  logic        in_valid,
    input  logic [1:0]  in_op,    // 0: ADD  1: XOR  2: LI (imm)  3: ADDI
    input  logic [1:0]  in_rd,
    input  logic [1:0]  in_rs1,
    input  logic [1:0]  in_rs2,
    input  logic [7:0]  in_imm,
    output logic [31:0] out_result
);
    // --------------------------------------------------------------------
    // Implementation register file (4 x 32, explicit registers)
    // --------------------------------------------------------------------
    logic [31:0] rf0 = 32'd0, rf1 = 32'd0, rf2 = 32'd0, rf3 = 32'd0;

    // WB stage registers
    logic        wb_valid = 1'b0;
    logic [1:0]  wb_rd    = 2'd0;
    logic [31:0] wb_val   = 32'd0;

    // Combinational regfile read
    wire [31:0] rf_rs1 = (in_rs1 == 2'd0) ? rf0 :
                         (in_rs1 == 2'd1) ? rf1 :
                         (in_rs1 == 2'd2) ? rf2 : rf3;
    wire [31:0] rf_rs2 = (in_rs2 == 2'd0) ? rf0 :
                         (in_rs2 == 2'd1) ? rf1 :
                         (in_rs2 == 2'd2) ? rf2 : rf3;

    // WB -> ID bypass (the WB write commits on this same edge, so the raw
    // regfile read would be one instruction stale)
    wire [31:0] id_a = rf_rs1;
    wire [31:0] id_b = rf_rs2;

    // --------------------------------------------------------------------
    // Stage 1 (decode) registers
    // --------------------------------------------------------------------
    logic        s1_valid = 1'b0;
    logic [1:0]  s1_op  = 2'd0;
    logic [1:0]  s1_rd  = 2'd0;
    logic [1:0]  s1_rs1 = 2'd0;
    logic [1:0]  s1_rs2 = 2'd0;
    logic [7:0]  s1_imm = 8'd0;
    logic [31:0] s1_a   = 32'd0;
    logic [31:0] s1_b   = 32'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
        end else begin
            s1_valid <= in_valid;
            s1_op    <= in_op;
            s1_rd    <= in_rd;
            s1_rs1   <= in_rs1;
            s1_rs2   <= in_rs2;
            s1_imm   <= in_imm;
            s1_a     <= id_a;
            s1_b     <= id_b;
        end
    end

    // --------------------------------------------------------------------
    // EX stage: WB -> EX forwarding + execute
    // --------------------------------------------------------------------
    wire [31:0] ex_a = (wb_valid && (wb_rd == s1_rs1)) ? wb_val : s1_a;
    wire [31:0] ex_b = (wb_valid && (wb_rd == s1_rs2)) ? wb_val : s1_b;

    wire [31:0] imm_ext = {24'd0, s1_imm};
    wire [31:0] ex_result = (s1_op == 2'd0) ? ex_a + ex_b :
                            (s1_op == 2'd1) ? ex_a ^ ex_b :
                            (s1_op == 2'd2) ? imm_ext :
                                              ex_a + imm_ext;

    always_ff @(posedge clk) begin
        if (rst) begin
            wb_valid <= 1'b0;
        end else begin
            wb_valid <= s1_valid;
            wb_rd    <= s1_rd;
            wb_val   <= ex_result;
        end
    end

    // WB: register file write
    always_ff @(posedge clk) begin
        if (rst) begin
            rf0 <= 32'd0; rf1 <= 32'd0; rf2 <= 32'd0; rf3 <= 32'd0;
        end else if (wb_valid) begin
            if (wb_rd == 2'd0) rf0 <= wb_val;
            if (wb_rd == 2'd1) rf1 <= wb_val;
            if (wb_rd == 2'd2) rf2 <= wb_val;
            if (wb_rd == 2'd3) rf3 <= wb_val;
        end
    end

    assign out_result = wb_val;

    // --------------------------------------------------------------------
    // Architectural reference model: commits when the instruction is in EX
    // --------------------------------------------------------------------
    logic [31:0] arch0 = 32'd0, arch1 = 32'd0, arch2 = 32'd0, arch3 = 32'd0;

    wire [31:0] arch_rs1 = (s1_rs1 == 2'd0) ? arch0 :
                           (s1_rs1 == 2'd1) ? arch1 :
                           (s1_rs1 == 2'd2) ? arch2 : arch3;
    wire [31:0] arch_rs2 = (s1_rs2 == 2'd0) ? arch0 :
                           (s1_rs2 == 2'd1) ? arch1 :
                           (s1_rs2 == 2'd2) ? arch2 : arch3;

    wire [31:0] arch_result = (s1_op == 2'd0) ? arch_rs1 + arch_rs2 :
                              (s1_op == 2'd1) ? arch_rs1 ^ arch_rs2 :
                              (s1_op == 2'd2) ? imm_ext :
                                                arch_rs1 + imm_ext;

    always_ff @(posedge clk) begin
        if (rst) begin
            arch0 <= 32'd0; arch1 <= 32'd0; arch2 <= 32'd0; arch3 <= 32'd0;
        end else if (s1_valid) begin
            if (s1_rd == 2'd0) arch0 <= arch_result;
            if (s1_rd == 2'd1) arch1 <= arch_result;
            if (s1_rd == 2'd2) arch2 <= arch_result;
            if (s1_rd == 2'd3) arch3 <= arch_result;
        end
    end

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Forwarded operands equal the architectural register values
        if (s1_valid && !rst) begin
            assert (ex_a == arch_rs1);
            assert (ex_b == arch_rs2);
        end
    end
endmodule
