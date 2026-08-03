// ============================================================================
// lfsr — 16-bit Fibonacci LFSR (x^16 + x^14 + x^13 + x^11 + 1)
//
// Right-shifting LFSR with a parallel load port. The load path structurally
// guards against loading the all-zero lockup state. Property: the LFSR state
// is never zero. (Safe by an invariant on the feedback taps: the tap set
// includes bit 0, so the only predecessor of zero is zero itself.)
// ============================================================================
module lfsr (
    input  logic clk,
    input  logic rst,
    input  logic load,
    input  logic [15:0] load_val,
    output logic [15:0] state_out
);
    logic [15:0] lfsr_q = 16'hACE1;

    // Fibonacci feedback: taps 16, 14, 13, 11 => bits 0, 2, 3, 5 of lfsr_q
    wire fb = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5];
    wire [15:0] lfsr_next = {fb, lfsr_q[15:1]};

    // Environment constraint modeled structurally: never load the zero state
    wire [15:0] load_guarded = (load_val == 16'd0) ? 16'h0001 : load_val;

    always_ff @(posedge clk) begin
        if (rst)
            lfsr_q <= 16'hACE1;
        else if (load)
            lfsr_q <= load_guarded;
        else
            lfsr_q <= lfsr_next;
    end

    assign state_out = lfsr_q;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // The LFSR never enters the all-zero lockup state
        assert (lfsr_q != 16'd0);
    end
endmodule
