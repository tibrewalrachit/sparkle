/-
  AMBA AXI — Spec-to-RTL Refinement

  Closes the gap between the verified AXI protocol spec model
  (Sparkle/Verification/AXIProps.lean, rules from ARM IHI 0022 Issue L)
  and the synthesizable Signal DSL implementation
  (Examples/AXI/LiteSubordinate.lean).

  Refinement chain (every link machine-checked):

    spec FSM (WrState / RdState)            -- AXIProps, spec-cited theorems
      ↕  decodeWr / decodeRd                -- bisimulation, `wrStepRTL_refines`
    RTL FSM on BitVec state                 -- if-chain form, `wrStepRTL`
      =  gate form                          -- `wrStepGates_eq_RTL`
    sum-of-products gate equations          -- `wrStepGates`
      =  Signal DSL body, pointwise         -- proven in LiteSubordinate.lean
    synthesizable implementation

  Plus stream-level theorems: cycle-accurate trace equality for every
  input stream, and uniqueness of the register-feedback fixpoint (the
  contract `Signal.loop` provides).

  The RTL write FSM uses the 4 *reachable* states of the spec model
  (bValid → awDone ∧ wDone is invariant, so ⟨t,f,t⟩-style states never
  occur); the read FSM uses the 2 reachable states. `decodeWr`/`decodeRd`
  are injective, so this is a bisimulation, not just simulation.
-/

import Sparkle.Verification.AXIProps

namespace Sparkle.Verification.AXIRefinement

open Sparkle.Verification.AXIProps

/-!
## Write-channel RTL FSM (AW/W/B)

State encoding (BitVec 2) over the reachable states of `WrState`:
  0 = IDLE  (nothing accepted)             ↦ ⟨false, false, false⟩
  1 = AW    (request accepted, no data)    ↦ ⟨true,  false, false⟩
  2 = W     (data accepted, no request)    ↦ ⟨false, true,  false⟩
  3 = RESP  (both accepted, BVALID high)   ↦ ⟨true,  true,  true⟩
-/

abbrev wrIdle : BitVec 2 := 0#2
abbrev wrAW   : BitVec 2 := 1#2
abbrev wrW    : BitVec 2 := 2#2
abbrev wrResp : BitVec 2 := 3#2

/-- RTL next-state function, priority-mux (if-chain) form. -/
def wrStepRTL (s : BitVec 2) (awValid wValid bReady : Bool) : BitVec 2 :=
  if s = wrIdle then
    if awValid && wValid then wrResp
    else if awValid then wrAW
    else if wValid then wrW
    else wrIdle
  else if s = wrAW then
    if wValid then wrResp else wrAW
  else if s = wrW then
    if awValid then wrResp else wrW
  else /- wrResp -/
    if bReady then wrIdle else wrResp

/--
  RTL next-state function, sum-of-products gate form — this is the exact
  boolean structure the Signal DSL implementation computes (one `hw_cond`
  priority mux over three go-conditions).
-/
def wrStepGates (s : BitVec 2) (awValid wValid bReady : Bool) : BitVec 2 :=
  let isIdle := s == wrIdle
  let isAW   := s == wrAW
  let isW    := s == wrW
  let isResp := s == wrResp
  let goResp := (isIdle && awValid && wValid) || (isAW && wValid) ||
                (isW && awValid) || (isResp && !bReady)
  let goAW   := (isIdle && awValid && !wValid) || (isAW && !wValid)
  let goW    := (isIdle && !awValid && wValid) || (isW && !awValid)
  if goResp then wrResp
  else if goAW then wrAW
  else if goW then wrW
  else wrIdle

/-- The gate form computes the same function as the if-chain form. -/
theorem wrStepGates_eq_RTL :
    ∀ (s : BitVec 2) (awValid wValid bReady : Bool),
      wrStepGates s awValid wValid bReady = wrStepRTL s awValid wValid bReady := by
  decide

/-- RTL output: AWREADY (accept a request in IDLE or W). -/
def awReadyRTL (s : BitVec 2) : Bool := s == wrIdle || s == wrW

