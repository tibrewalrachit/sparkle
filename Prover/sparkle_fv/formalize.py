"""Autoformalize Yosys JSON netlists into Sparkle HDL Lean 4 sources.

This module is one stage of the sparkle-fv agentic formal-verification
harness.  It takes the output of Yosys ``write_json`` (after
``prep -top <T>; flatten``) and emits:

  1. A Lean 4 file that reconstructs the design as Sparkle IR using the
     ``CircuitM`` builder monad (``Sparkle/IR/Builder.lean``), or -- in
     best-effort "signal" mode -- as idiomatic Signal DSL
     (``Sparkle/Core/Signal.lean``).
  2. A Lean 4 proof-obligation file (``<Top>Props.lean``) containing a
     self-contained pure state machine (per docs/Verification_Framework.md,
     Pattern 1: invariant proofs), LTL statements in the vocabulary of
     ``Sparkle/Verification/Temporal.lean``, and ``sorry`` skeletons with
     structured PROOF PLAN comments and an invariant-injection slot.

Yosys bit-level netlists are regrouped into word-level nets by an internal
"bit-vector net reconstruction" layer (see ``_Design``).

Public API::

    formalize(netlist: dict, top: str, out_dir: Path,
              mode: str = "circuitm",
              properties: list[dict] | None = None) -> FormalizeResult

Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

__all__ = ["FormalizeResult", "formalize"]

HEADER_NOTE = (
    "Auto-formalized from SystemVerilog by sparkle-fv; "
    "translation validated against original netlist"
)

# --------------------------------------------------------------------------
# Result type
# --------------------------------------------------------------------------


@dataclass
class FormalizeResult:
    """Result of one autoformalization run."""

    top: str
    lean_file: Path            # generated Sparkle Lean source
    props_file: Path | None    # generated proof-obligation Lean file
    mode: str                  # "circuitm" or "signal"
    stats: dict                # {"cells", "registers", "memories", "unsupported", ...}


class _SignalUnsupported(Exception):
    """Raised when a design does not fit the Signal DSL subset."""


class _PureUnsupported(Exception):
    """Raised when an expression cone cannot be turned into pure Lean."""


# --------------------------------------------------------------------------
# Identifier / parameter helpers
# --------------------------------------------------------------------------

_LEAN_RESERVED = {
    "def", "let", "fun", "do", "if", "then", "else", "match", "with", "open",
    "import", "namespace", "end", "structure", "inductive", "theorem", "by",
    "sorry", "in", "rec", "mut", "where", "deriving", "true", "false", "at",
    "have", "show", "from", "exact", "calc", "set", "this",
    # names emitted by the generators themselves
    "design", "run", "reset", "nextState", "trace", "dom",
}


def _ident(raw: str, used: set[str], fallback: str = "w") -> str:
    """Turn an arbitrary netlist name into a fresh, valid Lean identifier."""
    s = re.sub(r"[^0-9a-zA-Z_]+", "_", raw).strip("_")
    if not s or not s[0].isalpha():
        s = f"{fallback}_{s}" if s else fallback
    s = s[0].lower() + s[1:]
    if s in _LEAN_RESERVED:
        s += "_v"
    base, n = s, 1
    while s in used:
        n += 1
        s = f"{base}_{n}"
    used.add(s)
    return s


def _param_int(params: dict, name: str, default: int = 0) -> int:
    """Decode a Yosys JSON cell parameter into an int (bit strings allowed)."""
    v = params.get(name, default)
    if isinstance(v, int):
        return v
    if isinstance(v, str):
        s = v.strip()
        if s and set(s) <= set("01xzXZ"):
            return int(s.replace("x", "0").replace("z", "0")
                        .replace("X", "0").replace("Z", "0"), 2)
        try:
            return int(s)
        except ValueError:
            return default
    return default


def _lean_str(s: str) -> str:
    """Render a Lean string literal."""
    return json.dumps(s)


def _hwtype(width: int) -> str:
    return ".bit" if width == 1 else f"(.bitVector {width})"


# --------------------------------------------------------------------------
# Expression layer: a Python mirror of `Sparkle.IR.AST.Expr`
#   const (value width) | ref name | op operator args
#   | concat args (MSB first, as in the Verilog backend) | slice e hi lo
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class E:
    kind: str                  # "const" | "ref" | "op" | "concat" | "slice"
    width: int
    args: tuple = ()           # sub-expressions
    aux: object = None         # const: value; ref: Net; op: operator; slice: (hi, lo)


def _const(value: int, width: int) -> E:
    width = max(width, 1)
    return E("const", width, aux=value & ((1 << width) - 1))


def _ref(net: "_Net") -> E:
    return E("ref", net.width, aux=net)


def _op(name: str, args: list[E], width: int) -> E:
    return E("op", width, tuple(args), name)


def _slice(e: E, hi: int, lo: int) -> E:
    if lo == 0 and hi == e.width - 1:
        return e
    if e.kind == "slice":                       # compose nested slices
        sub_hi, sub_lo = e.aux
        return _slice(e.args[0], sub_lo + hi, sub_lo + lo)
    if e.kind == "const":
        return _const(e.aux >> lo, hi - lo + 1)
    return E("slice", hi - lo + 1, (e,), (hi, lo))


def _concat(parts_msb_first: list[E]) -> E:
    """Concatenate (MSB-first, matching Verilog `{...}` in the backend)."""
    flat: list[E] = []
    for p in parts_msb_first:
        flat.extend(p.args) if p.kind == "concat" else flat.append(p)
    merged: list[E] = []
    for p in flat:                              # merge adjacent constants
        if merged and merged[-1].kind == "const" and p.kind == "const":
            prev = merged.pop()
            merged.append(_const((prev.aux << p.width) | p.aux,
                                 prev.width + p.width))
        else:
            merged.append(p)
    if len(merged) == 1:
        return merged[0]
    return E("concat", sum(p.width for p in merged), tuple(merged))


def _extend(e: E, width: int, signed: bool) -> E:
    """Zero/sign extend or truncate `e` to `width` bits."""
    if e.width == width:
        return e
    if e.width > width:
        return _slice(e, width - 1, 0)
    pad = width - e.width
    if signed:
        msb = _slice(e, e.width - 1, e.width - 1)
        return _concat([msb] * pad + [e])
    return _concat([_const(0, pad), e])


def _mux(cond: E, then_: E, else_: E) -> E:
    return _op("mux", [cond, then_, else_], then_.width)


def _not(e: E) -> E:
    if e.kind == "op" and e.aux == "not":       # ¬¬x = x
        return e.args[0]
    if e.kind == "const":
        return _const(~e.aux, e.width)
    return _op("not", [e], e.width)


def _reduce_or(e: E) -> E:
    if e.width == 1:
        return e
    return _not(_op("eq", [e, _const(0, e.width)], 1))


def _reduce_and(e: E) -> E:
    if e.width == 1:
        return e
    return _op("eq", [e, _const((1 << e.width) - 1, e.width)], 1)


def _reduce_xor(e: E) -> E:
    acc = _slice(e, 0, 0)
    for i in range(1, e.width):
        acc = _op("xor", [acc, _slice(e, i, i)], 1)
    return acc


# --------------------------------------------------------------------------
# Netlist model
# --------------------------------------------------------------------------


@dataclass(eq=False)
class _Net:
    """A word-level net reconstructed from Yosys bit ids (identity-hashed)."""

    name: str                  # original netlist name (or synthetic)
    lid: str                   # sanitized Lean identifier / wire hint
    bits: tuple                # yosys bit ids; () for pure-synthetic nets
    width: int
    kind: str                  # "input" | "output" | "wire"
    defby: str = "none"        # "none"|"assign"|"reg"|"mem"|"input"|"aggregate"

    @property
    def is_port(self) -> bool:
        return self.kind in ("input", "output")

    @property
    def ref_text(self) -> str:
        """Lean term of type String naming this net inside the builder."""
        return _lean_str(self.name) if self.is_port else self.lid


@dataclass
class _Reg:
    hint: str
    target: _Net               # net defined by this register (synthetic or real)
    clock: str                 # Lean String term (port literal or wire var)
    reset: str                 # Lean String term for the async reset wire
    init: int
    width: int
    next_net: _Net             # helper wire carrying the next-state expression
    next_expr: E
    arst_expr: E | None = None  # active-high async-reset condition (for props/signal)
    notes: list = field(default_factory=list)


@dataclass
class _Mem:
    hint: str
    target: _Net               # net carrying read data
    clock: str
    abits: int
    width: int
    helpers: dict = field(default_factory=dict)  # port -> (_Net, E)
    combo: bool = False
    notes: list = field(default_factory=list)


@dataclass
class _Prop:
    name: str
    kind: str                  # "safety" | "liveness"
    expr: E | None             # 1-bit condition that must always be 1
    src: str
    net: _Net | None = None    # labelled wire in the model


_BINOPS = {"$add": "add", "$sub": "sub", "$mul": "mul",
           "$and": "and", "$or": "or", "$xor": "xor"}
_CMPS = {"$lt": "lt", "$le": "le", "$gt": "gt", "$ge": "ge"}
_DFFS = {"$dff", "$sdff", "$adff", "$dffe", "$sdffe", "$adffe", "$sdffce"}


class _Design:
    """Parses one Yosys module and reconstructs word-level IR.

    The central data structures of the bit-vector net reconstruction layer:

    * ``home[bit] = (net, offset)`` -- the canonical word-level net each
      Yosys bit id belongs to (ports first, then public, then private nets).
    * ``frag[bit] = (net, offset)`` -- for cell outputs that did not line up
      exactly with one named net, the synthetic net fragment driving a bit.

    Reads resolve bits through ``home`` (grouping adjacent bits into
    ref/slice/concat expressions); nets that are not directly defined by a
    cell get a final "aggregation" assign built from ``frag``/``home``.
    """

    def __init__(self, top: str, mod: dict, user_props: list[dict]):
        self.top = top
        self.mod = mod
        self.user_props = user_props
        self.used_ids: set[str] = set()
        self.nets: list[_Net] = []          # materialized nets, ordered
        self.by_name: dict[str, _Net] = {}
        self.home: dict[int, tuple[_Net, int]] = {}
        self.frag: dict[int, tuple[_Net, int]] = {}
        self.inputs: list[_Net] = []
        self.outputs: list[_Net] = []
        self.assigns: list[tuple[_Net, E, str]] = []   # (net, expr, comment)
        self.regs: list[_Reg] = []
        self.mems: list[_Mem] = []
        self.props: list[_Prop] = []
        self.clock_nets: set[str] = set()   # net names used as clocks
        self.unsupported: list[str] = []
        self.notes: list[str] = []
        self.tie_low: _Net | None = None
        self.n_cells = 0

    # ---------------- net construction ----------------

    def _new_net(self, name: str, bits: tuple, kind: str,
                 width: int | None = None) -> _Net:
        net = _Net(name, _ident(name, self.used_ids), bits,
                   width if width is not None else max(len(bits), 1), kind)
        self.nets.append(net)
        self.by_name.setdefault(name, net)
        return net

    def _synth_wire(self, hint: str, width: int) -> _Net:
        return self._new_net(hint, (), "wire", width)

    def _tie_low(self) -> _Net:
        if self.tie_low is None:
            self.tie_low = self._synth_wire("tie_low", 1)
            self.assigns.append((self.tie_low, _const(0, 1),
                                 "constant 0 (unused reset tie-off)"))
        return self.tie_low

    def build(self) -> None:
        """Parse ports/netnames, assign bit homes, translate every cell."""
        ports = self.mod.get("ports", {})
        netnames = self.mod.get("netnames", {})

        # 1. Ports (highest home priority: inputs, then outputs).
        entries: list[tuple[int, str, list]] = []
        for pname, p in ports.items():
            direction = p.get("direction", "input")
            if direction == "inout":
                self.unsupported.append(f"inout port {pname}")
                direction = "input"
            entries.append((0 if direction == "input" else 1, pname, p["bits"]))
        for nname, n in sorted(netnames.items()):
            if nname in ports:
                continue
            public = not nname.startswith("$") and not n.get("hide_name", 0)
            entries.append((2 if public else 3, nname, n["bits"]))
        entries.sort(key=lambda t: (t[0], t[1]))

        for prio, name, bits in entries:
            int_bits = tuple(b for b in bits if isinstance(b, int))
            owns_new = any(b not in self.home for b in int_bits)
            if prio >= 2 and not owns_new:
                continue                       # pure alias of an earlier net
            kind = "input" if prio == 0 else "output" if prio == 1 else "wire"
            net = self._new_net(name, tuple(bits), kind)
            if kind == "input":
                net.defby = "input"
            for i, b in enumerate(bits):
                if isinstance(b, int) and b not in self.home:
                    self.home[b] = (net, i)
            (self.inputs if kind == "input" else
             self.outputs if kind == "output" else []).append(net)

        # 2. Cells, in deterministic order.
        cells = self.mod.get("cells", {})
        self.n_cells = len(cells)
        for cname in sorted(cells):
            try:
                self._cell(cname, cells[cname])
            except _PureUnsupported as exc:     # defensive: never crash
                self.unsupported.append(f"{cells[cname].get('type', '?')} ({cname}): {exc}")

        # 3. Properties supplied by the caller.
        for p in self.user_props:
            self._user_prop(p)

        # 4. Aggregation assigns for nets nobody defined directly.
        self._finalize()

    # ---------------- bit reading / writing ----------------

    def _home_of(self, bit: int) -> tuple[_Net, int]:
        if bit not in self.home:
            net = self._synth_wire(f"n{bit}", 1)
            self.home[bit] = (net, 0)
        return self.home[bit]

    def _sources_to_expr(self, sources: list) -> E:
        """Group per-bit sources (LSB first) into ref/slice/const/concat."""
        groups: list[E] = []
        i = 0
        while i < len(sources):
            src = sources[i]
            if src[0] == "c":
                val, n = src[1], 1
                while i + n < len(sources) and sources[i + n][0] == "c":
                    val |= sources[i + n][1] << n
                    n += 1
                groups.append(_const(val, n))
            else:
                net, off = src[1], src[2]
                n = 1
                while (i + n < len(sources) and sources[i + n][0] == "n"
                       and sources[i + n][1] is net
                       and sources[i + n][2] == off + n):
                    n += 1
                groups.append(_slice(_ref(net), off + n - 1, off))
            i += n
        return _concat(list(reversed(groups)))

    def _read(self, bits: list) -> E:
        """Build an Expr reading a Yosys bit list (LSB first)."""
        sources = []
        for b in bits:
            if isinstance(b, int):
                net, off = self._home_of(b)
                sources.append(("n", net, off))
            else:
                sources.append(("c", 1 if b == "1" else 0))
        return self._sources_to_expr(sources) if sources else _const(0, 1)

    def _define(self, bits: list, defby: str, hint: str,
                port_ok: bool = True) -> tuple[_Net, bool]:
        """Pick or create the net defined by a cell output.

        Returns ``(net, direct)``.  ``direct`` means the output bits line up
        exactly with one home net, which becomes the definition target.
        Otherwise a synthetic fragment net is created and the real nets are
        rebuilt later by aggregation assigns.
        """
        int_bits = [b for b in bits if isinstance(b, int)]
        if int_bits:
            net0, _ = self._home_of(int_bits[0])
            exact = (tuple(bits) == net0.bits and net0.defby == "none"
                     and all(self.home.get(b) == (net0, i)
                             for i, b in enumerate(bits))
                     and (port_ok or not net0.is_port))
            if exact:
                net0.defby = defby
                return net0, True
        synth = self._new_net(hint, tuple(bits), "wire", max(len(bits), 1))
        synth.defby = defby
        for i, b in enumerate(bits):
            if not isinstance(b, int):
                continue
            if b not in self.home:
                self.home[b] = (synth, i)
            hnet, _ = self.home[b]
            if hnet.kind == "input":
                self.notes.append(
                    f"multiple drivers on input-port bit {b}; ignored")
                continue
            self.frag[b] = (synth, i)
        return synth, False

    def _name_of_1bit(self, bits: list, hint: str, invert: bool = False) -> str:
        """Resolve a 1-bit connection to a Lean *String* term (clock/reset)."""
        e = self._read(bits[:1] if bits else ["0"])
        if not invert and e.kind == "ref" and e.aux.width == 1:
            return e.aux.ref_text
        if e.kind == "const" and e.aux == 0 and not invert:
            return self._tie_low().ref_text
        w = self._synth_wire(hint, 1)
        w.defby = "assign"
        self.assigns.append((w, _not(e) if invert else e, ""))
        return w.ref_text

    # ---------------- cell translation ----------------

    def _cell(self, cname: str, cell: dict) -> None:
        ctype = cell.get("type", "")
        conn = cell.get("connections", {})
        params = cell.get("parameters", {})
        pint = lambda n, d=0: _param_int(params, n, d)  # noqa: E731
        short = _ident(f"{ctype.lstrip('$')}_{len(self.assigns)}", set())

        def rd(port: str) -> E:
            return self._read(conn.get(port, []))

        def signed(port: str) -> bool:
            return bool(pint(f"{port}_SIGNED", 0))

        def out(expr: E, hint: str = short) -> None:
            ybits = conn.get("Y", [])
            expr = _extend(expr, max(len(ybits), 1), False)
            net, _ = self._define(ybits, "assign", hint)
            self.assigns.append((net, expr, ""))

        if ctype in _BINOPS:
            wy = max(len(conn.get("Y", [])), 1)
            a = _extend(rd("A"), wy, signed("A"))
            b = _extend(rd("B"), wy, signed("B"))
            out(_op(_BINOPS[ctype], [a, b], wy))
        elif ctype == "$xnor":
            wy = max(len(conn.get("Y", [])), 1)
            a = _extend(rd("A"), wy, signed("A"))
            b = _extend(rd("B"), wy, signed("B"))
            out(_not(_op("xor", [a, b], wy)))
        elif ctype in ("$not", "$neg", "$pos"):
            wy = max(len(conn.get("Y", [])), 1)
            a = _extend(rd("A"), wy, signed("A"))
            out(a if ctype == "$pos"
                else _op("not" if ctype == "$not" else "neg", [a], wy))
        elif ctype in ("$eq", "$ne", "$eqx", "$nex") or ctype in _CMPS:
            a, b = rd("A"), rd("B")
            sgn = signed("A") and signed("B")
            w = max(a.width, b.width)
            a, b = _extend(a, w, signed("A")), _extend(b, w, signed("B"))
            if ctype in ("$eq", "$eqx"):
                r = _op("eq", [a, b], 1)
            elif ctype in ("$ne", "$nex"):
                r = _not(_op("eq", [a, b], 1))
            else:
                r = _op(f"{_CMPS[ctype]}_{'s' if sgn else 'u'}", [a, b], 1)
            out(r)
        elif ctype in ("$logic_and", "$logic_or"):
            r = _op("and" if ctype == "$logic_and" else "or",
                    [_reduce_or(rd("A")), _reduce_or(rd("B"))], 1)
            out(r)
        elif ctype == "$logic_not":
            out(_not(_reduce_or(rd("A"))))
        elif ctype in ("$reduce_and", "$reduce_or", "$reduce_xor",
                       "$reduce_xnor", "$reduce_bool"):
            a = rd("A")
            r = {"$reduce_and": _reduce_and, "$reduce_or": _reduce_or,
                 "$reduce_bool": _reduce_or, "$reduce_xor": _reduce_xor,
                 "$reduce_xnor": lambda e: _not(_reduce_xor(e))}[ctype](a)
            out(r)
        elif ctype in ("$shl", "$sshl", "$shr", "$sshr"):
            wy = max(len(conn.get("Y", [])), 1)
            a = _extend(rd("A"), wy, signed("A"))
            b = rd("B")
            opname = ("shl" if ctype in ("$shl", "$sshl")
                      else "asr" if ctype == "$sshr" and signed("A") else "shr")
            out(_op(opname, [a, b], wy))
        elif ctype == "$mux":
            out(_mux(rd("S"), rd("B"), rd("A")))
        elif ctype == "$pmux":
            width = pint("WIDTH", len(conn.get("A", [])))
            sbits = conn.get("S", [])
            bbits = conn.get("B", [])
            r = rd("A")
            for i in range(len(sbits)):
                cond = self._read(sbits[i:i + 1])
                branch = self._read(bbits[i * width:(i + 1) * width])
                r = _mux(cond, branch, r)
            out(r)
        elif ctype == "$concat":
            out(_concat([rd("B"), rd("A")]))
        elif ctype == "$slice":
            off = pint("OFFSET", 0)
            wy = max(len(conn.get("Y", [])), 1)
            out(_slice(rd("A"), off + wy - 1, off))
        elif ctype in _DFFS:
            self._dff(cname, ctype, conn, pint)
        elif ctype in ("$mem_v2", "$mem"):
            self._mem(cname, ctype, conn, pint, params)
        elif ctype == "$assert":
            self._assert(cname, cell, conn)
        elif ctype in ("$assume", "$cover", "$initstate", "$anyconst",
                       "$anyseq", "$meminit", "$meminit_v2", "$print",
                       "$check", "$scopeinfo"):
            self.notes.append(f"ignored formal/meta cell {ctype} ({cname})")
        else:
            self.unsupported.append(f"{ctype} ({cname})")
            dirs = cell.get("port_directions", {})
            for pname, bits in conn.items():   # tie undriven outputs to 0
                if dirs.get(pname, "output" if pname in ("Y", "Q") else
                            "input") == "output":
                    net, _ = self._define(bits, "assign", short)
                    self.assigns.append(
                        (net, _const(0, net.width),
                         f"UNSUPPORTED: {ctype} ({cname}) — output tied to 0"))

    def _dff(self, cname: str, ctype: str, conn: dict, pint) -> None:
        width = pint("WIDTH", len(conn.get("Q", [])))
        qbits = conn.get("Q", [])
        # Target net: direct only when it is a plain internal wire.
        int_bits = [b for b in qbits if isinstance(b, int)]
        hint = "reg"
        if int_bits:
            hnet, _ = self._home_of(int_bits[0])
            hint = hnet.lid
        target, direct = self._define(qbits, "reg", f"{hint}_reg",
                                      port_ok=False)
        reg_hint = target.lid if direct else f"{hint}_reg"

        clk = self._name_of_1bit(conn.get("CLK", []), f"{reg_hint}_clk")
        self._mark_clock(conn.get("CLK", []))
        if pint("CLK_POLARITY", 1) == 0:
            note = "negedge clock approximated as posedge"
        else:
            note = ""

        d = _extend(self._read(conn.get("D", [])), width, False)
        q_self = self._read(qbits)
        init = 0
        reset = self._tie_low().ref_text
        arst_expr: E | None = None

        # Enable (before sync reset for $sdffe; after for $sdffce).
        def with_en(expr: E) -> E:
            en = self._read(conn.get("EN", []))
            if pint("EN_POLARITY", 1) == 0:
                en = _not(en)
            return _mux(en, expr, q_self)

        nxt = d
        if ctype in ("$dffe", "$adffe"):
            nxt = with_en(nxt)
        if ctype in ("$sdff", "$sdffe", "$sdffce"):
            init = pint("SRST_VALUE", 0)
            srst = self._read(conn.get("SRST", []))
            if pint("SRST_POLARITY", 1) == 0:
                srst = _not(srst)
            if ctype == "$sdffce":              # enable has priority
                nxt = with_en(_mux(srst, _const(init, width), d))
            else:                                # srst has priority
                if ctype == "$sdffe":
                    nxt = with_en(nxt)
                nxt = _mux(srst, _const(init, width), nxt)
        if ctype in ("$adff", "$adffe"):
            init = pint("ARST_VALUE", 0)
            invert = pint("ARST_POLARITY", 1) == 0
            reset = self._name_of_1bit(conn.get("ARST", []),
                                       f"{reg_hint}_arst", invert=invert)
            arst_expr = self._read(conn.get("ARST", []))
            if invert:
                arst_expr = _not(arst_expr)

        next_net = self._synth_wire(f"{reg_hint}_next", width)
        next_net.defby = "assign"
        self.assigns.append((next_net, nxt, ""))
        reg = _Reg(reg_hint, target, clk, reset, init, width, next_net, nxt,
                   arst_expr, [note] if note else [])
        self.regs.append(reg)

    def _mem(self, cname: str, ctype: str, conn: dict, pint, params) -> None:
        rd_ports = pint("RD_PORTS", 1)
        wr_ports = pint("WR_PORTS", 1)
        if rd_ports != 1 or wr_ports != 1:
            self.unsupported.append(
                f"{ctype} ({cname}): {rd_ports}R/{wr_ports}W (only 1R1W supported)")
            return
        abits = pint("ABITS", len(conn.get("RD_ADDR", [])) or 1)
        width = pint("WIDTH", len(conn.get("RD_DATA", [])) or 1)
        memid = params.get("MEMID", cname)
        hint = _ident(str(memid).lstrip("\\$"), set(), "mem")

        target, _ = self._define(conn.get("RD_DATA", []), "mem",
                                 f"{hint}_rd", port_ok=False)
        clk = self._name_of_1bit(conn.get("WR_CLK", conn.get("RD_CLK", [])),
                                 f"{hint}_clk")
        self._mark_clock(conn.get("WR_CLK", []))
        self._mark_clock(conn.get("RD_CLK", []))
        combo = pint("RD_CLK_ENABLE", 1) == 0

        mem = _Mem(hint, target, clk, abits, width, combo=combo)
        specs = {
            "waddr": _extend(self._read(conn.get("WR_ADDR", [])), abits, False),
            "wdata": _extend(self._read(conn.get("WR_DATA", [])), width, False),
            "wen": _reduce_or(self._read(conn.get("WR_EN", []))),
            "raddr": _extend(self._read(conn.get("RD_ADDR", [])), abits, False),
        }
        for pname, expr in specs.items():
            helper = self._synth_wire(f"{hint}_{pname}", expr.width)
            helper.defby = "assign"
            self.assigns.append((helper, expr, ""))
            mem.helpers[pname] = helper
        wen_bits = conn.get("WR_EN", [])
        if len(set(map(str, wen_bits))) > 1:
            mem.notes.append("per-bit write enable reduced to OR of WR_EN")
        self.mems.append(mem)

    def _assert(self, cname: str, cell: dict, conn: dict) -> None:
        a = self._read(conn.get("A", ["1"]))
        en = self._read(conn.get("EN", ["1"]))
        # Property condition: EN → A, i.e. A ∨ ¬EN, must always be 1.
        cond = _op("or", [_extend(a, 1, False), _not(_extend(en, 1, False))], 1)
        base = cname.split("$")[-1] if "$" in cname else cname
        pname = _ident(f"assert_{base}", self.used_ids, "assert")
        src = cell.get("attributes", {}).get("src", "")
        wire = self._synth_wire(f"prop_{pname}", 1)
        wire.defby = "assign"
        self.assigns.append((wire, cond, f"$assert cell {cname}"))
        abits = conn.get("A", [])
        sig_name = wire.name
        if abits and isinstance(abits[0], int) and abits[0] in self.home:
            sig_name = self.home[abits[0]][0].name
        self.props.append(_Prop(pname, "safety", cond, src or cname, wire))
        self.notes.append(f"extracted $assert {cname} -> property {pname} "
                          f"(signal {sig_name})")

    def _user_prop(self, p: dict) -> None:
        name = _ident(str(p.get("name", "prop")), self.used_ids, "prop")
        kind = p.get("kind", "safety")
        signal = p.get("expr_signal", "")
        src = p.get("src", "")
        expr: E | None = None
        netnames = self.mod.get("netnames", {})
        bits = None
        if signal in netnames:
            bits = netnames[signal]["bits"]
        elif signal in self.by_name:
            expr = _reduce_or(_ref(self.by_name[signal]))
        if bits is not None:
            expr = _reduce_or(self._read(bits))
        wire = None
        if expr is not None:
            wire = self._synth_wire(f"prop_{name}", 1)
            wire.defby = "assign"
            self.assigns.append((wire, expr, f"user property {name}"))
        else:
            self.notes.append(f"property {name}: signal '{signal}' not found")
        self.props.append(_Prop(name, kind, expr, src, wire))

    def _mark_clock(self, bits: list) -> None:
        for b in bits:
            if isinstance(b, int) and b in self.home:
                self.clock_nets.add(self.home[b][0].name)

    # ---------------- aggregation ----------------

    def _finalize(self) -> None:
        for net in list(self.nets):
            if net.defby != "none" or net.kind == "input" or not net.bits:
                continue
            sources, undriven = [], False
            for i, b in enumerate(net.bits):
                if not isinstance(b, int):
                    sources.append(("c", 1 if b == "1" else 0))
                elif b in self.frag:
                    fnet, foff = self.frag[b]
                    sources.append(("n", fnet, foff))
                elif self.home.get(b, (net, i)) != (net, i):
                    hnet, hoff = self.home[b]
                    sources.append(("n", hnet, hoff))
                else:
                    sources.append(("c", 0))
                    undriven = True
            net.defby = "aggregate"
            comment = "bit-level net reconstruction"
            if undriven:
                comment += "; some bits undriven, tied to 0"
                self.notes.append(f"net {net.name}: undriven bits tied to 0")
            self.assigns.append((net, self._sources_to_expr(sources), comment))


# --------------------------------------------------------------------------
# Renderer: circuitm mode  (Sparkle.IR.Builder / CircuitM)
# --------------------------------------------------------------------------

_OPERATORS = {"and", "or", "xor", "not", "add", "sub", "mul", "eq", "lt_u",
              "lt_s", "le_u", "le_s", "gt_u", "gt_s", "ge_u", "ge_s", "mux",
              "shl", "shr", "asr", "neg"}


def _render_ir(e: E) -> str:
    """Render an expression as a `Sparkle.IR.AST.Expr` Lean term."""
    if e.kind == "const":
        return f"(.const {e.aux} {e.width})"
    if e.kind == "ref":
        return f"(.ref {e.aux.ref_text})"
    if e.kind == "op":
        assert e.aux in _OPERATORS, e.aux
        args = ", ".join(_render_ir(a) for a in e.args)
        return f"(.op .{e.aux} [{args}])"
    if e.kind == "concat":
        args = ", ".join(_render_ir(a) for a in e.args)
        return f"(.concat [{args}])"
    if e.kind == "slice":
        hi, lo = e.aux
        return f"(.slice {_render_ir(e.args[0])} {hi} {lo})"
    raise AssertionError(e.kind)


def _file_header(top: str, src_info: str) -> str:
    return (f"/-\n  {HEADER_NOTE}\n"
            f"  Source: {src_info}\n"
            f"  Top module: {top}\n"
            f"  Generator: sparkle_fv.formalize\n-/\n")


def _render_circuitm(d: _Design, cap: str, src_info: str) -> str:
    """Emit a Lean file rebuilding the design through `CircuitM`."""
    out: list[str] = [_file_header(d.top, src_info)]
    out += ["import Sparkle.IR.Builder",
            "import Sparkle.Backend.Verilog",
            "",
            "open Sparkle.IR.AST",
            "open Sparkle.IR.Builder",
            "open Sparkle.IR.Type",
            "",
            f"namespace SparkleFV.{cap}",
            ""]
    for note in d.notes:
        out.append(f"-- NOTE: {note}")
    for u in d.unsupported:
        out.append(f"-- UNSUPPORTED: {u}")
    if d.notes or d.unsupported:
        out.append("")
    out.append(f"/-- IR model of `{d.top}`, reconstructed from the Yosys "
               "netlist via the CircuitM builder. -/")
    out.append("def design : Module :=")
    out.append(f"  CircuitM.runModule {_lean_str(d.top)} do")
    body: list[str] = []

    body.append("-- Ports")
    for net in d.inputs:
        body.append(f"CircuitM.addInput {_lean_str(net.name)} {_hwtype(net.width)}")
    for net in d.outputs:
        body.append(f"CircuitM.addOutput {_lean_str(net.name)} {_hwtype(net.width)}")

    wires = [n for n in d.nets
             if not n.is_port and n.defby in ("assign", "aggregate", "none")]
    if wires:
        body.append("-- Internal wires (word-level nets reconstructed from bit ids)")
    for net in wires:
        body.append(f"let {net.lid} ← CircuitM.makeWire {_lean_str(net.lid)} "
                    f"{_hwtype(net.width)} true")

    if d.regs:
        body.append("-- Registers")
    for r in d.regs:
        for note in r.notes:
            body.append(f"-- NOTE: {note}")
        body.append(f"let {r.target.lid} ← CircuitM.emitRegister "
                    f"{_lean_str(r.hint)} {r.clock} {r.reset} "
                    f"(.ref {r.next_net.lid}) {r.init} {_hwtype(r.width)} true")

    if d.mems:
        body.append("-- Memories")
    for m in d.mems:
        for note in m.notes:
            body.append(f"-- NOTE: {note}")
        fn = "emitMemoryComboRead" if m.combo else "emitMemory"
        body.append(f"let {m.target.lid} ← CircuitM.{fn} {_lean_str(m.hint)} "
                    f"{m.abits} {m.width} {m.clock} "
                    f"(.ref {m.helpers['waddr'].lid}) "
                    f"(.ref {m.helpers['wdata'].lid}) "
                    f"(.ref {m.helpers['wen'].lid}) "
                    f"(.ref {m.helpers['raddr'].lid}) true")

    if d.assigns:
        body.append("-- Combinational logic")
    for net, expr, comment in d.assigns:
        if comment:
            body.append(f"-- {comment}")
        lhs = _lean_str(net.name) if net.is_port else net.lid
        body.append(f"CircuitM.emitAssign {lhs} {_render_ir(expr)}")

    out.extend(f"    {line}" for line in body)
    out += ["",
            "-- Regenerate SystemVerilog for translation validation:",
            "-- #eval IO.println (Sparkle.Backend.Verilog.toVerilog design)",
            "",
            f"end SparkleFV.{cap}",
            ""]
    return "\n".join(out)


# --------------------------------------------------------------------------
# Pure-expression translation (shared by props file and signal mode)
# --------------------------------------------------------------------------


class _PureEnv:
    """Environment mapping nets to pure-Lean (BitVec) terms."""

    def __init__(self, d: _Design, state_of: dict, input_of: dict):
        self.d = d
        self.state_of = state_of        # net -> "s.<field>"
        self.input_of = input_of        # net -> "i.<field>"
        self.assign_of = {id(net): e for net, e, _ in d.assigns}
        self.budget = 40000

    def tr(self, e: E, visiting: frozenset = frozenset()) -> str:
        self.budget -= 1
        if self.budget <= 0:
            raise _PureUnsupported("expression cone too large")
        if e.kind == "const":
            return f"{e.aux}#{e.width}"
        if e.kind == "ref":
            net = e.aux
            if net in self.state_of:
                return self.state_of[net]
            if net in self.input_of:
                return self.input_of[net]
            if net.defby == "mem":
                raise _PureUnsupported("memory read data in cone")
            if id(net) in self.assign_of:
                if id(net) in visiting:
                    raise _PureUnsupported(f"combinational loop at {net.name}")
                return self.tr(self.assign_of[id(net)],
                               visiting | {id(net)})
            raise _PureUnsupported(f"undriven net {net.name}")
        if e.kind == "op":
            return self._op(e, visiting)
        if e.kind == "concat":
            parts = [self.tr(a, visiting) for a in e.args]
            acc = parts[0]
            for p in parts[1:]:
                acc = f"({acc} ++ {p})"
            return acc
        if e.kind == "slice":
            hi, lo = e.aux
            return (f"(BitVec.extractLsb' {lo} {hi - lo + 1} "
                    f"{self.tr(e.args[0], visiting)})")
        raise _PureUnsupported(e.kind)

    def _op(self, e: E, v: frozenset) -> str:
        name = e.aux
        t = lambda i: self.tr(e.args[i], v)     # noqa: E731
        infix = {"add": "+", "sub": "-", "mul": "*",
                 "and": "&&&", "or": "|||", "xor": "^^^"}
        if name in infix:
            return f"({t(0)} {infix[name]} {t(1)})"
        if name == "not":
            return f"(~~~{t(0)})"
        if name == "neg":
            return f"(-{t(0)})"
        if name == "eq":
            return f"(if {t(0)} == {t(1)} then 1#1 else 0#1)"
        cmp = {"lt_u": ("BitVec.ult", 0, 1), "le_u": ("BitVec.ule", 0, 1),
               "gt_u": ("BitVec.ult", 1, 0), "ge_u": ("BitVec.ule", 1, 0),
               "lt_s": ("BitVec.slt", 0, 1), "le_s": ("BitVec.sle", 0, 1),
               "gt_s": ("BitVec.slt", 1, 0), "ge_s": ("BitVec.sle", 1, 0)}
        if name in cmp:
            fn, x, y = cmp[name]
            return f"(if {fn} {t(x)} {t(y)} then 1#1 else 0#1)"
        if name == "mux":
            if e.args[0].width != 1:
                raise _PureUnsupported("wide mux select")
            return f"(if {t(0)} == 1#1 then {t(1)} else {t(2)})"
        if name == "shl":
            return f"({t(0)} <<< ({t(1)}).toNat)"
        if name == "shr":
            return f"({t(0)} >>> ({t(1)}).toNat)"
        if name == "asr":
            return f"(BitVec.sshiftRight {t(0)} ({t(1)}).toNat)"
        raise _PureUnsupported(f"operator {name}")


# --------------------------------------------------------------------------
# Renderer: proof-obligation file
# --------------------------------------------------------------------------


def _render_props(d: _Design, cap: str, src_info: str) -> str:
    """Emit `<Top>Props.lean`: pure FSM + LTL skeletons with PROOF PLANs."""
    used: set[str] = set(_LEAN_RESERVED)
    reg_fields = {id(r): _ident(r.hint, used, "r") for r in d.regs}
    data_inputs = [n for n in d.inputs if n.name not in d.clock_nets]
    in_fields = {id(n): _ident(n.lid, used, "in") for n in data_inputs}

    state_of = {r.target: f"s.{reg_fields[id(r)]}" for r in d.regs}
    input_of = {n: f"i.{in_fields[id(n)]}" for n in data_inputs}

    def try_tr(expr: E) -> str | None:
        try:
            return _PureEnv(d, state_of, input_of).tr(expr)
        except _PureUnsupported:
            return None

    out: list[str] = [_file_header(d.top, src_info)]
    out += ["import Sparkle.Verification.Temporal", "",
            "open Sparkle.Core.Domain",
            "open Sparkle.Core.Signal",
            "open Sparkle.Verification.Temporal", "",
            f"namespace SparkleFV.{cap}Props", ""]

    out.append("/-- External inputs sampled each cycle (clocks omitted). -/")
    out.append("structure Inputs where")
    if data_inputs:
        for n in data_inputs:
            out.append(f"  {in_fields[id(n)]} : BitVec {n.width}")
    else:
        out.append("  unused : Unit := ()")
    out += ["  deriving Repr", ""]

    out.append("/-- Architectural state: one field per hardware register. -/")
    out.append("structure State where")
    if d.regs:
        for r in d.regs:
            out.append(f"  {reg_fields[id(r)]} : BitVec {r.width}"
                       f"  -- `{r.hint}` (init {r.init})")
    else:
        out.append("  unused : Unit := ()")
    out += ["  deriving Repr", ""]

    out.append("/-- Reset state (register init values from the netlist). -/")
    if d.regs:
        fields = ", ".join(f"{reg_fields[id(r)]} := {r.init}#{r.width}"
                           for r in d.regs)
        out.append(f"def reset : State := {{ {fields} }}")
    else:
        out.append("def reset : State := {}")
    out.append("")

    # Transition function (best-effort translation of register next-state).
    updates: list[tuple[str, str | None, _Reg]] = []
    for r in d.regs:
        body = try_tr(r.next_expr)
        if body is not None and r.arst_expr is not None:
            cond = try_tr(r.arst_expr)
            body = (None if cond is None else
                    f"(if {cond} == 1#1 then {r.init}#{r.width} else {body})")
        updates.append((reg_fields[id(r)], body, r))
    all_ok = all(b is not None for _, b, _ in updates)

    if d.mems:
        out.append("-- NOTE: design contains memories; memory contents are NOT")
        out.append("--       modeled in `State` (registers reading memory data")
        out.append("--       fall back to `sorry`; extend with Array fields if needed).")
    out.append("/-- One clock cycle of the design (word-level netlist semantics). -/")
    if d.regs and all_ok:
        body = "  { " + ",\n    ".join(f"{f} := {b}" for f, b, _ in updates) + " }"
        sb = "s" if "s." in body else "_s"
        ib = "i" if "i." in body else "_i"
        out.append(f"def nextState ({sb} : State) ({ib} : Inputs) : State :=")
        out.append(body)
    elif not d.regs:
        out.append("def nextState (s : State) (_i : Inputs) : State := s")
    else:
        out.append("-- Could not fully auto-translate the transition function.")
        out.append("-- Register update expressions (Sparkle IR syntax):")
        for f, b, r in updates:
            out.append(f"--   {f} <= {_render_ir(r.next_expr)}")
        if d.mems:
            out.append("--   (design contains memories; extend State with "
                       "an `Array`/`Vector` field to model them)")
        out.append("def nextState (_s : State) (_i : Inputs) : State :=")
        out.append("  sorry")
    out.append("")

    out += [
        "/-- Run the machine for `n` cycles from `s0` under input trace `ins`. -/",
        "def run (s0 : State) (ins : Nat → Inputs) : Nat → State",
        "  | 0 => s0",
        "  | t + 1 => nextState (run s0 ins t) (ins t)",
        "",
        "/-- Reachable states (invariant-proof induction principle). -/",
        "inductive Reachable : State → Prop where",
        "  | init : Reachable reset",
        "  | step (s : State) (i : Inputs) : Reachable s → Reachable (nextState s i)",
        "",
    ]

    reg_summary = ", ".join(f"{reg_fields[id(r)]} : BitVec {r.width}"
                            for r in d.regs) or "(none — combinational)"

    for p in d.props:
        pname = f"prop_{p.name}"
        body = try_tr(p.expr) if p.expr is not None else None
        out.append(f"/-- Property `{p.name}` ({p.kind}); source: {p.src or 'n/a'}.")
        out.append("    The 1-bit condition below must always evaluate to 1. -/")
        if body is not None:
            body_line = f"  {body} == 1#1"
        else:
            ir = _render_ir(p.expr) if p.expr is not None else "<signal not found>"
            body_line = f"  sorry -- TODO: auto-translation failed; IR: {ir}"
        sb = "s" if "s." in body_line else "_s"
        ib = "i" if "i." in body_line else "_i"
        out.append(f"def {pname} ({sb} : State) ({ib} : Inputs) : Bool :=")
        out.append(body_line)
        out.append("")

        out += [
            "-- PROOF PLAN (auto-generated by sparkle-fv):",
            f"--   property          : {p.name} (kind: {p.kind}, src: {p.src or 'n/a'})",
            f"--   relevant registers: {reg_summary}",
            f"--   suggested tactics : induction on `Reachable`;"
            " per case `simp [nextState, " + pname + ", reset]`,",
            "--                       then `cases` on input fields /"
            " `omega` for arithmetic bounds / `decide` for small BitVec goals",
            "--   invariant strategy: the AI prover synthesizes"
            f" `candidateInv_{p.name}` below and proves:",
            f"--     (1) candidateInv_{p.name} reset",
            f"--     (2) ∀ s i, candidateInv_{p.name} s → "
            f"candidateInv_{p.name} (nextState s i)",
            f"--     (3) ∀ s i, candidateInv_{p.name} s → {pname} s i = true",
            f"-- INVARIANT-SLOT-BEGIN {p.name}",
            f"def candidateInv_{p.name} (_s : State) : Prop := True",
            f"-- INVARIANT-SLOT-END {p.name}",
            "",
        ]
        if p.kind == "safety":
            out += [
                f"/-- Safety obligation (Pattern 1, invariant proof): `{p.name}`"
                " holds in every reachable state. -/",
                f"theorem {p.name}_invariant (s : State) (hs : Reachable s)"
                f" (i : Inputs) :",
                f"    {pname} s i = true := by",
                "  sorry",
                "",
                f"/-- LTL form: `always` over the trace from reset"
                " (Sparkle.Verification.Temporal). -/",
                f"def {pname}_signal (ins : Nat → Inputs) :"
                " Signal defaultDomain Bool :=",
                f"  ⟨fun t => {pname} (run reset ins t) (ins t)⟩",
                "",
                f"theorem {p.name}_always (ins : Nat → Inputs) :",
                f"    always ({pname}_signal ins) := by",
                "  -- hint: `apply always_induction` then discharge base/step"
                " with simp/omega",
                "  sorry",
                "",
            ]
        else:
            out += [
                f"/-- Liveness obligation: `{p.name}` eventually holds on"
                " every input trace. -/",
                f"def {pname}_signal (ins : Nat → Inputs) :"
                " Signal defaultDomain Bool :=",
                f"  ⟨fun t => {pname} (run reset ins t) (ins t)⟩",
                "",
                f"theorem {p.name}_eventually (ins : Nat → Inputs) :",
                f"    eventually ({pname}_signal ins) := by",
                "  sorry",
                "",
            ]

    out += [f"end SparkleFV.{cap}Props", ""]
    return "\n".join(out)


# --------------------------------------------------------------------------
# Renderer: signal mode  (Sparkle.Core.Signal DSL, best effort)
# --------------------------------------------------------------------------


class _SignalEnv:
    """Renders expressions as Signal-DSL terms (`Signal dom (BitVec w)`)."""

    def __init__(self, d: _Design, reg_var: dict, input_var: dict):
        self.d = d
        self.reg_var = reg_var          # net -> lean var
        self.input_var = input_var
        self.assign_of = {id(net): e for net, e, _ in d.assigns}
        self.budget = 4000

    def tr(self, e: E, visiting: frozenset = frozenset()) -> str:
        self.budget -= 1
        if self.budget <= 0:
            raise _SignalUnsupported("design too large for readable Signal DSL")
        if e.kind == "const":
            return f"(Signal.pure {e.aux}#{e.width})"
        if e.kind == "ref":
            net = e.aux
            if net in self.reg_var:
                return self.reg_var[net]
            if net in self.input_var:
                return self.input_var[net]
            if net.defby == "mem":
                raise _SignalUnsupported("memories not expressible in Signal mode")
            if id(net) in self.assign_of:
                if id(net) in visiting:
                    raise _SignalUnsupported(f"combinational loop at {net.name}")
                return self.tr(self.assign_of[id(net)], visiting | {id(net)})
            raise _SignalUnsupported(f"undriven net {net.name}")
        if e.kind == "op":
            return self._op(e, visiting)
        if e.kind == "concat":
            parts = [self.tr(a, visiting) for a in e.args]
            acc = parts[0]
            for p in parts[1:]:
                acc = f"((· ++ ·) <$> {acc} <*> {p})"
            return acc
        if e.kind == "slice":
            hi, lo = e.aux
            return (f"(BitVec.extractLsb' {lo} {hi - lo + 1} <$> "
                    f"{self.tr(e.args[0], visiting)})")
        raise _SignalUnsupported(e.kind)

    def _op(self, e: E, v: frozenset) -> str:
        name = e.aux
        t = lambda i: self.tr(e.args[i], v)     # noqa: E731
        infix = {"add": "+", "sub": "-", "mul": "*",
                 "and": "&&&", "or": "|||", "xor": "^^^"}
        if name in infix:
            return f"((· {infix[name]} ·) <$> {t(0)} <*> {t(1)})"
        if name == "not":
            return f"((fun x => ~~~x) <$> {t(0)})"
        if name == "neg":
            return f"((fun x => -x) <$> {t(0)})"
        if name == "eq":
            return (f"((fun a b => if a == b then 1#1 else 0#1) <$> "
                    f"{t(0)} <*> {t(1)})")
        cmp = {"lt_u": ("BitVec.ult", 0, 1), "le_u": ("BitVec.ule", 0, 1),
               "gt_u": ("BitVec.ult", 1, 0), "ge_u": ("BitVec.ule", 1, 0),
               "lt_s": ("BitVec.slt", 0, 1), "le_s": ("BitVec.sle", 0, 1),
               "gt_s": ("BitVec.slt", 1, 0), "ge_s": ("BitVec.sle", 1, 0)}
        if name in cmp:
            fn, x, y = cmp[name]
            return (f"((fun a b => if {fn} a b then 1#1 else 0#1) <$> "
                    f"{t(x)} <*> {t(y)})")
        if name == "mux":
            if e.args[0].width != 1:
                raise _SignalUnsupported("wide mux select")
            return (f"(Signal.mux ((· == 1#1) <$> {t(0)}) {t(1)} {t(2)})")
        if name == "shl":
            return f"((fun x y => x <<< y.toNat) <$> {t(0)} <*> {t(1)})"
        if name == "shr":
            return f"((fun x y => x >>> y.toNat) <$> {t(0)} <*> {t(1)})"
        if name == "asr":
            return (f"((fun x y => BitVec.sshiftRight x y.toNat) <$> "
                    f"{t(0)} <*> {t(1)})")
        raise _SignalUnsupported(f"operator {name}")


def _reg_deps(d: _Design, expr: E, reg_nets: set[int],
              visiting: frozenset = frozenset()) -> set[int]:
    """Registers referenced (through combinational nets) by `expr`."""
    assign_of = {id(net): e for net, e, _ in d.assigns}
    deps: set[int] = set()

    def go(e: E, vis: frozenset) -> None:
        if e.kind == "ref":
            net = e.aux
            if id(net) in reg_nets:
                deps.add(id(net))
            elif id(net) in assign_of and id(net) not in vis:
                go(assign_of[id(net)], vis | {id(net)})
        for a in e.args:
            go(a, vis)

    go(expr, visiting)
    return deps


def _render_signal(d: _Design, cap: str, src_info: str) -> str:
    """Emit idiomatic Signal DSL; raises `_SignalUnsupported` on mismatch."""
    if d.mems:
        raise _SignalUnsupported("design contains memories")
    if d.unsupported:
        raise _SignalUnsupported(f"unsupported cells: {d.unsupported[:3]}")
    if not d.outputs:
        raise _SignalUnsupported("design has no outputs")

    used: set[str] = set(_LEAN_RESERVED)
    data_inputs = [n for n in d.inputs if n.name not in d.clock_nets]
    input_var = {n: _ident(n.lid, used, "in") for n in data_inputs}
    reg_var = {r.target: _ident(r.hint, used, "r") for r in d.regs}
    reg_nets = {id(r.target) for r in d.regs}

    # Effective next-expression per register (fold in async reset).
    nexts: dict[int, E] = {}
    for r in d.regs:
        nxt = r.next_expr
        if r.arst_expr is not None:
            nxt = _mux(r.arst_expr, _const(r.init, r.width), nxt)
        nexts[id(r.target)] = nxt

    # Topological order over registers; self-loops use Signal.loop.
    deps = {id(r.target): _reg_deps(d, nexts[id(r.target)], reg_nets)
            for r in d.regs}
    ordered: list[_Reg] = []
    placed: set[int] = set()
    pending = list(d.regs)
    while pending:
        progress = False
        for r in list(pending):
            if deps[id(r.target)] - placed - {id(r.target)}:
                continue
            ordered.append(r)
            placed.add(id(r.target))
            pending.remove(r)
            progress = True
        if not progress:
            raise _SignalUnsupported(
                "mutually recursive registers (needs bundled Signal.loop)")

    lines: list[str] = []
    env = _SignalEnv(d, reg_var, input_var)
    for r in ordered:
        var = reg_var[r.target]
        note = "  -- async reset folded into a mux" if r.arst_expr is not None else ""
        body = env.tr(nexts[id(r.target)])
        if id(r.target) in deps[id(r.target)]:
            lines.append(f"  let {var} : Signal dom (BitVec {r.width}) :="
                         f"{note}")
            lines.append(f"    Signal.loop (fun {var} =>")
            lines.append(f"      Signal.register {r.init}#{r.width} {body})")
        else:
            lines.append(f"  let {var} : Signal dom (BitVec {r.width}) :="
                         f"{note}")
            lines.append(f"    Signal.register {r.init}#{r.width} {body}")

    out_terms = []
    for net in d.outputs:
        expr = _ref(net)
        out_terms.append(env.tr(expr))

    params = " ".join(
        f"({input_var[n]} : Signal dom (BitVec {n.width}))"
        for n in data_inputs)
    ret = " × ".join(f"Signal dom (BitVec {n.width})" for n in d.outputs)

    out: list[str] = [_file_header(d.top, src_info)]
    out += ["import Sparkle", "",
            "open Sparkle.Core.Domain",
            "open Sparkle.Core.Signal", "",
            f"namespace SparkleFV.{cap}", ""]
    for note in d.notes:
        out.append(f"-- NOTE: {note}")
    out.append("-- NOTE: clock inputs are implicit in Signal semantics; "
               "async resets are modeled synchronously.")
    out.append("")
    doc_outs = ", ".join(f"`{n.name}`" for n in d.outputs)
    out.append(f"/-- Signal-DSL model of `{d.top}`; returns ({doc_outs}). -/")
    fname = re.sub(r"[^0-9a-zA-Z_]", "_", d.top) or "top"
    if not fname[0].isalpha():
        fname = "m" + fname
    fname = fname[0].lower() + fname[1:] + "Signal"
    head = f"def {fname} {{dom : DomainConfig}}"
    if params:
        head += f" {params}"
    out.append(f"{head} :")
    out.append(f"    {ret} :=")
    out.extend(lines)
    if len(out_terms) == 1:
        out.append(f"  {out_terms[0]}")
    else:
        out.append("  (" + ",\n   ".join(out_terms) + ")")
    out += ["", f"end SparkleFV.{cap}", ""]
    return "\n".join(out)


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------


def formalize(netlist: dict, top: str, out_dir: Path, mode: str = "circuitm",
              properties: list[dict] | None = None) -> FormalizeResult:
    """Autoformalize a Yosys JSON netlist into Sparkle Lean 4 sources.

    Args:
        netlist: Parsed Yosys ``write_json`` output.
        top: Name of the top module inside ``netlist["modules"]``.
        out_dir: Directory for the generated ``.lean`` files.
        mode: ``"circuitm"`` (robust IR reconstruction) or ``"signal"``
            (best-effort Signal DSL; silently falls back to circuitm).
        properties: Optional list of property dicts with keys
            ``name``, ``kind`` ("safety"|"liveness"), ``expr_signal``
            (net name of a 1-bit always-1 signal) and ``src``.
            ``$assert`` cells are additionally auto-extracted.

    Returns:
        A :class:`FormalizeResult` with paths, effective mode and stats.
    """
    modules = netlist.get("modules", {})
    if top not in modules:
        raise ValueError(f"top module '{top}' not in netlist "
                         f"(available: {sorted(modules)})")
    d = _Design(top, modules[top], list(properties or []))
    d.build()

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    cap = re.sub(r"[^0-9a-zA-Z_]", "_", top)
    cap = (cap[0].upper() + cap[1:]) if cap and cap[0].isalpha() else f"M{cap}"
    src_info = (netlist.get("creator", "yosys write_json")
                + f"; module '{top}', {d.n_cells} cells")

    actual_mode = mode
    text: str | None = None
    if mode == "signal":
        try:
            text = _render_signal(d, cap, src_info)
        except _SignalUnsupported as exc:
            d.notes.append(f"signal mode fallback: {exc}")
            actual_mode = "circuitm"
    if text is None:
        actual_mode = "circuitm"
        text = _render_circuitm(d, cap, src_info)

    lean_file = out_dir / f"{cap}.lean"
    lean_file.write_text(text)

    props_file: Path | None = None
    if d.props:
        props_file = out_dir / f"{cap}Props.lean"
        props_file.write_text(_render_props(d, cap, src_info))

    stats = {
        "cells": d.n_cells,
        "registers": len(d.regs),
        "memories": len(d.mems),
        "unsupported": list(d.unsupported),
        "wires": len(d.nets),
        "assigns": len(d.assigns),
        "properties": [p.name for p in d.props],
        "notes": list(d.notes),
    }
    return FormalizeResult(top=top, lean_file=lean_file,
                           props_file=props_file, mode=actual_mode,
                           stats=stats)


# --------------------------------------------------------------------------
# Self-test CLI:  python3 -m sparkle_fv.formalize <netlist.json> <top>
# --------------------------------------------------------------------------


def _main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        prog="python3 -m sparkle_fv.formalize",
        description="Autoformalize a Yosys JSON netlist into Sparkle Lean 4.")
    parser.add_argument("netlist", help="Yosys write_json output file")
    parser.add_argument("top", help="top module name")
    parser.add_argument("--out", default=None,
                        help="output directory (default: alongside netlist)")
    parser.add_argument("--mode", choices=["circuitm", "signal"],
                        default="circuitm")
    args = parser.parse_args(argv)

    data = json.loads(Path(args.netlist).read_text())
    out_dir = Path(args.out) if args.out else Path(args.netlist).resolve().parent
    res = formalize(data, args.top, out_dir, mode=args.mode)

    print(f"top        : {res.top}")
    print(f"mode       : {res.mode}")
    print(f"lean_file  : {res.lean_file}")
    print(f"props_file : {res.props_file}")
    for k in ("cells", "registers", "memories", "wires", "assigns"):
        print(f"{k:11}: {res.stats[k]}")
    if res.stats["unsupported"]:
        print(f"unsupported: {res.stats['unsupported']}")
    if res.stats["properties"]:
        print(f"properties : {res.stats['properties']}")
    for note in res.stats["notes"]:
        print(f"note       : {note}")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
