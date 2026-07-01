/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/priority_arbiter/design.sv
  Top module : priority_arbiter
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Priority_arbiter

/-- Architectural state of `priority_arbiter` (one field per hardware register). -/
declare_signal_state Priority_arbiterState
  | wait0 : BitVec 4 := 0#4
  | wait1 : BitVec 4 := 0#4
  | wait2 : BitVec 4 := 0#4
  | wait3 : BitVec 4 := 0#4

/-- Signal-DSL model of `priority_arbiter`.
    Inputs: `rst`, `req`; outputs: `grant`. -/
private def priority_arbiterBody {dom : DomainConfig}
    (rst : Signal dom Bool) (req : Signal dom (BitVec 4))
    (state : Signal dom Priority_arbiterState) : Signal dom Priority_arbiterState :=
  let wait0 := Priority_arbiterState.wait0 state
  let wait1 := Priority_arbiterState.wait1 state
  let wait2 := Priority_arbiterState.wait2 state
  let wait3 := Priority_arbiterState.wait3 state
  -- combinational logic feeding the registers
  let starved := ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 3) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait3))) <*> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 2) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait2))) <*> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 1) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait1))) <*> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 0) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait0))))))
  let grant := (Signal.mux ((Signal.pure 0#4) === starved) (Signal.mux ((Signal.pure 0#4) === req) (Signal.pure 0#4) (req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> req)))) (starved &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> starved))))
  -- next-state values (non-blocking updates, one per register)
  let wait0_next :=
    hw_cond ((Signal.pure 1#4) + wait0)
    | rst => (Signal.pure 0#4)
    | ((~~~((·.getLsbD 0) <$> req)) ||| ((·.getLsbD 0) <$> grant)) => (Signal.pure 0#4)
  let wait1_next :=
    hw_cond ((Signal.pure 1#4) + wait1)
    | rst => (Signal.pure 0#4)
    | ((~~~((·.getLsbD 1) <$> req)) ||| ((·.getLsbD 1) <$> grant)) => (Signal.pure 0#4)
  let wait2_next :=
    hw_cond ((Signal.pure 1#4) + wait2)
    | rst => (Signal.pure 0#4)
    | ((~~~((·.getLsbD 2) <$> req)) ||| ((·.getLsbD 2) <$> grant)) => (Signal.pure 0#4)
  let wait3_next :=
    hw_cond ((Signal.pure 1#4) + wait3)
    | rst => (Signal.pure 0#4)
    | ((~~~((·.getLsbD 3) <$> req)) ||| ((·.getLsbD 3) <$> grant)) => (Signal.pure 0#4)
  bundleAll! [
    Signal.register 0#4 wait0_next,
    Signal.register 0#4 wait1_next,
    Signal.register 0#4 wait2_next,
    Signal.register 0#4 wait3_next
  ]

def priority_arbiter {dom : DomainConfig}
    (rst : Signal dom Bool) (req : Signal dom (BitVec 4))
    : Signal dom (BitVec 4) :=
  let state := Signal.loop fun state => priority_arbiterBody rst req state
  let wait0 := Priority_arbiterState.wait0 state
  let wait1 := Priority_arbiterState.wait1 state
  let wait2 := Priority_arbiterState.wait2 state
  let wait3 := Priority_arbiterState.wait3 state
  -- combinational logic feeding the outputs
  let starved := ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 3) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait3))) <*> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 2) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait2))) <*> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 1) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait1))) <*> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 0) <$> req) &&& ((BitVec.ule · ·) <$> (Signal.pure 8#4) <*> wait0))))))
  let grant := (Signal.mux ((Signal.pure 0#4) === starved) (Signal.mux ((Signal.pure 0#4) === req) (Signal.pure 0#4) (req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> req)))) (starved &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> starved))))
  grant

end SparkleFV.Priority_arbiter
