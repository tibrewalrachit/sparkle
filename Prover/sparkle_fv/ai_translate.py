"""AI-agent translation: SystemVerilog -> idiomatic Sparkle HDL (Lean 4).

The primary autoformalization engine when the LLM is configured. GLM 5.2
(via OpenRouter) receives the SystemVerilog source, a Sparkle Signal DSL
reference distilled from this repository, and few-shot SV->Lean pairs, and
emits idiomatic Signal DSL Lean. The emission runs inside an agentic
translate -> validate -> repair loop:

  1. candidate Lean is extracted from the model response;
  2. it is validated: structural checks (balanced delimiters, def/namespace
     shape), an API whitelist harvested live from the Sparkle sources (every
     `Signal.*` / DSL name the candidate uses must exist in the repo), and
     referenced-name binding;
  3. where a Lean toolchain is available (`lake` on PATH), the candidate is
     compiled (`lake env lean`), and its `#synthesizeVerilog` output is
     equivalence-checked against the original RTL with Yosys — the full
     round-trip anchor;
  4. failures are fed back verbatim as a repair prompt, up to `max_attempts`.

If the loop cannot produce a validated candidate (or the LLM is not
configured), callers fall back to the deterministic AST translator
(`translate.py`) and, last, the netlist-level CircuitM emitter
(`formalize.py`). The AI can therefore raise translation *quality* (idiom,
naming, structure) but never lowers the pipeline's floor.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import frontend, llm

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

_SYSTEM = """You are an expert in both SystemVerilog and Sparkle HDL \
(a hardware DSL embedded in Lean 4). You translate SystemVerilog RTL into \
idiomatic Sparkle Signal DSL, preserving module structure, signal names, \
and exact cycle-accurate semantics. Respond with ONLY a Lean 4 source file \
in one ```lean code fence — no prose outside the fence."""

_DSL_GUIDE = """# Sparkle Signal DSL reference (from the target repository)
- `Signal dom α` is a clock-indexed stream; combinational logic is pure.
- Registers: `Signal.register (init : α) (input : Signal dom α)` — 1-cycle
  delay, reset folded into the input expression:
  `Signal.register 0#8 (Signal.mux rst (Signal.pure 0#8) next)`.
- Feedback: `let rec q := Signal.register 0#8 (q.map (· + 1))`.
- Mux: `Signal.mux (c : Signal dom Bool) (t e : Signal dom α)`.
- Combinational: `s.map f`; two inputs: `(· + ·) <$> a <*> b`.
- DSL operators on signals: `===` (equality), `&&&`, `|||` (bool ops);
  constants lift implicitly: `let x : Signal dom (BitVec 8) := 42#8`.
- Conditional chains: `hw_cond` macro:
    `hw_cond sel | cond1 => v1 | cond2 => v2 | _ => vdef`
- Memory (sync read): `Signal.memory writeAddr writeData writeEnable readAddr`;
  combinational read: `Signal.memoryComboRead ...`.
- BitVec ops: `+ - * &&& ||| ^^^ <<< >>>`, `BitVec.ult/ule/slt/sle`,
  slicing `x.extractLsb' lo len`, concat `a ++ b`, `x.zeroExtend n`,
  `x.signExtend n`.
- File shape:
    import Sparkle
    open Sparkle.Core.Signal Sparkle.Core.Domain
    namespace <TopName>
    def <top> {dom : DomainConfig} (in1 : Signal dom (BitVec W)) ... :
        Signal dom (BitVec W) × ... := ...
    end <TopName>
"""

_USER_TMPL = """Translate this SystemVerilog module to idiomatic Sparkle \
Signal DSL (Lean 4). Rules:
- Preserve ALL signal/register names and the module's I/O contract
  (clock inputs disappear — Signal semantics are implicitly clocked;
  synchronous reset becomes a mux on register inputs).
- Cycle-accurate: non-blocking assignments in clocked always blocks are
  registers; combinational always/assign are pure `let` bindings.
- Immediate assertions: do NOT include in the design def; list them at the
  bottom as comments `-- PROPERTY <name>: <expr>` for the props generator.
- Emit exactly one Lean file.

{guide}

# Few-shot example
## SystemVerilog
```systemverilog
{shot_sv}
```
## Sparkle HDL (Lean 4)
```lean
{shot_lean}
```

