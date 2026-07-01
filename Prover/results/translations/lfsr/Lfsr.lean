/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/lfsr/design.sv
  Top module : lfsr
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Lfsr

/-- Signal-DSL model of `lfsr`.
    Inputs: `rst`, `load`, `load_val`; outputs: `state_out`. -/
def lfsr {dom : DomainConfig}
    (rst : Signal dom Bool) (load : Signal dom Bool) (load_val : Signal dom (BitVec 16))
    : Signal dom (BitVec 16) :=
  let lfsr_q : Signal dom (BitVec 16) := Signal.loop fun lfsr_q =>
    let load_guarded := (Signal.mux ((Signal.pure 0#16) === load_val) (Signal.pure 1#16) load_val)
    let lfsr_next := ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> (((·.getLsbD 0) <$> lfsr_q) ^^^ (((·.getLsbD 2) <$> lfsr_q) ^^^ (((·.getLsbD 3) <$> lfsr_q) ^^^ ((·.getLsbD 5) <$> lfsr_q))))) <*> ((BitVec.extractLsb' 1 15) <$> lfsr_q))
    let lfsr_q_next :=
      hw_cond lfsr_next
      | rst => (Signal.pure 44257#16)
      | load => load_guarded
    Signal.register 44257#16 lfsr_q_next
  -- combinational logic feeding the outputs
  let state_out := lfsr_q
  state_out

end SparkleFV.Lfsr
