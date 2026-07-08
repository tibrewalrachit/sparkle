/-
  AMBA AXI Formal Properties

  Machine-checked verification of the normative rules of the AMBA AXI
  protocol, extracted from the official specification:

    AMBA AXI Protocol Specification, ARM IHI 0022, Issue L (27 Aug 2025)

  Every theorem cites the spec section it verifies. The extraction map with
  verbatim rule text and page numbers is in docs/AXI_Spec_Map.md.

  Scope: the AXI5-Lite interface class (§B2.1.5) — all transactions have
  burst length 1, no exclusive accesses — over the Valid-Ready transport
  (§A2.3).

  Contents:
    Part 1 — Channel transmitter (VALID/READY handshake, §A2.3)
    Part 2 — Write transaction dependencies (AW/W/B channels, §A2.3.2.1, §A2.6)
    Part 3 — Read transaction dependencies (AR/R channels, §A2.3.2.2, §A2.6)
    Part 4 — Response encodings (BRESP/RRESP, §A3.3 Tables A3.28 & A3.31)
    Part 5 — Data correctness of a Lite subordinate (memory refinement)
    Part 6 — 4KB boundary rule (§A3.1)

  Pattern follows ArbiterProps.lean: self-contained definitions + proofs,
  no cross-library dependencies.
-/

namespace Sparkle.Verification.AXIProps

/-!
## Part 1 — Channel transmitter (§A2.3 Valid-Ready transport)

Every AXI channel uses the same handshake process (§A2.3), so one
transmitter model verifies the manager side of AW/W/AR and the
subordinate side of B/R alike.

The transmitter holds a `valid` flag and the information (`payload`)
currently presented on the channel. Each clock edge it observes the
receiver's READY and an `offer` from its upstream logic (the next item it
wants to send, if any).
-/

structure TxState (α : Type) where
  valid   : Bool
  payload : α
  deriving Repr, DecidableEq

/-- Reset state. §A2.3: "VALID signals must be LOW during reset." -/
def txReset {α : Type} (dflt : α) : TxState α := ⟨false, dflt⟩

/--
  One clock edge of a protocol-compliant transmitter.

  * If VALID is asserted and READY is not, the transfer has not occurred:
    the transmitter holds VALID and keeps the payload stable (§A2.3).
  * Otherwise the channel is free (either idle, or the handshake completed
    at this edge) and the transmitter presents the next offer, if any.
-/
def txStep {α : Type} (s : TxState α) (ready : Bool) (offer : Option α) : TxState α :=
  if s.valid && !ready then
    s
  else
    match offer with
    | some p => ⟨true, p⟩
    | none   => ⟨false, s.payload⟩

/-- §A2.3 R1: "Transfer occurs only when both the VALID and READY signals
    are HIGH." -/
def transfer {α : Type} (s : TxState α) (ready : Bool) : Bool :=
  s.valid && ready

/-!
### Safety Properties (§A2.3)
-/

/--
  §A2.3: "VALID signals must be LOW during reset."
  (Also §A2.1.2: signals required LOW in reset stay LOW until after
  ARESETn deassertion — the reset state itself drives VALID LOW.)
-/
theorem valid_low_during_reset {α : Type} (dflt : α) :
    (txReset dflt).valid = false := rfl

/--
  §A2.3: "When VALID is asserted, it must remain asserted until the
  handshake occurs, at a rising clock edge when VALID and READY are both
  asserted."

  If the receiver is not ready, a valid transmitter stays valid — no
  matter what the upstream logic offers.
-/
theorem valid_stable_until_handshake {α : Type} (s : TxState α) (offer : Option α)
    (h : s.valid = true) :
    (txStep s false offer).valid = true := by
  simp [txStep, h]

/--
  §A2.3: "The transmitter must keep its information stable until the
  transfer occurs."
-/
theorem payload_stable_until_handshake {α : Type} (s : TxState α) (offer : Option α)
    (h : s.valid = true) :
    (txStep s false offer).payload = s.payload := by
  simp [txStep, h]

/--
  §A2.3: "A transmitter is not permitted to wait until READY is asserted
  before asserting VALID."

  Formally: from an idle channel, whether the transmitter asserts VALID
  next cycle is independent of the receiver's READY. (The same holds for
  the payload it presents.)
