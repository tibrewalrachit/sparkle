# Sparkle STA — Design Document

A formally verified Static Timing Analysis engine for Sparkle, built as a new
library under `Sparkle/STA/`. The proved core works over ℚ with interval
delays; soundness theorems justify each signoff check against a
max/min-over-all-paths specification.

---

## 1. What exists in the repo today (exploration findings)

### 1.1 IR / netlist (`Sparkle/IR/AST.lean`)
- `Module` = `{ name, inputs outputs wires : List Port, body : List Stmt }`.
  A `Port` is a `(name : String, ty : HWType)` pair; **nets are identified by
  wire/port name (String)** — there is no separate pin or cell-instance layer.
- `Stmt` is one of:
  - `assign (lhs : String) (rhs : Expr)` — combinational logic. `Expr` is a
    tree of `Operator` applications (`and/or/xor/add/mux/…`), `ref`s to nets,
    `const`s, `concat/slice/index`.
  - `register (output clock reset : String) (input : Expr) (initValue)` — the
    sequential cut point. `output` names the Q net; `clock` names a net (so a
    clock **can** be driven through logic — gated/buffered clocks are
    representable, which is what makes derived skew meaningful).
  - `memory …` — synchronous RAM (registered read), i.e. sequential.
  - `inst …` — module instantiation (blackbox for this task).
- The compiler (`Sparkle/Compiler/Elab.lean`) emits **one operator per
  `assign` into a fresh wire** (`_tmp_*` / `_gen_*` names), so
  elaborator-produced bodies are effectively gate-level: each `assign` is a
  "cell" whose type is the root `Operator` of its RHS.

### 1.2 Combinational-loop-freedom: what the guarantee actually is
- At the `Signal` level (`Sparkle/Core/Signal.lean`), feedback is only
  expressible through `Signal.register` / `Signal.loop`; `register` delays by
  one cycle, and `loop`'s productivity comes from a register in its body.
  README ("No Combinational Loops") documents this as a **by-construction**
  DAG guarantee.
- **⚠ FLAG (design-decision deviation, per instructions):** there is **no
  Lean lemma or theorem in the codebase** stating acyclicity — no
  `Acyclic`, no topological-order invariant, nothing to `import`. The
  guarantee exists only architecturally. Worse, statement order in the IR is
  *not* topological: `Elab.handleLoop` emits `assign loopWire := resultWire`
  *after* the statements that reference `loopWire` (a forward reference,
  legal because the cycle is broken by a register inside the loop body — but
  that fact is nowhere stated in Lean).
