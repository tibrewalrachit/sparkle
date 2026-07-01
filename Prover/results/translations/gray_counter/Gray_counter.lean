/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/gray_counter/design.sv
  Top module : gray_counter
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Gray_counter

/-- Architectural state of `gray_counter` (one field per hardware register). -/
declare_signal_state Gray_counterState
  | bin : BitVec 8 := 0#8
  | gray : BitVec 8 := 0#8
  | gray_prev : BitVec 8 := 0#8
  | moved : Bool := false

/-- Signal-DSL model of `gray_counter`.
    Inputs: `rst`, `en`; outputs: `gray_out`. -/
private def gray_counterBody {dom : DomainConfig}
    (rst : Signal dom Bool) (en : Signal dom Bool)
    (state : Signal dom Gray_counterState) : Signal dom Gray_counterState :=
  let bin := Gray_counterState.bin state
  let gray := Gray_counterState.gray state
  let gray_prev := Gray_counterState.gray_prev state
  let moved := Gray_counterState.moved state
  -- combinational logic feeding the registers
  let bin_next := ((Signal.pure 1#8) + bin)
  let gray_next := (bin_next ^^^ ((fun x y => x >>> y.toNat) <$> bin_next <*> (Signal.pure 1#32)))
  -- next-state values (non-blocking updates, one per register)
  let bin_next_2 :=
    hw_cond bin
    | rst => (Signal.pure 0#8)
    | en => bin_next
  let gray_next_2 :=
    hw_cond gray
    | rst => (Signal.pure 0#8)
    | en => gray_next
  let gray_prev_next :=
    hw_cond gray_prev
    | rst => (Signal.pure 0#8)
    | en => gray
  let moved_next :=
    hw_cond moved
    | rst => (Signal.pure false)
    | en => (Signal.pure true)
  bundleAll! [
    Signal.register 0#8 bin_next_2,
    Signal.register 0#8 gray_next_2,
    Signal.register 0#8 gray_prev_next,
    Signal.register false moved_next
  ]

def gray_counter {dom : DomainConfig}
    (rst : Signal dom Bool) (en : Signal dom Bool)
    : Signal dom (BitVec 8) :=
  let state := Signal.loop fun state => gray_counterBody rst en state
  let bin := Gray_counterState.bin state
  let gray := Gray_counterState.gray state
  let gray_prev := Gray_counterState.gray_prev state
  let moved := Gray_counterState.moved state
  -- combinational logic feeding the outputs
  let gray_out := gray
  gray_out

end SparkleFV.Gray_counter
