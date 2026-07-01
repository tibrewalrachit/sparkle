# sparkle-fv — Agentic Autoformalization & Formal Verification Harness

`sparkle-fv` autoformalizes SystemVerilog designs into **Sparkle HDL** (this
repository's Lean 4 embedded HDL) and performs block-level and SoC-level
formal verification with an AI-assisted prover portfolio. When a property
fails, the harness surfaces the bug as a concrete counterexample and
generates stimulus that is replayed through **Verilator** against the
original RTL — a bug report is only *confirmed* once simulation reproduces
it.

The design follows the loop described in Pramaana Labs'
[*The Age of Everyday Provers*](https://pramaanalabs.ai/blog/the-age-of-everyday-provers):
translate domain artifacts into formal representations, search the solution
space with provers and solvers, and return **proof artifacts that experts can
inspect** — never a bare "trust me". Every SAFE verdict carries a
k-induction certificate or an explicit inductive invariant re-checked by Z3;
every BUG verdict carries a trace and a Verilator-runnable testbench; every
AI contribution is filtered through a sound fixpoint so the LLM can help but
can never mislead.

```
                          ┌────────────────────────────────────────────┐
                          │                agent.py                    │
                          │   (agentic loops: repair / prove-refine)   │
                          └────────────────────────────────────────────┘
 SystemVerilog ──► desugar ──► Yosys ──┬─► BTOR2 ──► Z3 transition system
   (frontend.py)   (+LLM repair loop)  │   (btor2.py)      (engine.py)
                                       │                    │
                                       ├─► JSON netlist     ├─ BMC (incremental)
                                       │    │               ├─ k-induction
                                       │    ▼               └─ Houdini invariant
                                       │  Sparkle HDL          synthesis
                                       │  Lean 4 source        ▲
                                       │  + proof obligations  │ candidate lemmas
                                       │  (formalize.py)       │
                                       │              templates + GLM-5.2
                                       │              (invariants.py, llm.py)
                                       └─► SMT2 ──► yosys-smtbmc (baseline)
                                                     (baselines.py)
        BUG verdict ──► trace.json + tb_replay.sv ──► Verilator --assert
                        (cex.py)                      └─► CONFIRMED / not
```

## Detailed architecture

### Pipeline stages and data formats

The harness is a pipeline of six stages. Each stage consumes and produces a
concrete, inspectable artifact — there is no hidden state between stages, so
any stage can be re-run, audited, or swapped in isolation.

| # | Stage | Module | Input | Output |
|---|-------|--------|-------|--------|
| 1 | Desugar & repair | `frontend.py`, `agent.repair_frontend` | `design.sv` | `design.desugared.sv` / `design.repairN.sv` |
| 2 | Elaboration | `frontend.compile_sv` (Yosys) | desugared SV | `top.btor2` + `top.json` + `top.smt2` |
| 3 | Autoformalization | `formalize.py` | `top.json` netlist | `Top.lean` + `TopProps.lean` |
| 4 | Model construction | `btor2.py` | `top.btor2` | `TransitionSystem` (Z3 terms) |
| 5 | Proof search | `engine.py` + `invariants.py` + `agent.prove_property` | `TransitionSystem` | `Verdict` (+ invariant / trace) |
| 6 | Bug confirmation | `cex.py` | `Trace` + original SV | `trace.json` + `tb_replay.sv` + Verilator run |

All three stage-2 outputs come from **one shared Yosys recipe**
(`prep -top … ; flatten ; setundef -undriven -zero -init`), which pins a
single semantic interpretation of the design:

- **BTOR2** is what *our* engine checks (HWMCC's word-level format:
  assertions become `bad` states, assumptions become `constraint`s);
- **SMT2** is what the *baseline* (`yosys-smtbmc`) checks;
- **JSON** is what the autoformalizer lifts to Lean.

Because `setundef -init` gives every flip-flop an explicit zero initial
value, the formal models and Verilator's two-state simulation agree on the
initial state — this is what makes counterexample replay deterministic and
the tool comparison apples-to-apples.

### The transition system (btor2.py)

`Btor2Parser` folds the BTOR2 node graph into Z3 terms and produces:

```
TransitionSystem
  states        [z3 consts]          registers + memories (Array sort)
  inputs        [z3 consts]          free per-frame inputs
  init          [Bool]               equalities over frame-0 states
  next_fn       {state -> expr}      the transition function
  bads          [(name, Bool)]       one per SV assertion (negated property)
  constraints   [Bool]               SV assumptions, asserted at every frame
```

Frames are materialized lazily by substitution: `expr_at(e, k)` renames every
state/input `x` to `x@k`. This keeps the system description symbolic and
lets BMC, induction, and Houdini share one model. Memories stay word-level
(`Array BitVec BitVec`) — no bit-blasting — which is what lets the SoC-scale
designs with RAMs remain tractable.

### The proof engine (engine.py)

Three cooperating procedures, dispatched by the `prove` portfolio:

1. **Incremental BMC** — one Z3 solver, frames added incrementally;
   each `bad` is checked under `push`/`pop` so learned clauses persist
   across depths. On SAT, the model is projected onto inputs-per-frame +
   initial state to form a `Trace`.
2. **k-induction** — base case delegates to BMC; the step case asserts
   k consecutive safe frames (plus pairwise-distinct *simple-path*
   constraints when no memories are present) and asks whether frame k can
   be bad. UNSAT ⇒ `SAFE` with certificate "k-inductive".
3. **Houdini invariant synthesis** — takes N candidate lemmas and computes
   their **greatest inductive subset** in O(N) solver calls: first drop
   candidates not implied by the initial states, then repeatedly ask Z3 for
   a transition that breaks any surviving candidate and drop everything
   falsified in that model, until UNSAT (fixpoint). The negated bad states
   are seeded into the candidate set; if they survive, the surviving
   conjunction is an inductive invariant that implies safety — an
   independently re-checkable proof object, written to
   `invariant.smt2.txt`.

Verdict semantics:

| Verdict | Artifact | Meaning |
|---|---|---|
| `BUG` | `Trace` → `trace.json`, `tb_replay.sv` | assertion falsifiable in `depth` cycles; replayed through Verilator |
| `SAFE` | k-induction depth or inductive invariant | property holds for **all** reachable states, unboundedly |
| `UNKNOWN` | bound + reason | inconclusive within budget; caller may escalate (deeper BMC, more lemmas, Lean obligation) |

### Candidate lemma synthesis (invariants.py)

Templates generate the classic strengthenings deterministically: power-of-two
and small-constant bounds (FIFO occupancy), one-hot/at-most-one-hot (FSM
encodings), per-bit constancy, and capped pairwise relations (`a <= b`,
`a != b`) between same-width registers. The LLM path sends the original SV
plus the induction-failure context to GLM 5.2 and receives lemmas in a small
JSON DSL (`ule/eq/ne/implies/onehot/bit/in`), compiled to Z3 with width
coercion. **Soundness is structural**: both sources feed the same Houdini
fixpoint, which discards anything non-inductive, and the final invariant is
re-checked — an LLM hallucination can waste time but cannot produce a wrong
`SAFE`.

### Autoformalization (formalize.py)

The Yosys JSON netlist is bit-indexed; Sparkle's IR is word-level. The
formalizer therefore runs a *bit-vector net reconstruction* layer that
groups adjacent bit ids back into word nets and emits `slice`/`concat`
expressions where cell connections straddle nets. On top of that:

- **`circuitm` mode** (robust, any netlist): emits Lean that rebuilds the
  design via Sparkle's `CircuitM` builder (`addInput/addOutput/makeWire/`
  `emitAssign/emitRegister/emitMemory`), covering the full RTL cell library
  — arithmetic/logic/compare/shift cells, `$mux`/`$pmux`, the complete DFF
  family (sync/async reset, enables, polarities), and `$mem_v2` memories.
- **`signal` mode** (idiomatic, small blocks): emits applicative Signal DSL
  (`Signal.register`, `Signal.mux`, `(· + ·) <$> a <*> b`) matching the
  style of `Examples/`; falls back to `circuitm` when a construct doesn't fit.
- **Proof obligations** (`TopProps.lean`): a pure Lean model
  (`Inputs`/`State`/`nextState`/`Reachable`) plus, per assertion, a
  decidable predicate, a PROOF-PLAN comment, an `INVARIANT-SLOT` where the
  engine's synthesized invariant is injected as `candidateInv`, and
  theorems in both the invariant-proof pattern and the repo's Temporal/LTL
  vocabulary. `$assert` cells found in the netlist become properties
  automatically.

Translation is validated two ways: structurally (the emitted IR mirrors the
netlist 1:1 — same registers, same cones) and, for agentic rewrites of the
*source*, by Yosys `equiv_make`/`equiv_simple` equivalence checking against
the last accepted version.

### Counterexample replay (cex.py)

A BMC frame corresponds to one clock cycle. The generated testbench drives
non-clock inputs to frame k's values in the low phase of cycle k (stable
before the k-th posedge), matching BTOR2's input-feeds-transition semantics,
then lets Verilator's `--assert` catch the immediate assertion. Initial
states agree by construction (zero-init on both sides), so replay is
deterministic: `ReplayResult.confirmed = True` means the SMT-level bug is
reproduced in simulation of the *original* RTL — the strongest evidence the
harness can offer that a finding is real.

