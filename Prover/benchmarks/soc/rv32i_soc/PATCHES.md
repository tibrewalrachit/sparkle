# rv32i_soc — patches relative to `verilator/rv32i_soc.sv`

`design.sv` is a copy of `/home/user/sparkle/verilator/rv32i_soc.sv` with the
minimal set of changes needed for the yosys 0.33 formal flow
(`read_verilog -sv; prep -top rv32i_soc; flatten; write_btor/write_smt2`).
Every change is listed here.

## PATCH 1 — desugar `automatic` block-local declarations (semantics-preserving)

yosys 0.33 rejects `automatic logic x = expr;` declarations local to an
unnamed `begin/end` block. The four UART write-logic temporaries in the big
`always_comb` block (original lines 1055–1058):

```systemverilog
begin
    automatic logic uartWE = idex_memWrite & isUART_ex;
    automatic logic [2:0] uartOff = alu_result_approx[2:0];
    automatic logic uartDLAB = uartLCR[7];
    automatic logic [7:0] uartWdata8 = ex_rs2_approx[7:0];
    ...
```

were desugared by hoisting the declarations to module scope (search for
`[SPARKLE-FV PATCH 1]`) and keeping the initializations in place as plain
blocking assignments:

```systemverilog
begin
    uartWE = idex_memWrite & isUART_ex;
    uartOff = alu_result_approx[2:0];
    uartDLAB = uartLCR[7];
    uartWdata8 = ex_rs2_approx[7:0];
    ...
```

The values are assigned before every use inside the same `always_comb`
process, so simulation and synthesis semantics are identical.

Note: the `function automatic [31:0] mkCsrNewVal(...)` declaration is
*function-level* `automatic` and is accepted by yosys 0.33 unchanged.

## PATCH 2 — embedded formal assertions (additive only)

Eight SoC-level safety invariants (FV1–FV8) plus a reset-tracking helper
register `fv_rst_seen` were added at the end of the module between the
markers:

```
// SPARKLE-FV ASSERTIONS BEGIN
...
// SPARKLE-FV ASSERTIONS END
```

The helper arms the assertions only after `rst` has been observed high, so
BMC (which otherwise starts from a fully unconstrained register state — the
SoC uses a synchronous reset, not initial values) only examines states
reachable from the architectural reset state. No functional logic was
modified; the block is purely additive.

Invariants (all verified by BMC on the safe design, see validate.sh):

* **FV1** MMU FSM uses only states {IDLE=0, PTW_WALK=2, DONE=3, FAULT=4};
  the declared TLB_LOOKUP state (1) is skipped by design and 5–7 are illegal.
* **FV2** PTW FSM never enters the undefined state 7.
* **FV3** A D-side page-table walk (`mmuState == PTW_WALK`) is never tagged
  as an instruction-fetch walk (`ptwIsIfetch`).
* **FV4** The cycle after any flush (`flushDelay`), the IF/ID instruction
  has been squashed to `NOP_INST`.
* **FV5** A memory-to-register instruction in EX always has writeback
  enabled (`idex_memToReg -> idex_regWrite`).
* **FV6** `idex_memToReg == idex_memRead` (decoded from identical
  instruction classes, preserved through squash/hold).
* **FV7** SC.W (`amoOp == 5'b00011`) is never routed through the
  memory-to-register load path.
* **FV8** While an AMO read-modify-write writeback is pending
  (`pendingWriteEn`, DMEM port hijacked), no read-modify-write AMO occupies
  the WB stage.

## Memory initialization / firmware

The original design loads firmware through the `imem_wr_en` /
`dmem_wr_en` testbench write ports; there is **no `$readmemh`** in the
source, so nothing had to be neutralized for formal. In the formal flow
`imem`, the four `dmem_b*` byte memories, and `regfile` start fully
unconstrained, i.e. the invariants are checked for **every possible
program and memory image**. This is intentional.

## REAL BUGS FOUND in the original SoC (not fixed here — documented)

While selecting invariants, two candidate assertions turned out to be
*falsifiable in the original design*. They were confirmed with BMC
counterexamples and are **deliberately not included** in the safe
assertion set; they point at real spec-compliance gaps in the RTL:

1. **`mstatus.MPP` is not legalized (WARL violation) → reserved privilege
   mode 2 is reachable.** `mkCsrNewVal` writes the CSR value back without
   masking, so `csrrw mstatus` can set MPP = 2'b10 (reserved). A subsequent
   `mret` executes `privMode_next = mpp`, putting the core into privilege
   mode 2, which decodes as neither M, S, nor U in `ecallCause` /
   `bypassMMU` / `privLeS`. The RISC-V privileged spec requires MPP to hold
   only legal modes (M/S/U). Assertion `privMode != 2'd2` fails in BMC.

2. **No instruction-address-misaligned check / no `mepc[1:0]` masking →
   misaligned PC is reachable.** JALR masks only bit 0 of the target
   (per spec) but the core neither raises a misaligned-fetch exception for
   `target[1] != 0` (required for IALIGN=32, no C extension — `misa`
   advertises RV32IMASU without C) nor forces `mepc[1:0]` to zero on CSR
   writes, so `mret`/`jalr` can set `pcReg` misaligned and the fetch path
   silently drops `fetchPC[1:0]` (`imem_addr = fetchPC[13:2]`). Assertion
   `pcReg[1:0] == 2'd0` fails in BMC.

Both are environment-independent (reachable from reset with an appropriate
instruction stream). Fixing them would change simulation semantics relative
to the Verilator reference model, so per the benchmark ground rules the RTL
was left untouched and the corresponding assertions were excluded from the
safe set.
