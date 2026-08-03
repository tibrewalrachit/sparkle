"""Full-SoC convergence: prove the property set and render the evidence.

"Convergence" for a DV team means: every property has a disposition
(proven / bounded / falsified / vacuous), the property set demonstrably
covers the design, and the whole claim is auditable. This module produces
that dossier (`CONVERGENCE.md` + `convergence.json`):

  * per-property disposition with method and certificate
    (k-induction depth, #invariant lemmas, or a Verilator-confirmed trace);
  * **proof radius** for every non-proven property (deepest clean BMC bound
    — the industry-standard bounded-proof claim);
  * **cone-of-influence coverage**: the fraction of the design's state bits
    that lie in the COI of at least one *proven* property. Registers outside
    every COI are listed by name — that is the DV team's to-do list, not a
    hidden gap;
  * assumption audit: every `constraint` (SV `assume`) in force, since a
    proof is only as strong as its environment assumptions;
  * synthesis provenance: which properties were user-written, structurally
    mined, or LLM-proposed (and that all three passed identical checking).
"""

from __future__ import annotations

import copy
import json
import time
from dataclasses import dataclass, field
from pathlib import Path

import z3

from . import frontend
from .btor2 import TransitionSystem, parse_btor2
from .cex import replay
from .engine import Engine, Verdict
from .invariants import template_candidates
from .properties import (PropertySet, SynthProperty, instrument_sv,
                         llm_properties, mine_structural, screen_tautology)


@dataclass
class PropResult:
    name: str
    origin: str
    description: str
    disposition: str        # "proven" | "bounded" | "falsified" | "vacuous" | "error"
    method: str = ""
    depth: int = 0          # k / proof radius / cex depth
    time_s: float = 0.0
    certificate: str = ""
    coi_bits: int = 0
    coi_regs: list[str] = field(default_factory=list)
    verilator_confirmed: bool | None = None


def _single_bad_ts(ts: TransitionSystem, name: str,
                   bad: z3.BoolRef) -> TransitionSystem:
    one = copy.copy(ts)
    one.bads = [(name, bad)]
    return one


def _coi(ts: TransitionSystem, root: z3.BoolRef) -> list[str]:
    """Transitive cone of influence: state vars syntactically reachable from
    `root` through the transition functions."""
    state_names = {s.decl().name(): s for s in ts.states}

    def vars_of(e: z3.ExprRef) -> set[str]:
        out: set[str] = set()
        stack = [e]
        seen: set[int] = set()
        while stack:
            x = stack.pop()
            if x.get_id() in seen:
                continue
            seen.add(x.get_id())
            if z3.is_const(x) and x.decl().name() in state_names:
                out.add(x.decl().name())
            stack.extend(x.children())
        return out

    frontier = vars_of(root)
    coi: set[str] = set()
    while frontier:
        n = frontier.pop()
        if n in coi:
            continue
        coi.add(n)
        nxt = ts.next_fn.get(n)
        if nxt is not None:
            frontier |= vars_of(nxt) - coi
    return sorted(coi)


def _bits(ts: TransitionSystem, names: list[str]) -> int:
    by = {s.decl().name(): s for s in ts.states}
    total = 0
    for n in names:
        s = by.get(n)
        if s is not None and isinstance(s.sort(), z3.BitVecSortRef):
            total += s.sort().size()
    return total


