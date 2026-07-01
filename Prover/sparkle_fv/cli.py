"""sparkle-fv command-line interface.

Subcommands:
  formalize  SV -> Sparkle HDL (Lean 4) + proof obligations
  prove      full agentic verification of one design (block or SoC)
  bughunt    BMC-only bug hunting with Verilator replay of counterexamples
  bench      run the benchmark suite vs yosys-smtbmc and render the report
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _cmd_formalize(args) -> int:
    from . import frontend
    from .formalize import formalize
    out = Path(args.out)
    comp = frontend.compile_sv(args.design, args.top, out)
    res = formalize(frontend.load_netlist(comp.json_file), args.top,
                    out / "lean")
    print(f"mode:  {res.mode}")
    print(f"lean:  {res.lean_file}")
    print(f"props: {res.props_file}")
    print(f"stats: {json.dumps(res.stats)}")
    return 0


def _cmd_prove(args) -> int:
    from .agent import verify_design
    report = verify_design(Path(args.design), args.top, Path(args.out),
                           max_bmc=args.max_bmc, max_k=args.max_k,
                           timeout_s=args.timeout, use_llm=not args.no_llm,
                           do_formalize=not args.no_formalize,
                           verbose=args.verbose)
    print(json.dumps(report.to_json(), indent=2))
    v = report.verdicts[0] if report.verdicts else {"status": "ERROR"}
    return {"SAFE": 0, "BUG": 1}.get(v["status"], 2)


def _cmd_bughunt(args) -> int:
    from . import frontend
    from .btor2 import parse_btor2
    from .cex import replay
    from .engine import Engine
    out = Path(args.out)
    comp = frontend.compile_sv(args.design, args.top, out)
    ts = parse_btor2(comp.btor2_file)
    print(f"model: {ts.stats()}")
    v = Engine(ts, verbose=args.verbose).bmc(args.max_bmc,
                                             timeout_s=args.timeout)
    print(f"{v.status} ({v.method}, depth {v.depth}, {v.time_s:.2f}s): {v.detail}")
    if v.status == "BUG" and v.trace:
        rr = replay(v.trace, args.top, comp.sv_file, out / "replay",
                    source_label=str(args.design))
        print(f"testbench: {rr.tb_file}")
        print(f"trace:     {rr.trace_file}")
        print(f"verilator confirmation: "
              f"{'CONFIRMED — assertion fired in simulation' if rr.confirmed else 'NOT confirmed (see replay.log)'}")
        return 1
    return 0 if v.status != "BUG" else 1


def _cmd_bench(args) -> int:
    from .bench import render_report, run_suite
    results = run_suite(Path(args.suite), Path(args.out),
                        timeout_s=args.timeout, max_bmc=args.max_bmc,
                        max_k=args.max_k, use_llm=not args.no_llm,
                        only=args.only, verbose=args.verbose)
    config = {"timeout_s": args.timeout, "max_bmc": args.max_bmc,
              "max_k": args.max_k, "llm": not args.no_llm}
    text = render_report(results, Path(args.out) / "REPORT.md", config)
    print(text)
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="sparkle-fv",
                                 description="Agentic autoformalization + "
                                             "formal verification for "
                                             "SystemVerilog / Sparkle HDL")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p, with_top=True):
        if with_top:
            p.add_argument("design", help="SystemVerilog file")
            p.add_argument("top", help="top module name")
        p.add_argument("--out", default="fv_out", help="output directory")
        p.add_argument("--timeout", type=float, default=600.0)
        p.add_argument("--max-bmc", type=int, default=60)
        p.add_argument("--max-k", type=int, default=12)
        p.add_argument("--no-llm", action="store_true",
                       help="disable the GLM-5.2/OpenRouter agentic layer")
        p.add_argument("--verbose", "-v", action="store_true")

    p = sub.add_parser("formalize", help="SV -> Sparkle HDL (Lean)")
    p.add_argument("design")
    p.add_argument("top")
    p.add_argument("--out", default="fv_out")
    p.set_defaults(fn=_cmd_formalize)

    p = sub.add_parser("prove", help="verify one design end to end")
    common(p)
    p.add_argument("--no-formalize", action="store_true")
    p.set_defaults(fn=_cmd_prove)

    p = sub.add_parser("bughunt", help="BMC bug hunt + Verilator replay")
    common(p)
    p.set_defaults(fn=_cmd_bughunt)

    p = sub.add_parser("bench", help="run benchmark suite vs yosys-smtbmc")
    common(p, with_top=False)
    p.add_argument("--suite", default=str(Path(__file__).resolve()
                                          .parent.parent / "benchmarks"))
    p.add_argument("--only", help="filter benchmarks by substring")
    p.set_defaults(fn=_cmd_bench)

    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
