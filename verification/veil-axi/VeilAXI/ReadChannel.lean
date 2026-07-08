/-
  AMBA AXI Read Channels (AR/R) — Veil Transition System

  Event-level model of one AXI5-Lite read transaction, mirroring the
  synchronous FSM `Sparkle.Verification.AXIProps.RdState`/`rdStep`
  (rules from ARM IHI 0022 Issue L §A2.3.2.2; see docs/AXI_Spec_Map.md).

  State (one outstanding transaction, §B2.1.5 burst length 1):
    arDone — the AR (read request) handshake has occurred
    rValid — RVALID is asserted (read data presented; single transfer,
             so this is also the last transfer)
-/

import Veil

veil module AXIReadChannel

individual arDone : Prop
individual rValid : Prop

#gen_state

after_init {
  arDone := False;
  rValid := False
}

/- AR handshake: ARVALID ∧ ARREADY, with ARREADY = ¬arDone ∧ ¬rValid
   (one outstanding request). -/
action ar_handshake = {
  require ¬arDone;
  require ¬rValid;
  arDone := True
}

/- RVALID assertion. §A2.3.2.2: "The Subordinate must wait for both
   ARVALID and ARREADY to be asserted before it asserts RVALID to
   indicate that valid data is available" — hence the guard. The spec
   also forbids waiting for RREADY, hence no RREADY guard. -/
action assert_rvalid = {
  require arDone;
  require ¬rValid;
  rValid := True
}

/- R handshake: RVALID ∧ RREADY delivers the (single, last) read data
   transfer and completes the transaction (§A2.3, §B2.1.5). -/
action r_handshake = {
  require rValid;
  arDone := False;
  rValid := False
}

/- §A2.3.2.2 / §A2.6 safety: read data is presented only after the read
   request handshake — the Veil counterpart of `AXIProps.RdInv` and the
   theorem `rvalid_only_after_ar`. -/
safety [rvalid_only_after_ar] rValid → arDone

#gen_spec

#check_invariants

/- Non-vacuity: an initial state exists. -/
sat trace [initial_state] { } by { bmc_sat }

/- Deadlock-freedom evidence: a complete read transaction is executable
   (cf. `AXIProps.read_completes_in_two_cycles`). -/
sat trace [read_transaction_completes] {
  ar_handshake
  assert_rvalid
  assert (rValid ∧ arDone)
  r_handshake
  assert (¬rValid ∧ ¬arDone)
} by { bmc_sat }

/- BMC cross-check of the safety property: no reachable violation
   within any 6 protocol events. -/
unsat trace [no_rvalid_violation] {
  any 6 actions
  assert ¬(rValid → arDone)
} by { bmc }

end AXIReadChannel
