"""Source-to-source SystemVerilog -> idiomatic Sparkle Signal DSL.

This module is the PRIMARY autoformalization path of the sparkle-fv
harness.  Unlike :mod:`sparkle_fv.formalize` (which reconstructs the
*synthesized* Yosys netlist through low-level CircuitM builder calls),
this translator works on the *behavioral* SystemVerilog source via
Verilator's XML AST (``verilator --xml-only``), which preserves always
blocks, if/case structure, expressions and original signal names.  The
output is the Signal DSL a human Sparkle designer writes:

  * clocked ``always_ff`` register updates  ->  ``Signal.register`` with
    the reset folded into a ``hw_cond``/``Signal.mux`` on the input,
  * feedback state                          ->  ``Signal.loop`` (with a
    ``declare_signal_state`` bundle for multi-register designs, the
    idiom of ``Examples/YOLOv8/Blocks/Bottleneck.lean``),
  * combinational logic                     ->  ``let`` bindings in
    dependency order using the applicative style / ``===``, ``&&&`` ...
  * unpacked arrays written in clocked always -> ``Signal.memoryComboRead``,
  * immediate assertions -> a companion ``<Top>Props.lean`` with
    ``Signal dom Bool`` property definitions and ``sorry`` theorem
    skeletons in the ``Sparkle.Verification.Temporal`` vocabulary.

Public API::

    translate(sv_path: Path, top: str, out_dir: Path) -> TranslateResult

Semantic equivalence of the translation is anchored by the shared Yosys
elaboration used by the prover backend; unsupported constructs degrade
to ``-- TODO(unsupported)`` comments plus a best-effort fallback and are
recorded in ``stats["todos"]`` (the translator never crashes on them).

Stdlib only; Python 3.10+.  Requires ``verilator`` on PATH.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

__all__ = ["TranslateResult", "TranslateError", "translate"]

HEADER_NOTE = (
    "Auto-translated from behavioral SystemVerilog by sparkle_fv.translate "
    "(Verilator XML AST front end)"
)


class TranslateError(RuntimeError):
    """Hard failure (verilator missing, XML unparsable, top not found)."""


@dataclass
class TranslateResult:
    top: str
    lean_file: Path
    props_file: Path | None
    stats: dict          # {"registers", "memories", "combinational",
                         #  "asserts", "todos": [...]}
    notes: list[str]


# --------------------------------------------------------------------------
# Lean identifier handling
# --------------------------------------------------------------------------

_LEAN_RESERVED = {
    "def", "let", "fun", "do", "if", "then", "else", "match", "with", "open",
    "import", "namespace", "end", "structure", "inductive", "theorem", "by",
    "sorry", "in", "rec", "mut", "where", "deriving", "true", "false", "at",
    "have", "show", "from", "exact", "calc", "set", "this", "instance",
    "abbrev", "private", "partial", "mutual", "variable",
    # names the generator itself introduces / state-macro companions
    "dom", "state", "default", "wireNames", "fromWires",
}


def _ident(raw: str, used: set[str], fallback: str = "w") -> str:
    """Sanitize `raw` into a fresh Lean identifier, preserving it verbatim
    when possible (original signal names are part of the spec)."""
    s = re.sub(r"[^0-9a-zA-Z_]+", "_", raw).strip("_")
    if not s or not s[0].isalpha():
        s = f"{fallback}_{s}" if s else fallback
    if s in _LEAN_RESERVED:
        s += "_v"
    base, n = s, 1
    while s in used:
        n += 1
        s = f"{base}_{n}"
    used.add(s)
    return s


# --------------------------------------------------------------------------
# Typed expression tree
#   ty is ("bool",) for 1-bit values or ("bv", w) for BitVec w.
# --------------------------------------------------------------------------

BOOL = ("bool",)


def BV(w: int) -> tuple:
    return ("bv", max(w, 1))


@dataclass(frozen=True)
class E:
    kind: str            # const | ref | op | mux | sel | memread | undef
    ty: tuple
    args: tuple = ()
    aux: object = None   # const: value; ref: var name; op: operator name;
                         # sel: (lo:int|None, width); memread: mem name;
                         # op zext/sext: target width


def _cbool(b: bool) -> E:
    return E("const", BOOL, aux=bool(b))


def _cbv(v: int, w: int) -> E:
    w = max(w, 1)
    return E("const", BV(w), aux=v & ((1 << w) - 1))


def _ref(name: str, ty: tuple) -> E:
    return E("ref", ty, aux=name)


def _width(ty: tuple) -> int:
    return 1 if ty == BOOL else ty[1]


def _not(e: E) -> E:
    if e.kind == "op" and e.aux == "not":
        return e.args[0]
    if e.kind == "op" and e.aux == "neq" and e.ty == BOOL:
        return E("op", BOOL, e.args, "eq")
    if e.kind == "op" and e.aux == "eq" and e.ty == BOOL:
        return E("op", BOOL, e.args, "neq")
    if e.kind == "const" and e.ty == BOOL:
        return _cbool(not e.aux)
    return E("op", e.ty, (e,), "not")


def _and(a: E | None, b: E) -> E:
    if a is None:
        return b
    if a.kind == "const" and a.ty == BOOL:
        return b if a.aux else a
    if b.kind == "const" and b.ty == BOOL:
        return a if b.aux else b
    return E("op", BOOL, (a, b), "and")


def _or(a: E, b: E) -> E:
    return E("op", BOOL, (a, b), "or")


def _mux(c: E, t: E, e: E) -> E:
    if c.kind == "const" and c.ty == BOOL:
        return t if c.aux else e
    if t == e:
        return t
    return E("mux", t.ty, (c, t, e))


def _coerce(e: E, ty: tuple, signed: bool = False) -> E:
    """Adapt `e` to type `ty` (bool <-> BitVec 1, zext/sext, truncate,
    Verilog truthiness for wide -> bool)."""
    if e.ty == ty:
        return e
    if ty == BOOL:
        if e.ty[1] == 1:
            return E("op", BOOL, (e,), "v2b")
        return E("op", BOOL, (e,), "redor")      # Verilog truthiness
    if e.ty == BOOL:
        bv1 = _cbv(1 if e.aux else 0, 1) if e.kind == "const" \
            else E("op", BV(1), (e,), "b2v")
        return _coerce(bv1, ty, signed)
    w, tw = e.ty[1], ty[1]
    if e.kind == "const":
        v = e.aux
        if signed and w < tw and (v >> (w - 1)) & 1:
            v |= ((1 << (tw - w)) - 1) << w
        return _cbv(v, tw)
    if w < tw:
        return E("op", ty, (e,), "sext" if signed else "zext")
    return E("sel", ty, (e,), (0, tw))           # truncate


def _refs(e: E, acc: set | None = None) -> set:
    """All variable names referenced by `e` (excluding memory names)."""
    if acc is None:
        acc = set()
    if e.kind == "ref":
        acc.add(e.aux)
    for a in e.args:
        _refs(a, acc)
    return acc


# --------------------------------------------------------------------------
# Module model
# --------------------------------------------------------------------------


@dataclass
class _Var:
    name: str
    ty: tuple
    direction: str = ""          # "input" | "output" | ""
    init: object = None          # int | bool | None (declared initial value)
    is_param: bool = False
    param_val: E | None = None
    pin_index: int = 0
    loc: str = ""


@dataclass
class _Mem:
    name: str
    data_width: int
    size: int
    abits: int
    writes: list = field(default_factory=list)   # [(guard E|None, addr E, data E)]
    notes: list = field(default_factory=list)


@dataclass
class _Reg:
    name: str
    ty: tuple
    next: E = None               # type: ignore[assignment]
    init: object = None
    notes: list = field(default_factory=list)


@dataclass
class _Prop:
    name: str
    expr: E                      # Bool signal condition; must always hold
    src: str                     # "file.sv:NN"
    text: str                    # original source line (best effort)


_STMT_TAGS = {"assign", "assigndly", "assignforce", "if", "begin", "case",
              "while", "display", "stop", "finish", "comment", "jumpblock",
              "delay", "timingcontrol"}

_BINOP_TAGS = {
    "add": "add", "sub": "sub", "mul": "mul", "muls": "mul",
    "and": "and", "or": "or", "xor": "xor",
    "shiftl": "shl", "shiftr": "shr", "shiftrs": "sra",
}
_CMP_TAGS = {
    "eq": ("eq", False), "neq": ("neq", False),
    "eqcase": ("eq", False), "neqcase": ("neq", False),
    "lt": ("ltu", False), "lte": ("leu", False),
    "gt": ("gtu", False), "gte": ("geu", False),
    "lts": ("lts", True), "ltes": ("les", True),
    "gts": ("gts", True), "gtes": ("ges", True),
}

_RST_NAMES = re.compile(r"^(a?s?rstn?|resetn?)(_i)?$", re.IGNORECASE)


class _Translator:
    """Parses one Verilator XML module and builds regs/combs/mems/props."""

    def __init__(self, sv_path: Path, top: str, root: ET.Element):
        self.sv_path = sv_path
        self.top = top
        self.root = root
        self.files: dict[str, str] = {}
        self.dtypes: dict[str, dict] = {}
        self.vars: dict[str, _Var] = {}
        self.mems: dict[str, _Mem] = {}
        self.combs: dict[str, E] = {}           # ordered (py3.7+ dicts)
        self.comb_notes: dict[str, str] = {}
        self.regs: dict[str, _Reg] = {}
        self.props: list[_Prop] = []
        self.clock_names: set[str] = set()
        self.sense_names: set[str] = set()
        self.body_refs: set[str] = set()        # vars read as data anywhere
        self.todos: list[str] = []
        self.notes: list[str] = []
        self._src_lines: list[str] = []
        try:
            self._src_lines = sv_path.read_text(errors="replace").splitlines()
        except OSError:
            pass

    # ---------------- diagnostics ----------------

    def _loc(self, node: ET.Element) -> str:
        loc = node.get("loc", "")
        parts = loc.split(",")
        if len(parts) >= 2:
            fname = self.files.get(parts[0], parts[0])
            return f"{Path(fname).name}:{parts[1]}"
        return "?"

    def _src_line(self, node: ET.Element) -> str:
        parts = node.get("loc", "").split(",")
        if len(parts) >= 2 and parts[0] == self._design_fid:
            try:
                return self._src_lines[int(parts[1]) - 1].strip()
            except (ValueError, IndexError):
                pass
        return ""

    def todo(self, what: str, node: ET.Element | None = None) -> None:
        where = self._loc(node) if node is not None else "?"
        self.todos.append(f"{what} at {where}")

    # ---------------- XML groundwork ----------------

    def parse(self) -> None:
        self._design_fid = "?"
        for f in self.root.iter("file"):
            self.files[f.get("id", "")] = f.get("filename", "")
            if Path(f.get("filename", "")).resolve() == self.sv_path.resolve():
                self._design_fid = f.get("id", "?")
        for t in self.root.iter("typetable"):
            for dt in t:
                self._parse_dtype(dt)
        mod = None
        for m in self.root.iter("module"):
            if m.get("name") == self.top or m.get("origName") == self.top:
                mod = m
                break
        if mod is None:
            for m in self.root.iter("module"):
                if m.get("topModule") == "1":
                    mod = m
                    self.notes.append(
                        f"module '{self.top}' not found by name; using top "
                        f"module '{m.get('name')}'")
                    break
        if mod is None:
            raise TranslateError(f"top module '{self.top}' not in XML AST")
        self.mod = mod
        self._build()

    def _parse_dtype(self, dt: ET.Element) -> None:
        i = dt.get("id")
        if i is None:
            return
        d = {"tag": dt.tag, "signed": dt.get("signed") == "true"}
        if dt.tag == "basicdtype":
            left, right = dt.get("left"), dt.get("right")
            if left is None:
                d["width"] = 1
            else:
                d["width"] = abs(int(left) - int(right or 0)) + 1
        elif dt.tag in ("unpackarraydtype", "packarraydtype"):
            d["sub"] = dt.get("sub_dtype_id")
            rng = dt.find("range")
            lo = hi = 0
            if rng is not None:
                consts = [self._const_int(c) for c in rng if c.tag == "const"]
                if len(consts) == 2:
                    lo, hi = min(consts), max(consts)
            d["lo"], d["size"] = lo, hi - lo + 1
        self.dtypes[i] = d

    def _ty_of(self, dtype_id: str | None) -> tuple:
        d = self.dtypes.get(dtype_id or "", {})
        w = d.get("width", 1)
        return BOOL if w == 1 else BV(w)

    def _signed(self, dtype_id: str | None) -> bool:
        return bool(self.dtypes.get(dtype_id or "", {}).get("signed"))

    @staticmethod
    def _const_int(c: ET.Element) -> int:
        m = re.match(r"(\d+)'s?([hbod])?([0-9a-fA-FxzXZ_?]+)",
                     c.get("name", ""))
        if not m:
            try:
                return int(c.get("name", "0"))
            except ValueError:
                return 0
        base = {"h": 16, "b": 2, "o": 8, "d": 10, None: 10}[m.group(2)]
        digits = m.group(3).replace("_", "")
        digits = re.sub(r"[xzXZ?]", "0", digits)
        return int(digits, base)

    # ---------------- module build ----------------

    def _build(self) -> None:
        m = self.mod
        # 1. Variables (ports, nets, params, unpacked arrays -> memories)
        for v in m.findall("var"):
            name = v.get("name", "")
            dtid = v.get("dtype_id")
            d = self.dtypes.get(dtid or "", {})
            if d.get("tag") == "unpackarraydtype":
                sub = self.dtypes.get(d.get("sub", ""), {})
                dw = sub.get("width", 1)
                size = max(d.get("size", 1), 1)
                abits = max((size - 1).bit_length(), 1)
                mem = _Mem(name, dw, size, abits)
                if (1 << abits) != size or d.get("lo", 0) != 0:
                    mem.notes.append(
                        f"array [{d.get('lo', 0)}:{d.get('lo', 0)+size-1}] "
                        f"modeled as full 2^{abits}-entry memory")
                self.mems[name] = mem
                continue
            var = _Var(name, self._ty_of(dtid),
                       direction=v.get("dir", ""),
                       is_param=(v.get("param") == "true"
                                 or v.get("localparam") == "true"),
                       pin_index=int(v.get("pinIndex", "0") or 0),
                       loc=self._loc(v))
            if var.is_param:
                c = v.find("const")
                if c is not None:
                    val = self._const_int(c)
                    var.param_val = (_cbool(bool(val)) if var.ty == BOOL
                                     else _cbv(val, _width(var.ty)))
            self.vars[name] = var

        # 2. Declared initial values.
        for ini in list(m.findall("initialstatic")) + list(m.findall("initial")):
            for a in ini.iter("assign"):
                kids = list(a)
                if len(kids) == 2 and kids[1].tag == "varref" \
                        and kids[0].tag == "const":
                    v = self.vars.get(kids[1].get("name", ""))
                    if v is not None:
                        val = self._const_int(kids[0])
                        v.init = bool(val) if v.ty == BOOL else val
                elif len(kids) == 2 and kids[1].tag == "arraysel":
                    self.todo("initial memory contents (ignored)", a)
                else:
                    self.todo("unsupported initial statement", a)

        # 3. Continuous assigns.
        for ca in m.findall("contassign"):
            self._contassign(ca)
        for ca in m.findall("assignalias"):
            self.notes.append(f"assignalias treated as assign ({self._loc(ca)})")
            self._contassign(ca)

        # 4. Always blocks.
        for al in m.findall("always"):
            self._always(al)

        # 5. Instances are not supported by the Signal translation.
        for inst in list(m.findall("instance")) + list(m.findall("cell")):
            self.todo(f"module instance {inst.get('name', '?')}", inst)

        # 6. Finalize registers: infer inits, prune unknowns.
        for r in self.regs.values():
            self._infer_init(r)

        # 7. Record data references (for clock detection).
        self.clock_names = {n for n in self.sense_names
                            if n not in self.body_refs}
        for n in self.sense_names - self.clock_names:
            self.notes.append(
                f"sense-list signal `{n}` is also read as data "
                f"(async reset?); modeled synchronously")

    def _contassign(self, ca: ET.Element) -> None:
        kids = [k for k in ca if k.tag != "comment"]
        if len(kids) != 2:
            self.todo("malformed continuous assign", ca)
            return
        rhs, lhs = kids
        if lhs.tag == "varref":
            name = lhs.get("name", "")
            var = self.vars.get(name)
            if var is None:
                self.todo(f"assign to unknown net {name}", ca)
                return
            e = self._expr(rhs, {})
            self.combs[name] = _coerce(e, var.ty)
        elif lhs.tag == "arraysel":
            self.todo("continuous assign to memory element", ca)
        else:
            self.todo(f"continuous assign to {lhs.tag} lhs", ca)

    # ---------------- always blocks ----------------

    def _always(self, al: ET.Element) -> None:
        sentree = al.find("sentree")
        clocked = False
        if sentree is not None:
            for si in sentree.findall("senitem"):
                if si.get("edgeType") in ("POS", "NEG"):
                    clocked = True
                    vr = si.find("varref")
                    if vr is not None:
                        self.sense_names.add(vr.get("name", ""))
                    if si.get("edgeType") == "NEG":
                        self.notes.append(
                            "negedge sensitivity approximated as posedge "
                            f"({self._loc(si)})")
        stmts = [k for k in al if k.tag != "sentree"]
        if clocked:
            nb: dict[str, E] = {}
            bl: dict[str, E] = {}
            self._exec(stmts, nb, bl, None, clocked=True)
            for name, e in bl.items():
                self.notes.append(
                    f"blocking assignment to `{name}` in clocked always "
                    "treated as a register update")
                nb.setdefault(name, e)
            for name, e in nb.items():
                var = self.vars.get(name)
                if var is None:
                    continue
                reg = self.regs.setdefault(name, _Reg(name, var.ty))
                if reg.next is not None:
                    # merge multiple always blocks writing the same reg
                    self.notes.append(
                        f"register `{name}` written from several always "
                        "blocks; updates merged")
                    e = _substitute(e, {name: reg.next})
                reg.next = _coerce(e, var.ty)
        else:
            bl: dict[str, E] = {}
            self._exec(stmts, {}, bl, None, clocked=False)
            for name, e in bl.items():
                var = self.vars.get(name)
                if var is None:
                    continue
                if name in _refs(e):
                    self.todo(f"latch inferred for `{name}` in always_comb "
                              "(self-reference replaced by 0)", al)
                    zero = _cbool(False) if var.ty == BOOL \
                        else _cbv(0, _width(var.ty))
                    e = _substitute(e, {name: zero})
                self.combs[name] = _coerce(e, var.ty)

    def _exec(self, nodes: list, nb: dict, bl: dict, guard: E | None,
              clocked: bool) -> None:
        """Symbolic execution with branch-merge semantics.

        nb: pending non-blocking (register) updates, var -> E
        bl: blocking environment, var -> E (reads resolve through it)
        guard: path condition (side effects only: memory writes, asserts)
        """
        for node in nodes:
            tag = node.tag
            if tag == "begin":
                self._exec(list(node), nb, bl, guard, clocked)
            elif tag in ("assigndly", "assign"):
                self._do_assign(node, nb, bl, guard, clocked,
                                blocking=(tag == "assign"))
            elif tag == "if":
                self._do_if(node, nb, bl, guard, clocked)
            elif tag == "case":
                self._do_case(node, nb, bl, guard, clocked)
            elif tag in ("display", "stop", "finish", "comment", "cexpr",
                         "sformatf", "text", "delay", "timingcontrol"):
                if tag == "finish":
                    self.notes.append(f"$finish ignored ({self._loc(node)})")
            else:
                self.todo(f"unsupported statement <{tag}>", node)

    def _do_assign(self, node: ET.Element, nb: dict, bl: dict,
                   guard: E | None, clocked: bool, blocking: bool) -> None:
        kids = [k for k in node if k.tag != "comment"]
        if len(kids) != 2:
            self.todo("malformed procedural assign", node)
            return
        rhs_n, lhs_n = kids
        rhs = self._expr(rhs_n, bl)
        store = bl if (blocking or not clocked) else nb

        if lhs_n.tag == "varref":
            name = lhs_n.get("name", "")
            var = self.vars.get(name)
            if var is None:
                self.todo(f"assign to unknown variable {name}", node)
                return
            store[name] = _coerce(rhs, var.ty)
        elif lhs_n.tag == "arraysel":
            base = lhs_n.find("varref")
            mname = base.get("name", "") if base is not None else ""
            mem = self.mems.get(mname)
            if mem is None:
                self.todo(f"write to unknown array {mname}", node)
                return
            idx = self._expr(list(lhs_n)[1], bl)
            mem.writes.append((guard,
                               _coerce(idx, BV(mem.abits)),
                               _coerce(rhs, BV(mem.data_width))))
        elif lhs_n.tag == "sel":
            self._do_partsel_assign(lhs_n, rhs, store, node, bl)
        else:
            self.todo(f"assign to {lhs_n.tag} lhs", node)

    def _do_partsel_assign(self, lhs_n: ET.Element, rhs: E, store: dict,
                           node: ET.Element, bl: dict) -> None:
        """v[lo +: w] <= rhs  — splice into the pending value of v."""
        kids = list(lhs_n)
        base_n = kids[0]
        if base_n.tag != "varref" or len(kids) != 3 \
                or kids[1].tag != "const" or kids[2].tag != "const":
            self.todo("unsupported part-select assignment target", node)
            return
        name = base_n.get("name", "")
        var = self.vars.get(name)
        if var is None or var.ty == BOOL:
            self.todo(f"part-select assign to {name}", node)
            return
        lo = self._const_int(kids[1])
        w = self._const_int(kids[2])
        total = _width(var.ty)
        base = store.get(name, bl.get(name, _ref(name, var.ty)))
        parts = []  # MSB first
        if lo + w < total:
            parts.append(E("sel", BV(total - lo - w), (base,),
                           (lo + w, total - lo - w)))
        parts.append(_coerce(rhs, BV(w)))
        if lo > 0:
            parts.append(E("sel", BV(lo), (base,), (0, lo)))
        e = parts[0]
        for p in parts[1:]:
            e = E("op", BV(_width(e.ty) + _width(p.ty)), (e, p), "concat")
        store[name] = e

    def _do_if(self, node: ET.Element, nb: dict, bl: dict,
               guard: E | None, clocked: bool) -> None:
        kids = [k for k in node if k.tag != "comment"]
        if not kids:
            return
        cond_n, branches = kids[0], kids[1:]

        # Verilator lowers `assert (P);` (with --assert) into
        #   if (<cexpr gate>) { if (!P) { $display(...); $stop; } }
        if cond_n.tag == "cexpr":
            for b in branches[:1]:                  # then-branch only
                self._exec([b] if b.tag != "begin" else list(b),
                           nb, bl, guard, clocked)
            return
        if self._is_assert_fail_branch(branches):
            fail = _coerce(self._expr(cond_n, bl), BOOL)
            prop = _not(_and(guard, fail))          # guard -> !fail
            n = len(self.props) + 1
            self.props.append(_Prop(f"prop_{n}", prop, self._loc(node),
                                    self._src_line(node)))
            return

        c = _coerce(self._expr(cond_n, bl), BOOL)
        nb_t, bl_t = dict(nb), dict(bl)
        nb_e, bl_e = dict(nb), dict(bl)
        then_n = branches[0] if branches else None
        else_n = branches[1] if len(branches) > 1 else None
        if then_n is not None:
            self._exec([then_n] if then_n.tag != "begin" else list(then_n),
                       nb_t, bl_t, _and(guard, c), clocked)
        if else_n is not None:
            self._exec([else_n] if else_n.tag != "begin" else list(else_n),
                       nb_e, bl_e, _and(guard, _not(c)), clocked)
        self._merge(nb, c, nb_t, nb_e, self._nb_base)
        self._merge(bl, c, bl_t, bl_e, self._bl_base)

    def _nb_base(self, name: str) -> E:
        var = self.vars.get(name)
        return _ref(name, var.ty if var else BOOL)

    _bl_base = _nb_base

    def _merge(self, out: dict, c: E, s_t: dict, s_e: dict, base_fn) -> None:
        names = list(s_t) + [n for n in s_e if n not in s_t]
        for name in names:                       # deterministic order
            t = s_t.get(name, out.get(name, base_fn(name)))
            e = s_e.get(name, out.get(name, base_fn(name)))
            out[name] = t if t is e else _mux(c, t, e)

    # `out.get(name, base_fn(name))` above makes an unmodified branch fall
    # back to the pre-branch pending value (Verilog "hold" semantics).

    def _do_case(self, node: ET.Element, nb: dict, bl: dict,
                 guard: E | None, clocked: bool) -> None:
        kids = [k for k in node if k.tag != "comment"]
        if not kids:
            return
        sel = self._expr(kids[0], bl)
        arms: list[tuple[E | None, list]] = []      # (cond|None=default, stmts)
        for item in kids[1:]:
            if item.tag != "caseitem":
                self.todo(f"unexpected case child <{item.tag}>", node)
                continue
            conds, stmts = [], []
            for k in item:
                if k.tag in _STMT_TAGS or stmts:
                    stmts.append(k)
                else:
                    conds.append(k)
            cond: E | None = None
            for cn in conds:
                ce = self._expr(cn, bl)
                w = max(_width(sel.ty), _width(ce.ty))
                eq = E("op", BOOL,
                       (_coerce(sel, BV(w)) if sel.ty != BOOL else sel,
                        _coerce(ce, sel.ty if sel.ty == BOOL else BV(w))),
                       "eq")
                cond = eq if cond is None else _or(cond, eq)
            arms.append((cond, stmts))
        # default arm(s) at the end; fold as an if/else-if chain.
        self._case_chain(arms, nb, bl, guard, clocked)

    def _case_chain(self, arms: list, nb: dict, bl: dict,
                    guard: E | None, clocked: bool) -> None:
        if not arms:
            return
        cond, stmts = arms[0]
        if cond is None:                            # default: unconditional
            self._exec(stmts, nb, bl, guard, clocked)
            self._case_chain(arms[1:], nb, bl, guard, clocked)
            return
        nb_t, bl_t = dict(nb), dict(bl)
        nb_e, bl_e = dict(nb), dict(bl)
        self._exec(stmts, nb_t, bl_t, _and(guard, cond), clocked)
        self._case_chain(arms[1:], nb_e, bl_e,
                         _and(guard, _not(cond)), clocked)
        self._merge(nb, cond, nb_t, nb_e, self._nb_base)
        self._merge(bl, cond, bl_t, bl_e, self._bl_base)

    @staticmethod
    def _is_assert_fail_branch(branches: list) -> bool:
        """True iff the then-branch only reports failure ($display/$stop)."""
        if not branches:
            return False
        then = branches[0]
        leaves = list(then.iter())
        tags = {n.tag for n in leaves if n is not then}
        if "stop" not in tags and "finish" not in tags:
            return False
        return tags <= {"display", "sformatf", "time", "scopename", "stop",
                        "finish", "begin", "text", "comment", "cvtpackstring"}

    # ---------------- expression translation ----------------

    def _expr(self, node: ET.Element, bl: dict) -> E:
        tag = node.tag
        ty = self._ty_of(node.get("dtype_id"))
        kids = [k for k in node if k.tag != "comment"]

        if tag == "const":
            v = self._const_int(node)
            return _cbool(bool(v)) if ty == BOOL else _cbv(v, _width(ty))
        if tag == "varref":
            name = node.get("name", "")
            var = self.vars.get(name)
            if var is None:
                if name in self.mems:
                    self.todo(f"whole-array reference `{name}`", node)
                    return _cbv(0, _width(ty))
                self.todo(f"reference to unknown variable `{name}`", node)
                return _cbool(False) if ty == BOOL else _cbv(0, _width(ty))
            if var.is_param and var.param_val is not None:
                return _coerce(var.param_val, var.ty)
            self.body_refs.add(name)
            if name in bl:
                return bl[name]
            return _ref(name, var.ty)
        if tag == "cexpr":
            return _cbool(True)

        if tag in _BINOP_TAGS:
            op = _BINOP_TAGS[tag]
            a = self._expr(kids[0], bl)
            b = self._expr(kids[1], bl)
            if op in ("and", "or", "xor") and ty == BOOL:
                return E("op", BOOL, (_coerce(a, BOOL), _coerce(b, BOOL)), op)
            sgn = self._signed(kids[0].get("dtype_id"))
            if op in ("shl", "shr", "sra"):
                a = _coerce(a, ty, sgn)
                b = _coerce(b, b.ty if b.ty != BOOL else BV(1))
                return E("op", ty, (a, b), op)
            return E("op", ty, (_coerce(a, ty, sgn), _coerce(b, ty, sgn)), op)
        if tag in _CMP_TAGS:
            op, sgn = _CMP_TAGS[tag]
            a = self._expr(kids[0], bl)
            b = self._expr(kids[1], bl)
            if a.ty == BOOL and b.ty == BOOL:
                pass
            elif a.ty == BOOL or b.ty == BOOL:
                a, b = _coerce(a, BOOL), _coerce(b, BOOL)
                if op not in ("eq", "neq"):
                    a, b = _coerce(a, BV(1)), _coerce(b, BV(1))
            else:
                w = max(_width(a.ty), _width(b.ty))
                a, b = _coerce(a, BV(w), sgn), _coerce(b, BV(w), sgn)
            return E("op", BOOL, (a, b), op)
        if tag == "not":
            a = self._expr(kids[0], bl)
            return _not(_coerce(a, ty))
        if tag == "negate":
            return E("op", ty, (_coerce(self._expr(kids[0], bl), ty),), "neg")
        if tag in ("logand", "logor"):
            a = _coerce(self._expr(kids[0], bl), BOOL)
            b = _coerce(self._expr(kids[1], bl), BOOL)
            return E("op", BOOL, (a, b), "and" if tag == "logand" else "or")
        if tag == "lognot":
            return _not(_coerce(self._expr(kids[0], bl), BOOL))
        if tag in ("redor", "redand", "redxor"):
            a = self._expr(kids[0], bl)
            if a.ty == BOOL:
                return a if tag != "redxor" else a
            if tag == "redxor":
                self.todo("reduction xor approximated (parity fold)", node)
            return E("op", BOOL, (a,), tag)
        if tag == "extend":
            w = int(node.get("width", _width(ty)))
            return _coerce(self._expr(kids[0], bl), BV(w) if w > 1 else ty)
        if tag == "extends":
            w = int(node.get("width", _width(ty)))
            return _coerce(self._expr(kids[0], bl),
                           BV(w) if w > 1 else ty, signed=True)
        if tag == "concat":
            a = self._expr(kids[0], bl)
            b = self._expr(kids[1], bl)
            a = _coerce(a, BV(_width(a.ty)))
            b = _coerce(b, BV(_width(b.ty)))
            return E("op", BV(_width(a.ty) + _width(b.ty)), (a, b), "concat")
        if tag == "replicate":
            val = self._expr(kids[0], bl)
            val = _coerce(val, BV(_width(val.ty)))
            n = self._const_int(kids[1]) if kids[1].tag == "const" else 0
            if n <= 0:
                self.todo("non-constant replicate", node)
                return _cbv(0, _width(ty))
            e = val
            for _ in range(n - 1):
                e = E("op", BV(_width(e.ty) + _width(val.ty)),
                      (e, val), "concat")
            return e
        if tag == "cond":
            c = _coerce(self._expr(kids[0], bl), BOOL)
            t = _coerce(self._expr(kids[1], bl), ty)
            e = _coerce(self._expr(kids[2], bl), ty)
            return _mux(c, t, e)
        if tag == "sel":
            base = self._expr(kids[0], bl)
            base = _coerce(base, BV(_width(base.ty)))
            w = self._const_int(kids[2]) if len(kids) > 2 else _width(ty)
            out_ty = BOOL if w == 1 else BV(w)
            if kids[1].tag == "const":
                lo = self._const_int(kids[1])
                return E("sel", out_ty, (base,), (lo, w))
            idx = self._expr(kids[1], bl)
            idx = _coerce(idx, BV(_width(idx.ty)))
            return E("sel", out_ty, (base, idx), (None, w))
        if tag == "arraysel":
            base_n = kids[0]
            if base_n.tag == "varref" and base_n.get("name", "") in self.mems:
                mem = self.mems[base_n.get("name", "")]
                idx = _coerce(self._expr(kids[1], bl), BV(mem.abits))
                rd_ty = BOOL if mem.data_width == 1 else BV(mem.data_width)
                e = E("memread", BV(mem.data_width), (idx,), mem.name)
                return _coerce(e, rd_ty)
            base = self._expr(base_n, bl)
            base = _coerce(base, BV(_width(base.ty)))
            idx = self._expr(kids[1], bl)
            w = _width(ty)
            return E("sel", BOOL if w == 1 else BV(w),
                     (base, _coerce(idx, BV(_width(idx.ty)))), (None, w))
        if tag in ("time", "scopename", "sformatf"):
            return _cbv(0, _width(ty))

        self.todo(f"unsupported expression <{tag}>", node)
        return _cbool(False) if ty == BOOL else _cbv(0, _width(ty))

    # ---------------- register init inference ----------------

    def _infer_init(self, r: _Reg) -> None:
        var = self.vars[r.name]
        if var.init is not None:
            r.init = var.init
            return
        # Sync-reset pattern: next == mux(rst, const, _)
        e = r.next
        if e is not None and e.kind == "mux":
            c, t, _ = e.args
            if c.kind == "ref" and _RST_NAMES.match(str(c.aux)) \
                    and t.kind == "const":
                r.init = t.aux
                r.notes.append("init inferred from sync-reset branch")
                return
        r.init = False if r.ty == BOOL else 0
        r.notes.append("no declared init; defaulting to 0")


def _substitute(e: E, mapping: dict[str, E], depth: int = 0) -> E:
    if depth > 200:
        return e
    if e.kind == "ref" and e.aux in mapping:
        return mapping[e.aux]
    if not e.args:
        return e
    args = tuple(_substitute(a, mapping, depth + 1) for a in e.args)
    return E(e.kind, e.ty, args, e.aux)


# --------------------------------------------------------------------------
# Renderer: E -> Signal-DSL Lean terms
# --------------------------------------------------------------------------


class _Renderer:
    """Renders expression trees as Signal-DSL terms.

    `resolve(name)` returns the Lean binder for a variable, or None to
    request inlining of its combinational definition (used by the props
    renderer so properties only mention registers and inputs).
    """

    def __init__(self, tr: _Translator, resolve, name_of: dict[str, str]):
        self.tr = tr
        self.resolve = resolve
        self.name_of = name_of
        self.budget = 20000

    def sig_ty(self, ty: tuple) -> str:
        return "Bool" if ty == BOOL else f"BitVec {ty[1]}"

    def const_lit(self, e: E) -> str:
        if e.ty == BOOL:
            return "true" if e.aux else "false"
        return f"{e.aux}#{e.ty[1]}"

    def r(self, e: E, visiting: frozenset = frozenset()) -> str:
        self.budget -= 1
        if self.budget <= 0:
            raise TranslateError("expression too large for readable output")
        k = e.kind
        if k == "const":
            return f"(Signal.pure {self.const_lit(e)})"
        if k == "ref":
            name = str(e.aux)
            bound = self.resolve(name)
            if bound is not None:
                return bound
            if name in visiting:
                raise TranslateError(f"combinational cycle at {name}")
            if name in self.tr.combs:
                return self.r(self.tr.combs[name], visiting | {name})
            return self.name_of.get(name, name)
        if k == "mux":
            c, t, f = e.args
            return f"(Signal.mux {self.r(c, visiting)} " \
                   f"{self.r(t, visiting)} {self.r(f, visiting)})"
        if k == "sel":
            return self._sel(e, visiting)
        if k == "memread":
            return self._memread(e, visiting)
        if k == "op":
            return self._op(e, visiting)
        if k == "undef":
            return f"(Signal.pure {self.const_lit(E('const', e.ty, aux=0 if e.ty != BOOL else False))})"
        raise TranslateError(f"render: {k}")

    def _sel(self, e: E, v: frozenset) -> str:
        lo, w = e.aux
        base = self.r(e.args[0], v)
        if lo is not None:
            if w == 1 and e.ty == BOOL:
                return f"((·.getLsbD {lo}) <$> {base})"
            return f"((BitVec.extractLsb' {lo} {w}) <$> {base})"
        idx = self.r(e.args[1], v)
        if w == 1 and e.ty == BOOL:
            return f"((fun x i => x.getLsbD i.toNat) <$> {base} <*> {idx})"
        return (f"((fun x i => BitVec.extractLsb' i.toNat {w} x) <$> "
                f"{base} <*> {idx})")

    def _memread(self, e: E, v: frozenset) -> str:
        mem = self.tr.mems[str(e.aux)]
        wen, waddr, wdata = _merge_mem_ports(mem)
        return (f"(Signal.memoryComboRead {self.r(waddr, v)} "
                f"{self.r(wdata, v)} {self.r(wen, v)} {self.r(e.args[0], v)})")

    def _op(self, e: E, v: frozenset) -> str:
        op = e.aux
        a = lambda i: self.r(e.args[i], v)          # noqa: E731
        if op in ("and", "or", "xor"):
            sym = {"and": "&&&", "or": "|||", "xor": "^^^"}[op]
            return f"({a(0)} {sym} {a(1)})"
        if op == "not":
            if e.ty == BOOL:
                return f"(~~~{a(0)})"
            return f"((fun x => ~~~x) <$> {a(0)})"
        if op in ("add", "sub", "mul"):
            sym = {"add": "+", "sub": "-", "mul": "*"}[op]
            return f"({a(0)} {sym} {a(1)})"
        if op == "neg":
            return f"((fun x => -x) <$> {a(0)})"
        if op == "eq":
            return f"({a(0)} === {a(1)})"
        if op == "neq":
            return f"(~~~({a(0)} === {a(1)}))"
        cmp = {"ltu": ("BitVec.ult", 0, 1), "leu": ("BitVec.ule", 0, 1),
               "gtu": ("BitVec.ult", 1, 0), "geu": ("BitVec.ule", 1, 0),
               "lts": ("BitVec.slt", 0, 1), "les": ("BitVec.sle", 0, 1),
               "gts": ("BitVec.slt", 1, 0), "ges": ("BitVec.sle", 1, 0)}
        if op in cmp:
            fn, x, y = cmp[op]
            return f"(({fn} · ·) <$> {a(x)} <*> {a(y)})"
        if op == "shl":
            return f"((fun x y => x <<< y.toNat) <$> {a(0)} <*> {a(1)})"
        if op == "shr":
            return f"((fun x y => x >>> y.toNat) <$> {a(0)} <*> {a(1)})"
        if op == "sra":
            return (f"((fun x y => x.sshiftRight y.toNat) <$> "
                    f"{a(0)} <*> {a(1)})")
        if op == "concat":
            return f"((· ++ ·) <$> {a(0)} <*> {a(1)})"
        if op == "zext":
            return f"((BitVec.zeroExtend {e.ty[1]}) <$> {a(0)})"
        if op == "sext":
            return f"((BitVec.signExtend {e.ty[1]}) <$> {a(0)})"
        if op == "b2v":
            return f"((fun b => if b then 1#1 else 0#1) <$> {a(0)})"
        if op == "v2b":
            return f"((· == 1#1) <$> {a(0)})"
        if op == "redor":
            w = e.args[0].ty[1]
            return f"((fun x => x != 0#{w}) <$> {a(0)})"
        if op == "redand":
            w = e.args[0].ty[1]
            return f"((fun x => x == BitVec.allOnes {w}) <$> {a(0)})"
        if op == "redxor":
            w = e.args[0].ty[1]
            return (f"((fun x => (List.range {w}).foldl "
                    f"(fun acc i => xor acc (x.getLsbD i)) false) <$> {a(0)})")
        raise TranslateError(f"render op {op}")

    # ---- hw_cond pretty-printing for mux chains -------------------------

    def mux_chain(self, e: E) -> tuple[list[tuple[E, E]], E]:
        arms: list[tuple[E, E]] = []
        while e.kind == "mux":
            arms.append((e.args[0], e.args[1]))
            e = e.args[2]
        return arms, e

    def render_next(self, e: E, indent: str) -> str:
        """Render a register-next / comb expression; use hw_cond for
        priority mux chains of depth >= 2 (idiomatic FSM style)."""
        arms, default = self.mux_chain(e)
        if len(arms) < 2:
            return self.r(e)
        lines = [f"hw_cond {self.r(default)}"]
        for c, val in arms:
            lines.append(f"{indent}| {self.r(c)} => {self.r(val)}")
        return "\n".join(lines)


def _merge_mem_ports(mem: _Mem) -> tuple[E, E, E]:
    """Merge write sites into one (wen, waddr, wdata) port (last wins)."""
    if not mem.writes:
        return (_cbool(False), _cbv(0, mem.abits), _cbv(0, mem.data_width))
    wen: E | None = None
    waddr, wdata = mem.writes[0][1], mem.writes[0][2]
    for guard, addr, data in mem.writes:
        g = guard if guard is not None else _cbool(True)
        wen = g if wen is None else _or(wen, g)
        if len(mem.writes) > 1:
            waddr = _mux(g, addr, waddr)
            wdata = _mux(g, data, wdata)
        else:
            waddr, wdata = addr, data
    return (wen if wen is not None else _cbool(True), waddr, wdata)


def _expr_deps(tr: _Translator, e: E, acc: set | None = None) -> set:
    """Variable dependencies of `e`, including memory write-port deps."""
    if acc is None:
        acc = set()
    if e.kind == "ref":
        acc.add(e.aux)
    if e.kind == "memread":
        mem = tr.mems[str(e.aux)]
        for part in _merge_mem_ports(mem):
            _expr_deps(tr, part, acc)
    for a in e.args:
        _expr_deps(tr, a, acc)
    return acc


def _comb_closure(tr: _Translator, roots: set) -> list[str]:
    """Topologically-ordered combinational defs needed for `roots`."""
    needed: set[str] = set()
    stack = [r for r in roots if r in tr.combs]
    while stack:
        n = stack.pop()
        if n in needed:
            continue
        needed.add(n)
        for d in _expr_deps(tr, tr.combs[n]):
            if d in tr.combs and d not in needed:
                stack.append(d)
    # topo order (Kahn over the needed sub-graph)
    deps = {n: {d for d in _expr_deps(tr, tr.combs[n])
                if d in needed and d != n} for n in needed}
    order: list[str] = []
    placed: set[str] = set()
    pending = [n for n in tr.combs if n in needed]  # keep source order
    guard = 0
    while pending and guard <= len(tr.combs) ** 2 + 10:
        guard += 1
        progress = False
        for n in list(pending):
            if deps[n] - placed:
                continue
            order.append(n)
            placed.add(n)
            pending.remove(n)
            progress = True
        if not progress:
            n = pending.pop(0)                       # cycle: break arbitrarily
            tr.todos.append(f"combinational cycle through `{n}` at "
                            f"{tr.sv_path.name}:? (order forced)")
            order.append(n)
            placed.add(n)
    return order


# --------------------------------------------------------------------------
# Lean file generation
# --------------------------------------------------------------------------


def _cap(name: str) -> str:
    s = re.sub(r"[^0-9a-zA-Z_]", "_", name)
    if not s or not s[0].isalpha():
        s = "M" + s
    return s[0].upper() + s[1:]


def _defname(name: str) -> str:
    s = re.sub(r"[^0-9a-zA-Z_]", "_", name)
    if not s or not s[0].isalpha():
        s = "m" + s
    s = s[0].lower() + s[1:]
    if s in _LEAN_RESERVED:
        s += "_v"
    return s


class _Emitter:
    def __init__(self, tr: _Translator):
        self.tr = tr
        self.used: set[str] = set(_LEAN_RESERVED)
        # Stable Lean names for every original signal (original names
        # preserved whenever they are valid Lean identifiers).
        self.name_of: dict[str, str] = {}
        for name in list(tr.vars) + list(tr.mems):
            self.name_of[name] = _ident(name, self.used)
        self.cap = _cap(tr.top)
        self.fname = _defname(tr.top)
        self.state_ty = f"{self.cap}State"
        self.rend = _Renderer(tr, lambda n: self.name_of.get(n), self.name_of)

        self.inputs = sorted(
            [v for v in tr.vars.values()
             if v.direction == "input" and v.name not in tr.clock_names],
            key=lambda v: v.pin_index)
        self.outputs = sorted(
            [v for v in tr.vars.values() if v.direction == "output"],
            key=lambda v: v.pin_index)
        self.regs = list(tr.regs.values())
        self._analyze_feedback()

    # ---- feedback analysis ----------------------------------------------

    def _analyze_feedback(self) -> None:
        tr = self.tr
        reg_names = set(tr.regs)

        def reg_deps(e: E) -> set:
            seen: set[str] = set()
            out: set[str] = set()
            stack = list(_expr_deps(tr, e))
            while stack:
                n = stack.pop()
                if n in seen:
                    continue
                seen.add(n)
                if n in reg_names:
                    out.add(n)
                elif n in tr.combs:
                    stack.extend(_expr_deps(tr, tr.combs[n]))
            return out

        graph = {r.name: reg_deps(r.next) if r.next is not None else set()
                 for r in self.regs}
        # also: memory write ports depending on registers keep the mem
        # inside the feedback story, but memread deps already include them.
        self.feedback = False
        for r in graph:
            seen: set[str] = set()
            stack = list(graph[r])
            while stack:
                n = stack.pop()
                if n == r:
                    self.feedback = True
                    break
                if n in seen:
                    continue
                seen.add(n)
                stack.extend(graph.get(n, ()))
            if self.feedback:
                break
        self.reg_graph = graph

    # ---- headers ----------------------------------------------------------

    def _header(self) -> list[str]:
        tr = self.tr
        out = [
            "/-",
            f"  {HEADER_NOTE}",
            f"  Source     : {tr.sv_path}",
            f"  Top module : {tr.top}",
            "  Semantics  : clk is implicit in Signal semantics; the",
            "               synchronous reset is folded into a mux on each",
            "               register input. Semantic equivalence with the",
            "               source is anchored by the shared Yosys",
            "               elaboration used by the prover backend.",
            "-/",
            "",
            "import Sparkle",
            "",
            "open Sparkle.Core.Domain",
            "open Sparkle.Core.Signal",
            "",
            f"namespace SparkleFV.{self.cap}",
            "",
        ]
        for n in tr.notes:
            out.append(f"-- NOTE: {n}")
        for t in tr.todos:
            out.append(f"-- TODO(unsupported): {t}")
        if tr.notes or tr.todos:
            out.append("")
        return out

    def _params(self) -> str:
        parts = []
        for v in self.inputs:
            parts.append(f"({self.name_of[v.name]} : Signal dom "
                         f"{'Bool' if v.ty == BOOL else f'(BitVec {v.ty[1]})'})")
        return " ".join(parts)

    def _ret_ty(self) -> str:
        tys = []
        for v in self.outputs:
            tys.append(f"Signal dom "
                       f"{'Bool' if v.ty == BOOL else f'(BitVec {v.ty[1]})'}")
        if not tys:
            return "Signal dom Bool  -- (no outputs; placeholder)"
        return " × ".join(tys)

    def _init_lit(self, r: _Reg) -> str:
        if r.ty == BOOL:
            return "true" if r.init else "false"
        return f"{int(r.init)}#{r.ty[1]}"

    # ---- output expression helpers ----------------------------------------

    def _out_expr(self, v: _Var) -> tuple[str, E | None]:
        """(rendered ref or fallback, root E for dependency computation)."""
        if v.name in self.tr.combs:
            return self.name_of[v.name], _ref(v.name, v.ty)
        if v.name in self.tr.regs:
            return self.name_of[v.name], _ref(v.name, v.ty)
        self.tr.todos.append(f"output `{v.name}` is undriven; tied to 0")
        lit = "true" if v.ty == BOOL else f"0#{v.ty[1]}"
        if v.ty == BOOL:
            lit = "false"
        return f"(Signal.pure {lit})", None

    def _emit_comb_lets(self, names: list[str], indent: str) -> list[str]:
        out = []
        for n in names:
            e = self.tr.combs[n]
            body = self.rend.render_next(e, indent + "  ")
            note = self.tr.comb_notes.get(n, "")
            if note:
                out.append(f"{indent}-- {note}")
            if "\n" in body:
                out.append(f"{indent}let {self.name_of[n]} :=")
                out.append(f"{indent}  " + body.replace("\n", "\n"))
            else:
                out.append(f"{indent}let {self.name_of[n]} := {body}")
        return out

    # ---- main design emission ----------------------------------------------

    def design(self) -> str:
        tr = self.tr
        out = self._header()

        # Documentation of ports.
        in_doc = ", ".join(f"`{v.name}`" for v in self.inputs) or "(none)"
        out_doc = ", ".join(f"`{v.name}`" for v in self.outputs) or "(none)"

        reg_next_roots: set[str] = set()
        for r in self.regs:
            if r.next is not None:
                reg_next_roots |= _expr_deps(tr, r.next)
        body_combs = _comb_closure(tr, reg_next_roots)

        out_roots: set[str] = set()
        out_rendered: list[str] = []
        for v in self.outputs:
            txt, root = self._out_expr(v)
            out_rendered.append(txt)
            if root is not None:
                out_roots |= _expr_deps(tr, root)
        out_combs = _comb_closure(tr, out_roots)

        multi = self.feedback and len(self.regs) >= 2
        single_loop = self.feedback and len(self.regs) == 1

        if multi:
            out.append(f"/-- Architectural state of `{tr.top}` "
                       "(one field per hardware register). -/")
            out.append(f"declare_signal_state {self.state_ty}")
            for r in self.regs:
                ty = "Bool" if r.ty == BOOL else f"BitVec {r.ty[1]}"
                out.append(f"  | {self.name_of[r.name]} : {ty} := "
                           f"{self._init_lit(r)}")
            out.append("")

        out.append(f"/-- Signal-DSL model of `{tr.top}`.")
        out.append(f"    Inputs: {in_doc}; outputs: {out_doc}. -/")

        if multi:
            out += self._design_multi(body_combs, out_combs, out_rendered)
        elif single_loop:
            out += self._design_single_loop(body_combs, out_combs,
                                            out_rendered)
        else:
            out += self._design_flat(out_combs, out_rendered)

        out += ["", f"end SparkleFV.{self.cap}", ""]
        return "\n".join(out)

    def _reg_next_lets(self, indent: str) -> list[str]:
        """`let <r>_next := ...` bindings for every register."""
        out = []
        self.next_name: dict[str, str] = {}
        for r in self.regs:
            nn = _ident(f"{self.name_of[r.name]}_next", self.used)
            self.next_name[r.name] = nn
            for note in r.notes:
                out.append(f"{indent}-- {note}")
            body = self.rend.render_next(
                r.next if r.next is not None else _ref(r.name, r.ty),
                indent + "  ")
            if "\n" in body:
                out.append(f"{indent}let {nn} :=")
                out.append(f"{indent}  " + body)
            else:
                out.append(f"{indent}let {nn} := {body}")
        return out

    def _design_multi(self, body_combs, out_combs, out_rendered) -> list[str]:
        tr = self.tr
        out = [f"private def {self.fname}Body {{dom : DomainConfig}}"]
        p = self._params()
        if p:
            out.append(f"    {p}")
        out.append(f"    (state : Signal dom {self.state_ty}) : "
                   f"Signal dom {self.state_ty} :=")
        for r in self.regs:
            n = self.name_of[r.name]
            out.append(f"  let {n} := {self.state_ty}.{n} state")
        if body_combs:
            out.append("  -- combinational logic feeding the registers")
            out += self._emit_comb_lets(body_combs, "  ")
        out.append("  -- next-state values (non-blocking updates, one per "
                   "register)")
        out += self._reg_next_lets("  ")
        out.append("  bundleAll! [")
        items = []
        for r in self.regs:
            items.append(f"    Signal.register {self._init_lit(r)} "
                         f"{self.next_name[r.name]}")
        out.append(",\n".join(items))
        out.append("  ]")
        out.append("")
        out.append(f"def {self.fname} {{dom : DomainConfig}}")
        if p:
            out.append(f"    {p}")
        out.append(f"    : {self._ret_ty()} :=")
        args = " ".join(self.name_of[v.name] for v in self.inputs)
        call = f"{self.fname}Body {args} state".replace("  ", " ")
        out.append(f"  let state := Signal.loop fun state => {call}")
        for r in self.regs:
            n = self.name_of[r.name]
            out.append(f"  let {n} := {self.state_ty}.{n} state")
        if out_combs:
            out.append("  -- combinational logic feeding the outputs")
            out += self._emit_comb_lets(out_combs, "  ")
        out.append(self._out_tuple(out_rendered))
        return out

    def _design_single_loop(self, body_combs, out_combs,
                            out_rendered) -> list[str]:
        r = self.regs[0]
        n = self.name_of[r.name]
        out = [f"def {self.fname} {{dom : DomainConfig}}"]
        p = self._params()
        if p:
            out.append(f"    {p}")
        out.append(f"    : {self._ret_ty()} :=")
        ty = "Bool" if r.ty == BOOL else f"BitVec {r.ty[1]}"
        out.append(f"  let {n} : Signal dom ({ty}) := Signal.loop fun {n} =>")
        if body_combs:
            out += self._emit_comb_lets(body_combs, "    ")
        out += self._reg_next_lets("    ")
        out.append(f"    Signal.register {self._init_lit(r)} "
                   f"{self.next_name[r.name]}")
        if out_combs:
            out.append("  -- combinational logic feeding the outputs")
            out += self._emit_comb_lets(out_combs, "  ")
        out.append(self._out_tuple(out_rendered))
        return out

    def _design_flat(self, out_combs, out_rendered) -> list[str]:
        """No feedback: interleave registers and combs topologically."""
        tr = self.tr
        out = [f"def {self.fname} {{dom : DomainConfig}}"]
        p = self._params()
        if p:
            out.append(f"    {p}")
        out.append(f"    : {self._ret_ty()} :=")
        # unified topo order over regs + all combs
        nodes: dict[str, E] = {}
        for name, e in tr.combs.items():
            nodes[name] = e
        for r in self.regs:
            nodes[r.name] = r.next if r.next is not None \
                else _ref(r.name, r.ty)
        deps = {n: {d for d in _expr_deps(tr, e) if d in nodes and d != n}
                for n, e in nodes.items()}
        # registers break timing arcs? No: a register's OUTPUT is available
        # only after its input in Lean binding order, and with no feedback
        # the graph is acyclic, so a plain topo sort works.
        order, placed = [], set()
        pending = list(nodes)
        while pending:
            progress = False
            for n in list(pending):
                if deps[n] - placed:
                    continue
                order.append(n)
                placed.add(n)
                pending.remove(n)
                progress = True
            if not progress:
                n = pending.pop(0)
                tr.todos.append(f"unexpected dependency cycle at `{n}` "
                                "(binding order forced)")
                order.append(n)
                placed.add(n)
        self.next_name = {}
        for n in order:
            if n in tr.regs:
                r = tr.regs[n]
                for note in r.notes:
                    out.append(f"  -- {note}")
                body = self.rend.render_next(
                    r.next if r.next is not None else _ref(n, r.ty), "      ")
                nn = _ident(f"{self.name_of[n]}_next", self.used)
                if "\n" in body:
                    out.append(f"  let {nn} :=")
                    out.append(f"    {body}")
                else:
                    out.append(f"  let {nn} := {body}")
                out.append(f"  let {self.name_of[n]} := "
                           f"Signal.register {self._init_lit(r)} {nn}")
            else:
                out += self._emit_comb_lets([n], "  ")
        out.append(self._out_tuple(out_rendered))
        return out

    def _out_tuple(self, out_rendered: list[str]) -> str:
        if not out_rendered:
            return "  (Signal.pure true)  -- no outputs"
        if len(out_rendered) == 1:
            return f"  {out_rendered[0]}"
        return "  (" + ", ".join(out_rendered) + ")"

    # ---- props file ---------------------------------------------------------

    def props(self) -> str | None:
        tr = self.tr
        if not tr.props:
            return None
        out = [
            "/-",
            f"  {HEADER_NOTE}",
            f"  Source     : {tr.sv_path}",
            f"  Top module : {tr.top}",
            "  Proof obligations extracted from immediate `assert`",
            "  statements; combinational nets are inlined so each property",
            "  mentions only registers and primary inputs.",
            "-/",
            "",
            "import Sparkle",
            "import Sparkle.Verification.Temporal",
            "",
            "open Sparkle.Core.Domain",
            "open Sparkle.Core.Signal",
            "open Sparkle.Verification.Temporal",
            "",
            f"namespace SparkleFV.{self.cap}Props",
            "",
        ]
        reg_summary = ", ".join(
            f"{self.name_of[r.name]} : "
            f"{'Bool' if r.ty == BOOL else f'BitVec {r.ty[1]}'}"
            for r in self.regs) or "(none — purely combinational)"

        for p in tr.props:
            # inline comb nets so params are registers/inputs only
            expr = self._inline_combs(p.expr)
            params = self._prop_params(expr)
            rend = _Renderer(tr, lambda n: None if n in tr.combs
                             else self.name_of.get(n), self.name_of)
            try:
                body = rend.r(expr)
            except TranslateError as exc:
                tr.todos.append(f"property {p.name}: {exc}")
                body = "(Signal.pure true)  -- TODO(unsupported): see header"
            plist = " ".join(
                f"({self.name_of[n]} : Signal dom "
                f"{'Bool' if t == BOOL else f'(BitVec {t[1]})'})"
                for n, t in params)
            src_doc = f"{p.src}" + (f" `{p.text}`" if p.text else "")
            out.append(f"/-- Property `{p.name}` (safety); source: {src_doc}")
            out.append("    The condition must hold at every cycle. -/")
            out.append(f"def {p.name} {{dom : DomainConfig}}")
            if plist:
                out.append(f"    {plist} : Signal dom Bool :=")
            else:
                out.append("    : Signal dom Bool :=")
            out.append(f"  {body}")
            out.append("")
            args = " ".join(self.name_of[n] for n, _ in params)
            out += [
                "-- PROOF PLAN (auto-generated by sparkle-fv):",
                f"--   property          : {p.name} (kind: safety, "
                f"src: {p.src})",
                f"--   design registers  : {reg_summary}",
                "--   binding           : instantiate the parameters with "
                "the signals produced",
                f"--                       by `SparkleFV.{self.cap}."
                f"{self.fname}` (project the state loop),",
                "--                       then unfold and prove by "
                "induction over time.",
                f"--   suggested tactics : `intro t`; `simp [{p.name}, "
                f"{self.fname}]`;",
                "--                       strengthen with an inductive "
                "invariant if the property",
                "--                       is not inductive as stated "
                "(invariant slot below).",
                f"-- INVARIANT-SLOT-BEGIN {p.name}",
                f"def candidateInv_{p.name} : Prop := True",
                f"-- INVARIANT-SLOT-END {p.name}",
                "",
                f"/-- Safety obligation: `{p.name}` holds at every cycle "
                "of the design.",
                "    NOTE: as stated the parameters are universally "
                "quantified; the AI prover",
                "    threads the actual design binding here before "
                "discharging the goal. -/",
                f"theorem {self.fname}_{p.name} {{dom : DomainConfig}}"
                + (f"\n    {plist} :" if plist else " :"),
                f"    always ({p.name}{' ' + args if args else ''}) := by",
                "  sorry",
                "",
            ]
        out += [f"end SparkleFV.{self.cap}Props", ""]
        return "\n".join(out)

    def _inline_combs(self, e: E, depth: int = 0,
                      visiting: frozenset = frozenset()) -> E:
        if depth > 500:
            return e
        if e.kind == "ref" and e.aux in self.tr.combs \
                and e.aux not in visiting:
            return self._inline_combs(self.tr.combs[e.aux], depth + 1,
                                      visiting | {e.aux})
        if not e.args:
            return e
        args = tuple(self._inline_combs(a, depth + 1, visiting)
                     for a in e.args)
        return E(e.kind, e.ty, args, e.aux)

    def _prop_params(self, e: E) -> list[tuple[str, tuple]]:
        seen: list[tuple[str, tuple]] = []
        names: set[str] = set()

        def go(x: E) -> None:
            if x.kind == "ref" and x.aux not in names \
                    and x.aux not in self.tr.combs:
                var = self.tr.vars.get(str(x.aux))
                names.add(x.aux)
                seen.append((str(x.aux), var.ty if var else x.ty))
            if x.kind == "memread":
                mem = self.tr.mems[str(x.aux)]
                for part in _merge_mem_ports(mem):
                    go(part)
            for a in x.args:
                go(a)

        go(e)
        return seen


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------


def _run_verilator(sv_path: Path, top: str, out_dir: Path) -> Path:
    if shutil.which("verilator") is None:
        raise TranslateError("verilator not found on PATH")
    xml_dir = out_dir / "xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    xml_file = xml_dir / f"{top}.xml"
    cmd = ["verilator", "--xml-only", "--assert",
           "--xml-output", str(xml_file), "-Wno-fatal",
           str(sv_path), "--top-module", top]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if proc.returncode != 0 or not xml_file.exists():
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-8:]
        raise TranslateError("verilator --xml-only failed: "
                             + " | ".join(tail))
    return xml_file


def translate(sv_path: Path, top: str, out_dir: Path) -> TranslateResult:
    """Translate behavioral SystemVerilog into idiomatic Sparkle Signal DSL.

    Args:
        sv_path: The original SystemVerilog source file.
        top: Top module name.
        out_dir: Output directory for the generated ``.lean`` files
            (Verilator XML is kept under ``out_dir/xml`` for auditing).

    Returns:
        A :class:`TranslateResult`.  Unsupported constructs never raise;
        they are recorded in ``stats["todos"]`` and marked with
        ``-- TODO(unsupported)`` comments.  Hard environment failures
        (missing verilator, unparsable XML, unknown top) raise
        :class:`TranslateError`.
    """
    sv_path = Path(sv_path)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    xml_file = _run_verilator(sv_path, top, out_dir)
    try:
        root = ET.parse(xml_file).getroot()
    except ET.ParseError as exc:
        raise TranslateError(f"cannot parse Verilator XML: {exc}") from exc

    tr = _Translator(sv_path, top, root)
    tr.parse()
    em = _Emitter(tr)

    lean_file = out_dir / f"{em.cap}.lean"
    lean_file.write_text(em.design())

    props_text = em.props()
    props_file: Path | None = None
    if props_text is not None:
        props_file = out_dir / f"{em.cap}Props.lean"
        props_file.write_text(props_text)

    stats = {
        "registers": len(tr.regs),
        "memories": len(tr.mems),
        "combinational": len(tr.combs),
        "asserts": len(tr.props),
        "todos": list(tr.todos),
    }
    return TranslateResult(top=top, lean_file=lean_file,
                           props_file=props_file, stats=stats,
                           notes=list(tr.notes))


# --------------------------------------------------------------------------
# Self-test CLI:  python3 -m sparkle_fv.translate <design.sv> <top> [--out DIR]
# --------------------------------------------------------------------------


def _main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        prog="python3 -m sparkle_fv.translate",
        description="Translate behavioral SystemVerilog into idiomatic "
                    "Sparkle Signal DSL (Lean 4) via the Verilator XML AST.")
    parser.add_argument("design", help="SystemVerilog source file")
    parser.add_argument("top", help="top module name")
    parser.add_argument("--out", default=None,
                        help="output directory (default: alongside design)")
    args = parser.parse_args(argv)

    sv = Path(args.design)
    out_dir = Path(args.out) if args.out else sv.resolve().parent
    try:
        res = translate(sv, args.top, out_dir)
    except TranslateError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"top          : {res.top}")
    print(f"lean_file    : {res.lean_file}")
    print(f"props_file   : {res.props_file}")
    for k in ("registers", "memories", "combinational", "asserts"):
        print(f"{k:13}: {res.stats[k]}")
    for t in res.stats["todos"]:
        print(f"todo         : {t}")
    for n in res.notes:
        print(f"note         : {n}")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
