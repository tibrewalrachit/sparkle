"""BTOR2 parser and Z3 transition-system builder.

BTOR2 is the word-level model-checking format used by the Hardware Model
Checking Competition (HWMCC).  Yosys emits it via `write_btor`, which maps
SystemVerilog immediate assertions to `bad` states and assumptions to
`constraint` nodes.  This module parses BTOR2 into a `TransitionSystem`
whose states/inputs/init/next/bad/constraint components are Z3 expressions,
ready for BMC, k-induction and invariant checking in `engine.py`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import z3


@dataclass
class Btor2Node:
    nid: int
    op: str
    args: list[str]
    symbol: str | None = None


@dataclass
class TransitionSystem:
    """Word-level transition system over Z3 terms.

    States and inputs are symbolic templates; `at_frame` instantiates fresh
    copies per unrolling frame.  All formulas below are functions of those
    templates and are re-instantiated per frame by substitution.
    """

    states: list[z3.ExprRef] = field(default_factory=list)
    inputs: list[z3.ExprRef] = field(default_factory=list)
    init: list[z3.BoolRef] = field(default_factory=list)          # over frame-0 states
    next_fn: dict[str, z3.ExprRef] = field(default_factory=dict)  # state name -> next expr
    bads: list[tuple[str, z3.BoolRef]] = field(default_factory=list)
    constraints: list[z3.BoolRef] = field(default_factory=list)
    uninit_states: list[z3.ExprRef] = field(default_factory=list)  # states without init
    name_src: dict[str, str] = field(default_factory=dict)         # bad name -> source loc

    @staticmethod
    def _copy(var: z3.ExprRef, frame: int) -> z3.ExprRef:
        name = f"{var.decl().name()}@{frame}"
        if z3.is_array(var):
            return z3.Const(name, var.sort())
        return z3.Const(name, var.sort())

    def state_at(self, frame: int) -> list[z3.ExprRef]:
        return [self._copy(s, frame) for s in self.states]

    def inputs_at(self, frame: int) -> list[z3.ExprRef]:
        return [self._copy(i, frame) for i in self.inputs]

    def _frame_subs(self, frame: int):
        subs = [(s, self._copy(s, frame)) for s in self.states]
        subs += [(i, self._copy(i, frame)) for i in self.inputs]
        return subs

    def init_at(self, frame: int) -> list[z3.BoolRef]:
        subs = self._frame_subs(frame)
        return [z3.substitute(f, *subs) for f in self.init]

    def constraints_at(self, frame: int) -> list[z3.BoolRef]:
        subs = self._frame_subs(frame)
        return [z3.substitute(f, *subs) for f in self.constraints]

    def bads_at(self, frame: int) -> list[tuple[str, z3.BoolRef]]:
        subs = self._frame_subs(frame)
        return [(n, z3.substitute(f, *subs)) for n, f in self.bads]

    def trans_at(self, frame: int) -> list[z3.BoolRef]:
        """Transition relation between `frame` and `frame + 1`."""
        subs = self._frame_subs(frame)
        out = []
        for s in self.states:
            nxt = self.next_fn.get(s.decl().name())
            if nxt is None:
                continue  # free-running state (no next): unconstrained
            out.append(self._copy(s, frame + 1) == z3.substitute(nxt, *subs))
        return out

    def expr_at(self, expr: z3.ExprRef, frame: int) -> z3.ExprRef:
        return z3.substitute(expr, *self._frame_subs(frame))

    def stats(self) -> dict:
        return {
            "states": len(self.states),
            "inputs": len(self.inputs),
            "state_bits": sum(
                s.sort().size() if isinstance(s.sort(), z3.BitVecSortRef) else -1
                for s in self.states
                if isinstance(s.sort(), z3.BitVecSortRef)
            ),
            "arrays": sum(1 for s in self.states if z3.is_array(s)),
            "bads": len(self.bads),
            "constraints": len(self.constraints),
        }


def _bv_bool(e: z3.ExprRef) -> z3.BoolRef:
    """1-bit bitvector -> Bool."""
    if z3.is_bool(e):
        return e
    return e == z3.BitVecVal(1, 1)


def _bool_bv(e: z3.ExprRef) -> z3.ExprRef:
    if z3.is_bool(e):
        return z3.If(e, z3.BitVecVal(1, 1), z3.BitVecVal(0, 1))
    return e


def _red(op, e: z3.ExprRef) -> z3.ExprRef:
    w = e.sort().size()
    acc = z3.Extract(0, 0, e)
    for i in range(1, w):
        acc = op(acc, z3.Extract(i, i, e))
    return acc


class Btor2Parser:
    """Parses a BTOR2 file into a TransitionSystem of Z3 expressions."""

    def __init__(self) -> None:
        self.sorts: dict[int, z3.SortRef] = {}
        self.exprs: dict[int, z3.ExprRef] = {}
        self.ts = TransitionSystem()
        self._sym_count = 0

    def parse_file(self, path: str | Path) -> TransitionSystem:
        return self.parse(Path(path).read_text())

    def parse(self, text: str) -> TransitionSystem:
        pending_next: list[tuple[int, int]] = []   # (state id, expr id)
        pending_init: list[tuple[int, int]] = []
        for raw in text.splitlines():
            line = raw.split(";", 1)[0].strip()
            comment = raw.split(";", 1)[1].strip() if ";" in raw else ""
            if not line:
                continue
            toks = line.split()
            nid = int(toks[0])
            op = toks[1]
            args = toks[2:]
            if op == "sort":
                self._sort(nid, args)
            elif op in ("input", "state"):
                self._var(nid, op, args)
            elif op in ("const", "constd", "consth", "zero", "one", "ones"):
                self._const(nid, op, args)
            elif op == "init":
                pending_init.append((int(args[1]), int(args[2])))
            elif op == "next":
                pending_next.append((int(args[1]), int(args[2])))
            elif op == "bad":
                name = args[1] if len(args) > 1 else f"bad_{nid}"
                cond = _bv_bool(self.exprs[int(args[0])])
                self.ts.bads.append((name, cond))
                if comment:
                    self.ts.name_src[name] = comment
            elif op == "constraint":
                self.ts.constraints.append(_bv_bool(self.exprs[int(args[0])]))
            elif op == "output":
                pass
            elif op == "fair" or op == "justice":
                pass  # liveness: handled via safety encodings upstream
            else:
                self._op(nid, op, args)

        for s_id, e_id in pending_next:
            st = self.exprs[s_id]
            self.ts.next_fn[st.decl().name()] = self.exprs[e_id]
        inited_names = set()
        for s_id, e_id in pending_init:
            st = self.exprs[s_id]
            inited_names.add(st.decl().name())
            val = self.exprs[e_id]
            if z3.is_array(st) and not z3.is_array(val):
                # BTOR2 initializes arrays with a scalar -> constant array
                val = z3.K(st.sort().domain(), val)
            self.ts.init.append(st == val)
        self.ts.uninit_states = [s for s in self.ts.states
                                 if s.decl().name() not in inited_names]
        return self.ts

    # -- node handlers -----------------------------------------------------

    def _sort(self, nid: int, args: list[str]) -> None:
        if args[0] == "bitvec":
            self.sorts[nid] = z3.BitVecSort(int(args[1]))
        elif args[0] == "array":
            self.sorts[nid] = z3.ArraySort(self.sorts[int(args[1])],
                                           self.sorts[int(args[2])])
        else:
            raise ValueError(f"unknown sort {args}")

    def _var(self, nid: int, op: str, args: list[str]) -> None:
        sort = self.sorts[int(args[0])]
        name = args[1] if len(args) > 1 else f"{op}_{nid}"
        # Yosys may emit duplicate symbols; disambiguate deterministically.
        v = z3.Const(name, sort)
        if any(v.decl().name() == e.decl().name()
               for e in self.ts.states + self.ts.inputs):
            self._sym_count += 1
            v = z3.Const(f"{name}__{self._sym_count}", sort)
        self.exprs[nid] = v
        (self.ts.inputs if op == "input" else self.ts.states).append(v)

    def _const(self, nid: int, op: str, args: list[str]) -> None:
        sort = self.sorts[int(args[0])]
        w = sort.size()
        if op == "zero":
            val = 0
        elif op == "one":
            val = 1
        elif op == "ones":
            val = (1 << w) - 1
        elif op == "const":
            val = int(args[1], 2)
        elif op == "constd":
            val = int(args[1], 10)
        else:  # consth
            val = int(args[1], 16)
        self.exprs[nid] = z3.BitVecVal(val, w)

    def _op(self, nid: int, op: str, args: list[str]) -> None:
        sort = self.sorts[int(args[0])]
        # NOTE: slice/uext/sext carry extra integer args that are NOT node
        # ids; they are read positionally below, never through self.exprs.
        a = self.exprs[int(args[1])] if len(args) > 1 else None

        def b():
            return self.exprs[int(args[2])]

        def c():
            return self.exprs[int(args[3])]

        w = sort.size() if isinstance(sort, z3.BitVecSortRef) else None

        if op == "slice":
            hi, lo = int(args[2]), int(args[3])
            e = z3.Extract(hi, lo, a)
        elif op == "uext":
            e = z3.ZeroExt(int(args[2]), _bool_bv(a))
        elif op == "sext":
            e = z3.SignExt(int(args[2]), _bool_bv(a))
        elif op == "not":
            e = ~a
        elif op == "inc":
            e = a + 1
        elif op == "dec":
            e = a - 1
        elif op == "neg":
            e = -a
        elif op in ("redand", "redor", "redxor"):
            fn = {"redand": lambda x, y: x & y,
                  "redor": lambda x, y: x | y,
                  "redxor": lambda x, y: x ^ y}[op]
            e = _red(fn, a)
        elif op == "ite":
            e = z3.If(_bv_bool(a), b(), c())
        elif op == "read":
            e = z3.Select(a, b())
        elif op == "write":
            e = z3.Store(a, b(), c())
        elif op == "concat":
            e = z3.Concat(a, b())
        elif op in _BINOPS:
            e = _BINOPS[op](a, b())
        else:
            raise ValueError(f"unsupported btor2 op: {op}")

        if isinstance(sort, z3.BitVecSortRef):
            e = _bool_bv(e)
            if e.sort().size() != w:
                if e.sort().size() < w:
                    e = z3.ZeroExt(w - e.sort().size(), e)
                else:
                    e = z3.Extract(w - 1, 0, e)
        self.exprs[nid] = e


_BINOPS = {
    "add": lambda a, b: a + b,
    "sub": lambda a, b: a - b,
    "mul": lambda a, b: a * b,
    "udiv": z3.UDiv,
    "sdiv": lambda a, b: a / b,
    "urem": z3.URem,
    "srem": z3.SRem,
    "smod": lambda a, b: a % b,
    "and": lambda a, b: a & b,
    "or": lambda a, b: a | b,
    "xor": lambda a, b: a ^ b,
    "nand": lambda a, b: ~(a & b),
    "nor": lambda a, b: ~(a | b),
    "xnor": lambda a, b: ~(a ^ b),
    "implies": lambda a, b: z3.Implies(_bv_bool(a), _bv_bool(b)),
    "iff": lambda a, b: _bv_bool(a) == _bv_bool(b),
    "eq": lambda a, b: a == b,
    "neq": lambda a, b: a != b,
    "ugt": z3.UGT,
    "ugte": z3.UGE,
    "ult": z3.ULT,
    "ulte": z3.ULE,
    "sgt": lambda a, b: a > b,
    "sgte": lambda a, b: a >= b,
    "slt": lambda a, b: a < b,
    "slte": lambda a, b: a <= b,
    "sll": lambda a, b: a << b,
    "srl": z3.LShR,
    "sra": lambda a, b: a >> b,
    "rol": z3.RotateLeft,
    "ror": z3.RotateRight,
    # overflow ops (rare from yosys)
    "uaddo": lambda a, b: z3.Not(z3.BVAddNoOverflow(a, b, False)),
    "saddo": lambda a, b: z3.Not(z3.BVAddNoOverflow(a, b, True)),
    "usubo": lambda a, b: z3.Not(z3.BVSubNoUnderflow(a, b, False)),
    "ssubo": lambda a, b: z3.Not(z3.BVSubNoUnderflow(a, b, True)),
    "umulo": lambda a, b: z3.Not(z3.BVMulNoOverflow(a, b, False)),
    "smulo": lambda a, b: z3.Not(z3.BVMulNoOverflow(a, b, True)),
}


def parse_btor2(path: str | Path) -> TransitionSystem:
    """Parse a BTOR2 file into a Z3 transition system."""
    return Btor2Parser().parse_file(path)