/-- RTL output: WREADY (accept data in IDLE or AW). -/
def wReadyRTL (s : BitVec 2) : Bool := s == wrIdle || s == wrAW

/-- RTL output: BVALID (respond in RESP). -/
def bValidRTL (s : BitVec 2) : Bool := s == wrResp

/-- Abstraction function: RTL state → spec state. -/
def decodeWr (v : BitVec 2) : WrState :=
  if v = wrIdle then ⟨false, false, false⟩
  else if v = wrAW then ⟨true, false, false⟩
  else if v = wrW then ⟨false, true, false⟩
  else ⟨true, true, true⟩

/-- `decodeWr` is injective — the RTL FSM is a bisimulation of the spec
    FSM restricted to its reachable states, not a lossy simulation. -/
theorem decodeWr_injective :
    ∀ v w : BitVec 2, decodeWr v = decodeWr w → v = w := by
  decide

/-- Every RTL state maps to a spec state satisfying the §A2.3.2.1
    invariant (BVALID → AW and last-W handshakes done). -/
theorem decodeWr_inv : ∀ v : BitVec 2, WrInv (decodeWr v) := by
  have h : ∀ v : BitVec 2, (decodeWr v).bValid = true →
      (decodeWr v).awDone = true ∧ (decodeWr v).wDone = true := by decide
  exact h

/--
  **Bisimulation square (write channel)**: one RTL step tracked through
  the abstraction function is exactly one spec step.

        WrState  ── wrStep ──▶  WrState
          ▲                        ▲
      decodeWr                 decodeWr
          │                        │
        BitVec 2 ── wrStepRTL ─▶ BitVec 2
-/
theorem wrStepRTL_refines :
    ∀ (v : BitVec 2) (awValid wValid bReady : Bool),
      wrStep (decodeWr v) awValid wValid bReady
        = decodeWr (wrStepRTL v awValid wValid bReady) := by
  decide

/-- RTL outputs equal spec outputs through the abstraction function
    (AWREADY, WREADY per the spec's `awReady`/`wReady`, BVALID per the
    spec state field). -/
theorem wrOutputs_refine :
    ∀ v : BitVec 2,
      awReadyRTL v = awReady (decodeWr v) ∧
      wReadyRTL v = wReady (decodeWr v) ∧
      bValidRTL v = (decodeWr v).bValid := by
  decide

/-- The RTL reset state abstracts to the spec reset state. -/
theorem wrIdle_is_reset : decodeWr wrIdle = wrReset := by decide

/-!
## Read-channel RTL FSM (AR/R)

State encoding (BitVec 1) over the reachable states of `RdState`:
  0 = IDLE (no request)                ↦ ⟨false, false⟩
  1 = RESP (request taken, RVALID)     ↦ ⟨true,  true⟩
-/

abbrev rdIdle : BitVec 1 := 0#1
abbrev rdResp : BitVec 1 := 1#1

/-- RTL next-state function, if-chain form. -/
def rdStepRTL (s : BitVec 1) (arValid rReady : Bool) : BitVec 1 :=
  if s = rdResp then
    if rReady then rdIdle else rdResp
  else
    if arValid then rdResp else rdIdle

/-- RTL next-state function, gate form (mirrors the Signal DSL body). -/
def rdStepGates (s : BitVec 1) (arValid rReady : Bool) : BitVec 1 :=
  let isResp := s == rdResp
  let goResp := (isResp && !rReady) || (!isResp && arValid)
  if goResp then rdResp else rdIdle

theorem rdStepGates_eq_RTL :
    ∀ (s : BitVec 1) (arValid rReady : Bool),
      rdStepGates s arValid rReady = rdStepRTL s arValid rReady := by
  decide

/-- RTL output: ARREADY (accept a request in IDLE). -/
def arReadyRTL (s : BitVec 1) : Bool := s == rdIdle

/-- RTL output: RVALID (data presented in RESP). -/
def rValidRTL (s : BitVec 1) : Bool := s == rdResp

