# AMBA AXI Formal Verification — Specification Extraction Map

**Source document**: *AMBA AXI Protocol Specification*, Arm Ltd.
Document number **ARM IHI 0022**, version **Issue L**, released 27 Aug 2025, non-confidential.
(`IHI0022L_amba_axi_protocol_spec.pdf`)

This document records the normative rules extracted from the official
specification and maps each rule to the machine-checked theorem that verifies
it in [`Sparkle/Verification/AXIProps.lean`](../Sparkle/Verification/AXIProps.lean).

The verified model targets the **AXI5-Lite** interface class (§B2.1.5): all
transactions have burst length 1, no exclusive accesses — the subset used by
register-based components such as Sparkle peripherals.

---

## 1. Rule extraction

### §A2.1.2 Reset (page 27)

> "Signals that are required to be deasserted during reset must remain
> deasserted at least until the rising ACLK edge after ARESETn is HIGH."

### §A2.3 Valid-Ready transport (pages 29–30)

| # | Rule (verbatim from spec) |
|---|---------------------------|
| R1 | "Transfer occurs only when both the VALID and READY signals are HIGH." |
| R2 | "VALID signals must be LOW during reset." |
| R3 | "The transmitter must keep its information stable until the transfer occurs." |
| R4 | "A transmitter is not permitted to wait until READY is asserted before asserting VALID." |
| R5 | "When VALID is asserted, it must remain asserted until the handshake occurs, at a rising clock edge when VALID and READY are both asserted." |
| R6 | "A receiver is permitted to wait for VALID to be asserted before asserting the corresponding READY." *(permission — not a proof obligation)* |
| R7 | "If READY is asserted, it is permitted to deassert READY before VALID is asserted." *(permission — not a proof obligation)* |
| R8 | "The default state of READY signals can be either HIGH or LOW. For request channels, it is recommended to use HIGH as the default state to minimize latency." |

### §A2.3.2.1 Write transaction dependencies (page 31)

| # | Rule |
|---|------|
| W1 | "The Subordinate must wait for AWVALID, AWREADY, WVALID, and WREADY to be asserted before asserting BVALID." |
| W2 | "The Subordinate must wait for the last write data transfer before asserting BVALID." |
| W3 | "The Subordinate must not wait for the Manager to assert BREADY before asserting BVALID." |
| W4 | "The Subordinate can assert AWREADY before AWVALID or WVALID, or both, are asserted." *(permission, exercised by the model)* |

### §A2.3.2.2 Read transaction dependencies (page 32)

| # | Rule |
|---|------|
| Rd1 | "The Subordinate must wait for both ARVALID and ARREADY to be asserted before it asserts RVALID to indicate that valid data is available." |
| Rd2 | "The Subordinate must not wait for the Manager to assert RREADY before asserting RVALID." |

### §A2.6 AXI transactions and transfers (page 41)

| # | Rule |
|---|------|
| T1 | "A write response must always follow the last write transfer in a write transaction." |
| T2 | "Read data and responses must always follow the read request." |

### §A3.1 Transaction request (page 43)

| # | Rule |
|---|------|
| Q1 | "A transaction must not cross a 4KB address boundary." |

### §A3.3.1 Write response, Table A3.28 BRESP encodings (pages 61–62)

3-bit encodings: `0b000` OKAY, `0b001` EXOKAY, `0b010` SLVERR, `0b011` DECERR,
`0b100` DEFER, `0b101` TRANSFAULT, `0b110` RESERVED, `0b111` UNSUPPORTED.

> OKAY: "The transaction was successful. If the transaction includes write
> data, the updated value is observable."

### §A3.3.2 Read response, Table A3.31 RRESP encodings (pages 62–63)

3-bit encodings: `0b000` OKAY, `0b001` EXOKAY, `0b010` SLVERR, `0b011` DECERR,
`0b100` PREFETCHED, `0b101` TRANSFAULT, `0b110` OKAYDIRTY, `0b111` RESERVED.

> EXOKAY: "Exclusive read succeeded. This response is only permitted for an
> exclusive read."

### §B2.1.5 AXI5-Lite (page 288)