### Baseline methodology (baselines.py, bench.py)

`yosys-smtbmc` — the checking engine behind SymbiYosys — runs in BMC and
temporal-induction modes *on the same SMT2 elaboration* our BTOR2 model came
from. The runner records wall time, child max-RSS, solved/unsolved per
variant, and the report renders per-variant and aggregate tables plus a
time-vs-state-bits scalability section. A "solved" requires the *expected*
verdict; a bounded clean BMC on a safe design counts as bounded evidence,
not a solve.

### Full-SoC convergence (properties.py, convergence.py)

Sign-off is not "we ran some properties" — it is a defensible claim that the
property set covers the design and every property has a disposition.
`sparkle-fv converge` produces that claim as a **convergence dossier**
(`CONVERGENCE.md` + machine-readable `convergence.json`):

1. **Property synthesis.** Structural mining derives conjectures from the
   elaborated model itself (FSM value-set validity, counter bounds at
   observed maxima, one-hot integrity, pointer orderings — sampled from
   shallow symbolic exploration), while GLM-5.2 reads the RTL and proposes
   architectural invariants as SV assert expressions, which are compiled by
   instrumenting a copy of the source one property at a time (a proposal
   that fails elaboration is dropped, never poisoning the batch). User
   assertions already in the design are picked up as-is. **All three
   origins go through identical checking** — mining and the LLM only
   propose; the prover disposes.