# Now translate
## SystemVerilog ({top})
```systemverilog
{src}
```{repair}
"""

_SHOT_SV = """module counter8(input logic clk, input logic rst,
                input logic en, output logic [7:0] q);
  always_ff @(posedge clk) begin
    if (rst) q <= 8'd0;
    else if (en) q <= q + 8'd1;
  end
endmodule"""

_SHOT_LEAN = """import Sparkle
open Sparkle.Core.Signal Sparkle.Core.Domain

namespace Counter8

/-- 8-bit enabled counter with synchronous reset.
    Translated from SystemVerilog `counter8`. -/
def counter8 {dom : DomainConfig}
    (rst : Signal dom Bool) (en : Signal dom Bool) :
    Signal dom (BitVec 8) :=
  let rec q := Signal.register 0#8 <|
    Signal.mux rst (0#8 : Signal dom (BitVec 8))
      (Signal.mux en ((· + 1#8) <$> q) q)
  q

end Counter8"""


@dataclass
class AiTranslateResult:
    top: str
    lean_file: Path | None
    attempts: int
    validated: list[str] = field(default_factory=list)   # checks that passed
    notes: list[str] = field(default_factory=list)
    ok: bool = False


# ------------------------------------------------------------------ validate

_API_PATTERNS = [
    (re.compile(r"\bSignal\.(\w+)"), "Sparkle/Core/Signal.lean"),
    (re.compile(r"\bhw_cond\b"), "Sparkle/Core"),
]


def _harvest_signal_api() -> set[str]:
    """Names defined under `Signal.` in the Sparkle sources — the whitelist
    for candidate validation."""
    api: set[str] = set()
    src_dir = REPO_ROOT / "Sparkle" / "Core"
    for f in src_dir.glob("*.lean"):
        for m in re.finditer(r"\bdef\s+([A-Za-z_][\w.]*)", f.read_text()):
            api.add(m.group(1).split(".")[-1])
    return api


def validate_candidate(lean_src: str, top: str) -> list[str]:
    """Return a list of validation ERRORS (empty = candidate accepted)."""
    errs: list[str] = []
    for o, c, what in [("(", ")", "parens"), ("[", "]", "brackets"),
                       ("{", "}", "braces")]:
        stripped = re.sub(r"--.*", "", lean_src)
        if stripped.count(o) != stripped.count(c):
            errs.append(f"unbalanced {what}: {stripped.count(o)} '{o}' vs "
                        f"{stripped.count(c)} '{c}'")
    if "import Sparkle" not in lean_src:
        errs.append("missing `import Sparkle`")
    if not re.search(rf"\bdef\s+{re.escape(top)}\b", lean_src):
        errs.append(f"no `def {top}` found (top module must keep its name)")
    api = _harvest_signal_api()
    for m in re.finditer(r"\bSignal\.(\w+)", lean_src):
        if m.group(1) not in api:
            errs.append(f"`Signal.{m.group(1)}` does not exist in "
                        f"Sparkle/Core (available e.g.: "
                        f"{', '.join(sorted(api)[:12])} ...)")
    if "sorry" in lean_src:
        errs.append("design definition must not contain `sorry`")
    return sorted(set(errs))


def _lake_available() -> bool:
    return shutil.which("lake") is not None


def compile_check(lean_file: Path) -> list[str]:
    """Compile the candidate with the repo's Lean toolchain if present."""
    if not _lake_available():
        return []
    p = subprocess.run(["lake", "env", "lean", str(lean_file)],
                       cwd=REPO_ROOT, capture_output=True, text=True,
                       timeout=600)
    if p.returncode != 0:
        return [(p.stdout + p.stderr)[-3000:]]
    return []


def roundtrip_equiv_check(lean_file: Path, sv_path: Path, top: str,
                          out_dir: Path) -> list[str]:
    """Full round-trip anchor: #synthesizeVerilog the candidate and
    equivalence-check against the original RTL with Yosys. Only runs when a
    Lean toolchain is available; the SMT-level anchor (shared Yosys
    elaboration checked by the prover) holds regardless."""
    if not _lake_available():
        return []
    gen_sv = out_dir / f"{top}.roundtrip.sv"
    # The repo convention: #synthesizeVerilog writes next to the module; a
    # driver script is required per-design. We generate a minimal driver.
    driver = out_dir / "RoundTrip.lean"
    driver.write_text(f"import Sparkle\nimport «{lean_file.stem}»\n"
                      f"#synthesizeVerilog {top} \"{gen_sv}\"\n")
    p = subprocess.run(["lake", "env", "lean", str(driver)], cwd=REPO_ROOT,
                       capture_output=True, text=True, timeout=900)
    if p.returncode != 0 or not gen_sv.exists():
        return [f"roundtrip synthesis failed: {(p.stdout + p.stderr)[-1500:]}"]
    try:
        frontend.run_yosys(
            f"read_verilog -sv {sv_path}; prep -top {top}; flatten; "
            f"rename -top gold; design -stash gold; "
            f"read_verilog -sv {gen_sv}; prep -top {top}; flatten; "
            f"rename -top gate; design -stash gate; "
            f"design -copy-from gold -as gold gold; "
            f"design -copy-from gate -as gate gate; "
            f"equiv_make gold gate equiv; equiv_simple; equiv_induct; "
            f"equiv_status -assert", timeout_s=600)
    except frontend.FrontendError as e:
        return [f"roundtrip equivalence FAILED: {e.log[-1500:]}"]
    return []


# ----------------------------------------------------------------- main loop

def ai_translate(sv_path: Path, top: str, out_dir: Path,
                 max_attempts: int = 4) -> AiTranslateResult:
    """Agentic SV -> Sparkle HDL translation with validate/repair loop."""
    out_dir.mkdir(parents=True, exist_ok=True)
    res = AiTranslateResult(top=top, lean_file=None, attempts=0)
    if not llm.llm_enabled():
        res.notes.append("LLM not configured (OPENROUTER_API_KEY unset or "
                         "SPARKLE_FV_NO_LLM=1); use deterministic translator")
        return res

    src = sv_path.read_text()
    repair_ctx = ""
    for attempt in range(1, max_attempts + 1):
        res.attempts = attempt
        try:
            resp = llm.chat(_SYSTEM,
                            _USER_TMPL.format(guide=_DSL_GUIDE,
                                              shot_sv=_SHOT_SV,
                                              shot_lean=_SHOT_LEAN,
                                              top=top, src=src[:48000],
                                              repair=repair_ctx),
                            max_tokens=16384, temperature=0.1)
        except llm.LLMUnavailable as e:
            res.notes.append(f"LLM unavailable: {e}")
            return res
        cand = _extract_lean(resp)
        if cand is None:
            repair_ctx = "\n\n# REPAIR\nYour last response contained no " \
                         "```lean fence. Emit exactly one Lean file."
            continue
        errs = validate_candidate(cand, top)
        if not errs:
            lean_file = out_dir / f"{_camel(top)}.lean"
            lean_file.write_text(cand)
            res.validated.append("structural+API-whitelist")
            cerrs = compile_check(lean_file)
            if not cerrs:
                if _lake_available():
                    res.validated.append("lake-compile")
                    eerrs = roundtrip_equiv_check(lean_file, sv_path, top,
                                                  out_dir)
                    if eerrs:
                        errs = eerrs
                    else:
                        res.validated.append("yosys-roundtrip-equiv")
                if not errs:
                    res.lean_file = lean_file
                    res.ok = True
                    res.notes.append(
                        f"AI translation accepted on attempt {attempt}; "
                        f"validated: {', '.join(res.validated)}")
                    return res
            else:
                errs = cerrs
        repair_ctx = ("\n\n# REPAIR (attempt " + str(attempt) + " rejected)\n"
                      "Your previous translation failed validation:\n- "
                      + "\n- ".join(e[:400] for e in errs[:10])
                      + "\nFix ALL issues and re-emit the complete file.")
    res.notes.append(f"no candidate passed validation in {max_attempts} "
                     f"attempts; falling back to deterministic translator")
    return res


def _extract_lean(resp: str) -> str | None:
    m = re.search(r"```lean\s*\n(.*?)```", resp, re.S)
    if m:
        return m.group(1)
    if "import Sparkle" in resp and "```" not in resp:
        return resp
    return None


def _camel(name: str) -> str:
    return "".join(w.capitalize() for w in re.split(r"[_\W]+", name) if w)
