// ============================================================================
// axi_lite_slave — AXI4-Lite write channel skeleton
//
// Accepts an address (AW) and data (W) beat in either order, then issues a
// single write response (B). Properties (slave-side handshake rules):
//   1. No response without a complete request: BVALID implies both the AW
//      and W beats have been captured
//   2. VALID-stable rule: once BVALID is asserted it stays asserted until
//      BREADY is seen (checked with a 1-cycle history register)
//   3. No new AW/W beats are accepted while a response is pending
// ============================================================================
module axi_lite_slave (
    input  logic clk,
    input  logic rst,
    // Write address channel
    input  logic        awvalid,
    output logic        awready,
    input  logic [3:0]  awaddr,
    // Write data channel
    input  logic        wvalid,
    output logic        wready,
    input  logic [31:0] wdata,
    // Write response channel
    output logic        bvalid,
    input  logic        bready
);
    logic [31:0] regs [0:15];

    logic        aw_done  = 1'b0;
    logic        w_done   = 1'b0;
    logic [3:0]  awaddr_q = 4'd0;
    logic [31:0] wdata_q  = 32'd0;
    logic        bvalid_q = 1'b0;

    assign awready = !aw_done && !bvalid_q;
    assign wready  = !w_done  && !bvalid_q;
    assign bvalid  = bvalid_q;

    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid  && wready;
    wire both_done = (aw_done || aw_fire) && (w_done || w_fire);

    always_ff @(posedge clk) begin
        if (rst) begin
            aw_done  <= 1'b0;
            w_done   <= 1'b0;
            bvalid_q <= 1'b0;
        end else begin
            if (aw_fire) begin
                awaddr_q <= awaddr;
                aw_done  <= 1'b1;
            end
            if (w_fire) begin
                wdata_q <= wdata;
                w_done  <= 1'b1;
            end
            if (!bvalid_q && both_done) begin
                // Commit the write and raise the response
                regs[aw_fire ? awaddr : awaddr_q] <= w_fire ? wdata : wdata_q;
                bvalid_q <= 1'b1;
            end else if (bvalid_q && bready) begin
                bvalid_q <= 1'b0;
                aw_done  <= 1'b0;
                w_done   <= 1'b0;
            end
        end
    end

    // 1-cycle history for the VALID-stable rule
    logic bvalid_p = 1'b0;
    logic bready_p = 1'b0;
    logic prev_ok  = 1'b0;
    always_ff @(posedge clk) begin
        if (rst)
            prev_ok <= 1'b0;
        else
            prev_ok <= 1'b1;
        bvalid_p <= bvalid;
        bready_p <= bready;
    end

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // No response without a complete request
        if (bvalid)
            assert (aw_done && w_done);
        // BVALID must remain asserted until BREADY (VALID-stable rule)
        if (prev_ok && !rst && bvalid_p && !bready_p)
            assert (bvalid);
        // No new beats accepted while a response is pending
        assert (!(bvalid && (awready || wready)));
    end
endmodule
