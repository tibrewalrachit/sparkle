/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/blocks/pipeline_hazard/design.sv
  Top module : pipeline_hazard
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Pipeline_hazard

/-- Architectural state of `pipeline_hazard` (one field per hardware register). -/
declare_signal_state Pipeline_hazardState
  | s1_valid : Bool := false
  | s1_op : BitVec 2 := 0#2
  | s1_rd : BitVec 2 := 0#2
  | s1_rs1 : BitVec 2 := 0#2
  | s1_rs2 : BitVec 2 := 0#2
  | s1_imm : BitVec 8 := 0#8
  | s1_a : BitVec 32 := 0#32
  | s1_b : BitVec 32 := 0#32
  | wb_valid : Bool := false
  | wb_rd : BitVec 2 := 0#2
  | wb_val : BitVec 32 := 0#32
  | rf0 : BitVec 32 := 0#32
  | rf1 : BitVec 32 := 0#32
  | rf2 : BitVec 32 := 0#32
  | rf3 : BitVec 32 := 0#32
  | arch0 : BitVec 32 := 0#32
  | arch1 : BitVec 32 := 0#32
  | arch2 : BitVec 32 := 0#32
  | arch3 : BitVec 32 := 0#32

/-- Signal-DSL model of `pipeline_hazard`.
    Inputs: `rst`, `in_valid`, `in_op`, `in_rd`, `in_rs1`, `in_rs2`, `in_imm`; outputs: `out_result`. -/
