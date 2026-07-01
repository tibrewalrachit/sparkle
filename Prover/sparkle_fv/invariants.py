"""Candidate invariant synthesis for the Houdini engine.

Two sources of candidate lemmas:

  1. Deterministic templates over the transition system's state variables —
     bounds, constant-prefix, one-hot, mutual exclusion, and pairwise
     relations.  These are cheap, reproducible, and cover the classic
     inductive-strengthening patterns (gray counters, FIFO occupancy, FSM
     validity).
  2. AI-proposed lemmas: the LLM (GLM 5.2 via OpenRouter) reads the original
     SystemVerilog plus the failed induction context and proposes invariants
     in a small JSON DSL, which we compile to Z3 terms.  Unsound proposals
     are harmless: Houdini discards anything not inductive, and the final
     invariant is re-checked by Z3 — the AI can only *help*, never mislead.

This mirrors the "translate → search with provers → return checkable proof
artifacts" loop described in Pramaana Labs' "The Age of Everyday Provers".
"""

from __future__ import annotations

import itertools

import z3

from .btor2 import TransitionSystem
from . import llm


def _bv_states(ts: TransitionSystem) -> list[z3.ExprRef]:
    return [s for s in ts.states if isinstance(s.sort(), z3.BitVecSortRef)]


def template_candidates(ts: TransitionSystem, max_pairwise: int = 400,
                        max_total: int = 3000) -> tuple[list[z3.BoolRef], list[str]]:
    """Generate candidate lemmas from syntactic templates.

    Templates (per bitvector state s of width w):
      * power-of-two upper bounds:      s <= 2^m - 1   (leading zeros)
      * small-constant upper bounds:    s <= c  for c near FIFO/FSM sizes
      * non-null / non-full:            s != 0, s != 2^w - 1
      * one-hot / at-most-one-hot:      exactly/at most one bit set
      * per-bit constancy:              s[i] == 0
    Pairwise (same width, capped):
      * s1 <= s2, s1 != s2, s1 - s2 bounded
    """
    cands: list[z3.BoolRef] = []
    labels: list[str] = []

    def add(lbl: str, e: z3.BoolRef):
        if len(cands) < max_total:
            cands.append(e)
            labels.append(lbl)

    small_consts = [1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 31]
    for s in _bv_states(ts):
        w = s.sort().size()
        n = s.decl().name()
        ones = (1 << w) - 1
        add(f"{n}!=0", s != z3.BitVecVal(0, w))
        add(f"{n}!=ones", s != z3.BitVecVal(ones, w))
        for m in range(1, min(w, 12)):
            add(f"{n}<2^{m}", z3.ULE(s, z3.BitVecVal((1 << m) - 1, w)))
        for c in small_consts:
            if c < ones:
                add(f"{n}<={c}", z3.ULE(s, z3.BitVecVal(c, w)))
        if 2 <= w <= 16:
            bits = [z3.Extract(i, i, s) for i in range(w)]
            pop = sum(z3.ZeroExt(4, b) for b in bits)
            add(f"onehot({n})", pop == z3.BitVecVal(1, 5))
            add(f"onehot0({n})", z3.ULE(pop, z3.BitVecVal(1, 5)))
        if w <= 16:
            for i in range(w):
                add(f"{n}[{i}]==0",
                    z3.Extract(i, i, s) == z3.BitVecVal(0, 1))

    pair_budget = max_pairwise
    by_width: dict[int, list[z3.ExprRef]] = {}
    for s in _bv_states(ts):
        by_width.setdefault(s.sort().size(), []).append(s)
    for w, group in sorted(by_width.items()):
        for a, b in itertools.combinations(group, 2):
            if pair_budget <= 0:
                break
            na, nb = a.decl().name(), b.decl().name()
            add(f"{na}<={nb}", z3.ULE(a, b))
            add(f"{nb}<={na}", z3.ULE(b, a))
            add(f"{na}!={nb}", a != b)
            pair_budget -= 3
    return cands, labels


# ---------------------------------------------------------------- LLM lemmas

_INV_SYSTEM = """You are a formal verification expert helping prove safety \
properties of hardware designs by inductive invariant synthesis. You propose \
candidate invariants over the design's registers. Unsound candidates are \
automatically discarded by a Houdini fixpoint, so propose generously; but \
each candidate must be well-formed. Respond ONLY with a JSON array of \
candidate objects, no prose."""

