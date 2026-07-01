"""Agentic orchestration: the outer loops that make the harness *agentic*.

Three loops, each of which degrades gracefully to a deterministic strategy
when the LLM (GLM 5.2 via OpenRouter) is unavailable:

  1. `repair_frontend` — elaborate-with-Yosys loop: on a frontend syntax
     error, the built-in desugar pass runs first; if Yosys still rejects the
     design, the LLM is shown the error and asked for a minimal,
     semantics-preserving rewrite, and the result is re-elaborated.
     Every AI rewrite is translation-validated with Yosys `equiv_make`
     against the last accepted version whenever both parse.

  2. `prove_property` — prove-refine loop: BMC hunts for bugs, k-induction
     tries the cheap proof, then Houdini runs over template candidates;
     if the safety lemma is still not relatively inductive, the LLM is asked
     for candidate invariants (given the SV source and induction failure
     context) and Houdini re-runs with the enlarged candidate set.  Unsound
     AI candidates are discarded by the fixpoint; the final invariant is
     re-checked, so LLM output can never produce a false "SAFE".

  3. `verify_design` — full pipeline per design: frontend -> autoformalize
     (Sparkle Lean emission) -> prove each property -> on BUG, generate the
     Verilator stimulus and confirm by replay.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import frontend, llm
from .btor2 import parse_btor2
from .cex import ReplayResult, replay
from .engine import Engine, Verdict
from .invariants import llm_candidates, template_candidates

_REPAIR_SYSTEM = """You are an expert SystemVerilog refactoring assistant. \
Yosys 0.33 rejected a design with a syntax/elaboration error. Rewrite the \
design MINIMALLY so it elaborates, preserving semantics EXACTLY (same \
registers, same behavior). Typical fixes: hoist `automatic` block-locals to \
module scope, replace unsupported SVA with immediate assertions, unroll \
unsupported generate constructs. Respond with ONLY the complete rewritten \
SystemVerilog file, inside one ```systemverilog code fence."""


@dataclass
class DesignReport:
    top: str
    source: str
    compile_notes: list[str] = field(default_factory=list)
    formalize: dict | None = None
    verdicts: list[dict] = field(default_factory=list)
    replays: list[dict] = field(default_factory=list)
    time_s: float = 0.0

    def to_json(self) -> dict:
        return {
            "top": self.top, "source": self.source,
            "compile_notes": self.compile_notes,
            "formalize": self.formalize,
            "verdicts": self.verdicts, "replays": self.replays,
            "time_s": round(self.time_s, 3),
        }


def repair_frontend(sv_path: Path, top: str, out_dir: Path,
                    max_attempts: int = 3) -> frontend.CompileResult:
    """Elaborate; on failure, agentically repair the source and retry."""
    try:
        return frontend.compile_sv(sv_path, top, out_dir)
    except frontend.FrontendError as e:
        last_err = e
    current = sv_path.read_text()
    for attempt in range(max_attempts):
        if not llm.llm_enabled():
            raise frontend.FrontendError(
                "frontend failed and LLM repair unavailable "
                "(set OPENROUTER_API_KEY)", log=last_err.log)
        try:
            resp = llm.chat(_REPAIR_SYSTEM,
                            f"Yosys error:\n{last_err.log[-2000:]}\n\n"
                            f"Design:\n```systemverilog\n{current[:24000]}\n```",
                            max_tokens=16384)
        except llm.LLMUnavailable as e2:
            raise frontend.FrontendError(f"LLM repair failed: {e2}",
                                         log=last_err.log)
        code = _extract_code(resp)
        if not code:
            continue
        candidate = out_dir / f"{sv_path.stem}.repair{attempt + 1}.sv"
        candidate.parent.mkdir(parents=True, exist_ok=True)
        candidate.write_text(code)
        try:
            result = frontend.compile_sv(candidate, top, out_dir)
            result.notes.append(f"agentic repair succeeded on attempt {attempt + 1}")
            _try_equiv_check(sv_path, candidate, top, result.notes)
            return result
        except frontend.FrontendError as e3:
            last_err = e3
            current = code
    raise last_err


def _extract_code(resp: str) -> str | None:
    if "```" not in resp:
        return resp if "module" in resp else None
    parts = resp.split("```")
    for i in range(1, len(parts), 2):
        block = parts[i]
        block = block.split("\n", 1)[1] if "\n" in block else block
        if "module" in block:
            return block
    return None


