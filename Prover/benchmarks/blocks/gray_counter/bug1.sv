// BUG (seeded): carry-propagation bug at the nibble boundary — when the
// low nibble is 0xF the binary counter increments by 2, so the Gray-code
// image changes in more than one bit position.
// ============================================================================
// gray_counter — 8-bit Gray-code counter
//
// Maintains a binary counter and its Gray-code image. Properties:
//   1. gray == bin ^ (bin >> 1)   (encoding invariant)
//   2. Between two successive updates, exactly one bit of the Gray value
//      changes (classic inductive invariant).
// ============================================================================
module gray_counter (
    input  logic clk,
    input  logic rst,
    input  logic en,
    output logic [7:0] gray_out
);
    logic [7:0] bin       = 8'd0;
    logic [7:0] gray      = 8'd0;
    logic [7:0] gray_prev = 8'd0;
    logic       moved     = 1'b0;   // (gray, gray_prev) pair is meaningful

    wire [7:0] bin_next  = (bin[3:0] == 4'hF) ? bin + 8'd2 : bin + 8'd1;
    wire [7:0] gray_next = bin_next ^ (bin_next >> 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            bin       <= 8'd0;
            gray      <= 8'd0;
            gray_prev <= 8'd0;
            moved     <= 1'b0;
        end else if (en) begin
            bin       <= bin_next;
            gray      <= gray_next;
            gray_prev <= gray;
            moved     <= 1'b1;
        end
    end

    assign gray_out = gray;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    wire [7:0] diff = gray ^ gray_prev;
    wire diff_onehot = (diff != 8'd0) && ((diff & (diff - 8'd1)) == 8'd0);

    always @(posedge clk) begin
        // Encoding invariant: gray is the Gray-code image of bin
        assert (gray == (bin ^ (bin >> 1)));
        // One-bit-change invariant across each counted step
        if (moved)
            assert (diff_onehot);
    end
endmodule
