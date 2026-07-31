# Formal Verification of the AMBA AXI Protocol in Sparkle HDL
## Technical Report

| | |
|---|---|
| **Subject** | Machine-checked verification of the AMBA AXI protocol (AXI5-Lite class), from official specification text to synthesizable SystemVerilog |
| **Source specification** | *AMBA AXI Protocol Specification*, ARM IHI 0022, **Issue L**, 27 Aug 2025 (non-confidential, 320 pp.) |
| **Verification framework** | Lean 4 (Sparkle HDL) + Veil (SMT) |
| **Toolchains** | Lean `v4.28.0-rc1` (repo pin; developed against `v4.28.1`), Veil sub-project: Lean `v4.24.0`, z3 4.15.4 / cvc5 1.3.1 |
| **Pull request** | [tibrewalrachit/sparkle#2](https://github.com/tibrewalrachit/sparkle/pull/2) |
| **Status** | All 74 Lean theorems check with zero `sorry`s; both CI jobs green; SMT layer verified in CI |

---

## 1. Executive Summary

This work formally verifies the AMBA AXI on-chip bus protocol as implemented
by Sparkle HDL's new AXI5-Lite subordinate IP. Unlike typical "formal-friendly"
bus work — where a hand-written model is *asserted* to correspond to the
standard — every layer here is either machine-checked or traced verbatim to
the official ARM specification document:

1. **Extraction.** The normative rules ("must" clauses) governing the
   Valid-Ready transport, channel dependencies, transaction relationships,
   response encodings, and addressing were extracted from ARM IHI 0022
   Issue L with verbatim quotes and page numbers (`docs/AXI_Spec_Map.md`).

2. **Specification proofs.** A pure state-machine model of the protocol was
   built in Lean and **45 theorems** proven against it, each annotated with
   the spec clause it verifies — including *trace-level* guarantees that hold
   against arbitrary (even non-compliant) bus managers.

3. **Refinement.** A register-transfer-level encoding of the protocol FSMs
   was proven **bisimilar** to the spec model, with cycle-accurate trace
   correspondence for every input stream (**20 theorems**).

4. **Implementation.** A synthesizable Signal DSL subordinate was written
   whose next-state logic is proven **definitionally equal** (`rfl`) to the
   verified RTL equations — eliminating the traditional "the RTL mirrors the
   model" trust gap — and compiled to SystemVerilog (**9 theorems**,
   3 generated modules).

