/-
  AXI5-Lite Subordinate — Signal DSL Implementation

  Synthesizable subordinate-side AXI5-Lite interface (write channels
  AW/W/B and read channels AR/R) implementing the verified protocol FSMs
  from Sparkle.Verification.AXIProps (rules extracted from the AMBA AXI
  Protocol Specification, ARM IHI 0022 Issue L).

  Unlike the round-robin arbiter example — where the Signal DSL "mirrors"
  the spec and agreement is checked by simulation — this implementation
  is *proven* to refine the spec:

  - The next-state logic is a transliteration of `wrStepGates`/`rdStepGates`
    (Sparkle.Verification.AXIRefinement), and the loop bodies are proven
    **pointwise equal by `rfl`** to those pure functions
    (`writeFsmBody_succ`, `readFsmBody_succ`).
  - `writeFsm_refines_spec` / `readFsm_refines_spec` then show: any
    fixpoint of the loop body (which is what `Signal.loop` returns, per
    its contract) abstracts, cycle by cycle, to exactly the spec FSM
    trace — so every spec-cited theorem in AXIProps (BVALID only after
    AW+W handshakes, no spurious responses, …) holds of this hardware.

  The subordinate bridges AXI to a simple internal register-file port
  (wrEn/wrAddr/wrData + rdAddr/rdData), the standard AXI-Lite slave shim
  for register-based components (IHI 0022L §B2.1.5).
-/

import Sparkle.Core.Domain
import Sparkle.Core.Signal
import Sparkle.Compiler.Elab
import Sparkle.Verification.AXIProps
import Sparkle.Verification.AXIRefinement

set_option maxRecDepth 4096

namespace Sparkle.Examples.AXI.LiteSubordinate

open Sparkle.Core.Domain
open Sparkle.Core.Signal
open Sparkle.Verification.AXIProps
open Sparkle.Verification.AXIRefinement

/-!
## Write-channel FSM (AW/W/B)

State encoding (BitVec 2), from AXIRefinement:
  0 = IDLE, 1 = AW (request accepted), 2 = W (data accepted), 3 = RESP.
-/

/--
  Loop body of the write FSM: one registered state with next-state
  priority mux. This is a term-for-term transliteration of
  `AXIRefinement.wrStepGates` — proven pointwise equal below.
-/
def writeFsmBody {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool)
    (state : Signal dom (BitVec 2)) : Signal dom (BitVec 2) :=
  let isIdle := state === Signal.pure wrIdle
  let isAW   := state === Signal.pure wrAW
  let isW    := state === Signal.pure wrW
  let isResp := state === Signal.pure wrResp
  -- inverted inputs ((fun b => !b) <$> ·, the synthesis-supported form)
  let nAwValid := (fun b => !b) <$> awValid
  let nWValid  := (fun b => !b) <$> wValid
  let nBReady  := (fun b => !b) <$> bReady
  -- go-conditions (mutually exclusive by construction)
  let goResp := (isIdle &&& awValid &&& wValid) ||| (isAW &&& wValid) |||
                (isW &&& awValid) ||| (isResp &&& nBReady)
  let goAW   := (isIdle &&& awValid &&& nWValid) ||| (isAW &&& nWValid)
  let goW    := (isIdle &&& nAwValid &&& wValid) ||| (isW &&& nAwValid)
  let nextState := hw_cond (Signal.pure wrIdle)
    | goResp => (Signal.pure wrResp)
    | goAW   => (Signal.pure wrAW)
    | goW    => (Signal.pure wrW)
  Signal.register wrIdle nextState

/-- Write-channel FSM state signal. -/
def writeFsmSignal {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool) : Signal dom (BitVec 2) :=
  Signal.loop (writeFsmBody awValid wValid bReady)

-- Verify synthesis
#synthesizeVerilog writeFsmSignal

/-- AWREADY output (§A2.3 R8: READY defaults HIGH — asserted in IDLE/W). -/
def awReadySignal {dom : DomainConfig}
    (state : Signal dom (BitVec 2)) : Signal dom Bool :=
  (state === Signal.pure wrIdle) ||| (state === Signal.pure wrW)

/-- WREADY output (asserted in IDLE/AW). -/
def wReadySignal {dom : DomainConfig}
    (state : Signal dom (BitVec 2)) : Signal dom Bool :=
  (state === Signal.pure wrIdle) ||| (state === Signal.pure wrAW)

/-- BVALID output (asserted in RESP). -/
def bValidSignal {dom : DomainConfig}
    (state : Signal dom (BitVec 2)) : Signal dom Bool :=
  state === Signal.pure wrResp

/-!
### Formal correspondence: Signal body = proven RTL equations

