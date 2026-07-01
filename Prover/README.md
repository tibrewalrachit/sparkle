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
