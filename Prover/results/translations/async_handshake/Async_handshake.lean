/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/async_handshake/design.sv
  Top module : async_handshake
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Async_handshake

/-- Architectural state of `async_handshake` (one field per hardware register). -/
declare_signal_state Async_handshakeState
  | sstate : BitVec 2 := 0#2
  | req : Bool := false
  | data_r : BitVec 8 := 0#8
  | rstate : BitVec 2 := 0#2
  | ack : Bool := false
  | cap : BitVec 8 := 0#8
  | rel_cnt : BitVec 2 := 0#2

/-- Signal-DSL model of `async_handshake`.
    Inputs: `rst`, `start`, `din`; outputs: `busy`, `dout`. -/
private def async_handshakeBody {dom : DomainConfig}
    (rst : Signal dom Bool) (start : Signal dom Bool) (din : Signal dom (BitVec 8))
    (state : Signal dom Async_handshakeState) : Signal dom Async_handshakeState :=
  let sstate := Async_handshakeState.sstate state
  let req := Async_handshakeState.req state
  let data_r := Async_handshakeState.data_r state
  let rstate := Async_handshakeState.rstate state
  let ack := Async_handshakeState.ack state
  let cap := Async_handshakeState.cap state
  let rel_cnt := Async_handshakeState.rel_cnt state
  -- next-state values (non-blocking updates, one per register)
  let sstate_next :=
    hw_cond (Signal.pure 0#2)
    | rst => (Signal.pure 0#2)
    | (sstate === (Signal.pure 0#2)) => (Signal.mux start (Signal.pure 1#2) sstate)
    | (sstate === (Signal.pure 1#2)) => (Signal.mux ack (Signal.pure 2#2) sstate)
    | (sstate === (Signal.pure 2#2)) => (Signal.mux (~~~ack) (Signal.pure 0#2) sstate)
  let req_next :=
    hw_cond req
    | rst => (Signal.pure false)
    | (sstate === (Signal.pure 0#2)) => (Signal.mux start (Signal.pure true) req)
    | (sstate === (Signal.pure 1#2)) => (Signal.mux ack (Signal.pure false) req)
  let data_r_next :=
    hw_cond data_r
    | rst => (Signal.pure 0#8)
    | (sstate === (Signal.pure 0#2)) => (Signal.mux start din data_r)
  let rstate_next :=
    hw_cond (Signal.pure 0#2)
    | rst => (Signal.pure 0#2)
    | (rstate === (Signal.pure 0#2)) => (Signal.mux req (Signal.pure 1#2) rstate)
    | (rstate === (Signal.pure 1#2)) => (Signal.mux (~~~req) (Signal.pure 2#2) rstate)
    | (rstate === (Signal.pure 2#2)) => (Signal.mux ((Signal.pure 1#2) === rel_cnt) (Signal.pure 0#2) rstate)
  let ack_next :=
    hw_cond ack
    | rst => (Signal.pure false)
    | (rstate === (Signal.pure 0#2)) => (Signal.mux req (Signal.pure true) ack)
    | (rstate === (Signal.pure 1#2)) => ack
    | (rstate === (Signal.pure 2#2)) => (Signal.mux ((Signal.pure 1#2) === rel_cnt) (Signal.pure false) ack)
  let cap_next :=
    hw_cond cap
    | rst => (Signal.pure 0#8)
    | (rstate === (Signal.pure 0#2)) => (Signal.mux req data_r cap)
  let rel_cnt_next :=
    hw_cond rel_cnt
    | rst => (Signal.pure 0#2)
    | (rstate === (Signal.pure 0#2)) => rel_cnt
    | (rstate === (Signal.pure 1#2)) => (Signal.mux (~~~req) (Signal.pure 0#2) rel_cnt)
    | (rstate === (Signal.pure 2#2)) => (Signal.mux ((Signal.pure 1#2) === rel_cnt) rel_cnt ((Signal.pure 1#2) + rel_cnt))
  bundleAll! [
    Signal.register 0#2 sstate_next,
    Signal.register false req_next,
    Signal.register 0#8 data_r_next,
    Signal.register 0#2 rstate_next,
    Signal.register false ack_next,
    Signal.register 0#8 cap_next,
    Signal.register 0#2 rel_cnt_next
  ]

def async_handshake {dom : DomainConfig}
    (rst : Signal dom Bool) (start : Signal dom Bool) (din : Signal dom (BitVec 8))
    : Signal dom Bool × Signal dom (BitVec 8) :=
  let state := Signal.loop fun state => async_handshakeBody rst start din state
  let sstate := Async_handshakeState.sstate state
  let req := Async_handshakeState.req state
  let data_r := Async_handshakeState.data_r state
  let rstate := Async_handshakeState.rstate state
  let ack := Async_handshakeState.ack state
  let cap := Async_handshakeState.cap state
  let rel_cnt := Async_handshakeState.rel_cnt state
  -- combinational logic feeding the outputs
  let busy := (~~~((Signal.pure 0#2) === sstate))
  let dout := cap
  (busy, dout)

end SparkleFV.Async_handshake