`writeFsmBody` is built from transparent combinators (`register`, `mux`,
`beq`, applicative lifting), so its per-cycle behavior reduces
*definitionally* to the pure gate function verified in AXIRefinement.
Both lemmas are closed by `rfl` — there is no gap to trust.
-/

theorem writeFsmBody_zero {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool) (st : Signal dom (BitVec 2)) :
    (writeFsmBody awValid wValid bReady st).val 0 = wrIdle := rfl

theorem writeFsmBody_succ {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool) (st : Signal dom (BitVec 2))
    (t : Nat) :
    (writeFsmBody awValid wValid bReady st).val (t + 1)
      = wrStepGates (st.val t) (awValid.val t) (wValid.val t) (bReady.val t) := rfl

/--
  **End-to-end refinement (write channel)**: any signal `st` that is a
  fixpoint of the loop body — which is exactly what `Signal.loop`
  returns — abstracts at every cycle to the spec FSM state under the
  same inputs. Combined with `AXIRefinement.wr_trace_refines` corollaries,
  all spec-cited AXIProps safety theorems hold of this implementation.
-/
theorem writeFsm_refines_spec {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool) (st : Signal dom (BitVec 2))
    (hfix : st = writeFsmBody awValid wValid bReady st) (t : Nat) :
    decodeWr (st.val t)
      = wrSpecTrace (fun k => (awValid.val k, wValid.val k, bReady.val k)) t := by
  induction t with
  | zero =>
    have h0 : st.val 0 = wrIdle := congrArg (fun s => Signal.val s 0) hfix
    rw [h0]
    exact wrIdle_is_reset
  | succ t ih =>
    have hstep : st.val (t + 1)
        = wrStepGates (st.val t) (awValid.val t) (wValid.val t) (bReady.val t) :=
      congrArg (fun s => Signal.val s (t + 1)) hfix
    rw [hstep, wrStepGates_eq_RTL, ← wrStepRTL_refines, ih]
    rfl

/-- The implementation's BVALID matches the spec's BVALID at every cycle
    (for any fixpoint of the body). With `no_spurious_write_response`
    (§A2.6) this hardware can never emit a spurious write response. -/
theorem writeFsm_bvalid_refines {dom : DomainConfig}
    (awValid wValid bReady : Signal dom Bool) (st : Signal dom (BitVec 2))
    (hfix : st = writeFsmBody awValid wValid bReady st) (t : Nat) :
    (bValidSignal st).val t
      = (wrSpecTrace (fun k => (awValid.val k, wValid.val k, bReady.val k)) t).bValid := by
  have h : (bValidSignal st).val t = bValidRTL (st.val t) := rfl
  rw [h, ← writeFsm_refines_spec awValid wValid bReady st hfix t]
  exact (wrOutputs_refine (st.val t)).2.2

/-!
## Read-channel FSM (AR/R)

State encoding (BitVec 1): 0 = IDLE, 1 = RESP (RVALID asserted).
-/

/-- Loop body of the read FSM — transliteration of
    `AXIRefinement.rdStepGates`. -/
def readFsmBody {dom : DomainConfig}
    (arValid rReady : Signal dom Bool)
    (state : Signal dom (BitVec 1)) : Signal dom (BitVec 1) :=
  let isResp := state === Signal.pure rdResp
  let nRReady := (fun b => !b) <$> rReady
  let nIsResp := (fun b => !b) <$> isResp
  let goResp := (isResp &&& nRReady) ||| (nIsResp &&& arValid)
  let nextState := hw_cond (Signal.pure rdIdle)
    | goResp => (Signal.pure rdResp)
  Signal.register rdIdle nextState

/-- Read-channel FSM state signal. -/
def readFsmSignal {dom : DomainConfig}
    (arValid rReady : Signal dom Bool) : Signal dom (BitVec 1) :=
  Signal.loop (readFsmBody arValid rReady)

-- Verify synthesis
#synthesizeVerilog readFsmSignal

/-- ARREADY output (asserted in IDLE, §A2.3 R8). -/
def arReadySignal {dom : DomainConfig}
    (state : Signal dom (BitVec 1)) : Signal dom Bool :=
  state === Signal.pure rdIdle

/-- RVALID output (asserted in RESP). -/
def rValidSignal {dom : DomainConfig}
    (state : Signal dom (BitVec 1)) : Signal dom Bool :=
  state === Signal.pure rdResp

theorem readFsmBody_zero {dom : DomainConfig}
    (arValid rReady : Signal dom Bool) (st : Signal dom (BitVec 1)) :
    (readFsmBody arValid rReady st).val 0 = rdIdle := rfl

