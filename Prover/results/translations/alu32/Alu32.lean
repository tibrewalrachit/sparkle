/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/alu32/design.sv
  Top module : alu32
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Alu32

/-- Signal-DSL model of `alu32`.
    Inputs: `rst`, `a`, `b`, `op`; outputs: `result`. -/
def alu32 {dom : DomainConfig}
    (rst : Signal dom Bool) (a : Signal dom (BitVec 32)) (b : Signal dom (BitVec 32)) (op : Signal dom (BitVec 3))
    : Signal dom (BitVec 32) :=
  let a_q_next := (Signal.mux rst (Signal.pure 0#32) a)
  let a_q := Signal.register 0#32 a_q_next
  let b_q_next := (Signal.mux rst (Signal.pure 0#32) b)
  let b_q := Signal.register 0#32 b_q_next
  let op_q_next := (Signal.mux rst (Signal.pure 0#3) op)
  let op_q := Signal.register 0#3 op_q_next
  let res :=
    hw_cond ((fun x y => x <<< y.toNat) <$> a_q <*> ((BitVec.extractLsb' 0 5) <$> b_q))
    | (op_q === (Signal.pure 0#3)) => (a_q + b_q)
    | (op_q === (Signal.pure 1#3)) => ((Signal.pure 1#32) + (a_q + ((fun x => ~~~x) <$> b_q)))
    | (op_q === (Signal.pure 2#3)) => (a_q &&& b_q)
    | (op_q === (Signal.pure 3#3)) => (a_q ||| b_q)
    | (op_q === (Signal.pure 4#3)) => (a_q ^^^ b_q)
    | (op_q === (Signal.pure 5#3)) => (Signal.mux ((BitVec.slt · ·) <$> a_q <*> b_q) (Signal.pure 1#32) (Signal.pure 0#32))
    | (op_q === (Signal.pure 6#3)) => (Signal.mux ((BitVec.ult · ·) <$> a_q <*> b_q) (Signal.pure 1#32) (Signal.pure 0#32))
  let result := res
  result

end SparkleFV.Alu32
