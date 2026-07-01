/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/uart_tx/design.sv
  Top module : uart_tx
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Uart_tx

/-- Architectural state of `uart_tx` (one field per hardware register). -/
declare_signal_state Uart_txState
  | state_v : BitVec 4 := 1#4
  | baud : BitVec 3 := 0#3
  | bitidx : BitVec 3 := 0#3
  | sh : BitVec 8 := 0#8

/-- Signal-DSL model of `uart_tx`.
    Inputs: `rst`, `tx_start`, `tx_data`; outputs: `tx`, `busy`. -/
private def uart_txBody {dom : DomainConfig}
    (rst : Signal dom Bool) (tx_start : Signal dom Bool) (tx_data : Signal dom (BitVec 8))
    (state : Signal dom Uart_txState) : Signal dom Uart_txState :=
  let state_v := Uart_txState.state_v state
  let baud := Uart_txState.baud state
  let bitidx := Uart_txState.bitidx state
  let sh := Uart_txState.sh state
  -- combinational logic feeding the registers
  let tick := ((Signal.pure 3#3) === baud)
  -- next-state values (non-blocking updates, one per register)
  let state_v_next :=
    hw_cond (Signal.pure 1#4)
    | rst => (Signal.pure 1#4)
    | (state_v === (Signal.pure 1#4)) => (Signal.mux tx_start (Signal.pure 2#4) state_v)
    | (state_v === (Signal.pure 2#4)) => (Signal.mux tick (Signal.pure 4#4) state_v)
    | (state_v === (Signal.pure 4#4)) => (Signal.mux tick (Signal.mux ((Signal.pure 7#3) === bitidx) (Signal.pure 8#4) state_v) state_v)
    | (state_v === (Signal.pure 8#4)) => (Signal.mux tick (Signal.pure 1#4) state_v)
  let baud_next :=
    hw_cond baud
    | rst => (Signal.pure 0#3)
    | (state_v === (Signal.pure 1#4)) => (Signal.pure 0#3)
    | (state_v === (Signal.pure 2#4)) => (Signal.mux tick (Signal.pure 0#3) ((Signal.pure 1#3) + baud))
    | (state_v === (Signal.pure 4#4)) => (Signal.mux tick (Signal.pure 0#3) ((Signal.pure 1#3) + baud))
    | (state_v === (Signal.pure 8#4)) => (Signal.mux tick (Signal.pure 0#3) ((Signal.pure 1#3) + baud))
  let bitidx_next :=
    hw_cond bitidx
    | rst => (Signal.pure 0#3)
    | (state_v === (Signal.pure 1#4)) => (Signal.pure 0#3)
    | (state_v === (Signal.pure 2#4)) => (Signal.mux tick (Signal.pure 0#3) bitidx)
    | (state_v === (Signal.pure 4#4)) => (Signal.mux tick (Signal.mux ((Signal.pure 7#3) === bitidx) bitidx ((Signal.pure 1#3) + bitidx)) bitidx)
  let sh_next :=
    hw_cond sh
    | rst => (Signal.pure 0#8)
    | (state_v === (Signal.pure 1#4)) => (Signal.mux tx_start tx_data sh)
    | (state_v === (Signal.pure 2#4)) => sh
    | (state_v === (Signal.pure 4#4)) => (Signal.mux tick ((BitVec.zeroExtend 8) <$> ((BitVec.extractLsb' 1 7) <$> sh)) sh)
  bundleAll! [
    Signal.register 1#4 state_v_next,
    Signal.register 0#3 baud_next,
    Signal.register 0#3 bitidx_next,
    Signal.register 0#8 sh_next
  ]

def uart_tx {dom : DomainConfig}
    (rst : Signal dom Bool) (tx_start : Signal dom Bool) (tx_data : Signal dom (BitVec 8))
    : Signal dom Bool × Signal dom Bool :=
  let state := Signal.loop fun state => uart_txBody rst tx_start tx_data state
  let state_v := Uart_txState.state_v state
  let baud := Uart_txState.baud state
  let bitidx := Uart_txState.bitidx state
  let sh := Uart_txState.sh state
  -- combinational logic feeding the outputs
  let tx := ((~~~((Signal.pure 2#4) === state_v)) &&& ((~~~((Signal.pure 4#4) === state_v)) ||| ((·.getLsbD 0) <$> sh)))
  let busy := (~~~((Signal.pure 1#4) === state_v))
  (tx, busy)

end SparkleFV.Uart_tx
