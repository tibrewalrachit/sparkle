/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/round_robin_arbiter/design.sv
  Top module : round_robin_arbiter
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Round_robin_arbiter

/-- Architectural state of `round_robin_arbiter` (one field per hardware register). -/
declare_signal_state Round_robin_arbiterState
  | last : BitVec 2 := 0#2
  | grant_prev : BitVec 4 := 0#4
  | req_prev : BitVec 4 := 0#4

/-- Signal-DSL model of `round_robin_arbiter`.
    Inputs: `rst`, `req`; outputs: `grant`. -/
private def round_robin_arbiterBody {dom : DomainConfig}
    (rst : Signal dom Bool) (req : Signal dom (BitVec 4))
    (state : Signal dom Round_robin_arbiterState) : Signal dom Round_robin_arbiterState :=
  let last := Round_robin_arbiterState.last state
  let grant_prev := Round_robin_arbiterState.grant_prev state
  let req_prev := Round_robin_arbiterState.req_prev state
  -- combinational logic feeding the registers
  let masked_req := (req &&& (Signal.mux ((Signal.pure 0#2) === last) (Signal.pure 14#4) (Signal.mux ((Signal.pure 1#2) === last) (Signal.pure 12#4) (Signal.mux ((Signal.pure 2#2) === last) (Signal.pure 8#4) (Signal.pure 0#4)))))
  let grant := (Signal.mux ((Signal.pure 0#4) === masked_req) (req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> req))) (masked_req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> masked_req))))
  let gidx :=
    hw_cond (Signal.pure 0#2)
    | ((·.getLsbD 1) <$> grant) => (Signal.pure 1#2)
    | ((·.getLsbD 2) <$> grant) => (Signal.pure 2#2)
    | ((·.getLsbD 3) <$> grant) => (Signal.pure 3#2)
  -- next-state values (non-blocking updates, one per register)
  let last_next :=
    hw_cond last
    | rst => (Signal.pure 0#2)
    | (~~~((Signal.pure 0#4) === grant)) => gidx
  let grant_prev_next := (Signal.mux rst (Signal.pure 0#4) grant)
  let req_prev_next := (Signal.mux rst (Signal.pure 0#4) req)
  bundleAll! [
    Signal.register 0#2 last_next,
    Signal.register 0#4 grant_prev_next,
    Signal.register 0#4 req_prev_next
  ]

def round_robin_arbiter {dom : DomainConfig}
    (rst : Signal dom Bool) (req : Signal dom (BitVec 4))
    : Signal dom (BitVec 4) :=
  let state := Signal.loop fun state => round_robin_arbiterBody rst req state
  let last := Round_robin_arbiterState.last state
  let grant_prev := Round_robin_arbiterState.grant_prev state
  let req_prev := Round_robin_arbiterState.req_prev state
  -- combinational logic feeding the outputs
  let masked_req := (req &&& (Signal.mux ((Signal.pure 0#2) === last) (Signal.pure 14#4) (Signal.mux ((Signal.pure 1#2) === last) (Signal.pure 12#4) (Signal.mux ((Signal.pure 2#2) === last) (Signal.pure 8#4) (Signal.pure 0#4)))))
  let grant := (Signal.mux ((Signal.pure 0#4) === masked_req) (req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> req))) (masked_req &&& ((Signal.pure 1#4) + ((fun x => ~~~x) <$> masked_req))))
  grant

end SparkleFV.Round_robin_arbiter