- **Treatment — surface the existing guarantee as a checkable certificate,
  do not re-derive it:**
  - `Graph.lean` defines a decidable predicate `IsTopoOrder G order`
    ("`order` lists every node exactly once and every edge goes strictly
    forward in it").
  - `topoOrder? : Graph → Option {order // IsTopoOrder G order}` runs Kahn's
    algorithm and then **re-checks its own output** with the decidable
    predicate, so we get a *proof-carrying* order without proving Kahn
    correct (certificate checking, not algorithm verification).
  - Every sweep's termination and every theorem is discharged **from the
    certificate** — the topo rank strictly decreases along edges. Nothing
    downstream ever re-assumes acyclicity; for elaborator-produced designs
    the certificate always exists, which is exactly Sparkle's by-construction
    invariant made checkable. If a hand-built fixture has a combinational
    loop, `topoOrder?` returns `none` and STA reports it (a useful DRC in
    itself). No parallel graph-theoretic DAG development is introduced.

### 1.3 DRC pass (`Sparkle/Compiler/DRC.lean`)
- One rule: `checkRegisteredOutputs : Module → List String` (STARC-inspired
  registered-output check). Pure function returning human-readable
  violations; the Verilog backend prints them. `Check.lean` follows this
  shape: pure `Module → STAReport`, driver prints.

### 1.4 Build setup
- Toolchain `leanprover/lean4:v4.28.0-rc1`; deps: **LSpec** (tests),
  **doc-gen4** (docs). **No Mathlib, no Batteries.**
- ℚ therefore means **core `Rat`** (`Init.Data.Rat`), which in 4.28 ships
  `le_refl/le_trans/le_antisymm/le_total/not_le/add_le_add_left/right`,
  `add_comm/assoc`, `sub` lemmas, `Min/Max` instances (`minOfLe/maxOfLe`),
  and `grind` order instances (`IsLinearOrder Rat`, `OrderedRing Rat`).
  That is enough to build the small interval/max/min lemma kit by hand; no
  new dependency is added to the lakefile.
- `lean_lib «Sparkle»` builds whatever `Sparkle.lean` transitively imports.
  STA modules are added to `Sparkle.lean` (repo convention: the root imports
  each module directly). `Sparkle/STA/Test.lean` uses `#guard`/`example`
  build-time assertions, so **`lake build` itself runs the STA tests**; no
  lakefile change is needed.

---

## 2. Module map

```
Sparkle/STA/
  DESIGN.md        (this file)
  Model.lean       Delay interval + arithmetic lemmas; NLDM table +
                   snap-outward lookup; cell library keyed by IR Operator;
                   clock spec; SDC-style constraints. Depends only on core Rat.
  Graph.lean       Pin type; timing graph (Fin-indexed); IsTopoOrder
                   certificate + topoOrder?; Module → (data graph, clock
                   graph) extraction with cuts.       Imports Model, IR.AST.
  Propagate.lean   Seeded-DAG sweep engine (one engine, two instances:
                   clock graph then data graph); arrival (both rails as one
                   interval); required (setup + hold edge relations); slack;
                   path-spec (allPathsTo, pathArrival) — spec-level only.
  Soundness.lean   block_eq_path (late), block_eq_path_early, setup_sound,
                   hold_sound; later phases append recovery/removal etc.
  Check.lean       Driver: extract graphs → certificates → clockArrival →
                   data arrival/required → per-endpoint report.
  Test.lean        In-Lean fixtures + #guard assertions (build-time).
```

Namespace: `Sparkle.STA.*`, matching `Sparkle.Compiler.DRC` style.

---

## 3. The proved core

### 3.1 Delay intervals (`Model.lean`)
```lean
structure Delay where
  lo : Rat
  hi : Rat
  h  : lo ≤ hi
```
- `Delay.add`, `Delay.hull` (component-wise: `[min lo lo', max hi hi']`),
  `Delay.max`/`Delay.min` where needed — each carrying the `lo ≤ hi` proof.
- The **early and late rails are the two endpoints of one interval**: the
  arrival interval at a node is `[min over paths of Σ lo, max over paths of
  Σ hi]`. Merging fan-in with `hull` and traversing edges with `add` computes
  both rails in one sweep; `block_eq_path` (late) and `block_eq_path_early`
  are the `.hi` and `.lo` projections of the same induction.
- Small lemma kit over (ℚ, max, +) / (ℚ, min, +): `max_le_iff`,
  `le_max_left/right`, `add_max` distributivity, and the `min` duals —
  proved from core `Rat` order lemmas (`le_total` case splits / `grind`).
  These are the pieces `block_eq_path` composes from.

### 3.2 NLDM, conservatively
```lean
structure NLDMTable where
  slewAxis loadAxis : List Rat        -- sorted axes
  values : List (List Delay)         -- values[i][j] at (slewAxis[i], loadAxis[j])
```
Lookup **snaps outward to the bounding grid cell**: take the `hull` of the
(up to four) surrounding corner entries — i.e. `[min of corner lo's, max of
corner hi's]`. Sound by pessimism: any interpolated value lies inside the
hull of the corners **assuming per-cell monotone behavior of real silicon**;
we do *not* model or prove continuity/interpolation — documented limitation,
not a `sorry`. Out-of-range indices clamp to the nearest edge cell (also
pessimistic-by-hull). A degenerate 1×1 table gives fixed-delay cells, which
Phase 1 fixtures use; the slew rail (needed for Phase 4 `maxTransition`)
rides the same table shape.

### 3.3 The one sweep engine (`Propagate.lean`)
Abstract input: a graph `G` over `Fin n`, edge list with `Delay` weights, a
seed function `seed : Fin n → Option Delay`, and a topo certificate.

- `arrival v` is defined by **strong recursion on the topo rank of `v`**
  (the rank of an edge's source is strictly below its target's — this is
  where the acyclicity certificate discharges termination, and the *only*
  place termination is argued):
  `arrival v = hull-merge of (seed v) with { arrival u + d | (u,v,d) ∈ E }`,
  `Option`-valued (`none` = unconstrained/unreachable, the max/min over an
  empty path set).
- Spec side: `allPathsTo v : List Path` by the same rank recursion
  (`Path` = seeded start node + chained edge list); `pathArrivalLate v =
  max? ((allPathsTo v).map (fun p => seed(p.start).hi + Σ e.hi))`, dually
  `pathArrivalEarly` with `min?`/`.lo`. Spec-level only — exponential is fine.
- `Check.lean` evaluates `arrival` with memoization along the topo order (a
  fold carrying a `Fin n → Option Delay` accumulator, proved equal to the
  recursive `arrival` by a fold-invariant lemma; if that refinement lemma
  turns out heavy, Phase 1 ships the rank-recursive evaluator directly —
  fixtures are tiny — and the fold refinement is flagged in the report).

**Instantiation twice (the data/clock split):**
1. **Clock graph**: nodes = clock-cone nets + register clock pins; seed =
   `[0,0]` at the clock source port; `clockArrival (regClk r)` **is** the
   launch/capture latency interval of `r` — skew is derived by real
   traversal, never an input.
2. **Data graph**: nodes = data nets + register D pins; seeds:
   - primary input `i` ↦ SDC input-delay interval,
   - register Q net of `r` ↦ `clockArrival(regClk r) + clkToQ(cell r)` —
     per-launch-register clock latency folds into every path from that
     register, so multi-startpoint merging at an endpoint is automatically
     per-path-correct.

### 3.4 Edge relations, required times, slack
For endpoint `e` (register D pin `r`, or output port):
- **Setup (adjacent edge)**: `requiredSetup r = T + clockArrival(regClk r).lo − tSetup r`;
  `slackSetup r = requiredSetup r − arrival(D r).hi`.
- **Hold (same edge, no T)**: `requiredHold r = clockArrival(regClk r).hi + tHold r`;
  `slackHold r = arrival(D r).lo − requiredHold r`.
  Hold is a distinct edge relation (no period term), not "setup with min":
  the two checks use opposite interval endpoints on *both* the data and the
  clock side (late data vs early capture for setup; early data vs late
  capture for hold — the standard OCV-pessimistic pairing).
- **Outputs**: required at output port `o` = `T − outputDelay o` (setup rail)
  and `outputDelayHold o` (hold rail); in→out paths get both ends from SDC.
- A **backward sweep** over the reversed topo order propagates required
  times to internal nodes for per-node slack reporting (same engine, reversed
  edges, min-merge for setup rail / max-merge for hold rail); endpoint
  soundness theorems consume only the endpoint values.

### 3.5 Soundness theorems (`Soundness.lean`)
With `physDelayLate p = seedHi(p.start) + Σ hi(e)` etc.:
- `block_eq_path`       : `(arrival v).map (·.hi) = pathArrivalLate v` —
  induction on topo rank; inductive step is list algebra over
  `max?`/`++`/`map` plus `add_max` distributivity (the (ℚ,max,+) semiring
  facts). "STA is exhaustive over all paths", late rail.
- `block_eq_path_early` : `.lo` projection with `min?` — same induction,
  max↦min, hi↦lo.
- `setup_sound` : `slackSetup r ≥ 0 → ∀ p ∈ pathsInto r,`
  `launchLat(p).hi + combDelay(p).hi + tSetup r ≤ T + clockArrival(regClk r).lo`
  (launch latency appears inside the path seed; this is the task's
  `physDelay p + tSetup ≤ T + captureLatency − launchLatency` with the launch
  term moved across — stated with derived latencies on both sides). Proof:
  interval invariant `physDelayLate p ≤ pathArrivalLate r` (a `max?` member
  bound) chained with `block_eq_path` and slack arithmetic.
- `hold_sound` : dual, shortest path meets the same-edge relation via
  `block_eq_path_early`.

### 3.6 Netlist → graph extraction (`Graph.lean`)
```lean
inductive Pin | net (name : String) | regD (reg : String) | regClk (reg : String)
```
Per statement:
- `assign lhs rhs`: for each `ref w` **leaf occurrence** in `rhs`, one edge
  `net w → net lhs` weighted by the interval sum of per-operator delays along
  the leaf→root spine of the expression tree (cell library keys delays by
  `Operator`; `concat/slice/const` contribute `[0,0]`). Multiple occurrences
  give parallel edges; the sweep's hull-merge handles them. This is exact for
  elaborator output (one op per assign) and conservative composition for
  nested fixtures.
- `register out clk rst in`: data edges from `in`'s refs terminate at
  `regD out`; `net out` becomes a data-graph seed (cut); `net clk → regClk out`
  joins the **clock** graph. `rst` is ignored in Phase 1 (async pins are
  Phase 2's recovery/removal).
- `memory`: treated register-like (read data net = startpoint, address/data
  inputs = endpoints) — documented approximation.
- `inst`: rejected with a report entry (blackbox; out of scope for this task).

The **clock cone** is found by backward closure from register clock nets to
the clock source; nets in the cone are excluded from the data graph
(a net that fans out to both — clock used as data — is reported as a
violation rather than silently analyzed).

---

## 4. Path model coverage

| Path type | Startpoint seed | Endpoint requirement |
|---|---|---|
| reg→reg | Q: `clkArr(launch) + clkToQ` | D: setup (adjacent edge, T), hold (same edge) |
| in→reg | input port: SDC input delay | same as above |
| reg→out | Q seed as above | output port: `T − outputDelay` / hold dual |
| in→out | SDC input delay | output port requirement |
| clock path | clock source `[0,0]` | consumed as launch/capture latencies |

---

## 5. Phase roadmap on this skeleton

- **Phase 2 (recovery/removal)**: async set/reset pin of a register becomes a
  data-graph endpoint `regAsync r`; recovery = setup-shaped relation against
  the capture edge, removal = hold-shaped. **No new path theorem** — new edge
  relations chain the existing `block_eq_path(_early)`.
- **Phase 3 (pulse width / min period)**: uses clock waveform (period, duty)
  + `clockArrival`; per-register `T ≥ minPeriod(cell)` is fully checkable.
  Pulse degradation through the clock tree is **not derivable from this
  model** (we propagate arrival intervals, not edge-pair waveform shapes) —
  the high/low-phase check at the register pin will be stated against the
  source waveform with a documented `-- PROOF GAP:` on physical degradation.
- **Phase 4 (DRVs)**: fanout = out-degree in the extracted graph (provable
  bound); cap = Σ pin caps on the net (provable); transition = slew rail from
  the NLDM model (check + soundness relative to the table model).
- **Phase 5 (latch borrowing, data-to-data)**: borrowing adds a bounded
  positive term to `requiredSetup` capped by the transparent window;
  data-to-data reuses arrival rails with user endpoints. Transparency beyond
  one borrow stage is a documented limit.
- **Phase 6 (multi-corner/OCV)**: a corner selects library values; mode (a)
  re-runs the engine per corner, mode (b) hulls corner libraries into one
  interval run. OCV derate = interval widening (`Delay.widen k`), which
  composes with `add`/`hull` monotonicity. `slack_monotone` reduces to:
  arrival is **monotone in the edge-delay intervals** (containment-preserving),
  one lemma over the same rank induction. Statistical STA: explicitly out of
  scope.

---

## 6. Honesty ledger (declared up front)

- **No existing acyclicity lemma** — surfaced as the checked
  `IsTopoOrder` certificate (§1.2). This is the load-bearing deviation.
- **NLDM interpolation** is replaced by snap-outward hull — sound by
  pessimism *relative to the assumption that true cell delay lies within the
  hull of surrounding characterized corners*; that physical assumption is not
  (and cannot be) proved in Lean.
- Phase 3 pulse degradation and Phase 5 deep transparency: expected
  `-- PROOF GAP:` entries, reasons above.
- `inst` (hierarchy) and SPEF/.lib/.sdc parsing: out of scope by instruction.