-/
theorem no_wait_for_ready {α : Type} (s : TxState α) (offer : Option α)
    (r₁ r₂ : Bool) (h : s.valid = false) :
    txStep s r₁ offer = txStep s r₂ offer := by
  cases offer <;> simp [txStep, h]

/--
  §A2.3 R1: no transfer occurs while VALID is deasserted, regardless of
  READY.
-/
theorem no_transfer_without_valid {α : Type} (s : TxState α) (ready : Bool)
    (h : s.valid = false) :
    transfer s ready = false := by
  simp [transfer, h]

/--
  §A2.3 R1: when the handshake completes (VALID ∧ READY), the channel is
  released — the transmitter may immediately present new information or go
  idle. The prior payload no longer constrains it.
-/
theorem handshake_transfers {α : Type} (s : TxState α) (p : α)
    (h : s.valid = true) :
    transfer s true = true ∧ txStep s true (some p) = ⟨true, p⟩ := by
  constructor
  · simp [transfer, h]
  · simp [txStep]

/-!
## Part 2 — Write transaction dependencies (§A2.3.2.1, §A2.6)

Subordinate-side FSM for one write transaction on the AW/W/B channels.
AXI5-Lite (§B2.1.5): burst length 1, so the single W transfer is the last
(`WLAST` behavior of §A3.2.1 is implicit).

