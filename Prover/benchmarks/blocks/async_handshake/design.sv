// ============================================================================
// async_handshake — 4-phase req/ack handshake pipeline
//
// A sender FSM and a receiver FSM communicate over a 4-phase (RZ) req/ack
// handshake. The receiver models a slow peripheral: it releases ack a few
// cycles after req falls. Properties:
//   1. req is asserted exactly in the sender's REQ phase
//   2. ack is asserted exactly while the receiver is busy/releasing
//   3. Data stability: while ack is high the captured data equals the
//      sender's held data (sender must not start a new transfer before
//      the handshake fully returns to zero).
// ============================================================================
module async_handshake (
    input  logic clk,
    input  logic rst,
    input  logic       start,
    input  logic [7:0] din,
    output logic       busy,
    output logic [7:0] dout
);
    // Sender FSM
    localparam logic [1:0] S_IDLE = 2'd0, S_REQ = 2'd1, S_WAIT = 2'd2;
    logic [1:0] sstate = S_IDLE;
    logic       req    = 1'b0;
    logic [7:0] data_r = 8'd0;

    // Receiver FSM (R_REL models slow ack release)
    localparam logic [1:0] R_IDLE = 2'd0, R_ACK = 2'd1, R_REL = 2'd2;
    logic [1:0] rstate  = R_IDLE;
    logic       ack     = 1'b0;
    logic [7:0] cap     = 8'd0;
    logic [1:0] rel_cnt = 2'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            sstate <= S_IDLE;
            req    <= 1'b0;
            data_r <= 8'd0;
        end else begin
            case (sstate)
                S_IDLE: if (start) begin
                    data_r <= din;
                    req    <= 1'b1;
                    sstate <= S_REQ;
                end
                S_REQ: if (ack) begin
                    req    <= 1'b0;
                    sstate <= S_WAIT;
                end
                // 4-phase: wait for ack to return low before accepting
                // a new transfer
                S_WAIT: if (!ack)
                    sstate <= S_IDLE;
                default: sstate <= S_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rstate  <= R_IDLE;
            ack     <= 1'b0;
            cap     <= 8'd0;
            rel_cnt <= 2'd0;
        end else begin
            case (rstate)
                R_IDLE: if (req) begin
                    cap    <= data_r;
                    ack    <= 1'b1;
                    rstate <= R_ACK;
                end
                R_ACK: if (!req) begin
                    rel_cnt <= 2'd0;
                    rstate  <= R_REL;
                end
                // Slow release: hold ack for 2 extra cycles
                R_REL: begin
                    if (rel_cnt == 2'd1) begin
                        ack    <= 1'b0;
                        rstate <= R_IDLE;
                    end else
                        rel_cnt <= rel_cnt + 2'd1;
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    assign busy = (sstate != S_IDLE);
    assign dout = cap;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Protocol phase invariants
        assert (req == (sstate == S_REQ));
        assert (ack == (rstate != R_IDLE));
        // Data stability across the handshake: while ack is high, the
        // sender's held data must equal the captured data
        if (ack)
            assert (cap == data_r);
    end
endmodule
