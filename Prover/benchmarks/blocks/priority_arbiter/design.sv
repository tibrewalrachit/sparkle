// ============================================================================
// priority_arbiter — 4-client priority arbiter with anti-starvation boost
//
// Fixed priority (client 0 highest), but each client has a starvation
// counter. Once a requesting client has waited LIMIT cycles it becomes
// "starved" and starved clients preempt normal priority (lowest starved
// index first). Bounded-wait safety encoding:
//   For every client i: wait_i <= LIMIT + 2
// (at most two lower-indexed starved clients can be served first; client 0
// can never starve under this policy).
// ============================================================================
module priority_arbiter (
    input  logic clk,
    input  logic rst,
    input  logic [3:0] req,
    output logic [3:0] grant
);
    localparam logic [3:0] LIMIT = 4'd8;
    localparam logic [3:0] BOUND = 4'd10;  // LIMIT + 2

    logic [3:0] wait0 = 4'd0;
    logic [3:0] wait1 = 4'd0;
    logic [3:0] wait2 = 4'd0;
    logic [3:0] wait3 = 4'd0;

    wire starved0 = req[0] && (wait0 >= LIMIT);
    wire starved1 = req[1] && (wait1 >= LIMIT);
    wire starved2 = req[2] && (wait2 >= LIMIT);
    wire starved3 = req[3] && (wait3 >= LIMIT);
    wire [3:0] starved = {starved3, starved2, starved1, starved0};

    // Lowest-set-bit isolation
    wire [3:0] pick_starved = starved & (~starved + 4'd1);
    wire [3:0] pick_normal  = req & (~req + 4'd1);

    assign grant = (starved != 4'd0) ? pick_starved :
                   (req     != 4'd0) ? pick_normal  : 4'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            wait0 <= 4'd0;
            wait1 <= 4'd0;
            wait2 <= 4'd0;
            wait3 <= 4'd0;
        end else begin
            wait0 <= (!req[0] || grant[0]) ? 4'd0 : wait0 + 4'd1;
            wait1 <= (!req[1] || grant[1]) ? 4'd0 : wait1 + 4'd1;
            wait2 <= (!req[2] || grant[2]) ? 4'd0 : wait2 + 4'd1;
            wait3 <= (!req[3] || grant[3]) ? 4'd0 : wait3 + 4'd1;
        end
    end

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Mutual exclusion and no grant without request
        assert ((grant & (grant - 4'd1)) == 4'd0);
        assert ((grant & ~req) == 4'd0);
        // Bounded wait (starvation-freedom as a safety property)
        assert (wait0 <= BOUND);
        assert (wait1 <= BOUND);
        assert (wait2 <= BOUND);
        assert (wait3 <= BOUND);
    end
endmodule
