"""Automatic property synthesis for full-SoC convergence.

A DV team converges a block when every signed-off property is proven and the
property set demonstrably covers the design. This module writes the
properties; `convergence.py` proves them and renders the evidence.

Two synthesis paths, both validated before use:

  1. **Structural mining** (deterministic) — candidate safety properties
     derived from the elaborated transition system itself:
       * FSM-register range validity (small registers stay within the value
         set reachable in shallow exploration — proposed, then *proven or
         discarded* like any other property);
       * counter/pointer bounds at power-of-two and observed maxima;
       * one-hot integrity for grant/select-shaped registers;
       * register-pair orderings (occupancy counters vs. capacities).
     Mined properties are checked as additional bad states on the SAME
     transition system, so they need no source instrumentation.

  2. **LLM proposal** (GLM 5.2) — the model reads the SystemVerilog and
     proposes end-to-end invariants as `assert` expressions over module
     signals (privilege legality, CSR mask consistency, protocol rules).
     Each proposal is compiled by instrumenting a copy of the source and
     re-elaborating with Yosys; proposals that do not compile are dropped,
     and the rest become ordinary bad states with provenance recorded.

Every synthesized property then goes through the same pipeline as a
hand-written one: tautology screen (vacuity), BMC falsification, unbounded
proof attempt. Nothing enters the dossier on the LLM's word alone.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import z3

from . import frontend, llm
from .btor2 import TransitionSystem, parse_btor2
from .engine import Engine


@dataclass
class SynthProperty:
    name: str
    origin: str                  # "user" | "mined" | "llm"
    description: str
    expr: z3.BoolRef | None = None   # over ts states (mined / user)
    sv_expr: str | None = None       # SV expression text (llm)
    module: str | None = None        # module to instrument (llm)


@dataclass
class PropertySet:
    props: list[SynthProperty] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def _bv_states(ts: TransitionSystem) -> list[z3.ExprRef]:
    return [s for s in ts.states if isinstance(s.sort(), z3.BitVecSortRef)]


def _explore_values(ts: TransitionSystem, depth: int = 12,
                    per_state_cap: int = 64) -> dict[str, set[int]]:
    """Shallow BMC-style exploration: collect reachable value samples per
    register by asking Z3 for a handful of distinct depth-`depth` runs."""
    seen: dict[str, set[int]] = {s.decl().name(): set() for s in _bv_states(ts)}
    s = z3.Solver()
    s.set("timeout", 15000)
    for f in ts.init_at(0):
        s.add(f)
    for k in range(depth):
        for c in ts.constraints_at(k):
            s.add(c)
        for c in ts.trans_at(k):
            s.add(c)
    for _round in range(4):
        if s.check() != z3.sat:
            break
        m = s.model()
        block = []
        for st in _bv_states(ts):
            for k in range(depth + 1):
                v = m.eval(ts.expr_at(st, k), model_completion=True)
                if z3.is_bv_value(v):
                    vals = seen[st.decl().name()]
                    if len(vals) < per_state_cap:
                        vals.add(v.as_long())
                    block.append(ts.expr_at(st, k) != v)
        s.add(z3.Or(block) if block else z3.BoolVal(False))
    return seen


def mine_structural(ts: TransitionSystem, max_props: int = 60) -> PropertySet:
    """Derive candidate safety properties from the transition system."""
    ps = PropertySet()
    samples = _explore_values(ts)

    def add(name: str, desc: str, expr: z3.BoolRef):
        if len(ps.props) < max_props:
            ps.props.append(SynthProperty(name, "mined", desc, expr=expr))

    for st in _bv_states(ts):
        n = st.decl().name()
        w = st.sort().size()
        vals = samples.get(n, set())
        if not vals:
            continue
        vmax = max(vals)
        # FSM-shaped: small width, few observed values, not a counter ramp
        if 2 <= w <= 6 and len(vals) <= min(8, (1 << w) - 1):
            add(f"fsm_valid[{n}]",
                f"register {n} stays within observed state set {sorted(vals)}",
                z3.Or([st == z3.BitVecVal(v, w) for v in sorted(vals)]))
        # Counter-shaped: bound at next power of two of the observed max
        if w >= 3 and 0 < vmax < (1 << w) - 1:
            bound = 1
            while bound <= vmax:
                bound <<= 1
            if bound < (1 << w):
                add(f"bound[{n}]",
                    f"register {n} never exceeds {bound - 1} "
                    f"(observed max {vmax})",
                    z3.ULE(st, z3.BitVecVal(bound - 1, w)))
        # One-hot-shaped: every observed value is a power of two (or zero)
        if 2 <= w <= 16 and vals and all(v == 0 or (v & (v - 1)) == 0
                                         for v in vals):
            bits = [z3.Extract(i, i, st) for i in range(w)]
            pop = sum(z3.ZeroExt(4, b) for b in bits)
            add(f"onehot0[{n}]",
                f"register {n} is at-most-one-hot in all observed states",
                z3.ULE(pop, z3.BitVecVal(1, 5)))
    ps.notes.append(f"mined {len(ps.props)} candidates from "
                    f"{len(_bv_states(ts))} registers")
    return ps


# ------------------------------------------------------------------- LLM path

_PROP_SYSTEM = """You are a senior design-verification engineer writing \
formal properties for SoC sign-off. Given SystemVerilog, propose safety \
invariants as immediate-assertion EXPRESSIONS over signals visible in the \
named module. Only reference signals that exist in the module. Prefer \
architectural invariants: privilege/mode legality, CSR consistency, \
alignment, handshake rules, FSM validity, counter bounds. Respond ONLY with \
a JSON array of {"name": str, "module": str, "expr": str (SV boolean \
expression), "rationale": str}."""


def llm_properties(sv_source: str, top: str, max_props: int = 12) -> PropertySet:
    """Ask GLM 5.2 for SoC-level invariants as SV assert expressions."""
    ps = PropertySet()
    if not llm.llm_enabled():
        ps.notes.append("LLM property synthesis skipped (no OPENROUTER_API_KEY)")
        return ps
    try:
        resp = llm.chat(_PROP_SYSTEM,
                        f"Top module: {top}\n```systemverilog\n"
                        f"{sv_source[:60000]}\n```\n"
                        f"Propose up to {max_props} properties.",
                        max_tokens=4096)
        items = llm.extract_json_block(resp)
    except (llm.LLMUnavailable, ValueError) as e:
        ps.notes.append(f"LLM property synthesis unavailable: {e}")
        return ps
    if not isinstance(items, list):
        return ps
    for i, it in enumerate(items[:max_props]):
        if not isinstance(it, dict) or not it.get("expr"):
            continue
        name = re.sub(r"\W+", "_", str(it.get("name", f"llm_prop_{i}")))
        ps.props.append(SynthProperty(
            name=name, origin="llm",
            description=str(it.get("rationale", ""))[:200],
            sv_expr=str(it["expr"]), module=str(it.get("module", top))))
    ps.notes.append(f"LLM proposed {len(ps.props)} properties")
    return ps


def instrument_sv(sv_path: Path, props: list[SynthProperty], out_path: Path,
                  top: str) -> tuple[Path, list[SynthProperty]]:
    """Insert `always_comb assert` for each LLM property into a copy of the
    source (before the target module's `endmodule`), then keep only the
    properties that still elaborate under Yosys — one at a time, so a single
    bad proposal cannot poison the batch."""
    src = sv_path.read_text()
    kept: list[SynthProperty] = []
    for p in props:
        if not p.sv_expr:
            continue
        trial_src = _apply_props(src, kept + [p], top)
        if trial_src == _apply_props(src, kept, top):
            continue  # module anchor not found; skip
        out_path.write_text(trial_src)
        try:
            frontend.run_yosys(
                f"read_verilog -sv -formal {out_path}; hierarchy -top {top}",
                timeout_s=120)
            kept.append(p)
        except frontend.FrontendError:
            continue
    out_path.write_text(_apply_props(sv_path.read_text(), kept, top))
    return out_path, kept


def _apply_props(src: str, props: list[SynthProperty], top: str) -> str:
    for p in props:
        mod = p.module or top
        pat = re.compile(rf"(module\s+{re.escape(mod)}\b.*?)(\nendmodule)",
                         re.S)
        line = (f"\n  // sparkle-fv synthesized property: {p.description}\n"
                f"  always_comb assert ({p.sv_expr}); // SPROP:{p.name}\n")
        src = pat.sub(lambda m: m.group(1) + line + m.group(2), src, count=1)
    return src


def screen_tautology(expr: z3.BoolRef, timeout_ms: int = 5000) -> bool:
    """True if the property is valid WITHOUT any reachability assumption —
    i.e. it constrains nothing about the design and is vacuous as a
    convergence claim (still sound, just worthless; flagged in the dossier)."""
    s = z3.Solver()
    s.set("timeout", timeout_ms)
    s.add(z3.Not(expr))
    return s.check() == z3.unsat
