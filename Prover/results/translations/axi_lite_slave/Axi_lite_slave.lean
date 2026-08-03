/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/axi_lite_slave/design.sv
  Top module : axi_lite_slave
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Axi_lite_slave

/-- Architectural state of `axi_lite_slave` (one field per hardware register). -/
declare_signal_state Axi_lite_slaveState
  | aw_done : Bool := false
  | w_done : Bool := false
  | bvalid_q : Bool := false
  | awaddr_q : BitVec 4 := 0#4
  | wdata_q : BitVec 32 := 0#32
  | prev_ok : Bool := false
  | bvalid_p : Bool := false
  | bready_p : Bool := false

/-- Signal-DSL model of `axi_lite_slave`.
    Inputs: `rst`, `awvalid`, `awaddr`, `wvalid`, `wdata`, `bready`; outputs: `awready`, `wready`, `bvalid`. -/
private def axi_lite_slaveBody {dom : DomainConfig}
    (rst : Signal dom Bool) (awvalid : Signal dom Bool) (awaddr : Signal dom (BitVec 4)) (wvalid : Signal dom Bool) (wdata : Signal dom (BitVec 32)) (bready : Signal dom Bool)
    (state : Signal dom Axi_lite_slaveState) : Signal dom Axi_lite_slaveState :=
  let aw_done := Axi_lite_slaveState.aw_done state
  let w_done := Axi_lite_slaveState.w_done state
  let bvalid_q := Axi_lite_slaveState.bvalid_q state
  let awaddr_q := Axi_lite_slaveState.awaddr_q state
  let wdata_q := Axi_lite_slaveState.wdata_q state
  let prev_ok := Axi_lite_slaveState.prev_ok state
  let bvalid_p := Axi_lite_slaveState.bvalid_p state
  let bready_p := Axi_lite_slaveState.bready_p state
  -- combinational logic feeding the registers
  let bvalid := bvalid_q
  let VdfgTmp_hab165a67__0 := (~~~bvalid_q)
  let awready := ((~~~aw_done) &&& VdfgTmp_hab165a67__0)
  let wready := ((~~~w_done) &&& VdfgTmp_hab165a67__0)
  let aw_fire := (awvalid &&& awready)
  let w_fire := (wvalid &&& wready)
  let both_done := ((aw_done ||| aw_fire) &&& (w_done ||| w_fire))
  -- next-state values (non-blocking updates, one per register)
  let aw_done_next :=
    hw_cond aw_done
    | rst => (Signal.pure false)
    | ((~~~bvalid_q) &&& both_done) => (Signal.mux aw_fire (Signal.pure true) aw_done)
    | (bvalid_q &&& bready) => (Signal.pure false)
    | aw_fire => (Signal.pure true)
  let w_done_next :=
    hw_cond w_done
    | rst => (Signal.pure false)
    | ((~~~bvalid_q) &&& both_done) => (Signal.mux w_fire (Signal.pure true) w_done)
    | (bvalid_q &&& bready) => (Signal.pure false)
    | w_fire => (Signal.pure true)
  let bvalid_q_next :=
    hw_cond bvalid_q
    | rst => (Signal.pure false)
    | ((~~~bvalid_q) &&& both_done) => (Signal.pure true)
    | (bvalid_q &&& bready) => (Signal.pure false)
  let awaddr_q_next :=
    hw_cond awaddr_q
    | rst => awaddr_q
    | aw_fire => awaddr
  let wdata_q_next :=
    hw_cond wdata_q
    | rst => wdata_q
    | w_fire => wdata
  let prev_ok_next := (~~~rst)
  let bvalid_p_next := bvalid
  let bready_p_next := bready
  bundleAll! [
    Signal.register false aw_done_next,
    Signal.register false w_done_next,
    Signal.register false bvalid_q_next,
    Signal.register 0#4 awaddr_q_next,
    Signal.register 0#32 wdata_q_next,
    Signal.register false prev_ok_next,
    Signal.register false bvalid_p_next,
    Signal.register false bready_p_next
  ]

def axi_lite_slave {dom : DomainConfig}
    (rst : Signal dom Bool) (awvalid : Signal dom Bool) (awaddr : Signal dom (BitVec 4)) (wvalid : Signal dom Bool) (wdata : Signal dom (BitVec 32)) (bready : Signal dom Bool)
    : Signal dom Bool × Signal dom Bool × Signal dom Bool :=
  let state := Signal.loop fun state => axi_lite_slaveBody rst awvalid awaddr wvalid wdata bready state
  let aw_done := Axi_lite_slaveState.aw_done state
  let w_done := Axi_lite_slaveState.w_done state
  let bvalid_q := Axi_lite_slaveState.bvalid_q state
  let awaddr_q := Axi_lite_slaveState.awaddr_q state
  let wdata_q := Axi_lite_slaveState.wdata_q state
  let prev_ok := Axi_lite_slaveState.prev_ok state
  let bvalid_p := Axi_lite_slaveState.bvalid_p state
  let bready_p := Axi_lite_slaveState.bready_p state
  -- combinational logic feeding the outputs
  let bvalid := bvalid_q
  let VdfgTmp_hab165a67__0 := (~~~bvalid_q)
  let awready := ((~~~aw_done) &&& VdfgTmp_hab165a67__0)
  let wready := ((~~~w_done) &&& VdfgTmp_hab165a67__0)
  (awready, wready, bvalid)

end SparkleFV.Axi_lite_slave
