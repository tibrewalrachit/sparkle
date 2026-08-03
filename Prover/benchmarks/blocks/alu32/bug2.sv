// BUG (seeded): decoder copy-paste error — the AND opcode selects the
// OR operation.
// ============================================================================
// alu32 — 32-bit ALU with registered operands
//
// Operands and opcode are registered, the result is combinational from the
// registered values. Properties are algebraic identities of the operations
// (they do not restate the implementation):
//   SUB:  a - a == 0, and result == 0 iff a == b
//   AND:  result is a lower bound of both operands (mask bound)
//   OR :  result is an upper bound of both operands
//   XOR:  a ^ a == 0
//   SLT/SLTU: irreflexive; SLTU result is boolean
//   SLL:  shift by zero is identity
// ============================================================================
module alu32 (
    input  logic clk,
    input  logic rst,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [2:0]  op,
    output logic [31:0] result
);
    localparam logic [2:0] OP_ADD  = 3'd0;
    localparam logic [2:0] OP_SUB  = 3'd1;
    localparam logic [2:0] OP_AND  = 3'd2;
    localparam logic [2:0] OP_OR   = 3'd3;
    localparam logic [2:0] OP_XOR  = 3'd4;
    localparam logic [2:0] OP_SLT  = 3'd5;
    localparam logic [2:0] OP_SLTU = 3'd6;
    localparam logic [2:0] OP_SLL  = 3'd7;

    logic [31:0] a_q  = 32'd0;
    logic [31:0] b_q  = 32'd0;
    logic [2:0]  op_q = 3'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            a_q  <= 32'd0;
            b_q  <= 32'd0;
            op_q <= 3'd0;
        end else begin
            a_q  <= a;
            b_q  <= b;
            op_q <= op;
        end
    end

    logic [31:0] res;
    always_comb begin
        case (op_q)
            OP_ADD:  res = a_q + b_q;
            OP_SUB:  res = a_q + ~b_q + 32'd1;   // two's complement subtract
            OP_AND:  res = a_q | b_q;
            OP_OR:   res = a_q | b_q;
            OP_XOR:  res = a_q ^ b_q;
            OP_SLT:  res = ($signed(a_q) < $signed(b_q)) ? 32'd1 : 32'd0;
            OP_SLTU: res = (a_q < b_q) ? 32'd1 : 32'd0;
            default: res = a_q << b_q[4:0];
        endcase
    end

    assign result = res;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (op_q == OP_SUB) begin
            // sub(a, a) == 0 and, more generally, zero iff equal
            assert ((result == 32'd0) == (a_q == b_q));
        end
        if (op_q == OP_AND) begin
            // AND mask bound: result cannot have bits outside either operand
            assert ((result & ~a_q) == 32'd0);
            assert ((result & ~b_q) == 32'd0);
        end
        if (op_q == OP_OR) begin
            // OR upper bound: result covers both operands
            assert ((result & a_q) == a_q);
            assert ((result & b_q) == b_q);
        end
        if (op_q == OP_XOR) begin
            if (a_q == b_q) assert (result == 32'd0);
        end
        if (op_q == OP_SLT) begin
            if (a_q == b_q) assert (result == 32'd0);
        end
        if (op_q == OP_SLTU) begin
            assert (result <= 32'd1);
            if (a_q == b_q) assert (result == 32'd0);
        end
        if (op_q == OP_SLL) begin
            if (b_q[4:0] == 5'd0) assert (result == a_q);
        end
    end
endmodule
