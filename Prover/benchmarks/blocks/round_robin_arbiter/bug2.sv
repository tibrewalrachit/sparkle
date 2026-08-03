// BUG (seeded): the lowest-set-bit isolation of the masked request
// vector was dropped, so several clients can be granted simultaneously.
// ============================================================================
// round_robin_arbiter — 4-client round-robin arbiter
//
// Rotating-priority arbiter in the spirit of Examples/Arbiter/RoundRobin.lean
// (generalized from 2 to 4 clients). The search for the next grant starts
// just above the last granted index and wraps via the unmasked fallback.
// Properties:
//   1. Mutual exclusion: at most one grant at a time
//   2. No grant without request
//   3. Work conservation: some grant iff some request
//   4. Round-robin alternation: a client is never granted twice in a row
//      while another client has been continuously requesting
// ============================================================================
module round_robin_arbiter (
    input  logic clk,
    input  logic rst,
    input  logic [3:0] req,
    output logic [3:0] grant
);
    logic [1:0] last = 2'd0;   // index of last granted client

    // Thermometer mask of positions strictly above 'last'
    wire [3:0] mask =
        (last == 2'd0) ? 4'b1110 :
        (last == 2'd1) ? 4'b1100 :
        (last == 2'd2) ? 4'b1000 :
                         4'b0000;
    wire [3:0] masked_req = req & mask;

    // Lowest-set-bit isolation (priority encode)
    wire [3:0] gnt_masked   = masked_req;
    wire [3:0] gnt_unmasked = req & (~req + 4'd1);

    assign grant = (masked_req != 4'd0) ? gnt_masked : gnt_unmasked;

    // Encode granted index
    wire [1:0] gidx = grant[1] ? 2'd1 :
                      grant[2] ? 2'd2 :
                      grant[3] ? 2'd3 : 2'd0;

    always_ff @(posedge clk) begin
        if (rst)
            last <= 2'd0;
        else if (grant != 4'd0)
            last <= gidx;
    end

    // History for the alternation property
    logic [3:0] grant_prev = 4'd0;
    logic [3:0] req_prev   = 4'd0;
    always_ff @(posedge clk) begin
        if (rst) begin
            grant_prev <= 4'd0;
            req_prev   <= 4'd0;
        end else begin
            grant_prev <= grant;
            req_prev   <= req;
        end
    end

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Mutual exclusion (grant is one-hot or zero)
        assert ((grant & (grant - 4'd1)) == 4'd0);
        // No grant without request
        assert ((grant & ~req) == 4'd0);
        // Work conservation
        assert ((req != 4'd0) == (grant != 4'd0));
        // Round-robin alternation: no back-to-back grant to the same client
        // while some other client has been continuously requesting
        assert (!((grant != 4'd0) && (grant == grant_prev) &&
                  ((req_prev & req & ~grant) != 4'd0)));
    end
endmodule