5. **Cross-verification.** The protocol FSMs were independently re-modeled
   as [Veil](https://github.com/verse-lab/veil) transition systems and the
   key invariants re-established **automatically by SMT solvers** (z3/cvc5),
   plus bounded model checking for non-vacuity. This layer runs green in CI.

The result is, to our knowledge, the first bus-protocol IP in this repository
— and one of few anywhere — with an unbroken, machine-checked chain from the
standard's text to synthesizable RTL, validated by two independent proof
engines.

---

## 2. Scope and Objective

**Target**: the **AXI5-Lite interface class** (IHI 0022L §B2.1.5): all
transactions have burst length 1; exclusive accesses are not supported. This
is the interface used for register-based components and simple memories —
the natural first bus IP for Sparkle's Verified Standard IP Library
(roadmap item 5).

**Properties in scope**: reset behavior, the VALID/READY handshake
discipline, write-channel (AW/W/B) and read-channel (AR/R) dependency rules,
transaction/transfer count relationships, response encodings at both the
default (2-bit) and extended (3-bit) widths, data observability semantics of
OKAY, the 4KB boundary rule, and bounded-latency liveness.

**Out of scope** (documented, not silently dropped): bursts (`AxLEN > 0`),
multiple outstanding transactions and ID-based ordering (§A5), exclusive
accesses (§A6), atomics, caches/QoS/user signals, byte-lane strobes
(`WSTRB` masking), and credited transport (§A2.4).

---

## 3. Specification Extraction Methodology

The official PDF (ARM IHI 0022 Issue L — identical to the document titled
`IHI0022L_amba_axi_protocol_spec.pdf`) was obtained from ARM's documentation
service and its text extracted per page. Normative rules were located by
section — §A2.1 (clock/reset), §A2.3 (Valid-Ready transport), §A2.3.2
(handshake dependencies), §A2.6 (transaction relationships), §A3.1 (requests),
§A3.3 (responses), §B2.1.5 (AXI5-Lite) — and recorded **verbatim** with page
numbers in `docs/AXI_Spec_Map.md`.

Two extraction principles were followed:

- **Requirements vs. permissions.** Spec clauses that *permit* behavior
  ("A receiver is permitted to wait…") generate no proof obligations; they are
  recorded and, where relevant, *exercised* by the model (e.g. READY-default-
  HIGH). Only "must" clauses become theorems.
- **One rule, one theorem.** Each theorem's docstring quotes the exact clause
  it discharges, and the spec-map document maintains the bidirectional index.

---

## 4. Verification Architecture

```
        ARM IHI 0022 Issue L (official specification text)
                       │  verbatim extraction, §/page-cited
                       ▼
  Layer 1  Spec FSMs + 45 theorems ............ Sparkle/Verification/AXIProps.lean
                       ▲
                       │  decodeWr / decodeRd (injective abstraction)
                       │  bisimulation squares, proven by `decide`
                       ▼
  Layer 2  RTL FSMs on BitVec states .......... Sparkle/Verification/AXIRefinement.lean
                       │  = gate-level form (by `decide`)
                       │  = Signal DSL loop bodies, per cycle (by `rfl`)
                       ▼
  Layer 3  Synthesizable implementation ....... Examples/AXI/LiteSubordinate.lean
                       │  #synthesizeVerilog
                       ▼
           SystemVerilog (3 modules)

  Layer 4  Veil transition systems (SMT) ...... verification/veil-axi/
           independent engine + semantics; cross-checks Layer 1 invariants
```

### 4.1 Layer 1 — Specification model (`AXIProps.lean`, 864 lines, 45 theorems)

Self-contained (zero imports), following the repository's verification
conventions. Four models:

- **`TxState`** — a generic channel transmitter. Because §A2.3 imposes the
  same handshake process on every channel, one model covers the manager side
  of AW/W/AR and the subordinate side of B/R. Theorems: VALID low during
  reset; VALID and payload held stable until the handshake; VALID assertion
  independent of READY ("must not wait"); transfer occurs iff VALID ∧ READY.

- **`WrState`/`wrStep`** — subordinate-side write-transaction FSM.
  The §A2.3.2.1 dependency rules are proven as an inductive invariant
  (`bvalid_only_after_aw_and_w`): in every reachable state, BVALID implies
  both the AW and last-W handshakes have occurred. BVALID assertion is
  READY-independent; the B channel obeys the §A2.3 hold rule.

- **`RdState`/`rdStep`** — read-transaction FSM, with `rvalid_only_after_ar`
  (§A2.3.2.2) and the analogous independence/stability theorems.

- **`LiteSubState`/`liteStep`** — the full subordinate with memory, latched
  addresses/data, and commit/capture semantics; proves the *meaning* of OKAY
  (Table A3.28: "the updated value is observable"; Table A3.31: "read data is
  valid").

**Trace-level safety (§A2.6).** The strongest results quantify over *every
input stream* — arbitrary AWVALID/WVALID/BREADY sequences, including
protocol-violating managers: the count of write responses never exceeds the
count of accepted write requests (`no_spurious_write_response`), nor the
count of accepted write data transfers (`write_response_after_data`); read
data never exceeds accepted read requests (`no_spurious_read_data`). Proofs
are by induction on the trace with per-step accounting lemmas discharged by
finite enumeration + `omega`.

**Response encodings.** Both response widths of Issue L are modeled:
the default **2-bit** field (`Resp2`, Tables A3.27/A3.30 — the classic
AXI4-Lite encoding) and the optional-feature **3-bit** tables
(`BResp`/`RResp`, Tables A3.28/A3.31). Lossless encode/decode round-trips are
proven at both widths, along with *width-consistency*: the 2-bit rows embed
into the 3-bit tables under zero-extension. The Lite response mapping targets
the default width and provably never emits EXOKAY (§B2.1.5).

**Arithmetic side conditions.** `aligned_access_no_4KB_crossing` proves the
§A3.1 4KB rule for size-aligned single transfers, for every transfer size
dividing 4096 (all `AxSIZE` values).

**Liveness.** `write_completes_in_two_cycles` / `read_completes_in_two_cycles`
give exact bounded latency with a cooperative manager — deadlock-freedom with
a hard bound, per the repository's efficiency-property framework.

### 4.2 Layer 2 — Spec ↔ RTL refinement (`AXIRefinement.lean`, 346 lines, 20 theorems)

The spec FSMs use record states with (potentially) unreachable combinations;
hardware wants dense encodings. Layer 2 defines RTL FSMs over exactly the
*reachable* states — write: 4 states in `BitVec 2` (IDLE/AW/W/RESP), read:
2 states in `BitVec 1` — with abstraction functions `decodeWr`/`decodeRd`
proven **injective**, making the correspondence a bisimulation rather than a
lossy simulation:

- **Bisimulation squares** (`wrStepRTL_refines`, `rdStepRTL_refines`): one
  RTL step tracked through `decode` equals one spec step. Proven by `decide`
  (kernel-checked finite enumeration; no tactics to trust).
- **Gate-form equivalence** (`wrStepGates_eq_RTL`): the if-chain (priority
  mux) form equals a sum-of-products form — the exact boolean structure the
  hardware computes.
- **Cycle-accurate trace refinement** (`wr_trace_refines`,
  `rd_trace_refines`): for every input stream and every cycle, the RTL state
  abstracts to exactly the spec state; corollaries transfer each output
  (AWREADY/WREADY/BVALID/ARREADY/RVALID) and the §A2.3.2.x invariants to the
  RTL FSM.
- **Mealy fixpoint uniqueness** (`mealy_fixpoint_unique`): any stream
  satisfying the register-feedback equations equals the canonical recursion —
  the bridge to the implementation layer's loop combinator.

### 4.3 Layer 3 — Synthesizable implementation (`Examples/AXI/LiteSubordinate.lean`, 377 lines, 9 theorems, 3 SystemVerilog modules)

The Signal DSL implementation improves on the repository's prior best
practice (the round-robin arbiter, where the DSL "mirrors" the spec and
agreement is checked by simulation): here the correspondence is *proven*.

Sparkle's `Signal` is a shallow embedding (`Nat → α`) with transparent
`register`/`mux`/`beq`/applicative combinators; only the feedback fixpoint
`Signal.loop` is opaque. Exploiting this:

- **`writeFsmBody_succ` / `readFsmBody_succ`**: the loop body's output at
  cycle `t+1` equals the Layer-2 gate function applied to the state and
  inputs at cycle `t` — proven **by `rfl`** (definitional equality). There is
  no informal transliteration step left: if a single gate in the DSL body is
  altered, the proof fails with "not a definitional equality" (verified by
  mutation testing, §6).
- **`writeFsm_refines_spec` / `readFsm_refines_spec`**: any fixpoint of the
  loop body — which is what `Signal.loop` returns, per its contract, and
  which `mealy_fixpoint_unique` proves unique — abstracts at every cycle to
  the spec FSM trace. Consequently every Layer-1 safety theorem holds of
  this hardware.
- **Payload latches** (`latchBody_zero/succ`, by `rfl`) implement the
  `liteStep` capture rule for AW/W/AR payloads.
- **`axi5LiteSubordinate`** composes the FSMs, latches, and commit pulse into
  an AXI ⇄ register-file bridge (the §B2.1.5 use case). `#synthesizeVerilog`
  emits `writeFsmSignal`, `readFsmSignal`, and `axi5LiteSubordinate`.
- A **simulation cross-check** drives the (proven-equal) RTL recursion
  against the spec trace over a manager scenario exercising RESP-hold under
  deasserted READY, same-cycle AW+W, and §A2.6 data-before-request ordering.
  It passes at every cycle.

### 4.4 Layer 4 — Veil/SMT cross-verification (`verification/veil-axi/`)

The write/read FSMs are independently re-expressed as **Veil** transition
systems (event-level semantics: each VALID∧READY handshake is one atomic
action, guarded exactly by the spec clause it models). Veil compiles these to
two-state transition relations and discharges verification conditions via
SMT:

- `safety [bvalid_only_after_aw_and_w]` and `safety [rvalid_only_after_ar]`
  are proven **inductive by SMT** (`#check_invariants`, z3/cvc5) — the same
  invariants as Layer 1, under an independent semantics, by an independent
  engine.
- **Bounded model checking**: `sat` traces establish non-vacuity (complete
  write/read transactions are executable; §A2.6 data-before-request ordering
  is admitted); `unsat` traces confirm no safety violation is reachable
  within any 6-event schedule.

Soundness of the two-semantics comparison: a synchronous `wrStep` cycle
composes at most three atomic events, so any property preserved by every
event is preserved by every cycle-level schedule.

This sub-project pins its own toolchain (Veil requires Lean v4.24.0 and
fetches lean-auto/lean-smt plus solver binaries at build time) and runs as a
dedicated, **gating** CI job — green on first run (≈7 min).

---

## 5. Trusted Computing Base

What must be trusted for each layer's guarantee:

| Layer | Trusted |
|---|---|
| 1–3 (theorems) | The Lean 4 kernel only. Proofs use `decide` (kernel-evaluated), `rfl` (definitional), `simp`/`omega` (certificate-checked by the kernel). No axioms beyond Lean's standard foundations; zero `sorry`s. |
| 3 (loop) | `Signal.loop` is an `opaque` compiler primitive; its documented contract — returning a fixpoint of the body — is assumed. `mealy_fixpoint_unique` proves any such fixpoint has the verified behavior, so this is the *only* assumption. |
| 3 (synthesis) | The `#synthesizeVerilog` compiler (Lean → SystemVerilog) is trusted, as for all Sparkle IP. The `rfl` theorems pin the *input* to synthesis to the verified equations. |
| 4 (Veil) | z3/cvc5 results, Veil's VC generation, lean-smt/lean-auto. Independent of Layers 1–3's trust base — which is precisely its value as cross-verification. |
| 0 (extraction) | Human fidelity of rule extraction from the PDF — mitigated by verbatim quotes with page numbers in the spec map, enabling line-by-line audit. |

---

## 6. Validation of the Verification (negative testing)

Proofs that cannot fail are worthless; each layer was mutation-tested:

| Mutation | Expected failure | Observed |
|---|---|---|
| Subordinate asserts BVALID after AW alone (ignores write data) — violates §A2.3.2.1 | `bvalid_only_after_aw_and_w` | ✅ fails with unsolved `False` goals at exactly that theorem |
| One gate rewired in the Signal DSL body (`isW &&& awValid` → `isW &&& wValid`) | `writeFsmBody_succ` | ✅ fails with "Not a definitional equality" |

Additionally, the simulation cross-check executes the proven-equal RTL
recursion against the spec model cycle-by-cycle (PASS), and the Veil layer
reproves the Layer-1 invariants under a different semantics with a different
engine.

---

## 7. Results and Metrics

| Artifact | Lines | Theorems / checks | Verification |
|---|---:|---:|---|
| `Sparkle/Verification/AXIProps.lean` | 864 | 45 theorems (42 public + 3 step lemmas) | Lean kernel, ≈2 s |
| `Sparkle/Verification/AXIRefinement.lean` | 346 | 20 theorems | Lean kernel |
| `Examples/AXI/LiteSubordinate.lean` | 377 | 9 theorems + 3 SV modules + sim PASS | Lean kernel + synthesis |
| `verification/veil-axi/` (2 modules) | 204 | 2 SMT-inductive safety properties, 7 BMC traces | z3/cvc5 via Veil, CI ≈7 min |
| `docs/AXI_Spec_Map.md` | — | rule ↔ theorem index | human-auditable |
| **Total** | **~1,800** | **74 Lean theorems + 9 SMT/BMC checks** | |

**CI**: main `build` job (spec + refinement + implementation + rest of repo)
and `veil-axi` job both **green** on PR #2. The veil-axi job is gating
(no `continue-on-error`).

**Spec coverage**: 20+ normative clauses from 8 sections of IHI 0022L are
discharged; the full bidirectional map is `docs/AXI_Spec_Map.md` §§1–2.

---

## 8. Limitations

1. **AXI5-Lite subset.** Bursts, ID-based ordering/interleaving, exclusive
   accesses, atomics, and cache/QoS attributes are unmodeled (§2). The
   trace-count framework and the Veil playground are designed to extend to
   these (Veil's counterexample-to-induction workflow is well suited to the
   ordering rules of §A5).
2. **`WSTRB` byte strobes** are not modeled; writes are whole-word
   (all-strobes-set), which matches the generated IP but not partial writes.
3. **Single outstanding transaction.** The subordinate serializes
   transactions (spec-permitted, §A2.6); throughput-oriented designs with
   outstanding-transaction queues would need the §A5 ordering model.
4. **Datapath trace-level refinement.** Memory commit/capture correctness is
   proven per-step (`write_commit_observable`, `read_data_matches_memory`);
   lifting these to whole-trace statements (as done for the control FSMs) is
   future work.
5. **`Signal.loop` opacity.** The fixpoint contract is assumed (uniqueness is
   proven). A transparent, fuel-based or well-founded `loop` in Sparkle core
   would eliminate this last assumption.
6. **Extraction fidelity** is human-checked, not machine-checked; the
   verbatim spec map is the audit trail.

---

## 9. Future Work

- **TileLink (TL-UL)** — the other half of roadmap item 5, using the same
  four-layer method.
- **§A5 ordering model** — IDs and multiple outstanding transactions, first
  in Veil (CTI-driven invariant discovery), then ported to Lean theorems.
- **WSTRB masking** with byte-granular observability theorems.
- **Verified AXI5-Lite manager** and a manager⇄subordinate composition
  theorem (end-to-end transaction correctness through both agents).
- **Datapath trace refinement** (item 4 above).
- **Yosys equivalence checking** of the emitted SystemVerilog against a
  golden netlist, closing the synthesis-trust gap experimentally.

---

## 10. Artifact Index

| Path | Role |
|---|---|
| `docs/AXI_Spec_Map.md` | Verbatim rule extraction (§/page), rule → theorem map, convergence chain, Veil correspondence |
| `Sparkle/Verification/AXIProps.lean` | Layer 1: spec model + 45 spec-cited theorems |
| `Sparkle/Verification/AXIRefinement.lean` | Layer 2: RTL encodings, bisimulation, trace refinement, fixpoint uniqueness |
| `Examples/AXI/LiteSubordinate.lean` | Layer 3: Signal DSL subordinate, `rfl` correspondence, synthesis, sim |
| `Examples/AXI.lean`, `lakefile.lean` (`Examples.AXI`) | Build integration |
| `verification/veil-axi/` | Layer 4: Veil transition systems, SMT invariants, BMC traces |
| `.github/workflows/build.yml` | CI: proof + synthesis steps, gating `veil-axi` job |
| `docs/Verification_Framework.md` | Updated with the proven-refinement pattern |
| PR [#2](https://github.com/tibrewalrachit/sparkle/pull/2) | Review record, CI runs |
