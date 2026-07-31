/-
  AMBA AXI Write Channels (AW/W/B) — Veil Transition System

  Event-level model of one AXI5-Lite write transaction, mirroring the
  synchronous FSM `Sparkle.Verification.AXIProps.WrState`/`wrStep`
  (rules extracted from the AMBA AXI Protocol Specification,
  ARM IHI 0022 Issue L; see docs/AXI_Spec_Map.md in the repo root).

  Model relationship: `AXIProps.wrStep` is one *clock cycle*, which
  composes up to three of the atomic protocol events below (accept AW,
  accept last W, assert/complete B). Any property preserved by every
  atomic event is preserved by their composition, so invariants checked
  here cover every synchronous schedule of the events — an independent,
  SMT-checked (z3/cvc5 via Veil) confirmation of the invariant proven
  interactively in AXIProps (`bvalid_only_after_aw_and_w`).

  State (one outstanding transaction, IHI 0022L §B2.1.5 burst length 1):
    awDone — the AW (write request) handshake has occurred
    wDone  — the last W (write data) handshake has occurred
    bValid — BVALID is asserted (response presented)
-/

import Veil

veil module AXIWriteChannel

individual awDone : Prop
individual wDone : Prop
individual bValid : Prop

#gen_state

/- Reset (IHI 0022L §A2.3: "VALID signals must be LOW during reset";
   nothing accepted yet). -/
after_init {
  awDone := False;
  wDone := False;
  bValid := False
}

/- AW handshake: AWVALID ∧ AWREADY. The subordinate's AWREADY is
   ¬awDone ∧ ¬bValid (accept one request per transaction; §A2.3 R8
   READY-default-HIGH is modeled by the absence of further guards). -/
action aw_handshake = {
  require ¬awDone;
  require ¬bValid;
  awDone := True
}

/- W handshake: WVALID ∧ WREADY, single (last) data transfer
   (§B2.1.5: burst length 1). May occur before the AW handshake —
   §A2.6: "write data can appear at an interface before the write
   request for the transaction". -/
action w_handshake = {
  require ¬wDone;
  require ¬bValid;
  wDone := True
}

/- BVALID assertion. §A2.3.2.1: "The Subordinate must wait for AWVALID,
   AWREADY, WVALID, and WREADY to be asserted before asserting BVALID"
   and "must wait for the last write data transfer before asserting
   BVALID" — hence the two `require` guards. §A2.3.2.1 also forbids
   waiting for BREADY, hence no BREADY guard here. -/
action assert_bvalid = {
  require awDone;
  require wDone;
  require ¬bValid;
  bValid := True
}

/- B handshake: BVALID ∧ BREADY completes the transaction (§A2.3);
   the subordinate returns to idle for the next transaction. -/
action b_handshake = {
  require bValid;
  awDone := False;
  wDone := False;
  bValid := False
}

/- §A2.3.2.1 / §A2.6 safety: a write response is presented only after
   both the write request and the (last) write data have been accepted.
   This is the Veil counterpart of `AXIProps.WrInv` and the theorem
   `bvalid_only_after_aw_and_w`. -/
safety [bvalid_only_after_aw_and_w] bValid → (awDone ∧ wDone)

#gen_spec

#check_invariants

/- Non-vacuity (bounded model checking): an initial state exists. -/
sat trace [initial_state] { } by { bmc_sat }

/- Deadlock-freedom evidence: a complete write transaction — request,
   data, response, completion — is executable (cf. the exact 2-cycle
   bound proven in `AXIProps.write_completes_in_two_cycles`). -/
sat trace [write_transaction_completes] {
  aw_handshake
  w_handshake
  assert_bvalid
  assert (bValid ∧ awDone ∧ wDone)
  b_handshake
  assert (¬bValid ∧ ¬awDone ∧ ¬wDone)
} by { bmc_sat }

/- §A2.6 data-before-request ordering is admitted (see w_handshake). -/
sat trace [data_before_request] {
  w_handshake
  aw_handshake
  assert_bvalid
  assert bValid
} by { bmc_sat }

/- BMC cross-check of the safety property: no reachable violation
   within any 6 protocol events. -/
unsat trace [no_bvalid_violation] {
  any 6 actions
  assert ¬(bValid → (awDone ∧ wDone))
} by { bmc }

end AXIWriteChannel
