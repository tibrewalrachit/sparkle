#!/usr/bin/env python3
"""Generate LaTeX tables (aggregate.tex, benchtable.tex, scaltable.tex)
from a sparkle-fv bench results.json."""

import json
import sys
from pathlib import Path


def esc(s: str) -> str:
    return str(s).replace("_", r"\_").replace("%", r"\%").replace("$", r"\$")


def main(results_path: str, out_dir: str) -> None:
    rs = json.loads(Path(results_path).read_text())
    out = Path(out_dir)

    def agg(key):
        sel = [r for r in rs if "solved" in r[key]]
        return (sum(1 for r in sel if r[key]["solved"]), len(sel),
                sum(r[key].get("time_s", 0) for r in sel))

    ss, st, stm = agg("sparkle")
    bs, bt, btm = agg("baseline")
    nbug = sum(1 for r in rs if r["expect"] == "bug")
    nconf = sum(1 for r in rs if r["sparkle"].get("verilator_confirmed"))

    (out / "aggregate.tex").write_text(rf"""\begin{{table}}[h]
\centering
\caption{{Aggregate results: {len(rs)} variants ({nbug} seeded bugs).
``Solved'' = expected verdict returned (unbounded proof for safe variants,
counterexample for bug variants).}}
\label{{tab:agg}}
\begin{{tabular}}{{lccc}}
\toprule
Tool & Solved & Total wall time (s) & Bugs Verilator-confirmed \\
\midrule
\sfv{{}} (BMC + $k$-ind + Houdini) & \textbf{{{ss}/{st}}} & {stm:.0f} & {nconf}/{nbug} \\
\tool{{yosys-smtbmc}} (BMC + temporal ind.) & {bs}/{bt} & {btm:.0f} & --- \\
\bottomrule
\end{{tabular}}
\end{{table}}
""")

    rows = []
    for r in rs:
        s, b = r["sparkle"], r["baseline"]
        mark_s = r"\checkmark" if s.get("solved") else \
            ("--" if s.get("status") == "UNKNOWN" else r"$\times$")
        mark_b = r"\checkmark" if b.get("solved") else \
            ("--" if b.get("status") == "UNKNOWN" else r"$\times$")
        vc = s.get("verilator_confirmed")
        vc_s = r"\checkmark" if vc else ("$\\times$" if vc is False else "")
        rows.append(
            f"{esc(r['bench'])} & {esc(r['variant'])} & {r['expect']} & "
            f"{r['state_bits']} & {mark_s} {esc(s.get('status', '?'))} & "
            f"{esc(s.get('method', '-'))} & {s.get('time_s', 0):.1f} & {vc_s} & "
            f"{mark_b} {esc(b.get('status', '?'))} & {b.get('time_s', 0):.1f} \\\\")
    (out / "benchtable.tex").write_text(
        r"""\begin{table}[h]
\centering
\caption{Per-variant results. State bits from the elaborated model;
``vlt'' = counterexample confirmed by Verilator replay.}
\label{tab:per}
\resizebox{\textwidth}{!}{%
\begin{tabular}{llccllrclr}
\toprule
Benchmark & Variant & Expect & Bits & \sfv{} & Method & t(s) & vlt &
\tool{smtbmc} & t(s) \\
\midrule
""" + "\n".join(rows) + r"""
\bottomrule
\end{tabular}}
\end{table}
""")

    srt = sorted((r for r in rs if r["expect"] == "safe"),
                 key=lambda r: r["state_bits"])
    rows2 = [f"{esc(r['bench'])} & {r['state_bits']} & "
             f"{esc(r['sparkle'].get('status', '?'))} & "
             f"{r['sparkle'].get('time_s', 0):.1f} & "
             f"{esc(r['baseline'].get('status', '?'))} & "
             f"{r['baseline'].get('time_s', 0):.1f} \\\\" for r in srt]
    (out / "scaltable.tex").write_text(
        r"""Table~\ref{tab:scal} orders the safe variants by model size.
\begin{table}[h]
\centering
\caption{Scalability: safe variants by state bits.}
\label{tab:scal}
\begin{tabular}{lrclcr}
\toprule
Benchmark & Bits & \sfv{} & t(s) & \tool{smtbmc} & t(s) \\
\midrule
""" + "\n".join(rows2) + r"""
\bottomrule
\end{tabular}
\end{table}
""")
    print("wrote aggregate.tex, benchtable.tex, scaltable.tex")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ".")
