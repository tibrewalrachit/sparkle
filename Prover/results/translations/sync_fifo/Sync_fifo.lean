/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/sync_fifo/design.sv
  Top module : sync_fifo
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Sync_fifo

/-- Architectural state of `sync_fifo` (one field per hardware register). -/
declare_signal_state Sync_fifoState
  | wr_ptr : BitVec 3 := 0#3
  | rd_ptr : BitVec 3 := 0#3
  | count : BitVec 4 := 0#4

/-- Signal-DSL model of `sync_fifo`.
    Inputs: `rst`, `enq_valid`, `enq_data`, `deq_ready`; outputs: `enq_ready`, `deq_valid`, `deq_data`. -/
private def sync_fifoBody {dom : DomainConfig}
    (rst : Signal dom Bool) (enq_valid : Signal dom Bool) (enq_data : Signal dom (BitVec 8)) (deq_ready : Signal dom Bool)
    (state : Signal dom Sync_fifoState) : Signal dom Sync_fifoState :=
  let wr_ptr := Sync_fifoState.wr_ptr state
  let rd_ptr := Sync_fifoState.rd_ptr state
  let count := Sync_fifoState.count state
  -- combinational logic feeding the registers
  let enq_ready := (~~~((Signal.pure 8#4) === count))
  let deq_valid := (~~~((Signal.pure 0#4) === count))
  let do_enq := (enq_ready &&& enq_valid)
  let do_deq := (deq_valid &&& deq_ready)
  -- next-state values (non-blocking updates, one per register)
  let wr_ptr_next :=
    hw_cond wr_ptr
    | rst => (Signal.pure 0#3)
    | do_enq => ((Signal.pure 1#3) + wr_ptr)
  let rd_ptr_next :=
    hw_cond rd_ptr
    | rst => (Signal.pure 0#3)
    | do_deq => ((Signal.pure 1#3) + rd_ptr)
  let count_next :=
    hw_cond count
    | rst => (Signal.pure 0#4)
    | (do_enq &&& (~~~do_deq)) => ((Signal.pure 1#4) + count)
    | ((~~~do_enq) &&& do_deq) => (count - (Signal.pure 1#4))
  bundleAll! [
    Signal.register 0#3 wr_ptr_next,
    Signal.register 0#3 rd_ptr_next,
    Signal.register 0#4 count_next
  ]

def sync_fifo {dom : DomainConfig}
    (rst : Signal dom Bool) (enq_valid : Signal dom Bool) (enq_data : Signal dom (BitVec 8)) (deq_ready : Signal dom Bool)
    : Signal dom Bool × Signal dom Bool × Signal dom (BitVec 8) :=
  let state := Signal.loop fun state => sync_fifoBody rst enq_valid enq_data deq_ready state
  let wr_ptr := Sync_fifoState.wr_ptr state
  let rd_ptr := Sync_fifoState.rd_ptr state
  let count := Sync_fifoState.count state
  -- combinational logic feeding the outputs
  let enq_ready := (~~~((Signal.pure 8#4) === count))
  let deq_valid := (~~~((Signal.pure 0#4) === count))
  let do_enq := (enq_ready &&& enq_valid)
  let deq_data := (Signal.memoryComboRead wr_ptr enq_data ((~~~rst) &&& do_enq) rd_ptr)
  (enq_ready, deq_valid, deq_data)

end SparkleFV.Sync_fifo