def check_property(ts: TransitionSystem, name: str, bad: z3.BoolRef,
                   prop: SynthProperty | None, design_file: Path, top: str,
                   out_dir: Path, max_bmc: int, max_k: int,
                   timeout_s: float, do_replay: bool = True) -> PropResult:
    origin = prop.origin if prop else "user"
    desc = prop.description if prop else ts.name_src.get(name, name)
    coi = _coi(ts, bad)
    pr = PropResult(name=name, origin=origin, description=desc,
                    disposition="error", coi_bits=_bits(ts, coi),
                    coi_regs=coi)
    if screen_tautology(z3.Not(bad)):
        pr.disposition = "vacuous"
        pr.certificate = "property is a tautology (holds in ALL states, " \
                         "reachable or not) — no design coverage"
        return pr
    one = _single_bad_ts(ts, name, bad)
    eng = Engine(one)
    cands, labels = template_candidates(one)
    t0 = time.monotonic()
    v: Verdict = eng.prove(max_bmc=max_bmc, max_k=max_k, candidates=cands,
                           labels=labels, timeout_s=timeout_s)
    pr.time_s = time.monotonic() - t0
    pr.method = v.method
    pr.depth = v.depth
    if v.status == "SAFE":
        pr.disposition = "proven"
        pr.certificate = (f"{v.depth}-inductive" if v.method == "kind"
                          else f"inductive invariant, "
                               f"{len(v.invariant or [])} lemmas")
        if v.invariant:
            (out_dir / f"invariant_{name}.smt2.txt").write_text(
                "\n".join(v.invariant))
    elif v.status == "BUG":
        if origin == "mined":
            # A falsified mined property is a rejected conjecture, not a
            # design bug: mining proposes, the prover disposes.
            pr.disposition = "discarded"
            pr.certificate = f"conjecture refuted at cycle {v.depth}"
        else:
            pr.disposition = "falsified"
            pr.certificate = f"counterexample at cycle {v.depth}"
            if v.trace and do_replay:
                rr = replay(v.trace, top, design_file,
                            out_dir / f"replay_{name}")
                pr.verilator_confirmed = rr.confirmed
    else:
        pr.disposition = "bounded"
        pr.certificate = f"proof radius {v.depth} (no violation within " \
                         f"{v.depth} cycles); {v.detail[:120]}"
    return pr


def converge(sv_path: Path, top: str, out_dir: Path,
             max_bmc: int = 40, max_k: int = 10, timeout_s: float = 300.0,
             use_llm: bool = True, mine: bool = True,
             max_mined: int = 40) -> dict:
    """Synthesize the SoC property set, prove it, and write the dossier."""
    out_dir.mkdir(parents=True, exist_ok=True)
    notes: list[str] = []

    # LLM properties instrument the source, so they must be merged before
    # elaboration; mined properties attach to the transition system directly.
    design = sv_path
    llm_ps = PropertySet()
    if use_llm:
        llm_ps = llm_properties(sv_path.read_text(), top)
        notes += llm_ps.notes
        if llm_ps.props:
            design, kept = instrument_sv(sv_path, llm_ps.props,
                                         out_dir / f"{sv_path.stem}.props.sv",
                                         top)
            notes.append(f"instrumented {len(kept)}/{len(llm_ps.props)} "
                         f"LLM properties (rest failed elaboration)")
            llm_ps.props = kept

    comp = frontend.compile_sv(design, top, out_dir)
    ts = parse_btor2(comp.btor2_file)
    stats = ts.stats()

    mined = mine_structural(ts, max_props=max_mined) if mine else PropertySet()
    notes += mined.notes

    by_origin: dict[str, SynthProperty | None] = {}
    work: list[tuple[str, z3.BoolRef, SynthProperty | None]] = []
    for name, bad in ts.bads:
        sp = next((p for p in llm_ps.props if f"SPROP:{p.name}" in
                   ts.name_src.get(name, "") or p.name in name), None)
        work.append((name, bad, sp))
    for p in mined.props:
        work.append((p.name, z3.Not(p.expr), p))

    results: list[PropResult] = []
    for name, bad, sp in work:
        pr = check_property(ts, name, bad, sp, comp.sv_file, top, out_dir,
                            max_bmc, max_k, timeout_s)
        results.append(pr)
        print(f"  {pr.disposition:9s} [{pr.origin:5s}] {name:40s} "
              f"{pr.method:12s} d={pr.depth:<4d} {pr.time_s:6.1f}s")

    proven = [r for r in results if r.disposition == "proven"]
    covered: set[str] = set()
    for r in proven:
        covered |= set(r.coi_regs)
    all_regs = [s.decl().name() for s in ts.states]
    uncovered = sorted(set(all_regs) - covered)
    cov_bits = _bits(ts, sorted(covered))
    tot_bits = stats["state_bits"]

    dossier = {
        "design": str(sv_path), "top": top, "model": stats,
        "assumption_audit": [str(c) for c in ts.constraints],
        "properties": [vars(r) for r in results],
        "summary": {
            "total": len(results),
            "proven": len(proven),
            "bounded": sum(r.disposition == "bounded" for r in results),
            "falsified": sum(r.disposition == "falsified" for r in results),
            "vacuous": sum(r.disposition == "vacuous" for r in results),
            "discarded": sum(r.disposition == "discarded" for r in results),
            "coi_coverage_bits": cov_bits,
            "state_bits": tot_bits,
            "coi_coverage_pct": round(100 * cov_bits / tot_bits, 1)
            if tot_bits else 0.0,
            "uncovered_registers": uncovered[:100],
        },
        "notes": notes,
    }
    (out_dir / "convergence.json").write_text(
        json.dumps(dossier, indent=2, default=str))
    render_dossier(dossier, out_dir / "CONVERGENCE.md")
    return dossier