> "AXI5-Lite is a subset of AXI5 where all transactions have one data transfer."
> Key functionality: "All transactions have burst length 1. …
> Exclusive accesses are not supported."

---

## 2. Rule → theorem map

All theorems live in `Sparkle/Verification/AXIProps.lean` and compile with
zero `sorry`s.

| Spec rule | Theorem | Proof pattern |
|-----------|---------|---------------|
| §A2.3 R2 (+ §A2.1.2) | `valid_low_during_reset` | definitional |
| §A2.3 R5 | `valid_stable_until_handshake` | case + simp |
| §A2.3 R3 | `payload_stable_until_handshake` | case + simp |
| §A2.3 R4 | `no_wait_for_ready` | READY-independence |
| §A2.3 R1 | `handshake_transfers`, `no_transfer_without_valid` | definitional |
| §A2.3 R8 | `subordinate_accepts_from_reset` (write), `arready_high_after_reset` (read) | definitional |
| §A2.3.2.1 W1+W2 | `bvalid_only_after_aw_and_w` (inductive invariant) | invariant |
| §A2.3.2.1 W3 | `bvalid_no_bready_wait` | READY-independence |
| §A2.3 R5 (B channel) | `bvalid_stable_until_bready` | case + simp |
| §A2.6 T1 | `no_spurious_write_response` (trace-level: #B ≤ #AW along every input trace) | trace induction |
| §A2.6 T1 | `write_response_after_data` (trace-level: #B ≤ #W along every input trace) | trace induction |
| §A2.3.2.2 Rd1 | `rvalid_only_after_ar` (inductive invariant) | invariant |
| §A2.3.2.2 Rd2 | `rvalid_no_rready_wait` | READY-independence |
| §A2.3 R5 (R channel) | `rvalid_stable_until_rready` | case + simp |
| §A2.6 T2 | `no_spurious_read_data` (trace-level: #R ≤ #AR along every input trace) | trace induction |
| Table A3.28 | `BResp.decode_encode`, `BResp.encode_decode`, `bresp_okay_is_zero` | round-trip |
| Table A3.31 | `RResp.decode_encode`, `RResp.encode_decode`, `rresp_okay_is_zero` | round-trip |
| §B2.1.5 no exclusives | `lite_write_never_exokay`, `lite_read_never_exokay` | enumeration |
| Table A3.28 OKAY semantics | `write_commit_observable`, `write_commit_other_addrs_unchanged` | refinement |
| Table A3.31 OKAY semantics | `read_data_matches_memory` (invariant) | invariant |
| §A3.1 Q1 | `aligned_access_no_4KB_crossing` (general), `lite32_no_4KB_crossing` | arithmetic |
| liveness (framework §2) | `write_completes_in_two_cycles`, `read_completes_in_two_cycles` | bounded latency |
| efficiency (framework §3) | `subordinate_accepts_from_reset` | work-conserving |

## 3. Spec → RTL → Signal DSL convergence

Beyond the spec-model theorems, the implementation is *proven* to refine
the spec — every link in the chain below is machine-checked:

```
AXIProps spec FSMs  (WrState / RdState — spec-cited theorems)
   ▲  decodeWr / decodeRd  (injective abstraction — bisimulation)
   │  wrStepRTL_refines, rdStepRTL_refines            [AXIRefinement]
RTL FSMs on BitVec state  (4 reachable write states, 2 read states)
   │  wrStepGates_eq_RTL, rdStepGates_eq_RTL          [AXIRefinement]
sum-of-products gate equations
   │  writeFsmBody_succ, readFsmBody_succ — proven by `rfl`
   │  (definitional equality, no gap)                 [LiteSubordinate]
Signal DSL loop bodies (register + mux + beq combinators)
   │  writeFsm_refines_spec, readFsm_refines_spec:
   │  any fixpoint of the body (Signal.loop's contract) equals the
   │  spec trace at every cycle                       [LiteSubordinate]
#synthesizeVerilog  →  SystemVerilog
```

Key theorems in `Sparkle/Verification/AXIRefinement.lean`:

| Theorem | Statement |
|---------|-----------|
| `wrStepRTL_refines` / `rdStepRTL_refines` | Bisimulation squares: one RTL step through `decode` = one spec step |
| `decodeWr_injective` / `decodeRd_injective` | The abstraction is a bisimulation, not a lossy simulation |
| `decodeWr_inv` / `decodeRd_inv` | Every RTL state satisfies the §A2.3.2.x invariants |
| `wrOutputs_refine` / `rdOutputs_refine` | AWREADY/WREADY/BVALID/ARREADY/RVALID match spec outputs |
| `wr_trace_refines` / `rd_trace_refines` | Cycle-accurate: for every input stream and cycle, RTL state = spec state |
| `mealy_fixpoint_unique` | The register-feedback fixpoint is unique (the `Signal.loop` contract) |
| `rtl_bvalid_only_after_aw_and_w`, `rtl_rvalid_only_after_ar` | §A2.3.2.1/§A2.3.2.2 transferred to the RTL FSM |

Key theorems in `Examples/AXI/LiteSubordinate.lean`:

| Theorem | Statement |
|---------|-----------|
| `writeFsmBody_zero/succ`, `readFsmBody_zero/succ` | The Signal loop body is **definitionally** (`rfl`) the proven gate function, per cycle |
| `writeFsm_refines_spec` / `readFsm_refines_spec` | Any body fixpoint abstracts to the spec FSM trace at every cycle |
| `writeFsm_bvalid_refines` | The implementation's BVALID equals the spec's BVALID at every cycle |
| `latchBody_zero/succ` | Payload latches implement `AXIProps.liteStep`'s capture rule (`rfl`) |

The one remaining trust assumption is `Signal.loop` itself (an `opaque`
compiler primitive): its documented contract is to return a fixpoint of
the body, and `mealy_fixpoint_unique` proves any such fixpoint has the
verified behavior. Synthesis (`#synthesizeVerilog`) emits three modules:
`writeFsmSignal`, `readFsmSignal`, and the full `axi5LiteSubordinate`
(AXI ⇄ register-file bridge, §B2.1.5 use case).

## 4. Cross-verification layer: Veil (SMT)

`verification/veil-axi/` re-expresses the two protocol FSMs as
[Veil](https://github.com/verse-lab/veil) transition systems and
re-establishes the §A2.3.2.1/§A2.3.2.2 invariants **automatically via
SMT** (z3/cvc5), plus bounded-model-checking traces for non-vacuity
(transactions complete) — an independent engine and an independent
(event-interleaved) semantics confirming the interactive proofs:

| Veil artifact | Mirrors | Checked by |
|---------------|---------|------------|
| `AXIWriteChannel.safety [bvalid_only_after_aw_and_w]` | `AXIProps.bvalid_only_after_aw_and_w` | `#check_invariants` (SMT induction) |
| `AXIReadChannel.safety [rvalid_only_after_ar]` | `AXIProps.rvalid_only_after_ar` | `#check_invariants` (SMT induction) |
| `sat trace [write_transaction_completes]` | `write_completes_in_two_cycles` | BMC |
| `unsat trace [no_bvalid_violation]` (any 6 events) | trace-level safety §A2.6 | BMC |

Each handshake is one atomic event in the Veil model; a synchronous
`wrStep` cycle composes up to three events, so event-level invariance
covers every cycle-level schedule. See `verification/veil-axi/README.md`
for the full correspondence table and build instructions (standalone
Lake project — Veil pins Lean v4.24.0 and fetches SMT solvers at build
time; runs as the `veil-axi` CI job).

## 5. Model notes

- The subordinate model implements the *permissions* the spec grants
  (AWREADY/WREADY/ARREADY defaulting HIGH per §A2.3 R8, W4) and is proven to
  satisfy every *requirement* (the "must" rules above).
- Trace-level theorems quantify over **all** input traces (any sequence of
  `xVALID`/`xREADY` values a Manager may drive), so they hold for arbitrary,
  even non-compliant, managers — the subordinate never emits a spurious
  response.
- The `TxState` transmitter model is channel-generic: it verifies the manager
  side of AW/W/AR and the subordinate side of B/R, since §A2.3 rules apply
  uniformly to every channel transmitter.
- Permissions R6/R7 constrain nothing and therefore generate no proof
  obligations; they are noted for completeness.