2. **Dispositions.** Every property ends in exactly one state:
   `proven` (unbounded certificate: k-induction or re-checked inductive
   invariant), `bounded` (explicit proof radius — the industry-standard
   bounded claim, never silently conflated with proven), `falsified`
   (counterexample + Verilator-confirmed replay), `vacuous` (tautology
   screen: holds in all states, reachable or not — flagged as contributing
   zero coverage), or `discarded` (a refuted mined conjecture — not a
   design bug).
3. **Coverage.** The dossier computes **cone-of-influence coverage**: the
   fraction of state bits lying in the COI of at least one *proven*
   property, with the uncovered registers listed by name as the DV team's
   explicit to-do list. Gaps are surfaced, never averaged away.
4. **Assumption audit.** Every environment assumption (`assume`) in force
   is listed — a proof is only as strong as its assumptions, and a DV
   reviewer must see them to accept the claim.

The dossier is designed to be *adversarially reviewable*: every certificate
is re-checkable with any SMT solver, every trace replays in the team's own
simulator, and the coverage metric is computed from the netlist, not
self-reported.

### Escalation ladder

The harness is designed as a ladder — each rung is cheaper and more
automatic than the one below, and every handoff carries its artifacts along:

```
BMC (bug?) → k-induction (cheap proof?) → Houdini/templates
    → Houdini + GLM-5.2 lemmas (agentic refinement)
        → Lean proof obligation with injected candidateInv
            (human/AI theorem proving in Sparkle's framework)
```

## The agentic loops

1. **Frontend repair** (`agent.repair_frontend`) — Yosys 0.33 rejects some
   modern SV (e.g. `automatic` block locals, as in this repo's
   `verilator/rv32i_soc.sv`). A deterministic desugar pass handles the
   common cases; remaining elaboration errors are shown to the LLM, which
   proposes a minimal semantics-preserving rewrite. Rewrites are
   translation-validated with Yosys `equiv_make` where possible.