The model exercises the spec's *permissions* — AWREADY/WREADY default
HIGH (§A2.3: "For request channels, it is recommended to use HIGH as the
default state") — and is proven to satisfy the spec's *requirements*.
-/

structure WrState where
  /-- The AW (write request) handshake for this transaction has occurred. -/
  awDone : Bool
  /-- The (last) W (write data) handshake for this transaction has occurred. -/
  wDone  : Bool
  /-- BVALID: a write response is being presented. -/
  bValid : Bool
  deriving Repr, DecidableEq

def wrReset : WrState := ⟨false, false, false⟩

/-- AWREADY: accept a write request unless one was already accepted or a
    response is still outstanding. -/
def awReady (s : WrState) : Bool := !s.awDone && !s.bValid

/-- WREADY: accept write data unless already accepted or responding. -/
def wReady (s : WrState) : Bool := !s.wDone && !s.bValid

/--
  One clock edge of the write-side subordinate.
  Inputs are the Manager-driven signals AWVALID, WVALID, BREADY.
-/
def wrStep (s : WrState) (awValid wValid bReady : Bool) : WrState :=
  if s.bValid && bReady then
    -- B handshake completes the transaction; return to reset state.
    wrReset
  else
    let awDone' := s.awDone || (awValid && awReady s)
    let wDone'  := s.wDone  || (wValid  && wReady  s)
    ⟨awDone', wDone', s.bValid || (awDone' && wDone')⟩

/-!
### Safety Properties (§A2.3.2.1)
-/

/-- Invariant: BVALID implies both the AW and the last-W handshakes have
    occurred. -/
def WrInv (s : WrState) : Prop :=
  s.bValid = true → (s.awDone = true ∧ s.wDone = true)

theorem wrReset_inv : WrInv wrReset := by
  simp [WrInv, wrReset]

/--
  §A2.3.2.1: "The Subordinate must wait for AWVALID, AWREADY, WVALID, and
  WREADY to be asserted before asserting BVALID" and "The Subordinate must
  wait for the last write data transfer before asserting BVALID."

  Inductive invariant: in every reachable state, BVALID is asserted only
  after both the write request handshake and the (last) write data
  handshake have occurred.
-/
theorem bvalid_only_after_aw_and_w (s : WrState) (awValid wValid bReady : Bool)
    (h : WrInv s) : WrInv (wrStep s awValid wValid bReady) := by
  obtain ⟨aw, w, b⟩ := s
  cases aw <;> cases w <;> cases b <;>
    cases awValid <;> cases wValid <;> cases bReady <;>
    simp_all [WrInv, wrStep, wrReset, awReady, wReady]

/--
  §A2.3.2.1: "The Subordinate must not wait for the Manager to assert
  BREADY before asserting BVALID."

  Formally: while no response is pending, the subordinate's decision to
  assert BVALID is independent of BREADY.
-/
theorem bvalid_no_bready_wait (s : WrState) (awValid wValid br br' : Bool)
    (h : s.bValid = false) :
    (wrStep s awValid wValid br).bValid = (wrStep s awValid wValid br').bValid := by
  simp [wrStep, h]

/--
  §A2.3 (applied to the B channel): once BVALID is asserted it remains
  asserted — with the whole state held stable — until the B handshake.
-/
theorem bvalid_stable_until_bready (s : WrState) (awValid wValid : Bool)
    (h : s.bValid = true) :
    wrStep s awValid wValid false = s := by
  obtain ⟨aw, w, b⟩ := s
  cases aw <;> cases w <;> simp_all [wrStep, awReady, wReady]

/--
  §A2.3 R8: "For request channels, it is recommended to use HIGH as the
  default state to minimize latency. In that case, the Subordinate must be
  able to accept any valid request that is presented to it."

  The subordinate accepts a request and data from reset (work-conserving).
-/
theorem subordinate_accepts_from_reset :
    awReady wrReset = true ∧ wReady wrReset = true := by
  constructor <;> rfl

/-!
### Trace-level Safety (§A2.6)

These theorems quantify over *every* input trace — arbitrary sequences of
AWVALID/WVALID/BREADY values, including those a non-compliant Manager
might drive — and show the subordinate never emits a spurious response.
-/

/-- Count of B handshakes (write responses issued) along an input trace.
    Trace entries are (AWVALID, WVALID, BREADY). -/
def countB : WrState → List (Bool × Bool × Bool) → Nat
  | _, [] => 0
  | s, (av, wv, br) :: rest =>
    (if s.bValid && br then 1 else 0) + countB (wrStep s av wv br) rest

/-- Count of AW handshakes (write requests accepted) along an input trace. -/
def countAW : WrState → List (Bool × Bool × Bool) → Nat
  | _, [] => 0
  | s, (av, wv, br) :: rest =>
    (if av && awReady s then 1 else 0) + countAW (wrStep s av wv br) rest

/-- Count of W handshakes (write data accepted) along an input trace. -/
def countW : WrState → List (Bool × Bool × Bool) → Nat
  | _, [] => 0
  | s, (av, wv, br) :: rest =>
    (if wv && wReady s then 1 else 0) + countW (wrStep s av wv br) rest

/-- Step lemma: a B handshake consumes an outstanding AW handshake. -/
private theorem countB_step_aw (s : WrState) (av wv br : Bool) (h : WrInv s) :
    (if s.bValid && br then 1 else 0)
      + (if (wrStep s av wv br).awDone then 1 else 0)
    ≤ (if av && awReady s then 1 else 0)
      + (if s.awDone then 1 else 0) := by
  obtain ⟨aw, w, b⟩ := s
  cases aw <;> cases w <;> cases b <;> cases av <;> cases wv <;> cases br <;>
    simp_all [WrInv, wrStep, wrReset, awReady, wReady]

/-- Step lemma: a B handshake consumes an outstanding W handshake. -/
private theorem countB_step_w (s : WrState) (av wv br : Bool) (h : WrInv s) :
    (if s.bValid && br then 1 else 0)
      + (if (wrStep s av wv br).wDone then 1 else 0)
    ≤ (if wv && wReady s then 1 else 0)
      + (if s.wDone then 1 else 0) := by
  obtain ⟨aw, w, b⟩ := s
  cases aw <;> cases w <;> cases b <;> cases av <;> cases wv <;> cases br <;>
    simp_all [WrInv, wrStep, wrReset, awReady, wReady]

/--
  §A2.6 T1 (request side): "A write response must always follow the last
  write transfer in a write transaction" — in particular, every write
  response corresponds to an accepted write request.

  Along **every** input trace, the number of B handshakes issued never
  exceeds the number of AW handshakes accepted (plus one for a request
  already outstanding in the start state).
-/
theorem no_spurious_write_response (tr : List (Bool × Bool × Bool)) :
    ∀ s : WrState, WrInv s →
      countB s tr ≤ countAW s tr + (if s.awDone then 1 else 0) := by
  induction tr with
  | nil => intro s _; simp [countB, countAW]
  | cons i rest ih =>
    intro s hInv
    obtain ⟨av, wv, br⟩ := i
    have hkey := countB_step_aw s av wv br hInv
    have hih := ih (wrStep s av wv br)
      (bvalid_only_after_aw_and_w s av wv br hInv)
    simp only [countB, countAW]
    omega

/--
  §A2.6 T1 (data side): every write response follows an accepted (last)
  write data transfer: #B ≤ #W along every input trace.
-/
theorem write_response_after_data (tr : List (Bool × Bool × Bool)) :
    ∀ s : WrState, WrInv s →
      countB s tr ≤ countW s tr + (if s.wDone then 1 else 0) := by
  induction tr with
  | nil => intro s _; simp [countB, countW]
  | cons i rest ih =>
    intro s hInv
    obtain ⟨av, wv, br⟩ := i
    have hkey := countB_step_w s av wv br hInv
    have hih := ih (wrStep s av wv br)
      (bvalid_only_after_aw_and_w s av wv br hInv)
    simp only [countB, countW]
    omega

/--
  From reset the bounds specialize to: never more responses than requests,
  never more responses than data transfers.
-/
theorem no_spurious_write_response_from_reset (tr : List (Bool × Bool × Bool)) :
    countB wrReset tr ≤ countAW wrReset tr ∧
    countB wrReset tr ≤ countW wrReset tr := by
  refine ⟨?_, ?_⟩
  · have h := no_spurious_write_response tr wrReset wrReset_inv
    simpa [wrReset] using h
  · have h := write_response_after_data tr wrReset wrReset_inv
    simpa [wrReset] using h

/-!
### Liveness / Bounded Latency (framework §2–3)

§A2.6 permits a Subordinate to "wait for one transaction to complete
before accepting another request" — this model does not even do that: a
cooperative Manager (all VALIDs and BREADY held HIGH) completes a full
write transaction every 2 cycles, forever. Deadlock-freedom with an
exact bound.
-/

/-- With AWVALID, WVALID, BREADY all held HIGH, a write transaction
    started from reset presents its response after 1 cycle and completes
    (B handshake, state back to reset) after 2. -/
theorem write_completes_in_two_cycles :
    (wrStep wrReset true true true).bValid = true ∧
    wrStep (wrStep wrReset true true true) true true true = wrReset := by
  constructor <;> rfl

/-!
## Part 3 — Read transaction dependencies (§A2.3.2.2, §A2.6)

Subordinate-side FSM for one read transaction on the AR/R channels.
AXI5-Lite: burst length 1, so the single R transfer is the last
(`RLAST` behavior of §A3.2.2 is implicit).
-/

structure RdState where
  /-- The AR (read request) handshake for this transaction has occurred. -/
  arDone : Bool
  /-- RVALID: read data is being presented. -/
  rValid : Bool
  deriving Repr, DecidableEq

def rdReset : RdState := ⟨false, false⟩

/-- ARREADY: accept a read request unless one is already in flight. -/
def arReady (s : RdState) : Bool := !s.arDone && !s.rValid

/--
  One clock edge of the read-side subordinate.
  Inputs are the Manager-driven signals ARVALID and RREADY.
-/
def rdStep (s : RdState) (arValid rReady : Bool) : RdState :=
  if s.rValid && rReady then
    -- R handshake completes the transaction (single transfer: RLAST).
    rdReset
  else
    let arDone' := s.arDone || (arValid && arReady s)
    ⟨arDone', s.rValid || arDone'⟩

/-!
### Safety Properties (§A2.3.2.2)
-/

/-- Invariant: RVALID implies the AR handshake has occurred. -/
def RdInv (s : RdState) : Prop := s.rValid = true → s.arDone = true

theorem rdReset_inv : RdInv rdReset := by
  simp [RdInv, rdReset]

/--
  §A2.3.2.2: "The Subordinate must wait for both ARVALID and ARREADY to be
  asserted before it asserts RVALID to indicate that valid data is
  available."

  Inductive invariant: RVALID only in states where the read request
  handshake has occurred.
-/
theorem rvalid_only_after_ar (s : RdState) (arValid rReady : Bool)
    (h : RdInv s) : RdInv (rdStep s arValid rReady) := by
  obtain ⟨ar, r⟩ := s
  cases ar <;> cases r <;> cases arValid <;> cases rReady <;>
    simp_all [RdInv, rdStep, rdReset, arReady]

/--
  §A2.3.2.2: "The Subordinate must not wait for the Manager to assert
  RREADY before asserting RVALID."
-/
theorem rvalid_no_rready_wait (s : RdState) (arValid rr rr' : Bool)
    (h : s.rValid = false) :
    (rdStep s arValid rr).rValid = (rdStep s arValid rr').rValid := by
  simp [rdStep, h]

/--
  §A2.3 (applied to the R channel): once RVALID is asserted it remains
  asserted — with the state held stable — until the R handshake.
-/
theorem rvalid_stable_until_rready (s : RdState) (arValid : Bool)
    (h : s.rValid = true) :
    rdStep s arValid false = s := by
  obtain ⟨ar, r⟩ := s
  cases ar <;> simp_all [rdStep, arReady]

/-- §A2.3 R8: ARREADY defaults HIGH — a request is accepted from reset. -/
theorem arready_high_after_reset : arReady rdReset = true := rfl

/-!
### Trace-level Safety (§A2.6)
-/

/-- Count of R handshakes (read data returned) along an input trace.
    Trace entries are (ARVALID, RREADY). -/
def countR : RdState → List (Bool × Bool) → Nat
  | _, [] => 0
  | s, (av, rr) :: rest =>
    (if s.rValid && rr then 1 else 0) + countR (rdStep s av rr) rest

/-- Count of AR handshakes (read requests accepted) along an input trace. -/
def countAR : RdState → List (Bool × Bool) → Nat
  | _, [] => 0
  | s, (av, rr) :: rest =>
    (if av && arReady s then 1 else 0) + countAR (rdStep s av rr) rest

/-- Step lemma: an R handshake consumes an outstanding AR handshake. -/
private theorem countR_step_ar (s : RdState) (av rr : Bool) (h : RdInv s) :
    (if s.rValid && rr then 1 else 0)
      + (if (rdStep s av rr).arDone then 1 else 0)
    ≤ (if av && arReady s then 1 else 0)
      + (if s.arDone then 1 else 0) := by
  obtain ⟨ar, r⟩ := s
  cases ar <;> cases r <;> cases av <;> cases rr <;>
    simp_all [RdInv, rdStep, rdReset, arReady]

/--
  §A2.6 T2: "Read data and responses must always follow the read request."

  Along **every** input trace, the number of R handshakes never exceeds
  the number of AR handshakes accepted (plus one for a request already
  outstanding in the start state).
-/
theorem no_spurious_read_data (tr : List (Bool × Bool)) :
    ∀ s : RdState, RdInv s →
      countR s tr ≤ countAR s tr + (if s.arDone then 1 else 0) := by
  induction tr with
  | nil => intro s _; simp [countR, countAR]
  | cons i rest ih =>
    intro s hInv
    obtain ⟨av, rr⟩ := i
    have hkey := countR_step_ar s av rr hInv
    have hih := ih (rdStep s av rr) (rvalid_only_after_ar s av rr hInv)
    simp only [countR, countAR]
    omega

/-- From reset: never more read data beats than accepted read requests. -/
theorem no_spurious_read_data_from_reset (tr : List (Bool × Bool)) :
    countR rdReset tr ≤ countAR rdReset tr := by
  have h := no_spurious_read_data tr rdReset rdReset_inv
  simpa [rdReset] using h

/-- With ARVALID and RREADY held HIGH, a read transaction started from
    reset presents data after 1 cycle and completes after 2. -/
theorem read_completes_in_two_cycles :
    (rdStep rdReset true true).rValid = true ∧
    rdStep (rdStep rdReset true true) true true = rdReset := by
  constructor <;> rfl

/-!
## Part 4 — Response encodings (§A3.3)

Round-trip proofs that the encode/decode functions realize Tables A3.28
(BRESP) and A3.31 (RRESP) losslessly, plus the AXI5-Lite restriction that
EXOKAY is never produced (§B2.1.5: "Exclusive accesses are not
supported"; Table A3.28/A3.31: EXOKAY "is only permitted for an
exclusive" access).
-/

/-- Write response codes, Table A3.28 (3-bit BRESP, BRESP_WIDTH = 3). -/
inductive BResp where
  | okay | exokay | slverr | decerr
  | defer | transfault | reserved | unsupported
  deriving Repr, DecidableEq, BEq, Inhabited

/-- Table A3.28 BRESP encodings. -/
def BResp.encode : BResp → BitVec 3
  | .okay        => 0b000#3
  | .exokay      => 0b001#3
  | .slverr      => 0b010#3
  | .decerr      => 0b011#3
  | .defer       => 0b100#3
  | .transfault  => 0b101#3
  | .reserved    => 0b110#3
  | .unsupported => 0b111#3

def BResp.decode (v : BitVec 3) : BResp :=
  if v = 0b000#3 then .okay
  else if v = 0b001#3 then .exokay
  else if v = 0b010#3 then .slverr
  else if v = 0b011#3 then .decerr
  else if v = 0b100#3 then .defer
  else if v = 0b101#3 then .transfault
  else if v = 0b110#3 then .reserved
  else .unsupported

/-- Table A3.28: the encoding is lossless (decode ∘ encode = id). -/
theorem BResp.decode_encode (r : BResp) : BResp.decode (BResp.encode r) = r := by
  cases r <;> decide

/-- Table A3.28: every 3-bit value decodes to a unique response
    (encode ∘ decode = id) — the table is exhaustive. -/
theorem BResp.encode_decode : ∀ v : BitVec 3, BResp.encode (BResp.decode v) = v := by
  decide

/-- §A3.3.1: BRESP default is 0b000 (OKAY). -/
theorem bresp_okay_is_zero : BResp.encode .okay = 0#3 := rfl

/-- Read response codes, Table A3.31 (3-bit RRESP, RRESP_WIDTH = 3). -/
inductive RResp where
  | okay | exokay | slverr | decerr
  | prefetched | transfault | okaydirty | reserved
  deriving Repr, DecidableEq, BEq, Inhabited

/-- Table A3.31 RRESP encodings. -/
def RResp.encode : RResp → BitVec 3
  | .okay       => 0b000#3
  | .exokay     => 0b001#3
  | .slverr     => 0b010#3
  | .decerr     => 0b011#3
  | .prefetched => 0b100#3
  | .transfault => 0b101#3
  | .okaydirty  => 0b110#3
  | .reserved   => 0b111#3

def RResp.decode (v : BitVec 3) : RResp :=
  if v = 0b000#3 then .okay
  else if v = 0b001#3 then .exokay
  else if v = 0b010#3 then .slverr
  else if v = 0b011#3 then .decerr
  else if v = 0b100#3 then .prefetched
  else if v = 0b101#3 then .transfault
  else if v = 0b110#3 then .okaydirty
  else .reserved

/-- Table A3.31: the encoding is lossless. -/
theorem RResp.decode_encode (r : RResp) : RResp.decode (RResp.encode r) = r := by
  cases r <;> decide

/-- Table A3.31: every 3-bit value decodes uniquely — the table is
    exhaustive. -/
theorem RResp.encode_decode : ∀ v : BitVec 3, RResp.encode (RResp.decode v) = v := by
  decide

/-- §A3.3.2: RRESP default is 0b000 (OKAY). -/
theorem rresp_okay_is_zero : RResp.encode .okay = 0#3 := rfl

/-!
### AXI5-Lite response restriction (§B2.1.5)
-/

/-- Outcomes a Lite subordinate can experience when servicing an access. -/
inductive LiteOutcome where
  /-- Access completed successfully. -/
  | success
  /-- Reached the subordinate but failed there (Table A3.28 SLVERR:
      "a problem within a Subordinate such as trying to access a
      read-only or powered-down function"). -/
  | subordinateError
  /-- Address does not decode (Table A3.28 DECERR: "the address decodes
      to an invalid address"). -/
  | decodeError
  deriving Repr, DecidableEq

/-- Response mapping of an AXI5-Lite write subordinate. -/
def liteWriteResp : LiteOutcome → BResp
  | .success          => .okay
  | .subordinateError => .slverr
  | .decodeError      => .decerr

/-- Response mapping of an AXI5-Lite read subordinate. -/
def liteReadResp : LiteOutcome → RResp
  | .success          => .okay
  | .subordinateError => .slverr
  | .decodeError      => .decerr

/--
  §B2.1.5: "Exclusive accesses are not supported" + Table A3.28: EXOKAY
  "is only permitted for an exclusive write." A Lite subordinate never
  responds EXOKAY on the write channel.
-/
theorem lite_write_never_exokay (o : LiteOutcome) :
    liteWriteResp o ≠ .exokay := by
  cases o <;> simp [liteWriteResp]

/--
  §B2.1.5 + Table A3.31: EXOKAY "is only permitted for an exclusive
  read." A Lite subordinate never responds EXOKAY on the read channel.
-/
theorem lite_read_never_exokay (o : LiteOutcome) :
    liteReadResp o ≠ .exokay := by
  cases o <;> simp [liteReadResp]

/-!
## Part 5 — Data correctness of a Lite subordinate (memory refinement)

Combines the Part 2/3 channel FSMs with a memory. Verifies the *meaning*
of an OKAY response:

  * Table A3.28 OKAY: "If the transaction includes write data, the
    updated value is observable."
  * Table A3.31 OKAY: "Transaction has completed successfully, read data
    is valid."

Memory is modeled as a total function from address to data (a register
block, per §B2.1.5: "communication with register-based components").
-/

structure LiteSubState (a d : Nat) where
  wr     : WrState
  /-- Write address, latched at the AW handshake. -/
  awAddr : BitVec a
  /-- Write data, latched at the W handshake. -/
  wData  : BitVec d
  rd     : RdState
  /-- Read address, latched at the AR handshake. -/
  arAddr : BitVec a
  /-- Read data, latched when RVALID asserts. -/
  rData  : BitVec d
  /-- The register block. -/
  mem    : BitVec a → BitVec d

/-- Write `v` at address `x` (whole-word write; AXI5-Lite single
    transfer with all strobes set). -/
def memWrite {a d : Nat} (m : BitVec a → BitVec d) (x : BitVec a) (v : BitVec d) :
    BitVec a → BitVec d :=
  fun y => if y = x then v else m y

/--
  One clock edge of the full AXI5-Lite subordinate.

  * AW/W payloads are latched at their handshakes.
  * The write commits to memory at the edge where BVALID asserts (both
    handshakes done), so the response is only ever given for an updated
    location.
  * Read data is latched from memory at the edge where RVALID asserts;
    a same-cycle write commit to the same address is not observed
    (reads sample pre-commit memory — a legal ordering, since AXI
    imposes no ordering between the read and write channels, §A2.6).
-/
def liteStep {a d : Nat} (s : LiteSubState a d)
    (awValid : Bool) (awAddrIn : BitVec a)
    (wValid : Bool) (wDataIn : BitVec d)
    (bReady : Bool)
    (arValid : Bool) (arAddrIn : BitVec a)
    (rReady : Bool) : LiteSubState a d :=
  -- Channel FSMs
  let wr' := wrStep s.wr awValid wValid bReady
  let rd' := rdStep s.rd arValid rReady
  -- Latch request/data payloads at their handshakes
  let awAddr' := if awValid && awReady s.wr then awAddrIn else s.awAddr
  let wData'  := if wValid && wReady s.wr then wDataIn else s.wData
  let arAddr' := if arValid && arReady s.rd then arAddrIn else s.arAddr
  -- Commit the write when the response asserts
  let commit := !s.wr.bValid && wr'.bValid
  let mem' := if commit then memWrite s.mem awAddr' wData' else s.mem
  -- Capture read data when RVALID asserts (pre-commit memory)
  let rData' := if !s.rd.rValid && rd'.rValid then s.mem arAddr' else s.rData
  ⟨wr', awAddr', wData', rd', arAddr', rData', mem'⟩

/--
  Table A3.28 OKAY: "If the transaction includes write data, the updated
  value is observable."

  At the edge where the subordinate asserts BVALID, memory at the latched
  write address holds the latched write data.
-/
theorem write_commit_observable {a d : Nat} (s : LiteSubState a d)
    (awValid : Bool) (awAddrIn : BitVec a) (wValid : Bool) (wDataIn : BitVec d)
    (bReady arValid : Bool) (arAddrIn : BitVec a) (rReady : Bool)
    (hb : s.wr.bValid = false)
    (hb' : (liteStep s awValid awAddrIn wValid wDataIn bReady
              arValid arAddrIn rReady).wr.bValid = true) :
    (liteStep s awValid awAddrIn wValid wDataIn bReady
        arValid arAddrIn rReady).mem
      (liteStep s awValid awAddrIn wValid wDataIn bReady
        arValid arAddrIn rReady).awAddr
    = (liteStep s awValid awAddrIn wValid wDataIn bReady
        arValid arAddrIn rReady).wData := by
  simp_all [liteStep, memWrite]

/--
  Isolation: committing a write leaves every other address unchanged.
-/
theorem write_commit_other_addrs_unchanged {a d : Nat}
    (m : BitVec a → BitVec d) (x y : BitVec a) (v : BitVec d)
    (h : y ≠ x) : memWrite m x v y = m y := by
  simp [memWrite, h]

/--
  Table A3.31 OKAY: "read data is valid" — at the edge where the
  subordinate asserts RVALID, the presented read data is the memory
  content at the latched read address.
-/
theorem read_data_matches_memory {a d : Nat} (s : LiteSubState a d)
    (awValid : Bool) (awAddrIn : BitVec a) (wValid : Bool) (wDataIn : BitVec d)
    (bReady arValid : Bool) (arAddrIn : BitVec a) (rReady : Bool)
    (hr : s.rd.rValid = false)
    (hr' : (liteStep s awValid awAddrIn wValid wDataIn bReady
              arValid arAddrIn rReady).rd.rValid = true) :
    (liteStep s awValid awAddrIn wValid wDataIn bReady
        arValid arAddrIn rReady).rData
    = s.mem (liteStep s awValid awAddrIn wValid wDataIn bReady
        arValid arAddrIn rReady).arAddr := by
  simp_all [liteStep]

/-!
## Part 6 — 4KB boundary rule (§A3.1)

§A3.1: "A transaction must not cross a 4KB address boundary."

For a single-transfer transaction (AXI5-Lite, §B2.1.5) whose address is
aligned to its size, the transfer can never cross a 4KB boundary — so a
Lite manager issuing aligned accesses is compliant by construction.
-/

/--
  A size-aligned single transfer stays within one 4KB page:
  the byte range [addr % 4096, addr % 4096 + size) fits inside the page,
  for any transfer size that divides 4096 (all AxSIZE values 1..128 do,
  Table A3.2).
-/
theorem aligned_access_no_4KB_crossing (addr size : Nat)
    (hdvd : size ∣ 4096) (halign : size ∣ addr) :
    addr % 4096 + size ≤ 4096 := by
  have hmod : size ∣ addr % 4096 := (Nat.dvd_mod_iff hdvd).mpr halign
  obtain ⟨j, hj⟩ := hmod
  obtain ⟨m, hm⟩ := hdvd
  have hlt : addr % 4096 < 4096 := Nat.mod_lt addr (by omega)
  have hjm : j < m := by
    apply Nat.lt_of_mul_lt_mul_left (a := size)
    rw [← hj, ← hm]
    exact hlt
  have hle : size * (j + 1) ≤ size * m :=
    Nat.mul_le_mul (Nat.le_refl size) hjm
  calc addr % 4096 + size = size * j + size := by rw [hj]
    _ = size * (j + 1) := by rw [Nat.mul_succ]
    _ ≤ size * m := hle
    _ = 4096 := hm.symm

/-- Specialization: a 32-bit (4-byte) aligned Lite access never crosses a
    4KB boundary. -/
theorem lite32_no_4KB_crossing (addr : Nat) (halign : 4 ∣ addr) :
    addr % 4096 + 4 ≤ 4096 := by
  obtain ⟨k, hk⟩ := halign
  subst hk
  omega

end Sparkle.Verification.AXIProps
