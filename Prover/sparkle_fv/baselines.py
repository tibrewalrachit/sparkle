"""Baseline formal tools for the evaluation: yosys-smtbmc (the engine used
by SymbiYosys) in BMC and temporal-induction modes, run on the same Yosys
elaboration (identical SMT2 model) as sparkle-fv's BTOR2 model, so the
comparison isolates the checking strategy rather than frontend differences.
"""

from __future__ import annotations

import resource
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass
class BaselineResult:
    tool: str
    status: str            # "SAFE" | "BUG" | "UNKNOWN"
    depth: int
    time_s: float
    max_rss_mb: float
    log_tail: str = ""


def _run(cmd: list[str], timeout_s: float) -> tuple[int, str, float, float]:
    t0 = time.monotonic()
    before = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout_s)
        rc, out = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        rc = -1
        out = ((e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes)
               else (e.stdout or "")) + "\n[timeout]"
    dt = time.monotonic() - t0
    after = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return rc, out, dt, max(0, after - before) / 1024.0


def smtbmc_bmc(smt2_file: Path, depth: int, timeout_s: float = 600.0,
               solver: str = "z3") -> BaselineResult:
    """yosys-smtbmc bounded model check to `depth`."""
    rc, out, dt, rss = _run(
        ["yosys-smtbmc", "-s", solver, "-t", str(depth), "--noinfo",
         str(smt2_file)], timeout_s)
    if "[timeout]" in out:
        return BaselineResult("yosys-smtbmc(bmc)", "UNKNOWN", depth, dt, rss,
                              "timeout")
    if rc == 0:
        return BaselineResult("yosys-smtbmc(bmc)", "UNKNOWN", depth, dt, rss,
                              f"no violation within bound {depth}")
    import re
    fail_depth = depth
    m = re.findall(r"Checking assertions in step (\d+)", out)
    if m and rc != 0:
        fail_depth = int(m[-1])
    return BaselineResult("yosys-smtbmc(bmc)", "BUG", fail_depth, dt, rss,
                          out[-500:])


def smtbmc_induction(smt2_file: Path, depth: int,
                     timeout_s: float = 600.0,
                     solver: str = "z3") -> BaselineResult:
    """yosys-smtbmc temporal induction (`-i`): proves if k-inductive."""
    rc, out, dt, rss = _run(
        ["yosys-smtbmc", "-s", solver, "-i", "-t", str(depth), "--noinfo",
         str(smt2_file)], timeout_s)
    if "[timeout]" in out:
        return BaselineResult("yosys-smtbmc(ind)", "UNKNOWN", depth, dt, rss,
                              "timeout")
    if rc == 0 and "Temporal induction successful" in out:
        import re
        m = re.findall(r"Trying induction in step (\d+)", out)
        k = int(m[-1]) if m else depth
        return BaselineResult("yosys-smtbmc(ind)", "SAFE", k, dt, rss)
    return BaselineResult("yosys-smtbmc(ind)", "UNKNOWN", depth, dt, rss,
                          out[-500:])


def smtbmc_portfolio(smt2_file: Path, bmc_depth: int, ind_depth: int,
                     timeout_s: float = 600.0) -> BaselineResult:
    """BMC for bugs, then induction for proofs — mirrors sparkle-fv.prove."""
    b = smtbmc_bmc(smt2_file, bmc_depth, timeout_s / 2)
    if b.status == "BUG":
        return b
    i = smtbmc_induction(smt2_file, ind_depth, timeout_s / 2)
    if i.status == "SAFE":
        i.time_s += b.time_s
        return i
    return BaselineResult("yosys-smtbmc", "UNKNOWN", bmc_depth,
                          b.time_s + i.time_s,
                          max(b.max_rss_mb, i.max_rss_mb),
                          f"bmc: {b.log_tail[-120:]} | ind: {i.log_tail[-120:]}")