2. **Prove–refine** (`agent.prove_property`) — the portfolio runs BMC (bug
   hunting), k-induction (cheap proofs), then **Houdini**: a greatest-
   fixpoint over a set of candidate lemmas that returns the largest
   *inductive* subset. The negated properties are themselves candidates —
   if they survive, the surviving conjunction is an inductive invariant
   proving safety. When the template candidates are insufficient, the agent
   asks the LLM for design-specific lemmas (FSM validity, pointer/counter
   relations) in a small JSON DSL and re-runs the fixpoint. **Soundness does
   not depend on the LLM**: unsound candidates are dropped by Z3, and the
   final invariant is re-checked.

3. **Autoformalization** (`formalize.py`) — the elaborated netlist is
   emitted as Sparkle HDL Lean 4 source (IR/CircuitM level, plus idiomatic
   Signal DSL for small blocks) together with Lean proof-obligation
   skeletons following `docs/Verification_Framework.md`'s proof patterns.
   Inductive invariants found by the engine are injected into the
   obligations as candidate lemmas, so an unbounded Lean proof can pick up
   where the SMT engine stopped. (Lean artifacts are generated under the
   output directory and are compile-checked wherever a Lean toolchain is
   available; this container has no network route to Lean releases.)

## Real-world industrial use

The harness maps onto the verification workflows hardware teams actually run
in production, and each is demonstrated in this repository:

### 1. RTL sign-off of safety-critical blocks (arbiter/FIFO/handshake class)

The classic "formal apps" of commercial tools (Cadence JasperGold FPV,
Synopsys VC Formal, Siemens Questa PropCheck): prove mutual exclusion on
arbiters, no-overflow/underflow on FIFOs, protocol legality on handshakes.
`benchmarks/blocks/` mirrors this class 1:1 — `sparkle-fv prove` returns an
unbounded proof (k-induction certificate or inductive invariant) that can go
into a sign-off report, not just "no bug found up to N cycles". The
difference from the commercial flow: the invariant is an explicit artifact
(`invariant.smt2.txt`) a reviewer can independently re-check with any SMT
solver, and the property carries over into a Lean theorem for permanent,
machine-checked documentation.

### 2. Bug hunting in legacy / third-party RTL before integration

Teams integrating purchased IP or decade-old in-house RTL rarely have specs.
The workflow here: drop immediate assertions at interfaces (or let the
autoformalizer surface the `$assert` cells already in the code), run
`sparkle-fv bughunt`, and every finding arrives as **a Verilator-runnable
testbench**, not an SMT model — so the finding transfers directly into the
team's existing simulation regression, in the team's own tool. No formal
expertise is needed to *consume* the result; that is the "everyday provers"
thesis applied to silicon.

### 3. Full-SoC convergence sign-off

`sparkle-fv converge` addresses the question DV leads actually get asked:
*"are we done?"* It writes the SoC property set itself (structural mining +
GLM-5.2 architectural proposals + existing assertions), proves it, and emits
a convergence dossier with per-property dispositions, explicit proof radii
for anything not fully proven, cone-of-influence coverage with named gaps,
and an assumption audit — the evidence package that convinces a DV team
because every claim in it is independently re-checkable (SMT certificates,
Verilator-replayable traces) and every gap is listed, not averaged away.
See `results/` for the dossier generated for this repo's RV32IMA SoC.

### 3b. SoC-level invariant checking (architectural safety nets)

Full-SoC formal is where commercial tools hit scalability walls and teams
fall back to simulation. `benchmarks/soc/rv32i_soc` demonstrates the
tractable middle ground on this repo's Linux-booting RV32IMA SoC (~4k lines,
CSRs, MMU, UART): architectural invariants — privilege-mode legality, CSR
write-mask correctness, trap-vector alignment — checked at the SoC top with
word-level memories (no bit-blasting). These are exactly the invariants that,
when violated, produce the unreproducible weeks-long Linux-boot debug
sessions; catching them formally at commit time is cheap by comparison.

### 4. Continuous verification in CI

