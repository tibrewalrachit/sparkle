"""SystemVerilog frontend: desugar -> Yosys -> BTOR2 + JSON netlist + SMT2.

Yosys 0.33's Verilog frontend rejects a few modern SV constructs. The
`desugar` pass rewrites the common ones mechanically; anything it cannot
handle is surfaced to the agentic repair loop in `agent.py`, which asks the
LLM for a minimal semantics-preserving rewrite and re-runs Yosys until the
design elaborates (or the attempt budget is exhausted).
"""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


class FrontendError(Exception):
    def __init__(self, msg: str, log: str = ""):
        super().__init__(msg)
        self.log = log


@dataclass
class CompileResult:
    top: str
    sv_file: Path              # possibly desugared copy actually given to yosys
    btor2_file: Path
    json_file: Path
    smt2_file: Path
    desugared: bool = False
    notes: list[str] = field(default_factory=list)


_AUTOMATIC_DECL = re.compile(
    r"^(\s*)automatic\s+(logic|reg|bit)\s*(\[[^\]]+\]\s*)?(\w+)\s*=\s*(.+);\s*$")


def desugar(src: str, notes: list[str] | None = None) -> str:
    """Rewrite SV constructs unsupported by Yosys 0.33.

    Currently: block-local `automatic logic [..] name = expr;` inside
    procedural blocks -> module-scope declaration + in-place blocking
    assignment (semantics preserved inside always_comb / always @* blocks,
    where such declarations are used as combinational temporaries).
    """
    notes = notes if notes is not None else []
    lines = src.splitlines()
    out: list[str] = []
    # hoists[always_line_index in `out`] -> declarations to insert before it
    hoists: dict[int, list[str]] = {}
    last_always_idx = -1
    for ln in lines:
        if re.match(r"\s*always(_comb|_ff|_latch)?\b|\s*always\s*@", ln):
            last_always_idx = len(out)
        m = _AUTOMATIC_DECL.match(ln)
        if m and last_always_idx >= 0:
            indent, _kw, dims, name, expr = m.groups()
            dims = (dims or "").strip()
            decl = f"    logic {dims + ' ' if dims else ''}{name};"
            hoists.setdefault(last_always_idx, []).append(decl)
            out.append(f"{indent}{name} = {expr};")
            notes.append(f"desugar: hoisted automatic local '{name}'")
        else:
            out.append(ln)
    if not hoists:
        return src
    final: list[str] = []
    for i, ln in enumerate(out):
        if i in hoists:
            final.append("    // sparkle-fv desugar: hoisted automatic locals")
            final.extend(hoists[i])
        final.append(ln)
    return "\n".join(final) + "\n"


def run_yosys(script: str, timeout_s: float = 600.0) -> str:
    p = subprocess.run(["yosys", "-q", "-p", script], capture_output=True,
                       text=True, timeout=timeout_s)
    if p.returncode != 0:
        raise FrontendError(f"yosys failed (rc={p.returncode})",
                            log=(p.stdout + p.stderr)[-4000:])
    return p.stdout


def compile_sv(sv_path: str | Path, top: str, out_dir: str | Path,
               extra_sources: list[Path] | None = None,
               timeout_s: float = 600.0) -> CompileResult:
    """Elaborate SV with Yosys and emit BTOR2 (prover), JSON (formalizer),
    and SMT2 (yosys-smtbmc baseline) from one shared elaboration recipe,
    so tool comparisons run on identical models."""
    sv_path = Path(sv_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    notes: list[str] = []
    src = sv_path.read_text()
    desugared_src = desugar(src, notes)
    use_path = sv_path
    if desugared_src != src:
        use_path = out_dir / f"{sv_path.stem}.desugared.sv"
        use_path.write_text(desugared_src)

    reads = f"read_verilog -sv -formal {use_path}"
    for e in extra_sources or []:
        reads += f"; read_verilog -sv -formal {e}"
    btor2 = out_dir / f"{top}.btor2"
    jsonf = out_dir / f"{top}.json"
    smt2 = out_dir / f"{top}.smt2"
    # `setundef -zero -init` gives every FF an explicit zero init value, so
    # the BTOR2 model (sparkle-fv), the SMT2 model (yosys-smtbmc baseline),
    # and Verilator's two-state simulation all share identical initial-state
    # semantics — required both for fair tool comparison and for faithful
    # counterexample replay.
    prep = f"{reads}; prep -top {top}; flatten; setundef -undriven -zero -init"
    run_yosys(f"{prep}; write_btor {btor2}", timeout_s)
    run_yosys(f"{prep}; write_json {jsonf}", timeout_s)
    run_yosys(f"{prep}; write_smt2 -wires {smt2}", timeout_s)
    return CompileResult(top, use_path, btor2, jsonf, smt2,
                         desugared=use_path is not sv_path, notes=notes)


def load_netlist(json_file: str | Path) -> dict:
    return json.loads(Path(json_file).read_text())