/-- Abstraction function: RTL state → spec state. -/
def decodeRd (v : BitVec 1) : RdState :=
  if v = rdResp then ⟨true, true⟩ else ⟨false, false⟩

theorem decodeRd_injective :
    ∀ v w : BitVec 1, decodeRd v = decodeRd w → v = w := by
  decide

/-- Every RTL state maps to a spec state satisfying the §A2.3.2.2
    invariant (RVALID → AR handshake done). -/
theorem decodeRd_inv : ∀ v : BitVec 1, RdInv (decodeRd v) := by
  have h : ∀ v : BitVec 1, (decodeRd v).rValid = true →
      (decodeRd v).arDone = true := by decide
  exact h

/-- **Bisimulation square (read channel)**. -/
theorem rdStepRTL_refines :
    ∀ (v : BitVec 1) (arValid rReady : Bool),
      rdStep (decodeRd v) arValid rReady
        = decodeRd (rdStepRTL v arValid rReady) := by
  decide

theorem rdOutputs_refine :
    ∀ v : BitVec 1,
      arReadyRTL v = arReady (decodeRd v) ∧
      rValidRTL v = (decodeRd v).rValid := by
  decide

theorem rdIdle_is_reset : decodeRd rdIdle = rdReset := by decide

/-!
## Stream-level (cycle-accurate) correspondence

A hardware register with feedback computes a Mealy recursion over time.
These theorems lift the per-step bisimulation squares to *whole traces*:
for **every** input stream, at **every** cycle, the RTL state abstracts
to exactly the spec state.
-/

/-- Generic Mealy state recursion: the semantics of a register with
    next-state feedback (`Signal.register init (step ∘ state × input)`). -/
def mealyRec {σ ι : Type} (step : σ → ι → σ) (init : σ) (i : Nat → ι) : Nat → σ
  | 0 => init
  | t + 1 => step (mealyRec step init i t) (i t)

/--
  **Fixpoint uniqueness**: any stream satisfying the register-feedback
  equations (`g 0 = init`, `g (t+1) = step (g t) (i t)`) is pointwise
  equal to `mealyRec`. This is the contract `Signal.loop` provides for a
  body of the form `register init (f state inputs)`: the loop's output is
  a fixpoint of the body, and by this theorem that fixpoint is unique —
  so any fixpoint the implementation returns has the verified behavior.
-/
theorem mealy_fixpoint_unique {σ ι : Type} (step : σ → ι → σ) (init : σ)
    (i : Nat → ι) (g : Nat → σ)
    (h0 : g 0 = init)
    (hs : ∀ t, g (t + 1) = step (g t) (i t)) :
    ∀ t, g t = mealyRec step init i t := by
  intro t
  induction t with
  | zero => exact h0
  | succ t ih => rw [hs t, ih]; rfl

/-- Spec write-FSM state at cycle `t` under an input stream of
    (AWVALID, WVALID, BREADY). -/
def wrSpecTrace (i : Nat → Bool × Bool × Bool) : Nat → WrState
  | 0 => wrReset
  | t + 1 => wrStep (wrSpecTrace i t) (i t).1 (i t).2.1 (i t).2.2

/-- RTL write-FSM state at cycle `t` under the same input stream. -/
def wrRTLTrace (i : Nat → Bool × Bool × Bool) : Nat → BitVec 2
  | 0 => wrIdle
  | t + 1 => wrStepRTL (wrRTLTrace i t) (i t).1 (i t).2.1 (i t).2.2

/--
  **Cycle-accurate write-channel refinement**: for every input stream
  and every cycle, the RTL state is exactly the spec state.
-/
theorem wr_trace_refines (i : Nat → Bool × Bool × Bool) :
    ∀ t, decodeWr (wrRTLTrace i t) = wrSpecTrace i t := by
  intro t
  induction t with
  | zero => exact wrIdle_is_reset
  | succ t ih =>
    show decodeWr (wrStepRTL (wrRTLTrace i t) _ _ _) = _
    rw [← wrStepRTL_refines, ih]
    rfl