Because verdicts are deterministic without the LLM (`--no-llm`), the
harness runs as a CI gate: `sparkle-fv bench` on the block suite finishes in
minutes on one core and exits non-zero on any unexpected verdict. Seeded-bug
variants double as *mutation testing for the property set* — if a seeded bug
stops being caught, the CI run fails, guarding against property rot.

### 5. Certification evidence (ISO 26262 / DO-254 flavored)

Functional-safety flows require traceable evidence that requirements hold.
The harness's chain — SV assertion → BTOR2 bad state → proof artifact
(invariant/certificate) → Lean theorem statement — gives requirement-level
traceability where every link is machine-checkable, and the Lean obligations
put the proofs in the same framework as the 60+ theorems already maintained
in this repository (`Sparkle/Verification/`).

### 6. Trust but verify for AI-generated RTL

As RTL is increasingly LLM-generated, the harness closes the loop from the
other side: AI-repaired or AI-generated code is admitted only through Yosys
equivalence checking (`repair_frontend`) and property proofs, never on the
model's word. The same applies to the harness's own AI layer — GLM-5.2
lemma proposals pass through the Houdini fixpoint and a final Z3 re-check,
so the AI accelerates proofs but sits entirely outside the trusted base.

## LLM configuration

The agentic layer uses **GLM 5.2 via OpenRouter** by default:

```bash
export OPENROUTER_API_KEY=sk-or-...        # never committed to the repo
export SPARKLE_FV_MODEL=z-ai/glm-5.2       # default; any OpenRouter model id
```

Without a key (or with `--no-llm`) the harness is fully functional and
deterministic — template candidates only. All benchmark numbers in
`results/` were produced with `--no-llm` for reproducibility.

## Usage

```bash
cd Prover
pip install z3-solver             # the only Python dependency
export PYTHONPATH=$PWD

# Autoformalize SV -> Sparkle HDL (Lean 4) + proof obligations
python3 -m sparkle_fv.cli formalize path/to/design.sv top_module --out out/

# Full agentic verification of one design (block or SoC)
python3 -m sparkle_fv.cli prove design.sv top --max-bmc 60 --max-k 12

# Pure bug hunting with Verilator replay
python3 -m sparkle_fv.cli bughunt bug.sv top --max-bmc 40

# Benchmark suite vs yosys-smtbmc (writes results.json + REPORT.md)
python3 -m sparkle_fv.cli bench --out results/run1 --timeout 300

# Full-SoC convergence: synthesize property set, prove, write the dossier
python3 -m sparkle_fv.cli converge soc.sv soc_top --out conv/ --timeout 300
```

Exit codes for `prove`/`bughunt`: `0` safe/clean, `1` bug found, `2` unknown.

## Benchmarks

`benchmarks/blocks/` is an HWMCC-safety-track-style suite (12 designs:
arbiters, FIFOs, handshakes, LFSR/gray counters, ALU, memory controller,
UART, AXI-lite, pipelined datapath), each with a proven-safe variant and
seeded-bug variants with known minimal counterexample depths.
`benchmarks/soc/rv32i_soc/` is the repository's Linux-booting RV32IMA SoC
(~4k lines) with SoC-level invariants asserted on the privilege/CSR/UART
logic — the scalability stressor.

Baseline: `yosys-smtbmc` (the checking engine used by SymbiYosys), run in
BMC + temporal-induction mode **on the identical Yosys elaboration**, so the
comparison isolates checking strategy rather than frontend parsing. See
`results/REPORT.md` for the current numbers and analysis.

## Layout

```
Prover/
  sparkle_fv/
    frontend.py    SV -> desugar -> Yosys -> BTOR2 + JSON + SMT2
    btor2.py       BTOR2 (HWMCC format) -> Z3 transition system
    engine.py      BMC, k-induction, Houdini; verdicts with artifacts
    invariants.py  template + LLM candidate lemma synthesis
    llm.py         OpenRouter client (GLM 5.2), offline-safe
    agent.py       agentic loops; verify_design end-to-end pipeline
    formalize.py   netlist -> Sparkle HDL Lean source + proof obligations
    cex.py         counterexample -> SV testbench -> Verilator replay
    baselines.py   yosys-smtbmc runners
    bench.py       suite runner + report renderer
    cli.py         sparkle-fv CLI
  benchmarks/      block + SoC benchmark suite (see benchmarks/README.md)
  results/         evaluation reports
```
