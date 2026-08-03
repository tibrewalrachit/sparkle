"""Benchmark runner: sparkle-fv vs yosys-smtbmc on the benchmark suite.

Each benchmark directory contains `meta.json` (see benchmarks/README) with a
safe variant and one or more seeded-bug variants.  For every variant we run:

  * sparkle-fv  — the agentic portfolio (BMC + k-induction + Houdini
                  [+ LLM lemmas when OPENROUTER_API_KEY is set]), and on
                  every BUG verdict, Verilator replay confirmation;
  * yosys-smtbmc — BMC + temporal induction on the identical Yosys
                  elaboration (the engine behind SymbiYosys).

Scoring: a tool "solves" a variant when it returns the expected verdict
(BUG for bug variants, SAFE for safe variants; for safe variants a bounded
`no violation up to depth N` counts as `bounded` only, not solved).
Outputs machine-readable results.json and a markdown report with per-design
and aggregate comparisons plus a scalability section (time vs state bits).
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import frontend
from .agent import prove_property, repair_frontend
from .baselines import BaselineResult, smtbmc_portfolio
from .btor2 import parse_btor2
from .cex import replay
from .engine import Engine


@dataclass
class VariantResult:
    bench: str
    variant: str
    expect: str
    category: str
    state_bits: int
    sparkle: dict = field(default_factory=dict)
    baseline: dict = field(default_factory=dict)


def discover(bench_root: Path) -> list[Path]:
    return sorted(p.parent for p in bench_root.rglob("meta.json"))


def run_variant(bench_dir: Path, meta: dict, variant: dict, out_root: Path,
                timeout_s: float, max_bmc: int, max_k: int,
                use_llm: bool, verbose: bool = False) -> VariantResult:
    top = meta["top"]
    sv = bench_dir / variant["file"]
    expect = variant["expect"]
    name = f"{bench_dir.name}/{variant['file']}"
    out_dir = out_root / bench_dir.name / Path(variant["file"]).stem
    out_dir.mkdir(parents=True, exist_ok=True)
    vr = VariantResult(bench=bench_dir.name, variant=variant["file"],
                       expect=expect, category=meta.get("category", "?"),
                       state_bits=meta.get("state_bits", 0))

    # --- sparkle-fv ------------------------------------------------------
    try:
        comp = repair_frontend(sv, top, out_dir)
        ts = parse_btor2(comp.btor2_file)
        vr.state_bits = ts.stats()["state_bits"] or vr.state_bits
        eng = Engine(ts, verbose=verbose)
        t0 = time.monotonic()
        v = prove_property(eng, sv.read_text(), max_bmc=max_bmc, max_k=max_k,
                           timeout_s=timeout_s, use_llm=use_llm,
                           verbose=verbose)
        dt = time.monotonic() - t0
        vr.sparkle = {"status": v.status, "method": v.method,
                      "depth": v.depth, "time_s": round(dt, 3),
                      "detail": v.detail[:200]}
        if v.status == "BUG" and v.trace is not None:
            rr = replay(v.trace, top, comp.sv_file, out_dir / "replay",
                        source_label=str(sv))
            vr.sparkle["verilator_confirmed"] = rr.confirmed
        solved = (v.status == "BUG" and expect == "bug") or \
                 (v.status == "SAFE" and expect == "safe")
        vr.sparkle["solved"] = solved
        if expect == "safe" and v.status == "UNKNOWN":
            vr.sparkle["bounded_depth"] = v.depth
    except Exception as e:
        vr.sparkle = {"status": "ERROR", "detail": f"{type(e).__name__}: {e}",
                      "solved": False, "time_s": 0.0}

    # --- baseline ---------------------------------------------------------
    try:
        smt2 = out_dir / f"{top}.smt2"
        if not smt2.exists():
            comp = frontend.compile_sv(sv, top, out_dir)
            smt2 = comp.smt2_file
        b: BaselineResult = smtbmc_portfolio(smt2, bmc_depth=max_bmc,
                                             ind_depth=max_k,
                                             timeout_s=timeout_s)
        solved = (b.status == "BUG" and expect == "bug") or \
                 (b.status == "SAFE" and expect == "safe")
        vr.baseline = {"tool": b.tool, "status": b.status, "depth": b.depth,
                       "time_s": round(b.time_s, 3),
                       "max_rss_mb": round(b.max_rss_mb, 1),
                       "solved": solved}
    except Exception as e:
        vr.baseline = {"status": "ERROR", "detail": f"{type(e).__name__}: {e}",
                       "solved": False, "time_s": 0.0}
    print(f"  {name:45s} expect={expect:4s} "
          f"sparkle={vr.sparkle.get('status'):8s}"
          f"[{vr.sparkle.get('method', '-'):12s}] "
          f"{vr.sparkle.get('time_s', 0):7.2f}s  "
          f"smtbmc={vr.baseline.get('status', '?'):8s} "
          f"{vr.baseline.get('time_s', 0):7.2f}s")
    return vr


def run_suite(bench_root: Path, out_root: Path, timeout_s: float = 300.0,
              max_bmc: int = 40, max_k: int = 12, use_llm: bool = True,
              only: str | None = None, verbose: bool = False) -> list[VariantResult]:
    results: list[VariantResult] = []
    for bench_dir in discover(bench_root):
        if only and only not in bench_dir.name:
            continue
        meta = json.loads((bench_dir / "meta.json").read_text())
        variants = [dict(meta["safe"])] + list(meta.get("bugs", []))
        print(f"[{bench_dir.name}] ({meta.get('category')}, "
              f"~{meta.get('state_bits', '?')} state bits)")
        for variant in variants:
            results.append(run_variant(bench_dir, meta, variant, out_root,
                                       timeout_s, max_bmc, max_k, use_llm,
                                       verbose))
    out_root.mkdir(parents=True, exist_ok=True)
    (out_root / "results.json").write_text(json.dumps(
        [vars(r) for r in results], indent=2, default=str))
    return results


def render_report(results: list[VariantResult], out_file: Path,
                  config: dict) -> str:
    """Markdown comparison report."""
    def agg(key):
        sel = [r for r in results if "solved" in getattr(r, key)]
        solved = sum(1 for r in sel if getattr(r, key)["solved"])
        t = sum(getattr(r, key).get("time_s", 0) for r in sel)
        return solved, len(sel), t

    ssolved, stot, stime = agg("sparkle")
    bsolved, btot, btime = agg("baseline")

    lines = ["# sparkle-fv evaluation report", "",
             f"Config: `{json.dumps(config)}`", "",
             "## Aggregate",
             "",
             "| tool | solved | total | wall time (s) |",
             "|---|---|---|---|",
             f"| **sparkle-fv** (BMC+k-ind+Houdini) | {ssolved} | {stot} | {stime:.1f} |",
             f"| yosys-smtbmc (BMC+ind, SymbiYosys engine) | {bsolved} | {btot} | {btime:.1f} |",
             "",
             "## Per-variant results",
             "",
             "| benchmark | variant | expect | state bits | sparkle-fv | method | t(s) | verilator | smtbmc | t(s) |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        s, b = r.sparkle, r.baseline
        vc = s.get("verilator_confirmed")
        vc_s = "✓" if vc else ("✗" if vc is False else "—")
        mark_s = "✅" if s.get("solved") else ("➖" if s.get("status") == "UNKNOWN" else "❌")
        mark_b = "✅" if b.get("solved") else ("➖" if b.get("status") == "UNKNOWN" else "❌")
        lines.append(
            f"| {r.bench} | {r.variant} | {r.expect} | {r.state_bits} "
            f"| {mark_s} {s.get('status')} | {s.get('method', '-')} "
            f"| {s.get('time_s', 0):.2f} | {vc_s} "
            f"| {mark_b} {b.get('status')} | {b.get('time_s', 0):.2f} |")

    lines += ["", "## Scalability (time vs design size)", "",
              "| benchmark | state bits | sparkle-fv t(s) | smtbmc t(s) |",
              "|---|---|---|---|"]
    for r in sorted(results, key=lambda r: r.state_bits):
        lines.append(f"| {r.bench}/{r.variant} | {r.state_bits} "
                     f"| {r.sparkle.get('time_s', 0):.2f} "
                     f"| {r.baseline.get('time_s', 0):.2f} |")
    text = "\n".join(lines) + "\n"
    out_file.write_text(text)
    return text