theorem readFsmBody_succ {dom : DomainConfig}
    (arValid rReady : Signal dom Bool) (st : Signal dom (BitVec 1)) (t : Nat) :
    (readFsmBody arValid rReady st).val (t + 1)
      = rdStepGates (st.val t) (arValid.val t) (rReady.val t) := rfl

/-- **End-to-end refinement (read channel)**. -/
theorem readFsm_refines_spec {dom : DomainConfig}
    (arValid rReady : Signal dom Bool) (st : Signal dom (BitVec 1))
    (hfix : st = readFsmBody arValid rReady st) (t : Nat) :
    decodeRd (st.val t)
      = rdSpecTrace (fun k => (arValid.val k, rReady.val k)) t := by
  induction t with
  | zero =>
    have h0 : st.val 0 = rdIdle := congrArg (fun s => Signal.val s 0) hfix
    rw [h0]
    exact rdIdle_is_reset
  | succ t ih =>
    have hstep : st.val (t + 1)
        = rdStepGates (st.val t) (arValid.val t) (rReady.val t) :=
      congrArg (fun s => Signal.val s (t + 1)) hfix
    rw [hstep, rdStepGates_eq_RTL, ← rdStepRTL_refines, ih]
    rfl

/-!
## Address/data latches and register-file port

The AW/W/AR payloads are captured at their handshakes
(`AXIProps.liteStep` latching semantics). The latch is `register` +
`mux` feedback; its per-cycle behavior is again provable by `rfl`.
-/

/-- Loop body of an enable-latch (holds last enabled value, resets to 0). -/
def latchBody {dom : DomainConfig} {w : Nat}
    (en : Signal dom Bool) (d : Signal dom (BitVec w))
    (q : Signal dom (BitVec w)) : Signal dom (BitVec w) :=
  Signal.register 0#w (Signal.mux en d q)

/-- Enable-latch signal. -/
def latchSignal {dom : DomainConfig} {w : Nat}
    (en : Signal dom Bool) (d : Signal dom (BitVec w)) : Signal dom (BitVec w) :=
  Signal.loop (latchBody en d)

theorem latchBody_zero {dom : DomainConfig} {w : Nat}
    (en : Signal dom Bool) (d q : Signal dom (BitVec w)) :
    (latchBody en d q).val 0 = 0#w := rfl

/-- Latch semantics: captures `d` when enabled, holds otherwise — the
    exact latching rule of `AXIProps.liteStep`. -/
theorem latchBody_succ {dom : DomainConfig} {w : Nat}
    (en : Signal dom Bool) (d q : Signal dom (BitVec w)) (t : Nat) :
    (latchBody en d q).val (t + 1)
      = if en.val t then d.val t else q.val t := rfl

/-!
## Full AXI5-Lite subordinate

Bridges the five AXI channels to a register-file port. All transactions
are single-transfer (IHI 0022L §B2.1.5: "All transactions have burst
length 1"), responses are always OKAY (`AXIProps.liteWriteResp .success`;
BRESP/RRESP width-0 default per §A3.3).
-/

/--
  AXI5-Lite subordinate control + datapath.

  Returns:
  - AXI outputs: `(awReady, wReady, bValid)`, `(arReady, rValid)`
  - register-file write port: `(wrEn, wrAddr, wrData)` — pulse + payload
    at the cycle BVALID rises (the commit point proven observable in
    `AXIProps.write_commit_observable`)
  - register-file read address: `rdAddr` (data returns on `rdData`)
-/
def axi5LiteSubordinate {dom : DomainConfig}
    (awValid : Signal dom Bool) (awAddr : Signal dom (BitVec 32))
    (wValid : Signal dom Bool) (wData : Signal dom (BitVec 32))
    (bReady : Signal dom Bool)
    (arValid : Signal dom Bool) (arAddr : Signal dom (BitVec 32))
    (rReady : Signal dom Bool) :
    Signal dom (((Bool × Bool) × Bool) ×
                ((Bool × Bool) × ((Bool × (BitVec 32 × BitVec 32)) × BitVec 32))) :=
  -- Channel FSMs (proven to refine the AXIProps spec model)
  let wrState := writeFsmSignal awValid wValid bReady
  let rdState := readFsmSignal arValid rReady
  -- AXI handshake outputs
  let awReady := awReadySignal wrState
  let wReady  := wReadySignal wrState
  let bValid  := bValidSignal wrState
  let arReady := arReadySignal rdState
  let rValid  := rValidSignal rdState
  -- Payload latches at their handshakes (AXIProps.liteStep latching)
  let awAddrQ := latchSignal (awValid &&& awReady) awAddr
  let wDataQ  := latchSignal (wValid &&& wReady) wData
  let arAddrQ := latchSignal (arValid &&& arReady) arAddr
  -- Commit pulse: entering RESP (both handshakes complete, §A2.3.2.1)
  let isIdle := wrState === Signal.pure wrIdle
  let isAW   := wrState === Signal.pure wrAW
  let isW    := wrState === Signal.pure wrW
  let wrEn := (isIdle &&& awValid &&& wValid) ||| (isAW &&& wValid) |||
              (isW &&& awValid)
  -- Write payload for the commit: captured value, or the in-flight input
  -- when the handshake happens in the commit cycle itself
  let wrAddr := Signal.mux (awValid &&& awReady) awAddr awAddrQ
  let wrData := Signal.mux (wValid &&& wReady) wData wDataQ
  bundle2 (bundle2 (bundle2 awReady wReady) bValid)
    (bundle2 (bundle2 arReady rValid)
      (bundle2 (bundle2 wrEn (bundle2 wrAddr wrData)) arAddrQ))