private def pipeline_hazardBody {dom : DomainConfig}
    (rst : Signal dom Bool) (in_valid : Signal dom Bool) (in_op : Signal dom (BitVec 2)) (in_rd : Signal dom (BitVec 2)) (in_rs1 : Signal dom (BitVec 2)) (in_rs2 : Signal dom (BitVec 2)) (in_imm : Signal dom (BitVec 8))
    (state : Signal dom Pipeline_hazardState) : Signal dom Pipeline_hazardState :=
  let s1_valid := Pipeline_hazardState.s1_valid state
  let s1_op := Pipeline_hazardState.s1_op state
  let s1_rd := Pipeline_hazardState.s1_rd state
  let s1_rs1 := Pipeline_hazardState.s1_rs1 state
  let s1_rs2 := Pipeline_hazardState.s1_rs2 state
  let s1_imm := Pipeline_hazardState.s1_imm state
  let s1_a := Pipeline_hazardState.s1_a state
  let s1_b := Pipeline_hazardState.s1_b state
  let wb_valid := Pipeline_hazardState.wb_valid state
  let wb_rd := Pipeline_hazardState.wb_rd state
  let wb_val := Pipeline_hazardState.wb_val state
  let rf0 := Pipeline_hazardState.rf0 state
  let rf1 := Pipeline_hazardState.rf1 state
  let rf2 := Pipeline_hazardState.rf2 state
  let rf3 := Pipeline_hazardState.rf3 state
  let arch0 := Pipeline_hazardState.arch0 state
  let arch1 := Pipeline_hazardState.arch1 state
  let arch2 := Pipeline_hazardState.arch2 state
  let arch3 := Pipeline_hazardState.arch3 state
  -- combinational logic feeding the registers
  let id_a :=
    hw_cond rf3
    | (wb_valid &&& (in_rs1 === wb_rd)) => wb_val
    | ((Signal.pure 0#2) === in_rs1) => rf0
    | ((Signal.pure 1#2) === in_rs1) => rf1
    | ((Signal.pure 2#2) === in_rs1) => rf2
  let id_b :=
    hw_cond rf3
    | (wb_valid &&& (in_rs2 === wb_rd)) => wb_val
    | ((Signal.pure 0#2) === in_rs2) => rf0
    | ((Signal.pure 1#2) === in_rs2) => rf1
    | ((Signal.pure 2#2) === in_rs2) => rf2
  let ex_a := (Signal.mux (wb_valid &&& (s1_rs1 === wb_rd)) wb_val s1_a)
  let arch_rs1 :=
    hw_cond arch3
    | ((Signal.pure 0#2) === s1_rs1) => arch0
    | ((Signal.pure 1#2) === s1_rs1) => arch1
    | ((Signal.pure 2#2) === s1_rs1) => arch2
  let ex_b := (Signal.mux (wb_valid &&& (s1_rs2 === wb_rd)) wb_val s1_b)
  let arch_rs2 :=
    hw_cond arch3
    | ((Signal.pure 0#2) === s1_rs2) => arch0
    | ((Signal.pure 1#2) === s1_rs2) => arch1
    | ((Signal.pure 2#2) === s1_rs2) => arch2
  let imm_ext := ((BitVec.zeroExtend 32) <$> s1_imm)
  let VdfgTmp_h0cff8c02__0 := ((Signal.pure 0#2) === s1_op)
  let VdfgTmp_h0c9bfc17__0 := ((Signal.pure 1#2) === s1_op)
  let VdfgTmp_h0c87edf8__0 := ((Signal.pure 2#2) === s1_op)
  let ex_result :=
    hw_cond (ex_a + imm_ext)
    | VdfgTmp_h0cff8c02__0 => (ex_a + ex_b)
    | VdfgTmp_h0c9bfc17__0 => (ex_a ^^^ ex_b)
    | VdfgTmp_h0c87edf8__0 => imm_ext
  let arch_result :=
    hw_cond (arch_rs1 + imm_ext)
    | VdfgTmp_h0cff8c02__0 => (arch_rs1 + arch_rs2)
    | VdfgTmp_h0c9bfc17__0 => (arch_rs1 ^^^ arch_rs2)
    | VdfgTmp_h0c87edf8__0 => imm_ext
  -- next-state values (non-blocking updates, one per register)
  let s1_valid_next := (Signal.mux rst (Signal.pure false) in_valid)
  let s1_op_next := (Signal.mux rst s1_op in_op)
  let s1_rd_next := (Signal.mux rst s1_rd in_rd)
  let s1_rs1_next := (Signal.mux rst s1_rs1 in_rs1)
  let s1_rs2_next := (Signal.mux rst s1_rs2 in_rs2)
  let s1_imm_next := (Signal.mux rst s1_imm in_imm)
  let s1_a_next := (Signal.mux rst s1_a id_a)
  let s1_b_next := (Signal.mux rst s1_b id_b)
  let wb_valid_next := (Signal.mux rst (Signal.pure false) s1_valid)
  let wb_rd_next := (Signal.mux rst wb_rd s1_rd)
  let wb_val_next := (Signal.mux rst wb_val ex_result)
  let rf0_next :=
    hw_cond rf0
    | rst => (Signal.pure 0#32)
    | wb_valid => (Signal.mux ((Signal.pure 0#2) === wb_rd) wb_val rf0)
  let rf1_next :=
    hw_cond rf1
    | rst => (Signal.pure 0#32)
    | wb_valid => (Signal.mux ((Signal.pure 1#2) === wb_rd) wb_val rf1)
  let rf2_next :=
    hw_cond rf2
    | rst => (Signal.pure 0#32)
    | wb_valid => (Signal.mux ((Signal.pure 2#2) === wb_rd) wb_val rf2)
  let rf3_next :=
    hw_cond rf3
    | rst => (Signal.pure 0#32)
    | wb_valid => (Signal.mux ((Signal.pure 3#2) === wb_rd) wb_val rf3)
  let arch0_next :=
    hw_cond arch0
    | rst => (Signal.pure 0#32)
    | s1_valid => (Signal.mux ((Signal.pure 0#2) === s1_rd) arch_result arch0)
  let arch1_next :=
    hw_cond arch1
    | rst => (Signal.pure 0#32)
    | s1_valid => (Signal.mux ((Signal.pure 1#2) === s1_rd) arch_result arch1)
  let arch2_next :=
    hw_cond arch2
    | rst => (Signal.pure 0#32)
    | s1_valid => (Signal.mux ((Signal.pure 2#2) === s1_rd) arch_result arch2)
  let arch3_next :=
    hw_cond arch3
    | rst => (Signal.pure 0#32)
    | s1_valid => (Signal.mux ((Signal.pure 3#2) === s1_rd) arch_result arch3)
  bundleAll! [
    Signal.register false s1_valid_next,
    Signal.register 0#2 s1_op_next,
    Signal.register 0#2 s1_rd_next,
    Signal.register 0#2 s1_rs1_next,
    Signal.register 0#2 s1_rs2_next,
    Signal.register 0#8 s1_imm_next,
    Signal.register 0#32 s1_a_next,
    Signal.register 0#32 s1_b_next,
    Signal.register false wb_valid_next,
    Signal.register 0#2 wb_rd_next,
    Signal.register 0#32 wb_val_next,
    Signal.register 0#32 rf0_next,
    Signal.register 0#32 rf1_next,
    Signal.register 0#32 rf2_next,
    Signal.register 0#32 rf3_next,
    Signal.register 0#32 arch0_next,
    Signal.register 0#32 arch1_next,
    Signal.register 0#32 arch2_next,
    Signal.register 0#32 arch3_next
  ]

def pipeline_hazard {dom : DomainConfig}
    (rst : Signal dom Bool) (in_valid : Signal dom Bool) (in_op : Signal dom (BitVec 2)) (in_rd : Signal dom (BitVec 2)) (in_rs1 : Signal dom (BitVec 2)) (in_rs2 : Signal dom (BitVec 2)) (in_imm : Signal dom (BitVec 8))
    : Signal dom (BitVec 32) :=
  let state := Signal.loop fun state => pipeline_hazardBody rst in_valid in_op in_rd in_rs1 in_rs2 in_imm state
  let s1_valid := Pipeline_hazardState.s1_valid state
  let s1_op := Pipeline_hazardState.s1_op state
  let s1_rd := Pipeline_hazardState.s1_rd state
  let s1_rs1 := Pipeline_hazardState.s1_rs1 state
  let s1_rs2 := Pipeline_hazardState.s1_rs2 state
  let s1_imm := Pipeline_hazardState.s1_imm state
  let s1_a := Pipeline_hazardState.s1_a state
  let s1_b := Pipeline_hazardState.s1_b state
  let wb_valid := Pipeline_hazardState.wb_valid state
  let wb_rd := Pipeline_hazardState.wb_rd state
  let wb_val := Pipeline_hazardState.wb_val state
  let rf0 := Pipeline_hazardState.rf0 state
  let rf1 := Pipeline_hazardState.rf1 state
  let rf2 := Pipeline_hazardState.rf2 state
  let rf3 := Pipeline_hazardState.rf3 state
  let arch0 := Pipeline_hazardState.arch0 state
  let arch1 := Pipeline_hazardState.arch1 state
  let arch2 := Pipeline_hazardState.arch2 state
  let arch3 := Pipeline_hazardState.arch3 state
  -- combinational logic feeding the outputs
  let out_result := wb_val
  out_result

end SparkleFV.Pipeline_hazard
