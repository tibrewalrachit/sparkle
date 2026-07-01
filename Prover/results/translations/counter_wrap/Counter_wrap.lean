/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/counter_wrap/design.sv
  Top module : counter_wrap
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Counter_wrap

/-- Signal-DSL model of `counter_wrap`.
    Inputs: `rst`, `en`; outputs: `count`. -/
def counter_wrap {dom : DomainConfig}
    (rst : Signal dom Bool) (en : Signal dom Bool)
    : Signal dom (BitVec 8) :=
  let cnt : Signal dom (BitVec 8) := Signal.loop fun cnt =>
    let cnt_next :=
      hw_cond cnt
      | rst => (Signal.pure 0#8)
      | en => (Signal.mux ((Signal.pure 10#8) === cnt) (Signal.pure 0#8) ((Signal.pure 1#8) + cnt))
    Signal.register 0#8 cnt_next
  -- combinational logic feeding the outputs
  let count := cnt
  count

end SparkleFV.Counter_wrap
