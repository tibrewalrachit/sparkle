"""Proof engine: BMC, k-induction, and Houdini invariant synthesis on Z3.

The engine works on the `TransitionSystem` produced by `btor2.py` and
implements a portfolio in the spirit of "everyday provers": every verdict
comes with an inspectable artifact —

  * BUG    -> a concrete counterexample trace (inputs + initial state per
              frame) that `cex.py` turns into a Verilator-runnable testbench;
  * SAFE   -> either a k-induction certificate (base + step depth) or an
              inductive invariant (conjunction of surviving candidate
              lemmas from Houdini), each re-checked by Z3;
  * UNKNOWN-> the bound reached, so the caller can escalate (deeper BMC,
              more candidate lemmas from the AI layer, or a Lean obligation).
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

import z3

from .btor2 import TransitionSystem


@dataclass
class Trace:
    """Counterexample: per-frame assignments extracted from a Z3 model."""

    depth: int
    inputs: list[dict[str, int]]        # frame -> input name -> value
    states0: dict[str, int]             # initial state assignment (frame 0)
    bad_name: str
    bad_frame: int
    input_widths: dict[str, int] = field(default_factory=dict)


@dataclass
class Verdict:
    status: str                          # "SAFE" | "BUG" | "UNKNOWN"
    method: str                          # "bmc" | "kind" | "houdini" | ...
    depth: int                           # bound reached / cex depth / k
    time_s: float
    trace: Trace | None = None
    invariant: list[str] | None = None   # surviving lemmas (SMT-LIB strings)
    detail: str = ""


def _model_val(model: z3.ModelRef, var: z3.ExprRef) -> int:
    v = model.eval(var, model_completion=True)
    if z3.is_bv_value(v):
        return v.as_long()
    if z3.is_true(v):
        return 1
    if z3.is_false(v):
        return 0
    return 0  # arrays / unhandled: not replayed


class Engine:
    def __init__(self, ts: TransitionSystem, zero_init_free_states: bool = True,
                 verbose: bool = False):
        self.ts = ts
        self.zero_init = zero_init_free_states
        self.verbose = verbose

    # ------------------------------------------------------------------ BMC
    def bmc(self, max_depth: int, timeout_s: float = 600.0,
            start_depth: int = 0) -> Verdict:
        """Incremental bounded model checking up to `max_depth` frames."""
        t0 = time.monotonic()
        s = z3.Solver()
        s.set("timeout", int(timeout_s * 1000))
        for f in self.ts.init_at(0):
            s.add(f)
        if self.zero_init:
            for st in self.ts.uninit_states:
                if isinstance(st.sort(), z3.BitVecSortRef):
                    s.add(self.ts.expr_at(st, 0) == z3.BitVecVal(0, st.sort().size()))
        depth = 0
        for k in range(0, max_depth + 1):
            depth = k
            for f in self.ts.constraints_at(k):
                s.add(f)
            if k >= start_depth:
                for name, bad in self.ts.bads_at(k):
                    if time.monotonic() - t0 > timeout_s:
                        return Verdict("UNKNOWN", "bmc", k, time.monotonic() - t0,
                                       detail="timeout")
                    s.push()
                    s.add(bad)
                    r = s.check()
                    if r == z3.sat:
                        trace = self._extract_trace(s.model(), k, name)
                        s.pop()
                        return Verdict("BUG", "bmc", k, time.monotonic() - t0,
                                       trace=trace,
                                       detail=f"assertion '{name}' fails at cycle {k}")
                    s.pop()
                    if r == z3.unknown:
                        return Verdict("UNKNOWN", "bmc", k, time.monotonic() - t0,
                                       detail="solver unknown")
            if k < max_depth:
                for f in self.ts.trans_at(k):
                    s.add(f)
            if self.verbose:
                print(f"  bmc: depth {k} clean ({time.monotonic() - t0:.1f}s)")
            if time.monotonic() - t0 > timeout_s:
                return Verdict("UNKNOWN", "bmc", k, time.monotonic() - t0,
                               detail="timeout")
        return Verdict("UNKNOWN", "bmc", depth, time.monotonic() - t0,
                       detail=f"no violation within bound {max_depth}")

    def _extract_trace(self, model: z3.ModelRef, depth: int, bad_name: str) -> Trace:
        inputs = []
        for f in range(depth + 1):
            frame = {i.decl().name(): _model_val(model, self.ts.expr_at(i, f))
                     for i in self.ts.inputs}
            inputs.append(frame)
        states0 = {s.decl().name(): _model_val(model, self.ts.expr_at(s, 0))
                   for s in self.ts.states
                   if isinstance(s.sort(), z3.BitVecSortRef)}
        widths = {i.decl().name(): i.sort().size() for i in self.ts.inputs
                  if isinstance(i.sort(), z3.BitVecSortRef)}
        return Trace(depth, inputs, states0, bad_name, depth, widths)

    # ---------------------------------------------------------- k-induction
    def k_induction(self, max_k: int, timeout_s: float = 600.0,
                    simple_path: bool = True) -> Verdict:
        """Base case (BMC) + inductive step with optional simple-path constraint.

        Proves all bad states unreachable if for some k: no cex of length <= k
        (base) and any k-step path of safe states cannot reach a bad state
        (step).
        """
        t0 = time.monotonic()
        for k in range(1, max_k + 1):
            remaining = timeout_s - (time.monotonic() - t0)
            if remaining <= 0:
                return Verdict("UNKNOWN", "kind", k - 1, time.monotonic() - t0,
                               detail="timeout")
            base = self.bmc(k - 1, timeout_s=remaining, start_depth=max(0, k - 2))
            if base.status == "BUG":
                base.method = "kind-base"
                return base
            if base.status == "UNKNOWN" and base.detail in ("timeout", "solver unknown"):
                return Verdict("UNKNOWN", "kind", k, time.monotonic() - t0,
                               detail=f"base case: {base.detail}")

            s = z3.Solver()
            remaining = timeout_s - (time.monotonic() - t0)
            if remaining <= 0:
                return Verdict("UNKNOWN", "kind", k, time.monotonic() - t0,
                               detail="timeout")
            s.set("timeout", int(remaining * 1000))
            for f in range(k + 1):
                for c in self.ts.constraints_at(f):
                    s.add(c)
                if f < k:
                    for c in self.ts.trans_at(f):
                        s.add(c)
                    for _, bad in self.ts.bads_at(f):
                        s.add(z3.Not(bad))
            if simple_path and not any(z3.is_array(st) for st in self.ts.states):
                for f1 in range(k + 1):
                    for f2 in range(f1 + 1, k + 1):
                        diff = [self.ts.expr_at(st, f1) != self.ts.expr_at(st, f2)
                                for st in self.ts.states]
                        if diff:
                            s.add(z3.Or(diff))
            s.add(z3.Or([bad for _, bad in self.ts.bads_at(k)]))
            r = s.check()
            if r == z3.unsat:
                return Verdict("SAFE", "kind", k, time.monotonic() - t0,
                               detail=f"{k}-inductive")
            if r == z3.unknown:
                return Verdict("UNKNOWN", "kind", k, time.monotonic() - t0,
                               detail="solver unknown in step case")
            if self.verbose:
                print(f"  kind: k={k} step case SAT, increasing k")
        return Verdict("UNKNOWN", "kind", max_k, time.monotonic() - t0,
                       detail=f"not inductive up to k={max_k}")

    # -------------------------------------------------------------- Houdini
    def houdini(self, candidates: list[z3.BoolRef], timeout_s: float = 600.0,
                labels: list[str] | None = None) -> Verdict:
        """Greatest inductive subset of `candidates`, then property check.

        The negated bad states are added as candidates themselves: if they
        survive the fixpoint, the surviving conjunction is an inductive
        invariant that implies safety — a machine-checked proof artifact.
        """
        t0 = time.monotonic()
        labels = labels or [f"c{i}" for i in range(len(candidates))]
        cands = list(zip(labels, candidates))
        for name, bad in self.ts.bads:
            cands.append((f"safe[{name}]", z3.Not(bad)))

        # Filter: must hold in all initial states.
        s0 = z3.Solver()
        s0.set("timeout", int(timeout_s * 1000 / 4))
        for f in self.ts.init_at(0):
            s0.add(f)
        if self.zero_init:
            for st in self.ts.uninit_states:
                if isinstance(st.sort(), z3.BitVecSortRef):
                    s0.add(self.ts.expr_at(st, 0) == z3.BitVecVal(0, st.sort().size()))
        for c in self.ts.constraints_at(0):
            s0.add(c)
        surviving = []
        for lbl, c in cands:
            s0.push()
            s0.add(z3.Not(self.ts.expr_at(c, 0)))
            if s0.check() == z3.unsat:
                surviving.append((lbl, c))
            s0.pop()
            if time.monotonic() - t0 > timeout_s:
                return Verdict("UNKNOWN", "houdini", 0, time.monotonic() - t0,
                               detail="timeout in init filtering")

        # Fixpoint: drop candidates not preserved by one transition.
        rounds = 0
        while True:
            rounds += 1
            s = z3.Solver()
            s.set("timeout", int(max(1.0, timeout_s - (time.monotonic() - t0)) * 1000))
            for c in self.ts.constraints_at(0) + self.ts.constraints_at(1):
                s.add(c)
            for c in self.ts.trans_at(0):
                s.add(c)
            for _, c in surviving:
                s.add(self.ts.expr_at(c, 0))
            s.add(z3.Or([z3.Not(self.ts.expr_at(c, 1)) for _, c in surviving]
                        or [z3.BoolVal(False)]))
            r = s.check()
            if r == z3.unsat:
                break  # fixpoint: all surviving candidates are inductive
            if r == z3.unknown:
                return Verdict("UNKNOWN", "houdini", rounds, time.monotonic() - t0,
                               detail="solver unknown in fixpoint")
            m = s.model()
            dropped = [lbl for lbl, c in surviving
                       if z3.is_false(m.eval(self.ts.expr_at(c, 1),
                                             model_completion=True))]
            if not dropped:
                # Defensive: drop everything violated in the post-state model.
                dropped = [lbl for lbl, c in surviving
                           if not z3.is_true(m.eval(self.ts.expr_at(c, 1),
                                                    model_completion=True))]
            if not dropped:
                return Verdict("UNKNOWN", "houdini", rounds, time.monotonic() - t0,
                               detail="fixpoint stalled")
            surviving = [(lbl, c) for lbl, c in surviving if lbl not in dropped]
            if self.verbose:
                print(f"  houdini: round {rounds}, dropped {len(dropped)}, "
                      f"{len(surviving)} remain")
            if time.monotonic() - t0 > timeout_s:
                return Verdict("UNKNOWN", "houdini", rounds, time.monotonic() - t0,
                               detail="timeout in fixpoint")

        safe_lbls = {f"safe[{name}]" for name, _ in self.ts.bads}
        have = {lbl for lbl, _ in surviving}
        if safe_lbls <= have:
            inv = [f"({lbl}) {c.sexpr()}" for lbl, c in surviving]
            return Verdict("SAFE", "houdini", rounds, time.monotonic() - t0,
                           invariant=inv,
                           detail=f"inductive invariant with {len(surviving)} lemmas")
        return Verdict("UNKNOWN", "houdini", rounds, time.monotonic() - t0,
                       detail=f"safety lemma not inductive relative to "
                              f"{len(surviving)} surviving candidates")

    # ------------------------------------------------------------ portfolio
    def prove(self, max_bmc: int = 60, max_k: int = 12,
              candidates: list[z3.BoolRef] | None = None,
              labels: list[str] | None = None,
              timeout_s: float = 600.0) -> Verdict:
        """Portfolio: BMC for bugs, then k-induction, then Houdini.

        Returns the first conclusive verdict; UNKNOWN only if everything
        is inconclusive within the budget.
        """
        t0 = time.monotonic()
        budget = timeout_s / 3
        v = self.bmc(max_bmc, timeout_s=budget)
        if v.status == "BUG":
            return v
        rem = timeout_s - (time.monotonic() - t0)
        vk = self.k_induction(max_k, timeout_s=max(rem / 2, 5.0))
        if vk.status in ("SAFE", "BUG"):
            return vk
        if candidates:
            rem = timeout_s - (time.monotonic() - t0)
            vh = self.houdini(candidates, timeout_s=max(rem, 5.0), labels=labels)
            if vh.status == "SAFE":
                return vh
            vh.detail += f" | bmc clean to {v.depth}; {vk.detail}"
            vh.depth = v.depth
            return vh
        vk.detail += f" | bmc clean to {v.depth}"
        return vk