def render_dossier(d: dict, out_file: Path) -> str:
    s = d["summary"]
    lines = [
        f"# Formal convergence dossier — `{d['top']}`", "",
        f"Design: `{d['design']}`  ",
        f"Model: {d['model']['states']} state elements "
        f"({d['model']['state_bits']} bits, {d['model']['arrays']} memories), "
        f"{d['model']['inputs']} inputs", "",
        "## Convergence summary", "",
        "| total | proven (unbounded) | bounded | falsified | vacuous | discarded conjectures |",
        "|---|---|---|---|---|---|",
        f"| {s['total']} | **{s['proven']}** | {s['bounded']} "
        f"| {s['falsified']} | {s['vacuous']} | {s.get('discarded', 0)} |", "",
        f"**Cone-of-influence coverage of proven properties: "
        f"{s['coi_coverage_pct']}%** of state bits "
        f"({s['coi_coverage_bits']}/{s['state_bits']}).", "",
        "A property is *proven* only with an unbounded certificate "
        "(k-induction or an inductive invariant re-checked by Z3). "
        "*Bounded* properties report their proof radius explicitly. "
        "*Falsified* properties ship a counterexample trace and, where "
        "marked, a Verilator-confirmed replay. *Vacuous* properties are "
        "tautologies contributing no coverage and are excluded from the "
        "convergence claim.", "",
        "## Per-property dispositions", "",
        "| property | origin | disposition | method | depth | COI bits | evidence |",
        "|---|---|---|---|---|---|---|",
    ]
    for p in d["properties"]:
        vc = ({"True": " (Verilator ✓)", "False": " (Verilator ✗)"}
              .get(str(p.get("verilator_confirmed")), ""))
        icon = {"proven": "✅", "bounded": "🟡", "falsified": "❌",
                "vacuous": "⚪", "discarded": "🗑️",
                "error": "⚠️"}[p["disposition"]]
        lines.append(
            f"| {p['name'][:48]} | {p['origin']} | {icon} {p['disposition']} "
            f"| {p['method'] or '—'} | {p['depth']} | {p['coi_bits']} "
            f"| {p['certificate'][:90]}{vc} |")
    lines += ["", "## Assumption audit", ""]
    if d["assumption_audit"]:
        lines += ["The following environment assumptions are in force; every "
                  "proof above is relative to them:", ""]
        lines += [f"- `{a}`" for a in d["assumption_audit"]]
    else:
        lines.append("No environment assumptions (`assume`) — all proofs are "
                     "unconditional over the free inputs.")
    lines += ["", "## Coverage gaps (DV to-do list)", ""]
    if s["uncovered_registers"]:
        lines += [f"{len(s['uncovered_registers'])} registers are outside the "
                  "COI of every proven property:", ""]
        lines += [f"- `{r}`" for r in s["uncovered_registers"][:40]]
        if len(s["uncovered_registers"]) > 40:
            lines.append(f"- … and {len(s['uncovered_registers']) - 40} more "
                         f"(see convergence.json)")
    else:
        lines.append("Every register lies in the cone of influence of at "
                     "least one proven property.")
    lines += ["", "## Synthesis provenance", ""]
    lines += [f"- {n}" for n in d["notes"]] or ["- all properties user-written"]
    lines += ["", "---", "*Generated by sparkle-fv `converge`. All "
              "certificates are machine-re-checkable: invariants in "
              "`invariant_*.smt2.txt`, traces in `replay_*/trace.json` with "
              "matching Verilator testbenches.*"]
    text = "\n".join(lines) + "\n"
    out_file.write_text(text)
    return text