-- Verify synthesis of the full subordinate
#synthesizeVerilog axi5LiteSubordinate

/-!
## Simulation cross-check

Runs the RTL gate-level recursion (`wrRTLTrace`/`rdRTLTrace`) — which is
the loop body's per-cycle semantics, proven **by `rfl`** in
`writeFsmBody_succ`/`readFsmBody_succ` — against the spec FSM traces for
a manager scenario, printing both. (The `Signal.loop` fixpoint itself
cannot be sampled in the interpreter; its behavior is covered by the
refinement theorems above.)
-/

def wrScenario : List (Bool × Bool × Bool) := [
  (false, false, false),  -- idle
  (true,  false, false),  -- AW only            → AW
  (false, true,  true),   -- W arrives           → RESP (BVALID)
  (false, false, true),   -- BREADY: handshake   → IDLE
  (true,  true,  false),  -- AW+W same cycle     → RESP
  (false, false, false),  -- manager not ready   → RESP held (§A2.3)
  (false, false, true),   -- BREADY              → IDLE
  (false, true,  false),  -- W before AW (§A2.6) → W
  (true,  false, true),   -- AW arrives          → RESP
  (false, false, true)    -- handshake           → IDLE
]

def rdScenario : List (Bool × Bool) := [
  (false, false),  -- idle
  (true,  false),  -- AR handshake        → RESP (RVALID)
  (false, false),  -- manager not ready   → RESP held (§A2.3)
  (false, true),   -- RREADY: handshake   → IDLE
  (true,  true),   -- back-to-back read   → RESP
  (false, true),   -- immediate handshake → IDLE
  (false, false)
]

def stateName : BitVec 2 → String
  | 0#2 => "IDLE"
  | 1#2 => "AW  "
  | 2#2 => "W   "
  | _   => "RESP"

def simTest : IO Unit := do
  IO.println "=== AXI5-Lite Subordinate: RTL trace vs. verified spec ==="
  let wrIn := fun t => wrScenario.getD t (false, false, false)
  IO.println "\nWrite FSM: cycle | AWV WV BR | RTL   | spec-BVALID (decoded RTL = spec?)"
  let mut wrSpec := wrReset
  let mut ok := true
  for t in [:wrScenario.length] do
    let rtlSt := wrRTLTrace wrIn t
    let match_ := decodeWr rtlSt == wrSpec
    ok := ok && match_
    let (av, wv, br) := wrIn t
    IO.println s!"   {t}   |  {av} {wv} {br}  | {stateName rtlSt} | bValid={wrSpec.bValid} {if match_ then "✓" else "✗ MISMATCH"}"
    wrSpec := wrStep wrSpec av wv br
  let rdIn := fun t => rdScenario.getD t (false, false)
  IO.println "\nRead FSM: cycle | ARV RR | RTL  | spec-RVALID (decoded RTL = spec?)"
  let mut rdSpec := rdReset
  for t in [:rdScenario.length] do
    let rtlSt := rdRTLTrace rdIn t
    let match_ := decodeRd rtlSt == rdSpec
    ok := ok && match_
    let (av, rr) := rdIn t
    IO.println s!"   {t}   |  {av} {rr} | {if rtlSt == rdResp then "RESP" else "IDLE"} | rValid={rdSpec.rValid} {if match_ then "✓" else "✗ MISMATCH"}"
    rdSpec := rdStep rdSpec av rr
  if ok then
    IO.println "\nPASS: RTL trace = spec trace at every cycle (as proven by wr/rd_trace_refines)."
  else
    IO.println "\nFAIL: RTL trace diverged from spec."
    throw <| IO.userError "AXI5-Lite RTL/spec divergence"

#eval simTest

end Sparkle.Examples.AXI.LiteSubordinate
