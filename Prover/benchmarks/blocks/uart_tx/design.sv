// ============================================================================
// uart_tx — UART transmitter FSM (8N1) with baud-rate divider
//
// One-hot FSM: IDLE -> START -> DATA(x8) -> STOP -> IDLE, one baud tick
// every DIV+1 clock cycles. Properties:
//   1. FSM state register is always one-hot and a legal state
//   2. Baud counter stays within its bound
//   3. Line level: tx is high in IDLE, low in START, high in STOP
//      (start/stop-bit guarantee)
// ============================================================================
module uart_tx (
    input  logic clk,
    input  logic rst,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx,
    output logic       busy
);
    // One-hot state encoding
    localparam logic [3:0] ST_IDLE  = 4'b0001;
    localparam logic [3:0] ST_START = 4'b0010;
    localparam logic [3:0] ST_DATA  = 4'b0100;
    localparam logic [3:0] ST_STOP  = 4'b1000;

    localparam logic [2:0] DIV = 3'd3;   // baud tick every 4 cycles

    logic [3:0] state  = ST_IDLE;
    logic [2:0] baud   = 3'd0;
    logic [2:0] bitidx = 3'd0;
    logic [7:0] sh     = 8'd0;

    wire tick = (baud == DIV);

    always_ff @(posedge clk) begin
        if (rst) begin
            state  <= ST_IDLE;
            baud   <= 3'd0;
            bitidx <= 3'd0;
            sh     <= 8'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    baud   <= 3'd0;
                    bitidx <= 3'd0;
                    if (tx_start) begin
                        sh    <= tx_data;
                        state <= ST_START;
                    end
                end
                ST_START: begin
                    if (tick) begin
                        baud   <= 3'd0;
                        bitidx <= 3'd0;
                        state  <= ST_DATA;
                    end else
                        baud <= baud + 3'd1;
                end
                ST_DATA: begin
                    if (tick) begin
                        baud <= 3'd0;
                        sh   <= {1'b0, sh[7:1]};
                        if (bitidx == 3'd7)
                            state <= ST_STOP;
                        else
                            bitidx <= bitidx + 3'd1;
                    end else
                        baud <= baud + 3'd1;
                end
                ST_STOP: begin
                    if (tick) begin
                        baud  <= 3'd0;
                        state <= ST_IDLE;
                    end else
                        baud <= baud + 3'd1;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    assign tx = (state == ST_START) ? 1'b0 :
                (state == ST_DATA)  ? sh[0] :
                                      1'b1;   // IDLE and STOP drive high
    assign busy = (state != ST_IDLE);

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // FSM one-hot / legal-state invariant
        assert (state == ST_IDLE || state == ST_START ||
                state == ST_DATA || state == ST_STOP);
        // Baud divider bound
        assert (baud <= DIV);
        // Idle line is high
        if (state == ST_IDLE) begin
            assert (tx == 1'b1);
            assert (baud == 3'd0);
        end
        // Start bit drives the line low
        if (state == ST_START)
            assert (tx == 1'b0);
        // Stop-bit guarantee: the line is high for the whole stop period
        if (state == ST_STOP)
            assert (tx == 1'b1);
    end
endmodule