_INV_USER = """Design (SystemVerilog):
```systemverilog
{source}
```

Safety properties are the `assert` statements above. Induction failed at \
k={k}; the property is not inductive on its own. Registers visible to the \
prover (name: width): {statelist}

Propose up to {n} candidate invariants as a JSON array. Each candidate uses \
this DSL (all values refer to register names from the list above):
  {{"kind": "ule", "a": "<reg or int>", "b": "<reg or int>"}}       // a <= b (unsigned)
  {{"kind": "eq"|"ne", "a": ..., "b": ...}}
  {{"kind": "implies", "if": <candidate>, "then": <candidate>}}
  {{"kind": "onehot"|"onehot0", "a": "<reg>"}}
  {{"kind": "bit", "a": "<reg>", "i": <bit index>, "v": 0|1}}       // a[i] == v
  {{"kind": "in", "a": "<reg>", "vals": [<ints>]}}                  // a ∈ vals
Focus on: FSM state validity, counter bounds tied to buffer sizes, \
relationships between pointers/counters, flags that guard datapath state."""


def _compile_dsl(item: dict, env: dict[str, z3.ExprRef]) -> z3.BoolRef | None:
    def operand(x, width_hint: int | None = None):
        if isinstance(x, int):
            return z3.BitVecVal(x, width_hint or 32)
        v = env.get(str(x))
        return v

    k = item.get("kind")
    if k in ("ule", "eq", "ne"):
        a, b = item.get("a"), item.get("b")
        av = operand(a) if not isinstance(a, int) else None
        bv = operand(b) if not isinstance(b, int) else None
        ref = av if av is not None else bv
        if ref is None:
            return None
        w = ref.sort().size()
        av = av if av is not None else z3.BitVecVal(int(a), w)
        bv = bv if bv is not None else z3.BitVecVal(int(b), w)
        if av.sort() != bv.sort():
            wa, wb = av.sort().size(), bv.sort().size()
            if wa < wb:
                av = z3.ZeroExt(wb - wa, av)
            else:
                bv = z3.ZeroExt(wa - wb, bv)
        return {"ule": z3.ULE, "eq": lambda x, y: x == y,
                "ne": lambda x, y: x != y}[k](av, bv)
    if k == "implies":
        a = _compile_dsl(item.get("if", {}), env)
        b = _compile_dsl(item.get("then", {}), env)
        return z3.Implies(a, b) if a is not None and b is not None else None
    if k in ("onehot", "onehot0"):
        v = env.get(str(item.get("a")))
        if v is None or v.sort().size() > 32:
            return None
        w = v.sort().size()
        pop = sum(z3.ZeroExt(6, z3.Extract(i, i, v)) for i in range(w))
        one = z3.BitVecVal(1, 7)
        return pop == one if k == "onehot" else z3.ULE(pop, one)
    if k == "bit":
        v = env.get(str(item.get("a")))
        i = item.get("i")
        if v is None or not isinstance(i, int) or i >= v.sort().size():
            return None
        return z3.Extract(i, i, v) == z3.BitVecVal(int(item.get("v", 0)) & 1, 1)
    if k == "in":
        v = env.get(str(item.get("a")))
        vals = item.get("vals")
        if v is None or not isinstance(vals, list):
            return None
        w = v.sort().size()
        return z3.Or([v == z3.BitVecVal(int(x) & ((1 << w) - 1), w) for x in vals])
    return None


def llm_candidates(ts: TransitionSystem, source: str, k_failed: int,
                   max_candidates: int = 40) -> tuple[list[z3.BoolRef], list[str]]:
    """Ask the LLM for candidate invariants; compile the JSON DSL to Z3.

    Returns ([], []) when the LLM is unavailable or the response is
    unusable — callers fall back to the template candidates alone.
    """
    if not llm.llm_enabled():
        return [], []
    env = {s.decl().name(): s for s in _bv_states(ts)}
    # Netlist register names look like \fifo.count — expose both spellings.
    for name, v in list(env.items()):
        env[name.lstrip("\\").split(".")[-1]] = v
    statelist = ", ".join(f"{s.decl().name()}: {s.sort().size()}"
                          for s in _bv_states(ts))
    try:
        resp = llm.chat(_INV_SYSTEM,
                        _INV_USER.format(source=source[:20000], k=k_failed,
                                         statelist=statelist, n=max_candidates))
        items = llm.extract_json_block(resp)
    except (llm.LLMUnavailable, ValueError):
        return [], []
    cands, labels = [], []
    if not isinstance(items, list):
        return [], []
    for i, item in enumerate(items[:max_candidates]):
        if not isinstance(item, dict):
            continue
        try:
            e = _compile_dsl(item, env)
        except (z3.Z3Exception, TypeError, ValueError):
            e = None
        if e is not None:
            cands.append(e)
            labels.append(f"llm{i}:{item.get('kind')}")
    return cands, labels
