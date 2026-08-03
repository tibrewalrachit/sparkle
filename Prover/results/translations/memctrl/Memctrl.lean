/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/memctrl/design.sv
  Top module : memctrl
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Memctrl

/-- Architectural state of `memctrl` (one field per hardware register). -/
declare_signal_state MemctrlState
  | watch_set : Bool := false
  | shadow_valid : Bool := false
  | watch_q : BitVec 4 := 0#4
  | shadow_data : BitVec 8 := 0#8
  | rd_data_q : BitVec 8 := 0#8
  | rd_valid_q : Bool := false
  | check_q : Bool := false
  | expected_q : BitVec 8 := 0#8

/-- Signal-DSL model of `memctrl`.
    Inputs: `rst`, `wr_en`, `wr_addr`, `wr_data`, `rd_en`, `rd_addr`, `watch_addr`; outputs: `rd_valid`, `rd_data`. -/
private def memctrlBody {dom : DomainConfig}
    (rst : Signal dom Bool) (wr_en : Signal dom Bool) (wr_addr : Signal dom (BitVec 4)) (wr_data : Signal dom (BitVec 8)) (rd_en : Signal dom Bool) (rd_addr : Signal dom (BitVec 4)) (watch_addr : Signal dom (BitVec 4))
    (state : Signal dom MemctrlState) : Signal dom MemctrlState :=
  let watch_set := MemctrlState.watch_set state
  let shadow_valid := MemctrlState.shadow_valid state
  let watch_q := MemctrlState.watch_q state
  let shadow_data := MemctrlState.shadow_data state
  let rd_data_q := MemctrlState.rd_data_q state
  let rd_valid_q := MemctrlState.rd_valid_q state
  let check_q := MemctrlState.check_q state
  let expected_q := MemctrlState.expected_q state
  -- next-state values (non-blocking updates, one per register)
  let watch_set_next :=
    hw_cond watch_set
    | rst => (Signal.pure false)
    | (~~~watch_set) => (Signal.pure true)
  let shadow_valid_next :=
    hw_cond shadow_valid
    | rst => (Signal.pure false)
    | ((wr_en &&& watch_set) &&& (wr_addr === watch_q)) => (Signal.pure true)
  let watch_q_next :=
    hw_cond watch_q
    | rst => watch_q
    | (~~~watch_set) => watch_addr
  let shadow_data_next :=
    hw_cond shadow_data
    | rst => shadow_data
    | ((wr_en &&& watch_set) &&& (wr_addr === watch_q)) => wr_data
  let rd_data_q_next := (Signal.memoryComboRead wr_addr wr_data wr_en rd_addr)
  let rd_valid_q_next := (rd_en &&& (~~~rst))
  let check_q_next := ((((rd_en &&& (~~~rst)) &&& watch_set) &&& shadow_valid) &&& (rd_addr === watch_q))
  let expected_q_next := shadow_data
  bundleAll! [
    Signal.register false watch_set_next,
    Signal.register false shadow_valid_next,
    Signal.register 0#4 watch_q_next,
    Signal.register 0#8 shadow_data_next,
    Signal.register 0#8 rd_data_q_next,
    Signal.register false rd_valid_q_next,
    Signal.register false check_q_next,
    Signal.register 0#8 expected_q_next
  ]

def memctrl {dom : DomainConfig}
    (rst : Signal dom Bool) (wr_en : Signal dom Bool) (wr_addr : Signal dom (BitVec 4)) (wr_data : Signal dom (BitVec 8)) (rd_en : Signal dom Bool) (rd_addr : Signal dom (BitVec 4)) (watch_addr : Signal dom (BitVec 4))
    : Signal dom Bool × Signal dom (BitVec 8) :=
  let state := Signal.loop fun state => memctrlBody rst wr_en wr_addr wr_data rd_en rd_addr watch_addr state
  let watch_set := MemctrlState.watch_set state
  let shadow_valid := MemctrlState.shadow_valid state
  let watch_q := MemctrlState.watch_q state
  let shadow_data := MemctrlState.shadow_data state
  let rd_data_q := MemctrlState.rd_data_q state
  let rd_valid_q := MemctrlState.rd_valid_q state
  let check_q := MemctrlState.check_q state
  let expected_q := MemctrlState.expected_q state
  -- combinational logic feeding the outputs
  let rd_valid := rd_valid_q
  let rd_data := rd_data_q
  (rd_valid, rd_data)

end SparkleFV.Memctrl
