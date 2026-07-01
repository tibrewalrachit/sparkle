// BUG (seeded): simultaneous enqueue+dequeue race — the if/else priority
// ignores the dequeue when both fire, so count drifts away from the
// pointer distance.
// ============================================================================
// sync_fifo — depth-8 synchronous FIFO with explicit count
//
// Valid/Ready (Decoupled) interface in the style of
// Sparkle/Library/Queue/SyncFIFO.lean (depth 8 instead of 4).
// Properties:
//   1. No overflow: count <= DEPTH
//   2. Pointer/count consistency: count mod 8 == wr_ptr - rd_ptr
//   3. Empty blocks dequeue, full blocks enqueue
// ============================================================================
module sync_fifo (
    input  logic clk,
    input  logic rst,
    input  logic       enq_valid,
    input  logic [7:0] enq_data,
    input  logic       deq_ready,
    output logic       enq_ready,
    output logic       deq_valid,
    output logic [7:0] deq_data
);
    localparam logic [3:0] DEPTH = 4'd8;

    logic [7:0] mem [0:7];
    logic [2:0] wr_ptr = 3'd0;
    logic [2:0] rd_ptr = 3'd0;
    logic [3:0] count  = 4'd0;

    wire full  = (count == DEPTH);
    wire empty = (count == 4'd0);

    assign enq_ready = !full;
    assign deq_valid = !empty;

    wire do_enq = enq_valid && enq_ready;
    wire do_deq = deq_ready && deq_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 3'd0;
            rd_ptr <= 3'd0;
            count  <= 4'd0;
        end else begin
            if (do_enq) begin
                mem[wr_ptr] <= enq_data;
                wr_ptr <= wr_ptr + 3'd1;
            end
            if (do_deq)
                rd_ptr <= rd_ptr + 3'd1;
            if (do_enq)
                count <= count + 4'd1;
            else if (do_deq)
                count <= count - 4'd1;
        end
    end

    assign deq_data = mem[rd_ptr];

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // No overflow / underflow (count is unsigned, underflow wraps high)
        assert (count <= DEPTH);
        // Pointer/count consistency (count == 0 and count == 8 both mean
        // wr_ptr == rd_ptr; anything else is the modular pointer distance)
        assert (count[2:0] == (wr_ptr - rd_ptr));
        // Empty blocks dequeue
        assert (!(deq_valid && count == 4'd0));
        // Full blocks enqueue
        assert (!(enq_ready && count == DEPTH));
    end
endmodule
