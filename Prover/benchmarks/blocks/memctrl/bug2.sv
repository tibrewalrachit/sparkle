// BUG (seeded): the read port spuriously forwards a same-cycle write
// (write-first), violating the documented read-first semantics.
// ============================================================================
// memctrl — small memory controller with 16-entry RAM (array reasoning)
//
// Synchronous-read, read-first RAM behind a simple request interface, plus a
// formal scoreboard: an arbitrary "watch" address is latched on the first
// cycle, writes to it are mirrored into a shadow register, and every read
// from it must return the shadow value (read-after-write consistency).
// ============================================================================
module memctrl (
    input  logic clk,
    input  logic rst,
    input  logic       wr_en,
    input  logic [3:0] wr_addr,
    input  logic [7:0] wr_data,
    input  logic       rd_en,
    input  logic [3:0] rd_addr,
    output logic       rd_valid,
    output logic [7:0] rd_data,
    // Formal: free input latched once, selects the audited address
    input  logic [3:0] watch_addr
);
    logic [7:0] mem [0:15];

    // --------------------------------------------------------------------
    // Scoreboard (reference model for one arbitrary address)
    // --------------------------------------------------------------------
    logic       watch_set    = 1'b0;
    logic [3:0] watch_q      = 4'd0;
    logic       shadow_valid = 1'b0;
    logic [7:0] shadow_data  = 8'd0;

    always_ff @(posedge clk) begin
        if (rst) begin
            watch_set    <= 1'b0;
            shadow_valid <= 1'b0;
        end else begin
            if (!watch_set) begin
                watch_q   <= watch_addr;
                watch_set <= 1'b1;
            end
            if (wr_en && watch_set && (wr_addr == watch_q)) begin
                shadow_data  <= wr_data;
                shadow_valid <= 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------
    // RAM: synchronous read, read-first (write visible next cycle)
    // --------------------------------------------------------------------
    logic       rd_valid_q = 1'b0;
    logic [7:0] rd_data_q  = 8'd0;
    logic       check_q    = 1'b0;
    logic [7:0] expected_q = 8'd0;

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        rd_data_q  <= (wr_en && (wr_addr == rd_addr)) ? wr_data : mem[rd_addr];
        rd_valid_q <= rd_en && !rst;
        // A read of the watched address must return the shadow value.
        // Read-first semantics: sample the shadow at read-issue time so a
        // simultaneous write to the same address is excluded consistently.
        check_q    <= rd_en && !rst && watch_set && shadow_valid &&
                      (rd_addr == watch_q);
        expected_q <= shadow_data;
    end

    assign rd_valid = rd_valid_q;
    assign rd_data  = rd_data_q;

    // ------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        // Read-after-write consistency on the watched address
        if (check_q)
            assert (rd_data_q == expected_q);
    end
endmodule
