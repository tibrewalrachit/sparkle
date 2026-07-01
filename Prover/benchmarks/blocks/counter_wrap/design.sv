// ============================================================================
// counter_wrap — 8-bit mod-11 wrapping counter (sanity benchmark)
//
// Counts 0..LIMIT and wraps to 0. Property: the counter never exceeds LIMIT.
// Trivial BMC/induction sanity check.
// ============================================================================
module counter_wrap (
    input  logic clk,
    input  logic rst,
    input  logic en,
    output logic [7:0] count
);
    localparam logic [7:0] LIMIT = 8'd10;

    logic [7:0] cnt = 8'd0;

    always_ff @(posedge clk) begin
        if (rst)
            cnt <= 8'd0;
        else if (en)
            cnt <= (cnt == LIMIT) ? 8'd0 : cnt + 8'd1;
    end

    assign count = cnt;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Bound: counter stays within [0, LIMIT]
        assert (cnt <= LIMIT);
    end
endmodule
