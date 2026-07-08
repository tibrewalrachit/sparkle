# Veil AXI — SMT-Checked AXI Protocol Models

A second, independent verification layer for the AMBA AXI protocol work
in this repository, built on [Veil](https://github.com/verse-lab/veil)
(verse-lab's foundational framework for automated verification of
transition systems, embedded in Lean 4).

## Why a second layer?

The main verification stack
(`Sparkle/Verification/AXIProps.lean` → `AXIRefinement.lean` →
`Examples/AXI/LiteSubordinate.lean`) proves the AXI rules of
**ARM IHI 0022 Issue L** interactively, down to the synthesizable Signal
DSL implementation. This sub-project re-expresses the protocol state
machines as Veil transition systems and re-establishes the key
invariants **automatically via SMT** (z3/cvc5), giving:

- **Methodological diversity**: the same §A2.3.2.1/§A2.3.2.2 invariants
  hold under an independent semantics (event-interleaved transition
  system vs. synchronous FSM) checked by an independent engine
  (SMT solvers vs. Lean tactics/kernel-only `decide`).
- **Counterexample-driven exploration**: Veil's `#check_invariants`
  produces counterexamples-to-induction for any future protocol
  extension (bursts, multiple outstanding transactions, IDs), making it
  the right playground for extending the verified subset.
- **Bounded model checking**: `sat`/`unsat trace` commands validate
  non-vacuity (transactions actually complete) and cross-check safety
  over bounded event schedules.

## Model correspondence

| Veil (this project) | Sparkle spec model | IHI 0022L |
|---------------------|--------------------|-----------|
| `AXIWriteChannel` individuals `awDone/wDone/bValid` | `AXIProps.WrState` | §A2.3.2.1 |
| `aw_handshake`/`w_handshake`/`assert_bvalid`/`b_handshake` events | one `wrStep` cycle composes ≤ 3 of these | §A2.3, §A2.6 |
| `safety [bvalid_only_after_aw_and_w]` | `bvalid_only_after_aw_and_w` (+ `WrInv`) | §A2.3.2.1 |
| `AXIReadChannel` individuals `arDone/rValid` | `AXIProps.RdState` | §A2.3.2.2 |
| `safety [rvalid_only_after_ar]` | `rvalid_only_after_ar` (+ `RdInv`) | §A2.3.2.2 |
| `sat trace [write_transaction_completes]` | `write_completes_in_two_cycles` | liveness |

The event-level model is the standard protocol abstraction: each
VALID∧READY handshake is one atomic event. A synchronous clock cycle
(`wrStep`) is a composition of these events, so invariants preserved by
every event are preserved by every cycle.

## Building

This is a standalone Lake project because Veil pins its own Lean
toolchain (`v4.24.0`) and dependencies (lean-auto, lean-smt) and
downloads SMT solvers (z3, cvc5) at build time.

```bash
cd verification/veil-axi
lake update   # fetches veil + lean-auto + lean-smt, downloads z3/cvc5
lake build    # runs #check_invariants + BMC traces; failures fail the build
```

Requires network access to GitHub (for dependencies and solver
binaries). CI runs this as the `veil-axi` job in
`.github/workflows/build.yml`.