/-- Corollary: the implementation's BVALID matches the spec's BVALID at
    every cycle — combined with `bvalid_only_after_aw_and_w` (§A2.3.2.1)
    and `no_spurious_write_response` (§A2.6) in AXIProps, every safety
    theorem proven on the spec holds of the RTL trace. -/
theorem wr_bvalid_trace (i : Nat → Bool × Bool × Bool) (t : Nat) :
    bValidRTL (wrRTLTrace i t) = (wrSpecTrace i t).bValid := by
  rw [← wr_trace_refines]
  exact (wrOutputs_refine (wrRTLTrace i t)).2.2

/-- Corollary: AWREADY and WREADY match the spec at every cycle. -/
theorem wr_ready_trace (i : Nat → Bool × Bool × Bool) (t : Nat) :
    awReadyRTL (wrRTLTrace i t) = awReady (wrSpecTrace i t) ∧
    wReadyRTL (wrRTLTrace i t) = wReady (wrSpecTrace i t) := by
  rw [← wr_trace_refines]
  exact ⟨(wrOutputs_refine _).1, (wrOutputs_refine _).2.1⟩

/-- Spec read-FSM state at cycle `t` under an input stream of
    (ARVALID, RREADY). -/
def rdSpecTrace (i : Nat → Bool × Bool) : Nat → RdState
  | 0 => rdReset
  | t + 1 => rdStep (rdSpecTrace i t) (i t).1 (i t).2

/-- RTL read-FSM state at cycle `t` under the same input stream. -/
def rdRTLTrace (i : Nat → Bool × Bool) : Nat → BitVec 1
  | 0 => rdIdle
  | t + 1 => rdStepRTL (rdRTLTrace i t) (i t).1 (i t).2

/-- **Cycle-accurate read-channel refinement**. -/
theorem rd_trace_refines (i : Nat → Bool × Bool) :
    ∀ t, decodeRd (rdRTLTrace i t) = rdSpecTrace i t := by
  intro t
  induction t with
  | zero => exact rdIdle_is_reset
  | succ t ih =>
    show decodeRd (rdStepRTL (rdRTLTrace i t) _ _) = _
    rw [← rdStepRTL_refines, ih]
    rfl

/-- Corollary: RVALID and ARREADY match the spec at every cycle. -/
theorem rd_outputs_trace (i : Nat → Bool × Bool) (t : Nat) :
    rValidRTL (rdRTLTrace i t) = (rdSpecTrace i t).rValid ∧
    arReadyRTL (rdRTLTrace i t) = arReady (rdSpecTrace i t) := by
  rw [← rd_trace_refines]
  exact ⟨(rdOutputs_refine _).2, (rdOutputs_refine _).1⟩

/-!
## Inherited spec properties

Because the traces coincide, the spec-cited safety theorems of AXIProps
transfer to the RTL FSM. Two examples are stated explicitly:
-/

/-- §A2.3.2.1 on the RTL FSM: BVALID is asserted only in states where
    both the AW and last-W handshakes have occurred. -/
theorem rtl_bvalid_only_after_aw_and_w (i : Nat → Bool × Bool × Bool) (t : Nat)
    (h : bValidRTL (wrRTLTrace i t) = true) :
    (wrSpecTrace i t).awDone = true ∧ (wrSpecTrace i t).wDone = true := by
  have hinv : WrInv (wrSpecTrace i t) := by
    rw [← wr_trace_refines]
    exact decodeWr_inv _
  apply hinv
  rw [← wr_bvalid_trace]
  exact h

/-- §A2.3.2.2 on the RTL FSM: RVALID is asserted only after the AR
    handshake. -/
theorem rtl_rvalid_only_after_ar (i : Nat → Bool × Bool) (t : Nat)
    (h : rValidRTL (rdRTLTrace i t) = true) :
    (rdSpecTrace i t).arDone = true := by
  have hinv : RdInv (rdSpecTrace i t) := by
    rw [← rd_trace_refines]
    exact decodeRd_inv _
  apply hinv
  rw [← (rd_outputs_trace i t).1]
  exact h

end Sparkle.Verification.AXIRefinement