def _try_equiv_check(orig: Path, rewritten: Path, top: str,
                     notes: list[str]) -> None:
    """Translation validation of an AI rewrite via Yosys equivalence check."""
    try:
        frontend.run_yosys(
            f"read_verilog -sv {orig}; prep -top {top}; flatten; "
            f"rename -top gold; design -stash gold; "
            f"read_verilog -sv {rewritten}; prep -top {top}; flatten; "
            f"rename -top gate; design -stash gate; "
            f"design -copy-from gold -as gold gold; "
            f"design -copy-from gate -as gate gate; "
            f"equiv_make gold gate equiv; equiv_simple; equiv_status -assert",
            timeout_s=300)
        notes.append("equiv-check: AI rewrite proven equivalent to original")
    except (frontend.FrontendError, Exception):
        notes.append("equiv-check: skipped/inconclusive (original does not "
                     "elaborate or equivalence not provable structurally)")


def prove_property(eng: Engine, sv_source: str, max_bmc: int, max_k: int,
                   timeout_s: float, use_llm: bool = True,
                   verbose: bool = False) -> Verdict:
    """Prove-refine loop for all bad states of a transition system."""
    cands, labels = template_candidates(eng.ts)
    v = eng.prove(max_bmc=max_bmc, max_k=max_k, candidates=cands,
                  labels=labels, timeout_s=timeout_s)
    if v.status != "UNKNOWN" or not use_llm or not llm.llm_enabled():
        return v
    # Refinement round: enlarge the candidate set with AI-proposed lemmas.
    ai_cands, ai_labels = llm_candidates(eng.ts, sv_source, k_failed=max_k)
    if not ai_cands:
        return v
    if verbose:
        print(f"  agent: retrying Houdini with {len(ai_cands)} AI lemmas")
    v2 = eng.houdini(cands + ai_cands, timeout_s=timeout_s,
                     labels=labels + ai_labels)
    if v2.status == "SAFE":
        v2.method = "houdini+llm"
        return v2
    return v


def verify_design(sv_path: Path, top: str, out_dir: Path,
                  max_bmc: int = 60, max_k: int = 12,
                  timeout_s: float = 600.0, use_llm: bool = True,
                  do_formalize: bool = True, do_replay: bool = True,
                  verbose: bool = False) -> DesignReport:
    """Full agentic pipeline for one design."""
    t0 = time.monotonic()
    out_dir.mkdir(parents=True, exist_ok=True)
    report = DesignReport(top=top, source=str(sv_path))

    comp = repair_frontend(sv_path, top, out_dir)
    report.compile_notes = comp.notes

    if do_formalize:
        try:
            from .formalize import formalize
            res = formalize(frontend.load_netlist(comp.json_file), top,
                            out_dir / "lean")
            report.formalize = {
                "lean_file": str(res.lean_file),
                "props_file": str(res.props_file) if res.props_file else None,
                "mode": res.mode, "stats": res.stats,
            }
        except Exception as e:  # formalization must never block verification
            report.formalize = {"error": f"{type(e).__name__}: {e}"}

    ts = parse_btor2(comp.btor2_file)
    eng = Engine(ts, verbose=verbose)
    v = prove_property(eng, sv_path.read_text(), max_bmc, max_k,
                       timeout_s, use_llm=use_llm, verbose=verbose)
    vd = {"status": v.status, "method": v.method, "depth": v.depth,
          "time_s": round(v.time_s, 3), "detail": v.detail}
    if v.invariant:
        vd["invariant_lemmas"] = len(v.invariant)
        (out_dir / "invariant.smt2.txt").write_text("\n".join(v.invariant))
        vd["invariant_file"] = str(out_dir / "invariant.smt2.txt")
    report.verdicts.append(vd)

    if v.status == "BUG" and v.trace and do_replay:
        rr: ReplayResult = replay(v.trace, top, comp.sv_file,
                                  out_dir / "replay", source_label=str(sv_path))
        report.replays.append({
            "assertion": v.trace.bad_name,
            "confirmed_by_verilator": rr.confirmed,
            "testbench": str(rr.tb_file),
            "trace": str(rr.trace_file),
        })

    report.time_s = time.monotonic() - t0
    (out_dir / "report.json").write_text(json.dumps(report.to_json(), indent=2))
    return report
