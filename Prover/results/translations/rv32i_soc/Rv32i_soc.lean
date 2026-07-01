/-
  Auto-translated from behavioral SystemVerilog by sparkle_fv.translate (Verilator XML AST front end)
  Source     : benchmarks/soc/rv32i_soc/design.sv
  Top module : rv32i_soc
  Semantics  : clk is implicit in Signal semantics; the
               synchronous reset is folded into a mux on each
               register input. Semantic equivalence with the
               source is anchored by the shared Yosys
               elaboration used by the prover backend.
-/

import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

namespace SparkleFV.Rv32i_soc

-- TODO(unsupported): unsupported expression <funcref> at design.sv:874
-- TODO(unsupported): unsupported expression <funcref> at design.sv:875
-- TODO(unsupported): unsupported expression <funcref> at design.sv:876
-- TODO(unsupported): unsupported expression <funcref> at design.sv:877
-- TODO(unsupported): unsupported expression <funcref> at design.sv:878
-- TODO(unsupported): unsupported expression <funcref> at design.sv:879
-- TODO(unsupported): unsupported expression <funcref> at design.sv:880
-- TODO(unsupported): unsupported expression <funcref> at design.sv:882
-- TODO(unsupported): unsupported expression <funcref> at design.sv:883
-- TODO(unsupported): unsupported expression <funcref> at design.sv:884
-- TODO(unsupported): unsupported expression <funcref> at design.sv:885
-- TODO(unsupported): unsupported expression <funcref> at design.sv:886
-- TODO(unsupported): unsupported expression <funcref> at design.sv:887
-- TODO(unsupported): unsupported expression <funcref> at design.sv:888
-- TODO(unsupported): unsupported expression <funcref> at design.sv:890
-- TODO(unsupported): unsupported expression <funcref> at design.sv:891
-- TODO(unsupported): unsupported expression <funcref> at design.sv:893
-- TODO(unsupported): unsupported expression <funcref> at design.sv:894
-- TODO(unsupported): unsupported expression <funcref> at design.sv:896
-- TODO(unsupported): module instance alu_approx_inst at design.sv:283
-- TODO(unsupported): module instance amo_inst at design.sv:588
-- TODO(unsupported): module instance alu_full_inst at design.sv:608
-- TODO(unsupported): module instance mext_inst at design.sv:614
-- TODO(unsupported): module instance branch_inst at design.sv:621
-- TODO(unsupported): module instance imm_inst at design.sv:750
-- TODO(unsupported): module instance alu_ctrl_inst at design.sv:756

/-- Architectural state of `rv32i_soc` (one field per hardware register). -/
declare_signal_state Rv32i_socState
  | pcReg : BitVec 32 := 0#32
  | fetchPC : BitVec 32 := 0#32
  | flushDelay : Bool := false
  | ifid_inst : BitVec 32 := 19#32
  | ifid_pc : BitVec 32 := 0#32
  | ifid_pc4 : BitVec 32 := 0#32
  | idex_aluOp : BitVec 4 := 0#4
  | idex_regWrite : Bool := false
  | idex_memRead : Bool := false
  | idex_memWrite : Bool := false
  | idex_memToReg : Bool := false
  | idex_branch : Bool := false
  | idex_jump : Bool := false
  | idex_auipc : Bool := false
  | idex_aluSrcB : Bool := false
  | idex_isJalr : Bool := false
  | idex_isCsr : Bool := false
  | idex_isEcall : Bool := false
  | idex_isMret : Bool := false
  | idex_rs1Val : BitVec 32 := 0#32
  | idex_rs2Val : BitVec 32 := 0#32
  | idex_imm : BitVec 32 := 0#32
  | idex_rd : BitVec 5 := 0#5
  | idex_rs1Idx : BitVec 5 := 0#5
  | idex_rs2Idx : BitVec 5 := 0#5
  | idex_funct3 : BitVec 3 := 0#3
  | idex_pc : BitVec 32 := 0#32
  | idex_pc4 : BitVec 32 := 0#32
  | idex_csrAddr : BitVec 12 := 0#12
  | idex_csrFunct3 : BitVec 3 := 0#3
  | exwb_alu : BitVec 32 := 0#32
  | exwb_physAddr : BitVec 32 := 0#32
  | exwb_rd : BitVec 5 := 0#5
  | exwb_regW : Bool := false
  | exwb_m2r : Bool := false
  | exwb_pc4 : BitVec 32 := 0#32
  | exwb_jump : Bool := false
  | exwb_isCsr : Bool := false
  | exwb_csrRdata : BitVec 32 := 0#32
  | prev_wb_addr : BitVec 5 := 0#5
  | prev_wb_data : BitVec 32 := 0#32
  | prev_wb_en : Bool := false
  | prevStoreAddr : BitVec 32 := 0#32
  | prevStoreData : BitVec 32 := 0#32
  | prevStoreEn : Bool := false
  | msipReg : BitVec 32 := 0#32
  | mtimeLoReg : BitVec 32 := 0#32
  | mtimeHiReg : BitVec 32 := 0#32
  | mtimecmpLoReg : BitVec 32 := 4294967295#32
  | mtimecmpHiReg : BitVec 32 := 4294967295#32
  | mstatusReg : BitVec 32 := 0#32
  | mieReg : BitVec 32 := 0#32
  | mtvecReg : BitVec 32 := 0#32
  | mscratchReg : BitVec 32 := 0#32
  | mepcReg : BitVec 32 := 0#32
  | mcauseReg : BitVec 32 := 0#32
  | mtvalReg : BitVec 32 := 0#32
  | aiStatusReg : BitVec 32 := 0#32
  | aiInputReg : BitVec 32 := 0#32
  | exwb_funct3 : BitVec 3 := 0#3
  | idex_isMext : Bool := false
  | reservationValid : Bool := false
  | reservationAddr : BitVec 32 := 0#32
  | idex_isAMO : Bool := false
  | idex_amoOp : BitVec 5 := 0#5
  | exwb_isAMO : Bool := false
  | exwb_amoOp : BitVec 5 := 0#5
  | pendingWriteEn : Bool := false
  | pendingWriteAddr : BitVec 32 := 0#32
  | pendingWriteData : BitVec 32 := 0#32
  | cycle_count : BitVec 64 := 0#64
  | privMode : BitVec 2 := 3#2
  | sieReg : BitVec 32 := 0#32
  | stvecReg : BitVec 32 := 0#32
  | sscratchReg : BitVec 32 := 0#32
  | sepcReg : BitVec 32 := 0#32
  | scauseReg : BitVec 32 := 0#32
  | stvalReg : BitVec 32 := 0#32
  | satpReg : BitVec 32 := 0#32
  | medelegReg : BitVec 32 := 0#32
  | midelegReg : BitVec 32 := 0#32
  | mcounterenReg : BitVec 32 := 0#32
  | scounterenReg : BitVec 32 := 0#32
  | mmuState : BitVec 3 := 0#3
  | ptwState : BitVec 3 := 0#3
  | ptwVaddr : BitVec 32 := 0#32
  | ptwPte : BitVec 32 := 0#32
  | ptwMega : Bool := false
  | replPtr : BitVec 2 := 0#2
  | tlb0Valid : Bool := false
  | tlb0VPN : BitVec 20 := 0#20
  | tlb0PPN : BitVec 22 := 0#22
  | tlb0Flags : BitVec 8 := 0#8
  | tlb0Mega : Bool := false
  | tlb1Valid : Bool := false
  | tlb1VPN : BitVec 20 := 0#20
  | tlb1PPN : BitVec 22 := 0#22
  | tlb1Flags : BitVec 8 := 0#8
  | tlb1Mega : Bool := false
  | tlb2Valid : Bool := false
  | tlb2VPN : BitVec 20 := 0#20
  | tlb2PPN : BitVec 22 := 0#22
  | tlb2Flags : BitVec 8 := 0#8
  | tlb2Mega : Bool := false
  | tlb3Valid : Bool := false
  | tlb3VPN : BitVec 20 := 0#20
  | tlb3PPN : BitVec 22 := 0#22
  | tlb3Flags : BitVec 8 := 0#8
  | tlb3Mega : Bool := false
  | ptwIsIfetch : Bool := false
  | ifetchFaultPending : Bool := false
  | dMissPC : BitVec 32 := 0#32
  | dMissVaddr : BitVec 32 := 0#32
  | dMissIsStore : Bool := false
  | idex_isSret : Bool := false
  | idex_isSFenceVMA : Bool := false
  | uartLCR : BitVec 8 := 0#8
  | uartIER : BitVec 8 := 0#8
  | uartMCR : BitVec 8 := 0#8
  | uartSCR : BitVec 8 := 0#8
  | uartDLL : BitVec 8 := 0#8
  | uartDLM : BitVec 8 := 0#8
  | uartRxBuf : BitVec 8 := 0#8
  | uartRxReady : Bool := false
  | dmem_b0_rdata : BitVec 8 := 0#8
  | dmem_b1_rdata : BitVec 8 := 0#8
  | dmem_b2_rdata : BitVec 8 := 0#8
  | dmem_b3_rdata : BitVec 8 := 0#8
  | fv_rst_seen : Bool := false

/-- Signal-DSL model of `rv32i_soc`.
    Inputs: `rst`, `imem_wr_en`, `imem_wr_addr`, `imem_wr_data`, `dmem_wr_en`, `dmem_wr_addr`, `dmem_wr_data`, `uart_rx_valid`, `uart_rx_data`; outputs: `pc_out`, `uart_tx_valid`, `uart_tx_data`, `trap_out`, `trap_cause_out`, `trap_pc_out`, `itlb_need_translate`, `itlb_hit`, `itlb_miss`, `itlb_stall`, `itlb_ptw_req`, `itlb_phys_addr`, `itlb_fetch_pc`. -/
private def rv32i_socBody {dom : DomainConfig}
    (rst : Signal dom Bool) (imem_wr_en : Signal dom Bool) (imem_wr_addr : Signal dom (BitVec 12)) (imem_wr_data : Signal dom (BitVec 32)) (dmem_wr_en : Signal dom Bool) (dmem_wr_addr : Signal dom (BitVec 23)) (dmem_wr_data : Signal dom (BitVec 32)) (uart_rx_valid : Signal dom Bool) (uart_rx_data : Signal dom (BitVec 8))
    (state : Signal dom Rv32i_socState) : Signal dom Rv32i_socState :=
  let pcReg := Rv32i_socState.pcReg state
  let fetchPC := Rv32i_socState.fetchPC state
  let flushDelay := Rv32i_socState.flushDelay state
  let ifid_inst := Rv32i_socState.ifid_inst state
  let ifid_pc := Rv32i_socState.ifid_pc state
  let ifid_pc4 := Rv32i_socState.ifid_pc4 state
  let idex_aluOp := Rv32i_socState.idex_aluOp state
  let idex_regWrite := Rv32i_socState.idex_regWrite state
  let idex_memRead := Rv32i_socState.idex_memRead state
  let idex_memWrite := Rv32i_socState.idex_memWrite state
  let idex_memToReg := Rv32i_socState.idex_memToReg state
  let idex_branch := Rv32i_socState.idex_branch state
  let idex_jump := Rv32i_socState.idex_jump state
  let idex_auipc := Rv32i_socState.idex_auipc state
  let idex_aluSrcB := Rv32i_socState.idex_aluSrcB state
  let idex_isJalr := Rv32i_socState.idex_isJalr state
  let idex_isCsr := Rv32i_socState.idex_isCsr state
  let idex_isEcall := Rv32i_socState.idex_isEcall state
  let idex_isMret := Rv32i_socState.idex_isMret state
  let idex_rs1Val := Rv32i_socState.idex_rs1Val state
  let idex_rs2Val := Rv32i_socState.idex_rs2Val state
  let idex_imm := Rv32i_socState.idex_imm state
  let idex_rd := Rv32i_socState.idex_rd state
  let idex_rs1Idx := Rv32i_socState.idex_rs1Idx state
  let idex_rs2Idx := Rv32i_socState.idex_rs2Idx state
  let idex_funct3 := Rv32i_socState.idex_funct3 state
  let idex_pc := Rv32i_socState.idex_pc state
  let idex_pc4 := Rv32i_socState.idex_pc4 state
  let idex_csrAddr := Rv32i_socState.idex_csrAddr state
  let idex_csrFunct3 := Rv32i_socState.idex_csrFunct3 state
  let exwb_alu := Rv32i_socState.exwb_alu state
  let exwb_physAddr := Rv32i_socState.exwb_physAddr state
  let exwb_rd := Rv32i_socState.exwb_rd state
  let exwb_regW := Rv32i_socState.exwb_regW state
  let exwb_m2r := Rv32i_socState.exwb_m2r state
  let exwb_pc4 := Rv32i_socState.exwb_pc4 state
  let exwb_jump := Rv32i_socState.exwb_jump state
  let exwb_isCsr := Rv32i_socState.exwb_isCsr state
  let exwb_csrRdata := Rv32i_socState.exwb_csrRdata state
  let prev_wb_addr := Rv32i_socState.prev_wb_addr state
  let prev_wb_data := Rv32i_socState.prev_wb_data state
  let prev_wb_en := Rv32i_socState.prev_wb_en state
  let prevStoreAddr := Rv32i_socState.prevStoreAddr state
  let prevStoreData := Rv32i_socState.prevStoreData state
  let prevStoreEn := Rv32i_socState.prevStoreEn state
  let msipReg := Rv32i_socState.msipReg state
  let mtimeLoReg := Rv32i_socState.mtimeLoReg state
  let mtimeHiReg := Rv32i_socState.mtimeHiReg state
  let mtimecmpLoReg := Rv32i_socState.mtimecmpLoReg state
  let mtimecmpHiReg := Rv32i_socState.mtimecmpHiReg state
  let mstatusReg := Rv32i_socState.mstatusReg state
  let mieReg := Rv32i_socState.mieReg state
  let mtvecReg := Rv32i_socState.mtvecReg state
  let mscratchReg := Rv32i_socState.mscratchReg state
  let mepcReg := Rv32i_socState.mepcReg state
  let mcauseReg := Rv32i_socState.mcauseReg state
  let mtvalReg := Rv32i_socState.mtvalReg state
  let aiStatusReg := Rv32i_socState.aiStatusReg state
  let aiInputReg := Rv32i_socState.aiInputReg state
  let exwb_funct3 := Rv32i_socState.exwb_funct3 state
  let idex_isMext := Rv32i_socState.idex_isMext state
  let reservationValid := Rv32i_socState.reservationValid state
  let reservationAddr := Rv32i_socState.reservationAddr state
  let idex_isAMO := Rv32i_socState.idex_isAMO state
  let idex_amoOp := Rv32i_socState.idex_amoOp state
  let exwb_isAMO := Rv32i_socState.exwb_isAMO state
  let exwb_amoOp := Rv32i_socState.exwb_amoOp state
  let pendingWriteEn := Rv32i_socState.pendingWriteEn state
  let pendingWriteAddr := Rv32i_socState.pendingWriteAddr state
  let pendingWriteData := Rv32i_socState.pendingWriteData state
  let cycle_count := Rv32i_socState.cycle_count state
  let privMode := Rv32i_socState.privMode state
  let sieReg := Rv32i_socState.sieReg state
  let stvecReg := Rv32i_socState.stvecReg state
  let sscratchReg := Rv32i_socState.sscratchReg state
  let sepcReg := Rv32i_socState.sepcReg state
  let scauseReg := Rv32i_socState.scauseReg state
  let stvalReg := Rv32i_socState.stvalReg state
  let satpReg := Rv32i_socState.satpReg state
  let medelegReg := Rv32i_socState.medelegReg state
  let midelegReg := Rv32i_socState.midelegReg state
  let mcounterenReg := Rv32i_socState.mcounterenReg state
  let scounterenReg := Rv32i_socState.scounterenReg state
  let mmuState := Rv32i_socState.mmuState state
  let ptwState := Rv32i_socState.ptwState state
  let ptwVaddr := Rv32i_socState.ptwVaddr state
  let ptwPte := Rv32i_socState.ptwPte state
  let ptwMega := Rv32i_socState.ptwMega state
  let replPtr := Rv32i_socState.replPtr state
  let tlb0Valid := Rv32i_socState.tlb0Valid state
  let tlb0VPN := Rv32i_socState.tlb0VPN state
  let tlb0PPN := Rv32i_socState.tlb0PPN state
  let tlb0Flags := Rv32i_socState.tlb0Flags state
  let tlb0Mega := Rv32i_socState.tlb0Mega state
  let tlb1Valid := Rv32i_socState.tlb1Valid state
  let tlb1VPN := Rv32i_socState.tlb1VPN state
  let tlb1PPN := Rv32i_socState.tlb1PPN state
  let tlb1Flags := Rv32i_socState.tlb1Flags state
  let tlb1Mega := Rv32i_socState.tlb1Mega state
  let tlb2Valid := Rv32i_socState.tlb2Valid state
  let tlb2VPN := Rv32i_socState.tlb2VPN state
  let tlb2PPN := Rv32i_socState.tlb2PPN state
  let tlb2Flags := Rv32i_socState.tlb2Flags state
  let tlb2Mega := Rv32i_socState.tlb2Mega state
  let tlb3Valid := Rv32i_socState.tlb3Valid state
  let tlb3VPN := Rv32i_socState.tlb3VPN state
  let tlb3PPN := Rv32i_socState.tlb3PPN state
  let tlb3Flags := Rv32i_socState.tlb3Flags state
  let tlb3Mega := Rv32i_socState.tlb3Mega state
  let ptwIsIfetch := Rv32i_socState.ptwIsIfetch state
  let ifetchFaultPending := Rv32i_socState.ifetchFaultPending state
  let dMissPC := Rv32i_socState.dMissPC state
  let dMissVaddr := Rv32i_socState.dMissVaddr state
  let dMissIsStore := Rv32i_socState.dMissIsStore state
  let idex_isSret := Rv32i_socState.idex_isSret state
  let idex_isSFenceVMA := Rv32i_socState.idex_isSFenceVMA state
  let uartLCR := Rv32i_socState.uartLCR state
  let uartIER := Rv32i_socState.uartIER state
  let uartMCR := Rv32i_socState.uartMCR state
  let uartSCR := Rv32i_socState.uartSCR state
  let uartDLL := Rv32i_socState.uartDLL state
  let uartDLM := Rv32i_socState.uartDLM state
  let uartRxBuf := Rv32i_socState.uartRxBuf state
  let uartRxReady := Rv32i_socState.uartRxReady state
  let dmem_b0_rdata := Rv32i_socState.dmem_b0_rdata state
  let dmem_b1_rdata := Rv32i_socState.dmem_b1_rdata state
  let dmem_b2_rdata := Rv32i_socState.dmem_b2_rdata state
  let dmem_b3_rdata := Rv32i_socState.dmem_b3_rdata state
  let fv_rst_seen := Rv32i_socState.fv_rst_seen state
  -- combinational logic feeding the registers
  let mstatusNewCSR := (Signal.pure 0#32)
  let mieNewCSR := (Signal.pure 0#32)
  let mtvecNewCSR := (Signal.pure 0#32)
  let mscratchNewCSR := (Signal.pure 0#32)
  let mepcNewCSR := (Signal.pure 0#32)
  let mcauseNewCSR := (Signal.pure 0#32)
  let mtvalNewCSR := (Signal.pure 0#32)
  let sieNewCSR := (Signal.pure 0#32)
  let stvecNewCSR := (Signal.pure 0#32)
  let sscratchNewCSR := (Signal.pure 0#32)
  let sepcNewCSR := (Signal.pure 0#32)
  let scauseNewCSR := (Signal.pure 0#32)
  let stvalNewCSR := (Signal.pure 0#32)
  let satpNewCSR := (Signal.pure 0#32)
  let medelegNewCSR := (Signal.pure 0#32)
  let midelegNewCSR := (Signal.pure 0#32)
  let mcounterenNewCSR := (Signal.pure 0#32)
  let scounterenNewCSR := (Signal.pure 0#32)
  let sstatusNewVal := (Signal.pure 0#32)
  let pcPlus4 := ((Signal.pure 4#32) + pcReg)
  let id_opcode := ((BitVec.extractLsb' 0 7) <$> ifid_inst)
  let id_funct3 := ((BitVec.extractLsb' 12 3) <$> ifid_inst)
  let id_funct7 := ((BitVec.extractLsb' 25 7) <$> ifid_inst)
  let sstatus_view := ((Signal.pure 786722#32) &&& mstatusReg)
  let mret_target := mepcReg
  let sret_target := sepcReg
  let fetchPCPlus4 := ((Signal.pure 4#32) + fetchPC)
  let holdEX := pendingWriteEn
  let id_isBranch := ((Signal.pure 99#7) === id_opcode)
  let id_isJALR := ((Signal.pure 103#7) === id_opcode)
  let id_rd := ((BitVec.extractLsb' 7 5) <$> ifid_inst)
  let id_rs1 := ((BitVec.extractLsb' 15 5) <$> ifid_inst)
  let id_rs2 := ((BitVec.extractLsb' 20 5) <$> ifid_inst)
  let id_csrAddr := ((BitVec.extractLsb' 20 12) <$> ifid_inst)
  let alu_result := (Signal.mux idex_isMext mext_result alu_result_raw)
  let wb_addr := exwb_rd
  let wb_en := (exwb_regW &&& (~~~((Signal.pure 0#5) === exwb_rd)))
  let mstatusMretVal := ((Signal.pure 128#32) ||| (Signal.mux ((·.getLsbD 7) <$> mstatusReg) ((Signal.pure 8#32) ||| ((Signal.pure 4294961151#32) &&& mstatusReg)) ((Signal.pure 4294961143#32) &&& mstatusReg)))
  let mstatusSretVal := ((Signal.pure 32#32) ||| (Signal.mux ((·.getLsbD 5) <$> mstatusReg) ((Signal.pure 2#32) ||| ((Signal.pure 4294967039#32) &&& mstatusReg)) ((Signal.pure 4294967037#32) &&& mstatusReg)))
  let sstatus_wdata_out := (((Signal.pure 4294180573#32) &&& mstatusReg) ||| ((Signal.pure 786722#32) &&& sstatusNewVal))
  let mpp := ((BitVec.extractLsb' 11 2) <$> mstatusReg)
  let sretPriv := ((BitVec.zeroExtend 2) <$> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 8) <$> mstatusReg)))
  let isUART_wb := ((Signal.pure 16#8) === ((BitVec.extractLsb' 24 8) <$> exwb_physAddr))
  let uartOffset_wb := ((BitVec.extractLsb' 0 3) <$> exwb_physAddr)
  let uartDLAB_wb := ((·.getLsbD 7) <$> uartLCR)
  let id_isAMO := ((Signal.pure 47#7) === id_opcode)
  let id_amoOp := ((BitVec.extractLsb' 27 5) <$> ifid_inst)
  let exwb_isLR := (exwb_isAMO &&& ((Signal.pure 2#5) === exwb_amoOp))
  let exwb_isSC := (exwb_isAMO &&& ((Signal.pure 3#5) === exwb_amoOp))
  let ptwIsIdle := ((Signal.pure 0#3) === ptwState)
  let dmem_rdata := ((· ++ ·) <$> dmem_b3_rdata <*> ((· ++ ·) <$> dmem_b2_rdata <*> ((· ++ ·) <$> dmem_b1_rdata <*> dmem_b0_rdata)))
  let ptwIsL1Wait := ((Signal.pure 2#3) === ptwState)
  let dmemPteIsLeaf := (((·.getLsbD 1) <$> dmem_b0_rdata) ||| ((·.getLsbD 3) <$> dmem_b0_rdata))
  let tlbFill := ((Signal.pure 5#3) === ptwState)
  let doFill0 := (tlbFill &&& ((Signal.pure 0#2) === replPtr))
  let fillVPN := ((BitVec.extractLsb' 12 20) <$> ptwVaddr)
  let fillPPN := ((BitVec.extractLsb' 10 22) <$> ptwPte)
  let fillFlags := ((BitVec.extractLsb' 0 8) <$> ptwPte)
  let doFill1 := (tlbFill &&& ((Signal.pure 1#2) === replPtr))
  let doFill2 := (tlbFill &&& ((Signal.pure 2#2) === replPtr))
  let doFill3 := (tlbFill &&& ((Signal.pure 3#2) === replPtr))
  let ptwIsFault := ((Signal.pure 6#3) === ptwState)
  let satpMode := ((·.getLsbD 31) <$> satpReg)
  let isMmode := ((Signal.pure 3#2) === privMode)
  let VdfgTmp_h8386f12b__0 := ((·.getLsbD 31) <$> fetchPC)
  let isMMUIdle := ((Signal.pure 0#3) === mmuState)
  let wb_data_non_mem :=
    hw_cond exwb_alu
    | exwb_isCsr => exwb_csrRdata
    | exwb_jump => exwb_pc4
  let fwd_rs1_match := (wb_en &&& (exwb_rd === idex_rs1Idx))
  let fwd_rs2_match := (wb_en &&& (exwb_rd === idex_rs2Idx))
  let isMMUDone := ((Signal.pure 3#3) === mmuState)
  let isMMUFault := ((Signal.pure 4#3) === mmuState)
  let ptwIsL1Req := ((Signal.pure 1#3) === ptwState)
  let ptwIsL0Req := ((Signal.pure 3#3) === ptwState)
  let ptwIsL0Wait := ((Signal.pure 4#3) === ptwState)
  let storeByteOff := ((BitVec.extractLsb' 0 2) <$> alu_result_approx)
  let storeFunct3Low := ((BitVec.extractLsb' 0 2) <$> idex_funct3)
  let isSB := ((Signal.pure 0#2) === storeFunct3Low)
  let isSH := ((Signal.pure 1#2) === storeFunct3Low)
  let isSW := ((Signal.pure 2#2) === storeFunct3Low)
  let storeHalfHigh := ((·.getLsbD 1) <$> alu_result_approx)
  let VdfgTmp_h032360d3__0 := (isSW ||| ((~~~storeHalfHigh) &&& isSH))
  let VdfgTmp_hb6af2209__0 := (isSW ||| (isSH &&& storeHalfHigh))
  let dVPN := ((BitVec.extractLsb' 12 20) <$> alu_result_approx)
  let VdfgTmp_h2dc589b2__0 := ((BitVec.extractLsb' 10 10) <$> tlb0VPN)
  let VdfgTmp_hb73c3f48__0 := ((BitVec.extractLsb' 22 10) <$> alu_result_approx)
  let tlb0Hit := (tlb0Valid &&& (Signal.mux tlb0Mega (VdfgTmp_h2dc589b2__0 === VdfgTmp_hb73c3f48__0) (tlb0VPN === dVPN)))
  let VdfgTmp_hdcacdbfe__0 := ((BitVec.extractLsb' 10 10) <$> tlb1VPN)
  let tlb1Hit := (tlb1Valid &&& (Signal.mux tlb1Mega (VdfgTmp_hdcacdbfe__0 === VdfgTmp_hb73c3f48__0) (tlb1VPN === dVPN)))
  let VdfgTmp_h0f16f169__0 := ((BitVec.extractLsb' 10 10) <$> tlb2VPN)
  let tlb2Hit := (tlb2Valid &&& (Signal.mux tlb2Mega (VdfgTmp_h0f16f169__0 === VdfgTmp_hb73c3f48__0) (tlb2VPN === dVPN)))
  let VdfgTmp_h2054660b__0 := ((BitVec.extractLsb' 10 10) <$> tlb3VPN)
  let tlb3Hit := (tlb3Valid &&& (Signal.mux tlb3Mega (VdfgTmp_h2054660b__0 === VdfgTmp_hb73c3f48__0) (tlb3VPN === dVPN)))
  let VdfgTmp_hd6071048__0 := ((BitVec.extractLsb' 0 20) <$> (Signal.mux tlb0Hit tlb0PPN (Signal.mux tlb1Hit tlb1PPN (Signal.mux tlb2Hit tlb2PPN (Signal.mux tlb3Hit tlb3PPN (Signal.pure 0#22))))))
  let iVPN := ((BitVec.extractLsb' 12 20) <$> fetchPC)
  let VdfgTmp_h839b6fc2__0 := ((BitVec.extractLsb' 22 10) <$> fetchPC)
  let dmemPteValid := ((·.getLsbD 0) <$> dmem_b0_rdata)
  let clintOffset_wb := ((BitVec.extractLsb' 0 16) <$> exwb_physAddr)
  let isCLINT_wb := ((Signal.pure 512#16) === ((BitVec.extractLsb' 16 16) <$> exwb_physAddr))
  let is_mmio_wb := ((·.getLsbD 30) <$> exwb_physAddr)
  let mmioOffset_wb := ((BitVec.extractLsb' 0 4) <$> exwb_physAddr)
  let loadByteOff := ((BitVec.extractLsb' 0 2) <$> exwb_physAddr)
  let timerIrq := (((BitVec.ult · ·) <$> mtimecmpHiReg <*> mtimeHiReg) ||| ((mtimeHiReg === mtimecmpHiReg) &&& ((BitVec.ule · ·) <$> mtimecmpLoReg <*> mtimeLoReg)))
  let swIrq := ((·.getLsbD 0) <$> msipReg)
  let VdfgTmp_h6aed8c94__0 := ((Signal.pure 256#12) === idex_csrAddr)
  let mstatusMIE := ((·.getLsbD 3) <$> mstatusReg)
  let id_isALUrr := ((Signal.pure 51#7) === id_opcode)
  let id_isALUimm := ((Signal.pure 19#7) === id_opcode)
  let id_isLoad := ((Signal.pure 3#7) === id_opcode)
  let id_isStore := ((Signal.pure 35#7) === id_opcode)
  let id_isLUI := ((Signal.pure 55#7) === id_opcode)
  let id_isAUIPC := ((Signal.pure 23#7) === id_opcode)
  let id_isJAL := ((Signal.pure 111#7) === id_opcode)
  let id_isSystem := ((Signal.pure 115#7) === id_opcode)
  let id_f3isZero := ((Signal.pure 0#3) === id_funct3)
  let id_isLR := (id_isAMO &&& ((Signal.pure 2#5) === id_amoOp))
  let id_isSC := (id_isAMO &&& ((Signal.pure 3#5) === id_amoOp))
  let VdfgTmp_he9f65336__0 := (id_isSystem &&& id_f3isZero)
  let mtimeLoInc := ((Signal.pure 1#32) + mtimeLoReg)
  let msSetSPIE := (Signal.mux ((·.getLsbD 1) <$> mstatusReg) ((Signal.pure 32#32) ||| ((Signal.pure 4294967293#32) &&& mstatusReg)) ((Signal.pure 4294967261#32) &&& mstatusReg))
  let idex_rs1Idx_next := (Signal.mux holdEX idex_rs1Idx id_rs1)
  let idex_rs2Idx_next := (Signal.mux holdEX idex_rs2Idx id_rs2)
  let idex_funct3_next := (Signal.mux holdEX idex_funct3 id_funct3)
  let idex_pc_next := (Signal.mux holdEX idex_pc ifid_pc)
  let idex_pc4_next := (Signal.mux holdEX idex_pc4 ifid_pc4)
  let idex_csrAddr_next := (Signal.mux holdEX idex_csrAddr id_csrAddr)
  let idex_csrFunct3_next := (Signal.mux holdEX idex_csrFunct3 id_funct3)
  let exwb_alu_next := (Signal.mux holdEX exwb_alu alu_result)
  let exwb_rd_next := (Signal.mux holdEX (Signal.pure 0#5) idex_rd)
  let exwb_m2r_next := ((~~~holdEX) &&& idex_memToReg)
  let exwb_pc4_next := (Signal.mux holdEX exwb_pc4 idex_pc4)
  let exwb_jump_next := ((~~~holdEX) &&& idex_jump)
  let exwb_isCsr_next := ((~~~holdEX) &&& idex_isCsr)
  let prev_wb_addr_next := wb_addr
  let prev_wb_en_next := wb_en
  let mieReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 772#12) === idex_csrAddr)) mieNewCSR mieReg)
  let mtvecReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 773#12) === idex_csrAddr)) mtvecNewCSR mtvecReg)
  let mscratchReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 832#12) === idex_csrAddr)) mscratchNewCSR mscratchReg)
  let sieReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 260#12) === idex_csrAddr)) sieNewCSR sieReg)
  let stvecReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 261#12) === idex_csrAddr)) stvecNewCSR stvecReg)
  let sscratchReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 320#12) === idex_csrAddr)) sscratchNewCSR sscratchReg)
  let satpReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 384#12) === idex_csrAddr)) satpNewCSR satpReg)
  let medelegReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 770#12) === idex_csrAddr)) medelegNewCSR medelegReg)
  let midelegReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 771#12) === idex_csrAddr)) midelegNewCSR midelegReg)
  let mcounterenReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 774#12) === idex_csrAddr)) mcounterenNewCSR mcounterenReg)
  let scounterenReg_next := (Signal.mux (idex_isCsr &&& ((Signal.pure 262#12) === idex_csrAddr)) scounterenNewCSR scounterenReg)
  let uartRxBuf_next := (Signal.mux uart_rx_valid uart_rx_data uartRxBuf)
  let uartRxReady_next :=
    hw_cond uartRxReady
    | uart_rx_valid => (Signal.pure true)
    | (((exwb_m2r &&& isUART_wb) &&& ((Signal.pure 0#3) === uartOffset_wb)) &&& (~~~uartDLAB_wb)) => (Signal.pure false)
  let exwb_funct3_next := (Signal.mux holdEX exwb_funct3 idex_funct3)
  let exwb_isAMO_next := ((~~~holdEX) &&& idex_isAMO)
  let exwb_amoOp_next := (Signal.mux holdEX exwb_amoOp idex_amoOp)
  let reservationValid_next :=
    hw_cond reservationValid
    | exwb_isLR => (Signal.pure true)
    | exwb_isSC => (Signal.pure false)
    | (prevStoreEn &&& (prevStoreAddr === reservationAddr)) => (Signal.pure false)
  let reservationAddr_next := (Signal.mux exwb_isLR exwb_physAddr reservationAddr)
  let pendingWriteEn_next := (Signal.mux ((exwb_isAMO &&& (~~~exwb_isLR)) &&& (~~~exwb_isSC)) (Signal.pure true) (Signal.pure false))
  let pendingWriteAddr_next := (Signal.mux ((exwb_isAMO &&& (~~~exwb_isLR)) &&& (~~~exwb_isSC)) exwb_physAddr pendingWriteAddr)
  let pendingWriteData_next := (Signal.mux ((exwb_isAMO &&& (~~~exwb_isLR)) &&& (~~~exwb_isSC)) amo_new_val pendingWriteData)
  let replPtr_next := (Signal.mux tlbFill ((Signal.pure 1#2) + replPtr) replPtr)
  let tlb0Valid_next := (doFill0 ||| ((~~~idex_isSFenceVMA) &&& tlb0Valid))
  let tlb0VPN_next := (Signal.mux doFill0 fillVPN tlb0VPN)
  let tlb0PPN_next := (Signal.mux doFill0 fillPPN tlb0PPN)
  let tlb0Flags_next := (Signal.mux doFill0 fillFlags tlb0Flags)
  let tlb0Mega_next := (Signal.mux doFill0 ptwMega tlb0Mega)
  let tlb1Valid_next := (doFill1 ||| ((~~~idex_isSFenceVMA) &&& tlb1Valid))
  let tlb1VPN_next := (Signal.mux doFill1 fillVPN tlb1VPN)
  let tlb1PPN_next := (Signal.mux doFill1 fillPPN tlb1PPN)
  let tlb1Flags_next := (Signal.mux doFill1 fillFlags tlb1Flags)
  let tlb1Mega_next := (Signal.mux doFill1 ptwMega tlb1Mega)
  let tlb2Valid_next := (doFill2 ||| ((~~~idex_isSFenceVMA) &&& tlb2Valid))
  let tlb2VPN_next := (Signal.mux doFill2 fillVPN tlb2VPN)
  let tlb2PPN_next := (Signal.mux doFill2 fillPPN tlb2PPN)
  let tlb2Flags_next := (Signal.mux doFill2 fillFlags tlb2Flags)
  let tlb2Mega_next := (Signal.mux doFill2 ptwMega tlb2Mega)
  let tlb3Valid_next := (doFill3 ||| ((~~~idex_isSFenceVMA) &&& tlb3Valid))
  let tlb3VPN_next := (Signal.mux doFill3 fillVPN tlb3VPN)
  let tlb3PPN_next := (Signal.mux doFill3 fillPPN tlb3PPN)
  let tlb3Flags_next := (Signal.mux doFill3 fillFlags tlb3Flags)
  let tlb3Mega_next := (Signal.mux doFill3 ptwMega tlb3Mega)
  let itlb_need_translate := (satpMode &&& ((~~~isMmode) &&& VdfgTmp_h8386f12b__0))
  let busRdataRaw :=
    hw_cond dmem_rdata
    | isCLINT_wb => (Signal.mux ((Signal.pure 0#16) === clintOffset_wb) msipReg (Signal.mux ((Signal.pure 16384#16) === clintOffset_wb) mtimecmpLoReg (Signal.mux ((Signal.pure 16388#16) === clintOffset_wb) mtimecmpHiReg (Signal.mux ((Signal.pure 49144#16) === clintOffset_wb) mtimeLoReg (Signal.mux ((Signal.pure 49148#16) === clintOffset_wb) mtimeHiReg (Signal.pure 0#32))))))
    | isUART_wb => (Signal.mux ((Signal.pure 0#3) === uartOffset_wb) (Signal.mux uartDLAB_wb ((BitVec.zeroExtend 32) <$> uartDLL) ((BitVec.zeroExtend 32) <$> uartRxBuf)) (Signal.mux ((Signal.pure 1#3) === uartOffset_wb) (Signal.mux uartDLAB_wb ((BitVec.zeroExtend 32) <$> uartDLM) ((BitVec.zeroExtend 32) <$> uartIER)) (Signal.mux ((Signal.pure 2#3) === uartOffset_wb) (Signal.pure 1#32) (Signal.mux ((Signal.pure 3#3) === uartOffset_wb) ((BitVec.zeroExtend 32) <$> uartLCR) (Signal.mux ((Signal.pure 4#3) === uartOffset_wb) ((BitVec.zeroExtend 32) <$> uartMCR) (Signal.mux ((Signal.pure 5#3) === uartOffset_wb) ((· ++ ·) <$> (Signal.pure 48#31) <*> ((fun b => if b then 1#1 else 0#1) <$> uartRxReady)) (Signal.mux ((Signal.pure 7#3) === uartOffset_wb) ((BitVec.zeroExtend 32) <$> uartSCR) (Signal.pure 0#32))))))))
    | is_mmio_wb => (Signal.mux ((Signal.pure 0#4) === mmioOffset_wb) aiStatusReg (Signal.mux ((Signal.pure 8#4) === mmioOffset_wb) (Signal.pure 3735928559#32) (Signal.pure 0#32)))
    | (prevStoreEn &&& (((BitVec.extractLsb' 2 30) <$> prevStoreAddr) === ((BitVec.extractLsb' 2 30) <$> exwb_physAddr))) => prevStoreData
  let id_memRead := (id_isLoad ||| (id_isLR ||| ((~~~(id_isLR ||| id_isSC)) &&& id_isAMO)))
  let id_memWrite := (id_isStore ||| id_isSC)
  let id_jump := (id_isJAL ||| id_isJALR)
  let id_auipc := (id_isAUIPC ||| id_isJAL)
  let id_aluSrcB := (id_isALUimm ||| (id_isLoad ||| (id_isStore ||| (id_isLUI ||| (id_isAUIPC ||| (id_isJAL ||| (id_isJALR ||| id_isAMO)))))))
  let id_isCsr := ((~~~id_f3isZero) &&& id_isSystem)
  let id_isEcall := (VdfgTmp_he9f65336__0 &&& ((Signal.pure 0#12) === id_csrAddr))
  let id_isMret := (VdfgTmp_he9f65336__0 &&& ((Signal.pure 770#12) === id_csrAddr))
  let id_imm := (Signal.mux id_isAMO (Signal.pure 0#32) id_imm_raw)
  let csr_rdata :=
    hw_cond (Signal.pure 0#32)
    | ((Signal.pure 768#12) === idex_csrAddr) => mstatusReg
    | ((Signal.pure 772#12) === idex_csrAddr) => mieReg
    | ((Signal.pure 773#12) === idex_csrAddr) => mtvecReg
    | ((Signal.pure 832#12) === idex_csrAddr) => mscratchReg
    | ((Signal.pure 833#12) === idex_csrAddr) => mepcReg
    | ((Signal.pure 834#12) === idex_csrAddr) => mcauseReg
    | ((Signal.pure 835#12) === idex_csrAddr) => mtvalReg
    | ((Signal.pure 836#12) === idex_csrAddr) => ((Signal.mux timerIrq (Signal.pure 128#32) (Signal.pure 0#32)) ||| (Signal.mux swIrq (Signal.pure 8#32) (Signal.pure 0#32)))
    | ((Signal.pure 769#12) === idex_csrAddr) => (Signal.pure 1075056897#32)
    | ((Signal.pure 3860#12) === idex_csrAddr) => (Signal.pure 0#32)
    | ((Signal.pure 770#12) === idex_csrAddr) => medelegReg
    | ((Signal.pure 771#12) === idex_csrAddr) => midelegReg
    | VdfgTmp_h6aed8c94__0 => sstatus_view
    | ((Signal.pure 260#12) === idex_csrAddr) => sieReg
    | ((Signal.pure 261#12) === idex_csrAddr) => stvecReg
    | ((Signal.pure 320#12) === idex_csrAddr) => sscratchReg
    | ((Signal.pure 321#12) === idex_csrAddr) => sepcReg
    | ((Signal.pure 322#12) === idex_csrAddr) => scauseReg
    | ((Signal.pure 323#12) === idex_csrAddr) => stvalReg
    | ((Signal.pure 324#12) === idex_csrAddr) => (Signal.pure 0#32)
    | ((Signal.pure 384#12) === idex_csrAddr) => satpReg
    | ((Signal.pure 774#12) === idex_csrAddr) => mcounterenReg
    | ((Signal.pure 262#12) === idex_csrAddr) => scounterenReg
  let ex_rs2_approx := (Signal.mux fwd_rs2_match (Signal.mux exwb_m2r idex_rs2Val wb_data_non_mem) idex_rs2Val)
  let sstatusWriteActive := (idex_isCsr &&& VdfgTmp_h6aed8c94__0)
  let VdfgExtracted_hff53a329__0 := ((BitVec.extractLsb' 0 8) <$> ex_rs2_approx)
  let id_isMext := (id_isALUrr &&& ((Signal.pure 1#7) === id_funct7))
  let isDataReady := (ptwIsL1Wait ||| ptwIsL0Wait)
  let dmemPteInvalid := (~~~dmemPteValid)
  let bypassMMU := ((~~~satpMode) ||| isMmode)
  let byte0_wdata := (Signal.mux pendingWriteEn ((BitVec.extractLsb' 0 8) <$> pendingWriteData) VdfgExtracted_hff53a329__0)
  let byte2_wdata :=
    hw_cond VdfgExtracted_hff53a329__0
    | pendingWriteEn => ((BitVec.extractLsb' 16 8) <$> pendingWriteData)
    | isSW => ((BitVec.extractLsb' 16 8) <$> ex_rs2_approx)
  let timerIntEnabled := (mstatusMIE &&& (((·.getLsbD 7) <$> mieReg) &&& timerIrq))
  let swIntEnabled := (mstatusMIE &&& (((·.getLsbD 3) <$> mieReg) &&& swIrq))
  let itlb0Hit := (tlb0Valid &&& (Signal.mux tlb0Mega (VdfgTmp_h2dc589b2__0 === VdfgTmp_h839b6fc2__0) (tlb0VPN === iVPN)))
  let itlb1Hit := (tlb1Valid &&& (Signal.mux tlb1Mega (VdfgTmp_hdcacdbfe__0 === VdfgTmp_h839b6fc2__0) (tlb1VPN === iVPN)))
  let itlb2Hit := (tlb2Valid &&& (Signal.mux tlb2Mega (VdfgTmp_h0f16f169__0 === VdfgTmp_h839b6fc2__0) (tlb2VPN === iVPN)))
  let itlb3Hit := (tlb3Valid &&& (Signal.mux tlb3Mega (VdfgTmp_h2054660b__0 === VdfgTmp_h839b6fc2__0) (tlb3VPN === iVPN)))
  let VdfgTmp_h184f0194__0 := ((BitVec.extractLsb' 0 20) <$> (Signal.mux itlb0Hit tlb0PPN (Signal.mux itlb1Hit tlb1PPN (Signal.mux itlb2Hit tlb2PPN (Signal.mux itlb3Hit tlb3PPN (Signal.pure 0#22))))))
  let dPhysAddr := (Signal.mux (Signal.mux tlb0Hit tlb0Mega (Signal.mux tlb1Hit tlb1Mega (Signal.mux tlb2Hit tlb2Mega (tlb3Hit &&& tlb3Mega)))) (((· ++ ·) <$> VdfgTmp_hd6071048__0 <*> (Signal.pure 0#12)) + ((BitVec.zeroExtend 32) <$> ((BitVec.extractLsb' 0 22) <$> alu_result_approx))) ((· ++ ·) <$> VdfgTmp_hd6071048__0 <*> ((BitVec.extractLsb' 0 12) <$> alu_result_approx)))
  let VdfgTmp_h88d03c83__0 := (~~~bypassMMU)
  let anyTLBHit := (tlb0Hit ||| (tlb1Hit ||| (tlb2Hit ||| tlb3Hit)))
  let byte1_wdata_ex := (Signal.mux isSB VdfgExtracted_hff53a329__0 ((BitVec.extractLsb' 8 8) <$> ex_rs2_approx))
  let selByte :=
    hw_cond ((BitVec.extractLsb' 24 8) <$> busRdataRaw)
    | ((Signal.pure 0#2) === loadByteOff) => ((BitVec.extractLsb' 0 8) <$> busRdataRaw)
    | ((Signal.pure 1#2) === loadByteOff) => ((BitVec.extractLsb' 8 8) <$> busRdataRaw)
    | ((Signal.pure 2#2) === loadByteOff) => ((BitVec.extractLsb' 16 8) <$> busRdataRaw)
  let selHalf := (Signal.mux ((·.getLsbD 1) <$> exwb_physAddr) ((BitVec.extractLsb' 16 16) <$> busRdataRaw) ((BitVec.extractLsb' 0 16) <$> busRdataRaw))
  let idex_imm_next := (Signal.mux holdEX idex_imm id_imm)
  let exwb_csrRdata_next := (Signal.mux holdEX exwb_csrRdata csr_rdata)
  let ptwPte_next := (Signal.mux isDataReady dmem_rdata ptwPte)
  let ptwMega_next := (((ptwIsL1Wait &&& dmemPteIsLeaf) &&& (~~~dmemPteInvalid)) ||| ((~~~ptwIsIdle) &&& ptwMega))
  let itlb_hit := (itlb0Hit ||| (itlb1Hit ||| (itlb2Hit ||| itlb3Hit)))
  let itlb_miss := ((~~~itlb_hit) &&& itlb_need_translate)
  let itlb_stall := ((~~~ifetchFaultPending) &&& itlb_miss)
  let itlb_phys_addr := (Signal.mux (Signal.mux itlb0Hit tlb0Mega (Signal.mux itlb1Hit tlb1Mega (Signal.mux itlb2Hit tlb2Mega (itlb3Hit &&& tlb3Mega)))) (((· ++ ·) <$> VdfgTmp_h184f0194__0 <*> (Signal.pure 0#12)) + ((BitVec.zeroExtend 32) <$> ((BitVec.extractLsb' 0 22) <$> fetchPC))) ((· ++ ·) <$> VdfgTmp_h184f0194__0 <*> ((BitVec.extractLsb' 0 12) <$> fetchPC)))
  let dMMURedirect := (VdfgTmp_h88d03c83__0 &&& isMMUDone)
  let stall := ((idex_memRead &&& ((~~~((Signal.pure 0#5) === idex_rd)) &&& ((idex_rd === id_rs1) ||| (idex_rd === id_rs2)))) ||| (((~~~(idex_isAMO &&& (((Signal.pure 2#5) === idex_amoOp) ||| ((Signal.pure 3#5) === idex_amoOp)))) &&& idex_isAMO) ||| (pendingWriteEn ||| (((~~~(isMMUIdle ||| (isMMUDone ||| isMMUFault))) &&& VdfgTmp_h88d03c83__0) ||| itlb_stall))))
  let id_regWrite := (id_isALUrr ||| (id_isALUimm ||| (id_isLoad ||| (id_isLUI ||| (id_isAUIPC ||| (id_isJAL ||| (id_isJALR ||| (id_isAMO ||| id_isCsr))))))))
  let dTLBMiss := (VdfgTmp_h88d03c83__0 &&& ((idex_memRead ||| idex_memWrite) &&& ((~~~anyTLBHit) &&& (isMMUIdle &&& ptwIsIdle))))
  let wb_data :=
    hw_cond exwb_alu
    | exwb_isSC => (Signal.pure 0#32)
    | exwb_isCsr => exwb_csrRdata
    | exwb_jump => exwb_pc4
    | exwb_m2r => (Signal.mux exwb_m2r (Signal.mux (isCLINT_wb ||| (isUART_wb ||| is_mmio_wb)) busRdataRaw (Signal.mux ((Signal.pure 0#3) === exwb_funct3) ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte)) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 7) <$> selByte))) <*> selByte) (Signal.mux ((Signal.pure 1#3) === exwb_funct3) ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((· ++ ·) <$> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf)) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> ((fun b => if b then 1#1 else 0#1) <$> ((·.getLsbD 15) <$> selHalf))) <*> selHalf) (Signal.mux ((Signal.pure 4#3) === exwb_funct3) ((BitVec.zeroExtend 32) <$> selByte) (Signal.mux ((Signal.pure 5#3) === exwb_funct3) ((BitVec.zeroExtend 32) <$> selHalf) busRdataRaw))))) busRdataRaw)
  let ifetchPageFault := (VdfgTmp_h88d03c83__0 &&& ifetchFaultPending)
  let pageFault := (VdfgTmp_h88d03c83__0 &&& isMMUFault)
  let VdfgExtracted_ha2592bfb__0 :=
    hw_cond (Signal.pure 0#3)
    | isMMUIdle => (Signal.mux dTLBMiss (Signal.pure 2#3) (Signal.pure 0#3))
    | ((Signal.pure 2#3) === mmuState) => (Signal.mux tlbFill (Signal.pure 3#3) (Signal.mux ptwIsFault (Signal.pure 4#3) (Signal.pure 2#3)))
  let byte1_wdata := (Signal.mux pendingWriteEn ((BitVec.extractLsb' 8 8) <$> pendingWriteData) byte1_wdata_ex)
  let byte3_wdata :=
    hw_cond byte1_wdata_ex
    | pendingWriteEn => ((BitVec.extractLsb' 24 8) <$> pendingWriteData)
    | isSW => ((BitVec.extractLsb' 24 8) <$> ex_rs2_approx)
  let VdfgTmp_h449091ff__0 :=
    hw_cond (Signal.pure 0#32)
    | idex_isEcall => (Signal.mux ((Signal.pure 0#2) === privMode) (Signal.pure 8#32) (Signal.mux ((Signal.pure 1#2) === privMode) (Signal.pure 9#32) (Signal.pure 11#32)))
    | pageFault => (Signal.mux (pageFault &&& dMissIsStore) (Signal.pure 15#32) (Signal.pure 13#32))
    | timerIntEnabled => (Signal.pure 2147483655#32)
    | swIntEnabled => (Signal.pure 2147483651#32)
  let VdfgTmp_h806edf84__0 := (~~~dTLBMiss)
  let ifetchTranslated := (itlb_need_translate &&& itlb_hit)
  let ifetch_word_addr := (Signal.mux ifetchTranslated ((BitVec.extractLsb' 2 23) <$> itlb_phys_addr) ((BitVec.extractLsb' 2 23) <$> fetchPC))
  let useTranslatedAddr := (VdfgTmp_h88d03c83__0 &&& anyTLBHit)
  let causeIdx := (Signal.mux ifetchPageFault (Signal.pure 12#5) ((BitVec.extractLsb' 0 5) <$> VdfgTmp_h449091ff__0))
  let ifid_pc_next := (Signal.mux stall ifid_pc fetchPC)
  let ifid_pc4_next := (Signal.mux stall ifid_pc4 fetchPCPlus4)
  let exwb_regW_next := ((~~~(dTLBMiss ||| holdEX)) &&& idex_regWrite)
  let prev_wb_data_next := wb_data
  let prevStoreEn_next := ((~~~(dTLBMiss ||| holdEX)) &&& idex_memWrite)
  let mmuState_next := VdfgExtracted_ha2592bfb__0
  let ifetchFaultPending_next := ((~~~ifetchPageFault) &&& ((~~~bypassMMU) &&& ((ptwIsFault &&& ptwIsIfetch) ||| ifetchFaultPending)))
  let trap_out := (idex_isEcall ||| (pageFault ||| (timerIntEnabled ||| (swIntEnabled ||| ifetchPageFault))))
  let trap_cause_out := (Signal.mux ifetchPageFault (Signal.pure 12#32) VdfgTmp_h449091ff__0)
  let itlb_ptw_req := (itlb_miss &&& (ptwIsIdle &&& (VdfgTmp_h806edf84__0 &&& isMMUIdle)))
  let ex_rs1 := (Signal.mux fwd_rs1_match wb_data idex_rs1Val)
  let ex_rs2 := (Signal.mux fwd_rs2_match wb_data idex_rs2Val)
  let flush := ((branchCond &&& idex_branch) ||| (idex_jump ||| (trap_out ||| (idex_isMret ||| (idex_isSret ||| (idex_isSFenceVMA ||| dMMURedirect))))))
  let jumpTarget := (Signal.mux idex_isJalr ((Signal.pure 4294967294#32) &&& (ex_rs1 + idex_imm)) (idex_imm + idex_pc))
  let flushOrDelay := (flush ||| flushDelay)
  let squash := (((~~~pendingWriteEn) &&& stall) ||| flushOrDelay)
  let id_rs1Val :=
    hw_cond (Signal.memoryComboRead wb_addr wb_data wb_en id_rs1)
    | ((Signal.pure 0#5) === id_rs1) => (Signal.pure 0#32)
    | (wb_en &&& (exwb_rd === id_rs1)) => wb_data
    | (prev_wb_en &&& (prev_wb_addr === id_rs1)) => prev_wb_data
  let id_rs2Val :=
    hw_cond (Signal.memoryComboRead wb_addr wb_data wb_en id_rs2)
    | ((Signal.pure 0#5) === id_rs2) => (Signal.pure 0#32)
    | (wb_en &&& (exwb_rd === id_rs2)) => wb_data
    | (prev_wb_en &&& (prev_wb_addr === id_rs2)) => prev_wb_data
  let effectiveAddr := (Signal.mux useTranslatedAddr dPhysAddr alu_result_approx)
  let VdfgExtracted_h60ca4114__0 := (Signal.mux useTranslatedAddr dPhysAddr alu_result)
  let clintOffset := ((BitVec.extractLsb' 0 16) <$> effectiveAddr)
  let trapToS := (trap_out &&& ((Signal.mux ((~~~ifetchPageFault) &&& ((·.getLsbD 31) <$> VdfgTmp_h449091ff__0)) ((fun x i => x.getLsbD i.toNat) <$> midelegReg <*> causeIdx) ((fun x i => x.getLsbD i.toNat) <$> medelegReg <*> causeIdx)) &&& ((BitVec.ule · ·) <$> privMode <*> (Signal.pure 1#2))))
  let mmioOffset_ex := ((BitVec.extractLsb' 0 4) <$> effectiveAddr)
  let isUART_ex := ((Signal.pure 16#8) === ((BitVec.extractLsb' 24 8) <$> effectiveAddr))
  let VdfgExtracted_h8a316ac8__0 :=
    hw_cond (Signal.pure 0#3)
    | ptwIsIdle => (Signal.mux (dTLBMiss ||| itlb_ptw_req) (Signal.pure 1#3) (Signal.pure 0#3))
    | ptwIsL1Req => (Signal.pure 2#3)
    | ptwIsL1Wait => (Signal.mux dmemPteValid (Signal.mux dmemPteIsLeaf (Signal.pure 5#3) (Signal.pure 3#3)) (Signal.pure 6#3))
    | ptwIsL0Req => (Signal.pure 4#3)
    | ptwIsL0Wait => (Signal.mux dmemPteValid (Signal.mux dmemPteIsLeaf (Signal.pure 5#3) (Signal.pure 6#3)) (Signal.pure 6#3))
  let dmem_addr :=
    hw_cond ((BitVec.extractLsb' 2 23) <$> effectiveAddr)
    | (ptwIsL1Req ||| ptwIsL0Req) => ((BitVec.extractLsb' 2 23) <$> (Signal.mux ptwIsL1Req (((fun x y => x <<< y.toNat) <$> satpReg <*> (Signal.pure 12#32)) + ((BitVec.zeroExtend 32) <$> ((· ++ ·) <$> ((BitVec.extractLsb' 22 10) <$> ptwVaddr) <*> (Signal.pure 0#2)))) (((· ++ ·) <$> ((BitVec.extractLsb' 10 20) <$> ptwPte) <*> (Signal.pure 0#12)) + ((BitVec.zeroExtend 32) <$> ((· ++ ·) <$> ((BitVec.extractLsb' 12 10) <$> ptwVaddr) <*> (Signal.pure 0#2))))))
    | pendingWriteEn => ((BitVec.extractLsb' 2 23) <$> pendingWriteAddr)
  let isCLINT_ex := ((Signal.pure 512#16) === ((BitVec.extractLsb' 16 16) <$> effectiveAddr))
  let is_mmio_ex := ((·.getLsbD 30) <$> effectiveAddr)
  let dmem_we := ((idex_memWrite &&& (VdfgTmp_h806edf84__0 &&& (~~~(isCLINT_ex ||| (is_mmio_ex ||| isUART_ex))))) ||| pendingWriteEn)
  let VdfgTmp_hbd568130__0 := (~~~squash)
  let flushDelay_next := flush
  let idex_aluOp_next :=
    hw_cond id_aluOp
    | holdEX => idex_aluOp
    | squash => (Signal.pure 0#4)
  let idex_regWrite_next := (Signal.mux holdEX idex_regWrite ((~~~squash) &&& id_regWrite))
  let idex_memRead_next := (Signal.mux holdEX idex_memRead ((~~~squash) &&& id_memRead))
  let idex_memWrite_next := (Signal.mux holdEX idex_memWrite ((~~~squash) &&& id_memWrite))
  let idex_memToReg_next := (Signal.mux holdEX idex_memToReg ((~~~squash) &&& id_memRead))
  let idex_branch_next := (Signal.mux holdEX idex_branch ((~~~squash) &&& id_isBranch))
  let idex_jump_next := (Signal.mux holdEX idex_jump ((~~~squash) &&& id_jump))
  let idex_auipc_next := (Signal.mux holdEX idex_auipc ((~~~squash) &&& id_auipc))
  let idex_aluSrcB_next := (Signal.mux holdEX idex_aluSrcB ((~~~squash) &&& id_aluSrcB))
  let idex_isJalr_next := (Signal.mux holdEX idex_isJalr ((~~~squash) &&& id_isJALR))
  let idex_isCsr_next := (Signal.mux holdEX idex_isCsr ((~~~squash) &&& id_isCsr))
  let idex_isEcall_next := (Signal.mux holdEX idex_isEcall ((~~~squash) &&& id_isEcall))
  let idex_isMret_next := (Signal.mux holdEX idex_isMret ((~~~squash) &&& id_isMret))
  let idex_rs1Val_next := (Signal.mux holdEX idex_rs1Val id_rs1Val)
  let idex_rs2Val_next := (Signal.mux holdEX idex_rs2Val id_rs2Val)
  let idex_rd_next :=
    hw_cond id_rd
    | holdEX => idex_rd
    | squash => (Signal.pure 0#5)
  let exwb_physAddr_next := (Signal.mux holdEX exwb_physAddr effectiveAddr)
  let prevStoreAddr_next := VdfgExtracted_h60ca4114__0
  let prevStoreData_next := ex_rs2
  let sepcReg_next :=
    hw_cond sepcReg
    | trapToS => (Signal.mux ifetchPageFault fetchPC (Signal.mux pageFault dMissPC idex_pc))
    | (idex_isCsr &&& ((Signal.pure 321#12) === idex_csrAddr)) => sepcNewCSR
  let scauseReg_next :=
    hw_cond scauseReg
    | trapToS => trap_cause_out
    | (idex_isCsr &&& ((Signal.pure 322#12) === idex_csrAddr)) => scauseNewCSR
  let stvalReg_next :=
    hw_cond stvalReg
    | trapToS => (Signal.mux ifetchPageFault fetchPC (Signal.mux pageFault dMissVaddr (Signal.pure 0#32)))
    | (idex_isCsr &&& ((Signal.pure 323#12) === idex_csrAddr)) => stvalNewCSR
  let uartLCR_next := (Signal.mux ((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 3#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) VdfgExtracted_hff53a329__0 uartLCR)
  let uartIER_next := (Signal.mux (((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 1#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) &&& (~~~((·.getLsbD 7) <$> uartLCR))) VdfgExtracted_hff53a329__0 uartIER)
  let uartMCR_next := (Signal.mux ((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 4#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) VdfgExtracted_hff53a329__0 uartMCR)
  let uartSCR_next := (Signal.mux ((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 7#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) VdfgExtracted_hff53a329__0 uartSCR)
  let uartDLL_next := (Signal.mux (((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 0#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) &&& ((·.getLsbD 7) <$> uartLCR)) VdfgExtracted_hff53a329__0 uartDLL)
  let uartDLM_next := (Signal.mux (((idex_memWrite &&& isUART_ex) &&& ((Signal.pure 1#3) === ((BitVec.extractLsb' 0 3) <$> alu_result_approx))) &&& ((·.getLsbD 7) <$> uartLCR)) VdfgExtracted_hff53a329__0 uartDLM)
  let idex_isMext_next := (Signal.mux holdEX idex_isMext ((~~~squash) &&& id_isMext))
  let idex_isAMO_next := (Signal.mux holdEX idex_isAMO ((~~~squash) &&& id_isAMO))
  let idex_amoOp_next :=
    hw_cond id_amoOp
    | holdEX => idex_amoOp
    | squash => (Signal.pure 0#5)
  let ptwVaddr_next :=
    hw_cond ptwVaddr
    | (ptwIsIdle &&& dTLBMiss) => alu_result_approx
    | (ptwIsIdle &&& itlb_ptw_req) => fetchPC
  let ptwState_next := VdfgExtracted_h8a316ac8__0
  let ptwIsIfetch_next := (((ptwIsIdle &&& itlb_ptw_req) &&& (~~~dTLBMiss)) ||| ((~~~(ptwIsIdle &&& dTLBMiss)) &&& ((~~~ptwIsIdle) &&& ptwIsIfetch)))
  let trap_target := (Signal.mux trapToS ((Signal.pure 4294967292#32) &&& stvecReg) ((Signal.pure 4294967292#32) &&& mtvecReg))
  let clintWE := (idex_memWrite &&& isCLINT_ex)
  let VdfgExtracted_h9b0cffa3__0 := (Signal.mux (clintWE &&& ((Signal.pure 49144#16) === clintOffset)) ex_rs2_approx mtimeLoInc)
  let VdfgExtracted_h53a59808__0 := (Signal.mux (clintWE &&& ((Signal.pure 49148#16) === clintOffset)) ex_rs2_approx (mtimeHiReg + ((BitVec.zeroExtend 32) <$> ((fun b => if b then 1#1 else 0#1) <$> ((Signal.pure 0#32) === mtimeLoInc)))))
  let mstatusTrapVal := (Signal.mux trapToS (Signal.mux ((·.getLsbD 0) <$> privMode) ((Signal.pure 256#32) ||| msSetSPIE) ((Signal.pure 4294967039#32) &&& msSetSPIE)) (((Signal.pure 4294961151#32) &&& (Signal.mux mstatusMIE ((Signal.pure 128#32) ||| ((Signal.pure 4294967287#32) &&& mstatusReg)) ((Signal.pure 4294967159#32) &&& mstatusReg))) ||| ((fun x y => x <<< y.toNat) <$> ((BitVec.zeroExtend 32) <$> privMode) <*> (Signal.pure 11#32))))
  let trapToM := ((~~~trapToS) &&& trap_out)
  let mmioWE := (idex_memWrite &&& is_mmio_ex)
  let VdfgExtracted_h6efb24d2__0 := (VdfgTmp_hbd568130__0 &&& (VdfgTmp_he9f65336__0 &&& ((Signal.pure 258#12) === id_csrAddr)))
  let VdfgExtracted_h6d025057__0 := (VdfgTmp_hbd568130__0 &&& (VdfgTmp_he9f65336__0 &&& ((Signal.pure 9#7) === id_funct7)))
  let byte0_we := ((dmem_we &&& (VdfgTmp_h032360d3__0 ||| (isSB &&& ((Signal.pure 0#2) === storeByteOff)))) ||| pendingWriteEn)
  let byte1_we := ((dmem_we &&& (VdfgTmp_h032360d3__0 ||| (isSB &&& ((Signal.pure 1#2) === storeByteOff)))) ||| pendingWriteEn)
  let byte2_we := ((dmem_we &&& (VdfgTmp_hb6af2209__0 ||| (isSB &&& ((Signal.pure 2#2) === storeByteOff)))) ||| pendingWriteEn)
  let byte3_we := ((dmem_we &&& (VdfgTmp_hb6af2209__0 ||| (isSB &&& ((Signal.pure 3#2) === storeByteOff)))) ||| pendingWriteEn)
  let pcReg_next :=
    hw_cond pcPlus4
    | trap_out => trap_target
    | idex_isMret => mret_target
    | idex_isSret => sret_target
    | dMMURedirect => dMissPC
    | idex_isSFenceVMA => idex_pc4
    | flush => jumpTarget
    | stall => pcReg
  let fetchPC_next :=
    hw_cond pcReg
    | flush => (Signal.mux trap_out trap_target (Signal.mux idex_isMret mret_target (Signal.mux idex_isSret sret_target (Signal.mux dMMURedirect dMissPC (Signal.mux idex_isSFenceVMA idex_pc4 (Signal.mux flush jumpTarget (Signal.mux stall pcReg pcPlus4)))))))
    | stall => fetchPC
  let msipReg_next := (Signal.mux (clintWE &&& ((Signal.pure 0#16) === clintOffset)) ex_rs2_approx msipReg)
  let mtimeLoReg_next := VdfgExtracted_h9b0cffa3__0
  let mtimeHiReg_next := VdfgExtracted_h53a59808__0
  let mtimecmpLoReg_next := (Signal.mux (clintWE &&& ((Signal.pure 16384#16) === clintOffset)) ex_rs2_approx mtimecmpLoReg)
  let mtimecmpHiReg_next := (Signal.mux (clintWE &&& ((Signal.pure 16388#16) === clintOffset)) ex_rs2_approx mtimecmpHiReg)
  let mstatusReg_next :=
    hw_cond mstatusReg
    | trap_out => mstatusTrapVal
    | idex_isMret => mstatusMretVal
    | idex_isSret => mstatusSretVal
    | sstatusWriteActive => sstatus_wdata_out
    | (idex_isCsr &&& ((Signal.pure 768#12) === idex_csrAddr)) => mstatusNewCSR
  let mepcReg_next :=
    hw_cond mepcReg
    | trapToM => (Signal.mux ifetchPageFault fetchPC (Signal.mux pageFault dMissPC idex_pc))
    | (idex_isCsr &&& ((Signal.pure 833#12) === idex_csrAddr)) => mepcNewCSR
  let mcauseReg_next :=
    hw_cond mcauseReg
    | trapToM => trap_cause_out
    | (idex_isCsr &&& ((Signal.pure 834#12) === idex_csrAddr)) => mcauseNewCSR
  let mtvalReg_next :=
    hw_cond mtvalReg
    | trapToM => (Signal.mux ifetchPageFault fetchPC (Signal.mux pageFault dMissVaddr (Signal.pure 0#32)))
    | (idex_isCsr &&& ((Signal.pure 835#12) === idex_csrAddr)) => mtvalNewCSR
  let privMode_next :=
    hw_cond privMode
    | trapToM => (Signal.pure 3#2)
    | trapToS => (Signal.pure 1#2)
    | idex_isMret => mpp
    | idex_isSret => sretPriv
  let aiStatusReg_next := (Signal.mux (mmioWE &&& ((Signal.pure 0#4) === mmioOffset_ex)) ex_rs2_approx aiStatusReg)
  let aiInputReg_next := (Signal.mux (mmioWE &&& ((Signal.pure 4#4) === mmioOffset_ex)) ex_rs2_approx aiInputReg)
  let idex_isSret_next := VdfgExtracted_h6efb24d2__0
  let idex_isSFenceVMA_next := VdfgExtracted_h6d025057__0
  let final_imem_rdata := (Signal.mux (Signal.mux ifetchTranslated ((·.getLsbD 31) <$> itlb_phys_addr) VdfgTmp_h8386f12b__0) ((· ++ ·) <$> (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte3_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte3_we) byte3_wdata ((BitVec.extractLsb' 24 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte3_we)) ifetch_word_addr) <*> ((· ++ ·) <$> (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte2_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte2_we) byte2_wdata ((BitVec.extractLsb' 16 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte2_we)) ifetch_word_addr) <*> ((· ++ ·) <$> (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte1_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte1_we) byte1_wdata ((BitVec.extractLsb' 8 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte1_we)) ifetch_word_addr) <*> (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte0_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte0_we) byte0_wdata ((BitVec.extractLsb' 0 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte0_we)) ifetch_word_addr)))) (Signal.memoryComboRead imem_wr_addr imem_wr_data imem_wr_en ((BitVec.extractLsb' 2 12) <$> fetchPC)))
  let ifid_inst_next :=
    hw_cond final_imem_rdata
    | flushOrDelay => (Signal.pure 19#32)
    | stall => ifid_inst
  -- next-state values (non-blocking updates, one per register)
  -- init inferred from sync-reset branch
  let pcReg_next_2 := (Signal.mux rst (Signal.pure 0#32) pcReg_next)
  -- init inferred from sync-reset branch
  let fetchPC_next_2 := (Signal.mux rst (Signal.pure 0#32) fetchPC_next)
  -- init inferred from sync-reset branch
  let flushDelay_next_2 := (Signal.mux rst (Signal.pure false) flushDelay_next)
  -- init inferred from sync-reset branch
  let ifid_inst_next_2 := (Signal.mux rst (Signal.pure 19#32) ifid_inst_next)
  -- init inferred from sync-reset branch
  let ifid_pc_next_2 := (Signal.mux rst (Signal.pure 0#32) ifid_pc_next)
  -- init inferred from sync-reset branch
  let ifid_pc4_next_2 := (Signal.mux rst (Signal.pure 0#32) ifid_pc4_next)
  -- init inferred from sync-reset branch
  let idex_aluOp_next_2 := (Signal.mux rst (Signal.pure 0#4) idex_aluOp_next)
  -- init inferred from sync-reset branch
  let idex_regWrite_next_2 := (Signal.mux rst (Signal.pure false) idex_regWrite_next)
  -- init inferred from sync-reset branch
  let idex_memRead_next_2 := (Signal.mux rst (Signal.pure false) idex_memRead_next)
  -- init inferred from sync-reset branch
  let idex_memWrite_next_2 := (Signal.mux rst (Signal.pure false) idex_memWrite_next)
  -- init inferred from sync-reset branch
  let idex_memToReg_next_2 := (Signal.mux rst (Signal.pure false) idex_memToReg_next)
  -- init inferred from sync-reset branch
  let idex_branch_next_2 := (Signal.mux rst (Signal.pure false) idex_branch_next)
  -- init inferred from sync-reset branch
  let idex_jump_next_2 := (Signal.mux rst (Signal.pure false) idex_jump_next)
  -- init inferred from sync-reset branch
  let idex_auipc_next_2 := (Signal.mux rst (Signal.pure false) idex_auipc_next)
  -- init inferred from sync-reset branch
  let idex_aluSrcB_next_2 := (Signal.mux rst (Signal.pure false) idex_aluSrcB_next)
  -- init inferred from sync-reset branch
  let idex_isJalr_next_2 := (Signal.mux rst (Signal.pure false) idex_isJalr_next)
  -- init inferred from sync-reset branch
  let idex_isCsr_next_2 := (Signal.mux rst (Signal.pure false) idex_isCsr_next)
  -- init inferred from sync-reset branch
  let idex_isEcall_next_2 := (Signal.mux rst (Signal.pure false) idex_isEcall_next)
  -- init inferred from sync-reset branch
  let idex_isMret_next_2 := (Signal.mux rst (Signal.pure false) idex_isMret_next)
  -- init inferred from sync-reset branch
  let idex_rs1Val_next_2 := (Signal.mux rst (Signal.pure 0#32) idex_rs1Val_next)
  -- init inferred from sync-reset branch
  let idex_rs2Val_next_2 := (Signal.mux rst (Signal.pure 0#32) idex_rs2Val_next)
  -- init inferred from sync-reset branch
  let idex_imm_next_2 := (Signal.mux rst (Signal.pure 0#32) idex_imm_next)
  -- init inferred from sync-reset branch
  let idex_rd_next_2 := (Signal.mux rst (Signal.pure 0#5) idex_rd_next)
  -- init inferred from sync-reset branch
  let idex_rs1Idx_next_2 := (Signal.mux rst (Signal.pure 0#5) idex_rs1Idx_next)
  -- init inferred from sync-reset branch
  let idex_rs2Idx_next_2 := (Signal.mux rst (Signal.pure 0#5) idex_rs2Idx_next)
  -- init inferred from sync-reset branch
  let idex_funct3_next_2 := (Signal.mux rst (Signal.pure 0#3) idex_funct3_next)
  -- init inferred from sync-reset branch
  let idex_pc_next_2 := (Signal.mux rst (Signal.pure 0#32) idex_pc_next)
  -- init inferred from sync-reset branch
  let idex_pc4_next_2 := (Signal.mux rst (Signal.pure 0#32) idex_pc4_next)
  -- init inferred from sync-reset branch
  let idex_csrAddr_next_2 := (Signal.mux rst (Signal.pure 0#12) idex_csrAddr_next)
  -- init inferred from sync-reset branch
  let idex_csrFunct3_next_2 := (Signal.mux rst (Signal.pure 0#3) idex_csrFunct3_next)
  -- init inferred from sync-reset branch
  let exwb_alu_next_2 := (Signal.mux rst (Signal.pure 0#32) exwb_alu_next)
  -- init inferred from sync-reset branch
  let exwb_physAddr_next_2 := (Signal.mux rst (Signal.pure 0#32) exwb_physAddr_next)
  -- init inferred from sync-reset branch
  let exwb_rd_next_2 := (Signal.mux rst (Signal.pure 0#5) exwb_rd_next)
  -- init inferred from sync-reset branch
  let exwb_regW_next_2 := (Signal.mux rst (Signal.pure false) exwb_regW_next)
  -- init inferred from sync-reset branch
  let exwb_m2r_next_2 := (Signal.mux rst (Signal.pure false) exwb_m2r_next)
  -- init inferred from sync-reset branch
  let exwb_pc4_next_2 := (Signal.mux rst (Signal.pure 0#32) exwb_pc4_next)
  -- init inferred from sync-reset branch
  let exwb_jump_next_2 := (Signal.mux rst (Signal.pure false) exwb_jump_next)
  -- init inferred from sync-reset branch
  let exwb_isCsr_next_2 := (Signal.mux rst (Signal.pure false) exwb_isCsr_next)
  -- init inferred from sync-reset branch
  let exwb_csrRdata_next_2 := (Signal.mux rst (Signal.pure 0#32) exwb_csrRdata_next)
  -- init inferred from sync-reset branch
  let prev_wb_addr_next_2 := (Signal.mux rst (Signal.pure 0#5) prev_wb_addr_next)
  -- init inferred from sync-reset branch
  let prev_wb_data_next_2 := (Signal.mux rst (Signal.pure 0#32) prev_wb_data_next)
  -- init inferred from sync-reset branch
  let prev_wb_en_next_2 := (Signal.mux rst (Signal.pure false) prev_wb_en_next)
  -- init inferred from sync-reset branch
  let prevStoreAddr_next_2 := (Signal.mux rst (Signal.pure 0#32) prevStoreAddr_next)
  -- init inferred from sync-reset branch
  let prevStoreData_next_2 := (Signal.mux rst (Signal.pure 0#32) prevStoreData_next)
  -- init inferred from sync-reset branch
  let prevStoreEn_next_2 := (Signal.mux rst (Signal.pure false) prevStoreEn_next)
  -- init inferred from sync-reset branch
  let msipReg_next_2 := (Signal.mux rst (Signal.pure 0#32) msipReg_next)
  -- init inferred from sync-reset branch
  let mtimeLoReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mtimeLoReg_next)
  -- init inferred from sync-reset branch
  let mtimeHiReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mtimeHiReg_next)
  -- init inferred from sync-reset branch
  let mtimecmpLoReg_next_2 := (Signal.mux rst (Signal.pure 4294967295#32) mtimecmpLoReg_next)
  -- init inferred from sync-reset branch
  let mtimecmpHiReg_next_2 := (Signal.mux rst (Signal.pure 4294967295#32) mtimecmpHiReg_next)
  -- init inferred from sync-reset branch
  let mstatusReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mstatusReg_next)
  -- init inferred from sync-reset branch
  let mieReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mieReg_next)
  -- init inferred from sync-reset branch
  let mtvecReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mtvecReg_next)
  -- init inferred from sync-reset branch
  let mscratchReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mscratchReg_next)
  -- init inferred from sync-reset branch
  let mepcReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mepcReg_next)
  -- init inferred from sync-reset branch
  let mcauseReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mcauseReg_next)
  -- init inferred from sync-reset branch
  let mtvalReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mtvalReg_next)
  -- init inferred from sync-reset branch
  let aiStatusReg_next_2 := (Signal.mux rst (Signal.pure 0#32) aiStatusReg_next)
  -- init inferred from sync-reset branch
  let aiInputReg_next_2 := (Signal.mux rst (Signal.pure 0#32) aiInputReg_next)
  -- init inferred from sync-reset branch
  let exwb_funct3_next_2 := (Signal.mux rst (Signal.pure 0#3) exwb_funct3_next)
  -- init inferred from sync-reset branch
  let idex_isMext_next_2 := (Signal.mux rst (Signal.pure false) idex_isMext_next)
  -- init inferred from sync-reset branch
  let reservationValid_next_2 := (Signal.mux rst (Signal.pure false) reservationValid_next)
  -- init inferred from sync-reset branch
  let reservationAddr_next_2 := (Signal.mux rst (Signal.pure 0#32) reservationAddr_next)
  -- init inferred from sync-reset branch
  let idex_isAMO_next_2 := (Signal.mux rst (Signal.pure false) idex_isAMO_next)
  -- init inferred from sync-reset branch
  let idex_amoOp_next_2 := (Signal.mux rst (Signal.pure 0#5) idex_amoOp_next)
  -- init inferred from sync-reset branch
  let exwb_isAMO_next_2 := (Signal.mux rst (Signal.pure false) exwb_isAMO_next)
  -- init inferred from sync-reset branch
  let exwb_amoOp_next_2 := (Signal.mux rst (Signal.pure 0#5) exwb_amoOp_next)
  -- init inferred from sync-reset branch
  let pendingWriteEn_next_2 := (Signal.mux rst (Signal.pure false) pendingWriteEn_next)
  -- init inferred from sync-reset branch
  let pendingWriteAddr_next_2 := (Signal.mux rst (Signal.pure 0#32) pendingWriteAddr_next)
  -- init inferred from sync-reset branch
  let pendingWriteData_next_2 := (Signal.mux rst (Signal.pure 0#32) pendingWriteData_next)
  -- init inferred from sync-reset branch
  let cycle_count_next := (Signal.mux rst (Signal.pure 0#64) ((Signal.pure 1#64) + cycle_count))
  -- init inferred from sync-reset branch
  let privMode_next_2 := (Signal.mux rst (Signal.pure 3#2) privMode_next)
  -- init inferred from sync-reset branch
  let sieReg_next_2 := (Signal.mux rst (Signal.pure 0#32) sieReg_next)
  -- init inferred from sync-reset branch
  let stvecReg_next_2 := (Signal.mux rst (Signal.pure 0#32) stvecReg_next)
  -- init inferred from sync-reset branch
  let sscratchReg_next_2 := (Signal.mux rst (Signal.pure 0#32) sscratchReg_next)
  -- init inferred from sync-reset branch
  let sepcReg_next_2 := (Signal.mux rst (Signal.pure 0#32) sepcReg_next)
  -- init inferred from sync-reset branch
  let scauseReg_next_2 := (Signal.mux rst (Signal.pure 0#32) scauseReg_next)
  -- init inferred from sync-reset branch
  let stvalReg_next_2 := (Signal.mux rst (Signal.pure 0#32) stvalReg_next)
  -- init inferred from sync-reset branch
  let satpReg_next_2 := (Signal.mux rst (Signal.pure 0#32) satpReg_next)
  -- init inferred from sync-reset branch
  let medelegReg_next_2 := (Signal.mux rst (Signal.pure 0#32) medelegReg_next)
  -- init inferred from sync-reset branch
  let midelegReg_next_2 := (Signal.mux rst (Signal.pure 0#32) midelegReg_next)
  -- init inferred from sync-reset branch
  let mcounterenReg_next_2 := (Signal.mux rst (Signal.pure 0#32) mcounterenReg_next)
  -- init inferred from sync-reset branch
  let scounterenReg_next_2 := (Signal.mux rst (Signal.pure 0#32) scounterenReg_next)
  -- init inferred from sync-reset branch
  let mmuState_next_2 := (Signal.mux rst (Signal.pure 0#3) mmuState_next)
  -- init inferred from sync-reset branch
  let ptwState_next_2 := (Signal.mux rst (Signal.pure 0#3) ptwState_next)
  -- init inferred from sync-reset branch
  let ptwVaddr_next_2 := (Signal.mux rst (Signal.pure 0#32) ptwVaddr_next)
  -- init inferred from sync-reset branch
  let ptwPte_next_2 := (Signal.mux rst (Signal.pure 0#32) ptwPte_next)
  -- init inferred from sync-reset branch
  let ptwMega_next_2 := (Signal.mux rst (Signal.pure false) ptwMega_next)
  -- init inferred from sync-reset branch
  let replPtr_next_2 := (Signal.mux rst (Signal.pure 0#2) replPtr_next)
  -- init inferred from sync-reset branch
  let tlb0Valid_next_2 := (Signal.mux rst (Signal.pure false) tlb0Valid_next)
  -- init inferred from sync-reset branch
  let tlb0VPN_next_2 := (Signal.mux rst (Signal.pure 0#20) tlb0VPN_next)
  -- init inferred from sync-reset branch
  let tlb0PPN_next_2 := (Signal.mux rst (Signal.pure 0#22) tlb0PPN_next)
  -- init inferred from sync-reset branch
  let tlb0Flags_next_2 := (Signal.mux rst (Signal.pure 0#8) tlb0Flags_next)
  -- init inferred from sync-reset branch
  let tlb0Mega_next_2 := (Signal.mux rst (Signal.pure false) tlb0Mega_next)
  -- init inferred from sync-reset branch
  let tlb1Valid_next_2 := (Signal.mux rst (Signal.pure false) tlb1Valid_next)
  -- init inferred from sync-reset branch
  let tlb1VPN_next_2 := (Signal.mux rst (Signal.pure 0#20) tlb1VPN_next)
  -- init inferred from sync-reset branch
  let tlb1PPN_next_2 := (Signal.mux rst (Signal.pure 0#22) tlb1PPN_next)
  -- init inferred from sync-reset branch
  let tlb1Flags_next_2 := (Signal.mux rst (Signal.pure 0#8) tlb1Flags_next)
  -- init inferred from sync-reset branch
  let tlb1Mega_next_2 := (Signal.mux rst (Signal.pure false) tlb1Mega_next)
  -- init inferred from sync-reset branch
  let tlb2Valid_next_2 := (Signal.mux rst (Signal.pure false) tlb2Valid_next)
  -- init inferred from sync-reset branch
  let tlb2VPN_next_2 := (Signal.mux rst (Signal.pure 0#20) tlb2VPN_next)
  -- init inferred from sync-reset branch
  let tlb2PPN_next_2 := (Signal.mux rst (Signal.pure 0#22) tlb2PPN_next)
  -- init inferred from sync-reset branch
  let tlb2Flags_next_2 := (Signal.mux rst (Signal.pure 0#8) tlb2Flags_next)
  -- init inferred from sync-reset branch
  let tlb2Mega_next_2 := (Signal.mux rst (Signal.pure false) tlb2Mega_next)
  -- init inferred from sync-reset branch
  let tlb3Valid_next_2 := (Signal.mux rst (Signal.pure false) tlb3Valid_next)
  -- init inferred from sync-reset branch
  let tlb3VPN_next_2 := (Signal.mux rst (Signal.pure 0#20) tlb3VPN_next)
  -- init inferred from sync-reset branch
  let tlb3PPN_next_2 := (Signal.mux rst (Signal.pure 0#22) tlb3PPN_next)
  -- init inferred from sync-reset branch
  let tlb3Flags_next_2 := (Signal.mux rst (Signal.pure 0#8) tlb3Flags_next)
  -- init inferred from sync-reset branch
  let tlb3Mega_next_2 := (Signal.mux rst (Signal.pure false) tlb3Mega_next)
  -- init inferred from sync-reset branch
  let ptwIsIfetch_next_2 := (Signal.mux rst (Signal.pure false) ptwIsIfetch_next)
  -- init inferred from sync-reset branch
  let ifetchFaultPending_next_2 := (Signal.mux rst (Signal.pure false) ifetchFaultPending_next)
  -- init inferred from sync-reset branch
  let dMissPC_next :=
    hw_cond dMissPC
    | rst => (Signal.pure 0#32)
    | dTLBMiss => idex_pc
  -- init inferred from sync-reset branch
  let dMissVaddr_next :=
    hw_cond dMissVaddr
    | rst => (Signal.pure 0#32)
    | dTLBMiss => alu_result_approx
  -- init inferred from sync-reset branch
  let dMissIsStore_next :=
    hw_cond dMissIsStore
    | rst => (Signal.pure false)
    | dTLBMiss => idex_memWrite
  -- init inferred from sync-reset branch
  let idex_isSret_next_2 := (Signal.mux rst (Signal.pure false) idex_isSret_next)
  -- init inferred from sync-reset branch
  let idex_isSFenceVMA_next_2 := (Signal.mux rst (Signal.pure false) idex_isSFenceVMA_next)
  -- init inferred from sync-reset branch
  let uartLCR_next_2 := (Signal.mux rst (Signal.pure 0#8) uartLCR_next)
  -- init inferred from sync-reset branch
  let uartIER_next_2 := (Signal.mux rst (Signal.pure 0#8) uartIER_next)
  -- init inferred from sync-reset branch
  let uartMCR_next_2 := (Signal.mux rst (Signal.pure 0#8) uartMCR_next)
  -- init inferred from sync-reset branch
  let uartSCR_next_2 := (Signal.mux rst (Signal.pure 0#8) uartSCR_next)
  -- init inferred from sync-reset branch
  let uartDLL_next_2 := (Signal.mux rst (Signal.pure 0#8) uartDLL_next)
  -- init inferred from sync-reset branch
  let uartDLM_next_2 := (Signal.mux rst (Signal.pure 0#8) uartDLM_next)
  -- init inferred from sync-reset branch
  let uartRxBuf_next_2 := (Signal.mux rst (Signal.pure 0#8) uartRxBuf_next)
  -- init inferred from sync-reset branch
  let uartRxReady_next_2 := (Signal.mux rst (Signal.pure false) uartRxReady_next)
  -- no declared init; defaulting to 0
  let dmem_b0_rdata_next := (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte0_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte0_we) byte0_wdata ((BitVec.extractLsb' 0 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte0_we)) dmem_addr)
  -- no declared init; defaulting to 0
  let dmem_b1_rdata_next := (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte1_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte1_we) byte1_wdata ((BitVec.extractLsb' 8 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte1_we)) dmem_addr)
  -- no declared init; defaulting to 0
  let dmem_b2_rdata_next := (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte2_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte2_we) byte2_wdata ((BitVec.extractLsb' 16 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte2_we)) dmem_addr)
  -- no declared init; defaulting to 0
  let dmem_b3_rdata_next := (Signal.memoryComboRead (Signal.mux ((~~~dmem_wr_en) &&& byte3_we) dmem_addr dmem_wr_addr) (Signal.mux ((~~~dmem_wr_en) &&& byte3_we) byte3_wdata ((BitVec.extractLsb' 24 8) <$> dmem_wr_data)) (dmem_wr_en ||| ((~~~dmem_wr_en) &&& byte3_we)) dmem_addr)
  let fv_rst_seen_next := (Signal.mux rst (Signal.pure true) fv_rst_seen)
  bundleAll! [
    Signal.register 0#32 pcReg_next_2,
    Signal.register 0#32 fetchPC_next_2,
    Signal.register false flushDelay_next_2,
    Signal.register 19#32 ifid_inst_next_2,
    Signal.register 0#32 ifid_pc_next_2,
    Signal.register 0#32 ifid_pc4_next_2,
    Signal.register 0#4 idex_aluOp_next_2,
    Signal.register false idex_regWrite_next_2,
    Signal.register false idex_memRead_next_2,
    Signal.register false idex_memWrite_next_2,
    Signal.register false idex_memToReg_next_2,
    Signal.register false idex_branch_next_2,
    Signal.register false idex_jump_next_2,
    Signal.register false idex_auipc_next_2,
    Signal.register false idex_aluSrcB_next_2,
    Signal.register false idex_isJalr_next_2,
    Signal.register false idex_isCsr_next_2,
    Signal.register false idex_isEcall_next_2,
    Signal.register false idex_isMret_next_2,
    Signal.register 0#32 idex_rs1Val_next_2,
    Signal.register 0#32 idex_rs2Val_next_2,
    Signal.register 0#32 idex_imm_next_2,
    Signal.register 0#5 idex_rd_next_2,
    Signal.register 0#5 idex_rs1Idx_next_2,
    Signal.register 0#5 idex_rs2Idx_next_2,
    Signal.register 0#3 idex_funct3_next_2,
    Signal.register 0#32 idex_pc_next_2,
    Signal.register 0#32 idex_pc4_next_2,
    Signal.register 0#12 idex_csrAddr_next_2,
    Signal.register 0#3 idex_csrFunct3_next_2,
    Signal.register 0#32 exwb_alu_next_2,
    Signal.register 0#32 exwb_physAddr_next_2,
    Signal.register 0#5 exwb_rd_next_2,
    Signal.register false exwb_regW_next_2,
    Signal.register false exwb_m2r_next_2,
    Signal.register 0#32 exwb_pc4_next_2,
    Signal.register false exwb_jump_next_2,
    Signal.register false exwb_isCsr_next_2,
    Signal.register 0#32 exwb_csrRdata_next_2,
    Signal.register 0#5 prev_wb_addr_next_2,
    Signal.register 0#32 prev_wb_data_next_2,
    Signal.register false prev_wb_en_next_2,
    Signal.register 0#32 prevStoreAddr_next_2,
    Signal.register 0#32 prevStoreData_next_2,
    Signal.register false prevStoreEn_next_2,
    Signal.register 0#32 msipReg_next_2,
    Signal.register 0#32 mtimeLoReg_next_2,
    Signal.register 0#32 mtimeHiReg_next_2,
    Signal.register 4294967295#32 mtimecmpLoReg_next_2,
    Signal.register 4294967295#32 mtimecmpHiReg_next_2,
    Signal.register 0#32 mstatusReg_next_2,
    Signal.register 0#32 mieReg_next_2,
    Signal.register 0#32 mtvecReg_next_2,
    Signal.register 0#32 mscratchReg_next_2,
    Signal.register 0#32 mepcReg_next_2,
    Signal.register 0#32 mcauseReg_next_2,
    Signal.register 0#32 mtvalReg_next_2,
    Signal.register 0#32 aiStatusReg_next_2,
    Signal.register 0#32 aiInputReg_next_2,
    Signal.register 0#3 exwb_funct3_next_2,
    Signal.register false idex_isMext_next_2,
    Signal.register false reservationValid_next_2,
    Signal.register 0#32 reservationAddr_next_2,
    Signal.register false idex_isAMO_next_2,
    Signal.register 0#5 idex_amoOp_next_2,
    Signal.register false exwb_isAMO_next_2,
    Signal.register 0#5 exwb_amoOp_next_2,
    Signal.register false pendingWriteEn_next_2,
    Signal.register 0#32 pendingWriteAddr_next_2,
    Signal.register 0#32 pendingWriteData_next_2,
    Signal.register 0#64 cycle_count_next,
    Signal.register 3#2 privMode_next_2,
    Signal.register 0#32 sieReg_next_2,
    Signal.register 0#32 stvecReg_next_2,
    Signal.register 0#32 sscratchReg_next_2,
    Signal.register 0#32 sepcReg_next_2,
    Signal.register 0#32 scauseReg_next_2,
    Signal.register 0#32 stvalReg_next_2,
    Signal.register 0#32 satpReg_next_2,
    Signal.register 0#32 medelegReg_next_2,
    Signal.register 0#32 midelegReg_next_2,
    Signal.register 0#32 mcounterenReg_next_2,
    Signal.register 0#32 scounterenReg_next_2,
    Signal.register 0#3 mmuState_next_2,
    Signal.register 0#3 ptwState_next_2,
    Signal.register 0#32 ptwVaddr_next_2,
    Signal.register 0#32 ptwPte_next_2,
    Signal.register false ptwMega_next_2,
    Signal.register 0#2 replPtr_next_2,
    Signal.register false tlb0Valid_next_2,
    Signal.register 0#20 tlb0VPN_next_2,
    Signal.register 0#22 tlb0PPN_next_2,
    Signal.register 0#8 tlb0Flags_next_2,
    Signal.register false tlb0Mega_next_2,
    Signal.register false tlb1Valid_next_2,
    Signal.register 0#20 tlb1VPN_next_2,
    Signal.register 0#22 tlb1PPN_next_2,
    Signal.register 0#8 tlb1Flags_next_2,
    Signal.register false tlb1Mega_next_2,
    Signal.register false tlb2Valid_next_2,
    Signal.register 0#20 tlb2VPN_next_2,
    Signal.register 0#22 tlb2PPN_next_2,
    Signal.register 0#8 tlb2Flags_next_2,
    Signal.register false tlb2Mega_next_2,
    Signal.register false tlb3Valid_next_2,
    Signal.register 0#20 tlb3VPN_next_2,
    Signal.register 0#22 tlb3PPN_next_2,
    Signal.register 0#8 tlb3Flags_next_2,
    Signal.register false tlb3Mega_next_2,
    Signal.register false ptwIsIfetch_next_2,
    Signal.register false ifetchFaultPending_next_2,
    Signal.register 0#32 dMissPC_next,
    Signal.register 0#32 dMissVaddr_next,
    Signal.register false dMissIsStore_next,
    Signal.register false idex_isSret_next_2,
    Signal.register false idex_isSFenceVMA_next_2,
    Signal.register 0#8 uartLCR_next_2,
    Signal.register 0#8 uartIER_next_2,
    Signal.register 0#8 uartMCR_next_2,
    Signal.register 0#8 uartSCR_next_2,
    Signal.register 0#8 uartDLL_next_2,
    Signal.register 0#8 uartDLM_next_2,
    Signal.register 0#8 uartRxBuf_next_2,
    Signal.register false uartRxReady_next_2,
    Signal.register 0#8 dmem_b0_rdata_next,
    Signal.register 0#8 dmem_b1_rdata_next,
    Signal.register 0#8 dmem_b2_rdata_next,
    Signal.register 0#8 dmem_b3_rdata_next,
    Signal.register false fv_rst_seen_next
  ]

def rv32i_soc {dom : DomainConfig}
    (rst : Signal dom Bool) (imem_wr_en : Signal dom Bool) (imem_wr_addr : Signal dom (BitVec 12)) (imem_wr_data : Signal dom (BitVec 32)) (dmem_wr_en : Signal dom Bool) (dmem_wr_addr : Signal dom (BitVec 23)) (dmem_wr_data : Signal dom (BitVec 32)) (uart_rx_valid : Signal dom Bool) (uart_rx_data : Signal dom (BitVec 8))
    : Signal dom (BitVec 32) × Signal dom Bool × Signal dom (BitVec 32) × Signal dom Bool × Signal dom (BitVec 32) × Signal dom (BitVec 32) × Signal dom Bool × Signal dom Bool × Signal dom Bool × Signal dom Bool × Signal dom Bool × Signal dom (BitVec 32) × Signal dom (BitVec 32) :=
  let state := Signal.loop fun state => rv32i_socBody rst imem_wr_en imem_wr_addr imem_wr_data dmem_wr_en dmem_wr_addr dmem_wr_data uart_rx_valid uart_rx_data state
  let pcReg := Rv32i_socState.pcReg state
  let fetchPC := Rv32i_socState.fetchPC state
  let flushDelay := Rv32i_socState.flushDelay state
  let ifid_inst := Rv32i_socState.ifid_inst state
  let ifid_pc := Rv32i_socState.ifid_pc state
  let ifid_pc4 := Rv32i_socState.ifid_pc4 state
  let idex_aluOp := Rv32i_socState.idex_aluOp state
  let idex_regWrite := Rv32i_socState.idex_regWrite state
  let idex_memRead := Rv32i_socState.idex_memRead state
  let idex_memWrite := Rv32i_socState.idex_memWrite state
  let idex_memToReg := Rv32i_socState.idex_memToReg state
  let idex_branch := Rv32i_socState.idex_branch state
  let idex_jump := Rv32i_socState.idex_jump state
  let idex_auipc := Rv32i_socState.idex_auipc state
  let idex_aluSrcB := Rv32i_socState.idex_aluSrcB state
  let idex_isJalr := Rv32i_socState.idex_isJalr state
  let idex_isCsr := Rv32i_socState.idex_isCsr state
  let idex_isEcall := Rv32i_socState.idex_isEcall state
  let idex_isMret := Rv32i_socState.idex_isMret state
  let idex_rs1Val := Rv32i_socState.idex_rs1Val state
  let idex_rs2Val := Rv32i_socState.idex_rs2Val state
  let idex_imm := Rv32i_socState.idex_imm state
  let idex_rd := Rv32i_socState.idex_rd state
  let idex_rs1Idx := Rv32i_socState.idex_rs1Idx state
  let idex_rs2Idx := Rv32i_socState.idex_rs2Idx state
  let idex_funct3 := Rv32i_socState.idex_funct3 state
  let idex_pc := Rv32i_socState.idex_pc state
  let idex_pc4 := Rv32i_socState.idex_pc4 state
  let idex_csrAddr := Rv32i_socState.idex_csrAddr state
  let idex_csrFunct3 := Rv32i_socState.idex_csrFunct3 state
  let exwb_alu := Rv32i_socState.exwb_alu state
  let exwb_physAddr := Rv32i_socState.exwb_physAddr state
  let exwb_rd := Rv32i_socState.exwb_rd state
  let exwb_regW := Rv32i_socState.exwb_regW state
  let exwb_m2r := Rv32i_socState.exwb_m2r state
  let exwb_pc4 := Rv32i_socState.exwb_pc4 state
  let exwb_jump := Rv32i_socState.exwb_jump state
  let exwb_isCsr := Rv32i_socState.exwb_isCsr state
  let exwb_csrRdata := Rv32i_socState.exwb_csrRdata state
  let prev_wb_addr := Rv32i_socState.prev_wb_addr state
  let prev_wb_data := Rv32i_socState.prev_wb_data state
  let prev_wb_en := Rv32i_socState.prev_wb_en state
  let prevStoreAddr := Rv32i_socState.prevStoreAddr state
  let prevStoreData := Rv32i_socState.prevStoreData state
  let prevStoreEn := Rv32i_socState.prevStoreEn state
  let msipReg := Rv32i_socState.msipReg state
  let mtimeLoReg := Rv32i_socState.mtimeLoReg state
  let mtimeHiReg := Rv32i_socState.mtimeHiReg state
  let mtimecmpLoReg := Rv32i_socState.mtimecmpLoReg state
  let mtimecmpHiReg := Rv32i_socState.mtimecmpHiReg state
  let mstatusReg := Rv32i_socState.mstatusReg state
  let mieReg := Rv32i_socState.mieReg state
  let mtvecReg := Rv32i_socState.mtvecReg state
  let mscratchReg := Rv32i_socState.mscratchReg state
  let mepcReg := Rv32i_socState.mepcReg state
  let mcauseReg := Rv32i_socState.mcauseReg state
  let mtvalReg := Rv32i_socState.mtvalReg state
  let aiStatusReg := Rv32i_socState.aiStatusReg state
  let aiInputReg := Rv32i_socState.aiInputReg state
  let exwb_funct3 := Rv32i_socState.exwb_funct3 state
  let idex_isMext := Rv32i_socState.idex_isMext state
  let reservationValid := Rv32i_socState.reservationValid state
  let reservationAddr := Rv32i_socState.reservationAddr state
  let idex_isAMO := Rv32i_socState.idex_isAMO state
  let idex_amoOp := Rv32i_socState.idex_amoOp state
  let exwb_isAMO := Rv32i_socState.exwb_isAMO state
  let exwb_amoOp := Rv32i_socState.exwb_amoOp state
  let pendingWriteEn := Rv32i_socState.pendingWriteEn state
  let pendingWriteAddr := Rv32i_socState.pendingWriteAddr state
  let pendingWriteData := Rv32i_socState.pendingWriteData state
  let cycle_count := Rv32i_socState.cycle_count state
  let privMode := Rv32i_socState.privMode state
  let sieReg := Rv32i_socState.sieReg state
  let stvecReg := Rv32i_socState.stvecReg state
  let sscratchReg := Rv32i_socState.sscratchReg state
  let sepcReg := Rv32i_socState.sepcReg state
  let scauseReg := Rv32i_socState.scauseReg state
  let stvalReg := Rv32i_socState.stvalReg state
  let satpReg := Rv32i_socState.satpReg state
  let medelegReg := Rv32i_socState.medelegReg state
  let midelegReg := Rv32i_socState.midelegReg state
  let mcounterenReg := Rv32i_socState.mcounterenReg state
  let scounterenReg := Rv32i_socState.scounterenReg state
  let mmuState := Rv32i_socState.mmuState state
  let ptwState := Rv32i_socState.ptwState state
  let ptwVaddr := Rv32i_socState.ptwVaddr state
  let ptwPte := Rv32i_socState.ptwPte state
  let ptwMega := Rv32i_socState.ptwMega state
  let replPtr := Rv32i_socState.replPtr state
  let tlb0Valid := Rv32i_socState.tlb0Valid state
  let tlb0VPN := Rv32i_socState.tlb0VPN state
  let tlb0PPN := Rv32i_socState.tlb0PPN state
  let tlb0Flags := Rv32i_socState.tlb0Flags state
  let tlb0Mega := Rv32i_socState.tlb0Mega state
  let tlb1Valid := Rv32i_socState.tlb1Valid state
  let tlb1VPN := Rv32i_socState.tlb1VPN state
  let tlb1PPN := Rv32i_socState.tlb1PPN state
  let tlb1Flags := Rv32i_socState.tlb1Flags state
  let tlb1Mega := Rv32i_socState.tlb1Mega state
  let tlb2Valid := Rv32i_socState.tlb2Valid state
  let tlb2VPN := Rv32i_socState.tlb2VPN state
  let tlb2PPN := Rv32i_socState.tlb2PPN state
  let tlb2Flags := Rv32i_socState.tlb2Flags state
  let tlb2Mega := Rv32i_socState.tlb2Mega state
  let tlb3Valid := Rv32i_socState.tlb3Valid state
  let tlb3VPN := Rv32i_socState.tlb3VPN state
  let tlb3PPN := Rv32i_socState.tlb3PPN state
  let tlb3Flags := Rv32i_socState.tlb3Flags state
  let tlb3Mega := Rv32i_socState.tlb3Mega state
  let ptwIsIfetch := Rv32i_socState.ptwIsIfetch state
  let ifetchFaultPending := Rv32i_socState.ifetchFaultPending state
  let dMissPC := Rv32i_socState.dMissPC state
  let dMissVaddr := Rv32i_socState.dMissVaddr state
  let dMissIsStore := Rv32i_socState.dMissIsStore state
  let idex_isSret := Rv32i_socState.idex_isSret state
  let idex_isSFenceVMA := Rv32i_socState.idex_isSFenceVMA state
  let uartLCR := Rv32i_socState.uartLCR state
  let uartIER := Rv32i_socState.uartIER state
  let uartMCR := Rv32i_socState.uartMCR state
  let uartSCR := Rv32i_socState.uartSCR state
  let uartDLL := Rv32i_socState.uartDLL state
  let uartDLM := Rv32i_socState.uartDLM state
  let uartRxBuf := Rv32i_socState.uartRxBuf state
  let uartRxReady := Rv32i_socState.uartRxReady state
  let dmem_b0_rdata := Rv32i_socState.dmem_b0_rdata state
  let dmem_b1_rdata := Rv32i_socState.dmem_b1_rdata state
  let dmem_b2_rdata := Rv32i_socState.dmem_b2_rdata state
  let dmem_b3_rdata := Rv32i_socState.dmem_b3_rdata state
  let fv_rst_seen := Rv32i_socState.fv_rst_seen state
  -- combinational logic feeding the outputs
  let pc_out := pcReg
  let uart_tx_valid := (prevStoreEn &&& (((Signal.pure 16#8) === ((BitVec.extractLsb' 24 8) <$> prevStoreAddr)) &&& ((Signal.pure 0#3) === ((BitVec.extractLsb' 0 3) <$> prevStoreAddr))))
  let uart_tx_data := prevStoreData
  let trap_pc_out := idex_pc
  let itlb_fetch_pc := fetchPC
  let ptwIsIdle := ((Signal.pure 0#3) === ptwState)
  let satpMode := ((·.getLsbD 31) <$> satpReg)
  let isMmode := ((Signal.pure 3#2) === privMode)
  let VdfgTmp_h8386f12b__0 := ((·.getLsbD 31) <$> fetchPC)
  let isMMUIdle := ((Signal.pure 0#3) === mmuState)
  let isMMUFault := ((Signal.pure 4#3) === mmuState)
  let dVPN := ((BitVec.extractLsb' 12 20) <$> alu_result_approx)
  let VdfgTmp_h2dc589b2__0 := ((BitVec.extractLsb' 10 10) <$> tlb0VPN)
  let VdfgTmp_hb73c3f48__0 := ((BitVec.extractLsb' 22 10) <$> alu_result_approx)
  let tlb0Hit := (tlb0Valid &&& (Signal.mux tlb0Mega (VdfgTmp_h2dc589b2__0 === VdfgTmp_hb73c3f48__0) (tlb0VPN === dVPN)))
  let VdfgTmp_hdcacdbfe__0 := ((BitVec.extractLsb' 10 10) <$> tlb1VPN)
  let tlb1Hit := (tlb1Valid &&& (Signal.mux tlb1Mega (VdfgTmp_hdcacdbfe__0 === VdfgTmp_hb73c3f48__0) (tlb1VPN === dVPN)))
  let VdfgTmp_h0f16f169__0 := ((BitVec.extractLsb' 10 10) <$> tlb2VPN)
  let tlb2Hit := (tlb2Valid &&& (Signal.mux tlb2Mega (VdfgTmp_h0f16f169__0 === VdfgTmp_hb73c3f48__0) (tlb2VPN === dVPN)))
  let VdfgTmp_h2054660b__0 := ((BitVec.extractLsb' 10 10) <$> tlb3VPN)
  let tlb3Hit := (tlb3Valid &&& (Signal.mux tlb3Mega (VdfgTmp_h2054660b__0 === VdfgTmp_hb73c3f48__0) (tlb3VPN === dVPN)))
  let iVPN := ((BitVec.extractLsb' 12 20) <$> fetchPC)
  let VdfgTmp_h839b6fc2__0 := ((BitVec.extractLsb' 22 10) <$> fetchPC)
  let timerIrq := (((BitVec.ult · ·) <$> mtimecmpHiReg <*> mtimeHiReg) ||| ((mtimeHiReg === mtimecmpHiReg) &&& ((BitVec.ule · ·) <$> mtimecmpLoReg <*> mtimeLoReg)))
  let swIrq := ((·.getLsbD 0) <$> msipReg)
  let mstatusMIE := ((·.getLsbD 3) <$> mstatusReg)
  let itlb_need_translate := (satpMode &&& ((~~~isMmode) &&& VdfgTmp_h8386f12b__0))
  let bypassMMU := ((~~~satpMode) ||| isMmode)
  let timerIntEnabled := (mstatusMIE &&& (((·.getLsbD 7) <$> mieReg) &&& timerIrq))
  let swIntEnabled := (mstatusMIE &&& (((·.getLsbD 3) <$> mieReg) &&& swIrq))
  let itlb0Hit := (tlb0Valid &&& (Signal.mux tlb0Mega (VdfgTmp_h2dc589b2__0 === VdfgTmp_h839b6fc2__0) (tlb0VPN === iVPN)))
  let itlb1Hit := (tlb1Valid &&& (Signal.mux tlb1Mega (VdfgTmp_hdcacdbfe__0 === VdfgTmp_h839b6fc2__0) (tlb1VPN === iVPN)))
  let itlb2Hit := (tlb2Valid &&& (Signal.mux tlb2Mega (VdfgTmp_h0f16f169__0 === VdfgTmp_h839b6fc2__0) (tlb2VPN === iVPN)))
  let itlb3Hit := (tlb3Valid &&& (Signal.mux tlb3Mega (VdfgTmp_h2054660b__0 === VdfgTmp_h839b6fc2__0) (tlb3VPN === iVPN)))
  let VdfgTmp_h184f0194__0 := ((BitVec.extractLsb' 0 20) <$> (Signal.mux itlb0Hit tlb0PPN (Signal.mux itlb1Hit tlb1PPN (Signal.mux itlb2Hit tlb2PPN (Signal.mux itlb3Hit tlb3PPN (Signal.pure 0#22))))))
  let VdfgTmp_h88d03c83__0 := (~~~bypassMMU)
  let anyTLBHit := (tlb0Hit ||| (tlb1Hit ||| (tlb2Hit ||| tlb3Hit)))
  let itlb_hit := (itlb0Hit ||| (itlb1Hit ||| (itlb2Hit ||| itlb3Hit)))
  let itlb_miss := ((~~~itlb_hit) &&& itlb_need_translate)
  let itlb_stall := ((~~~ifetchFaultPending) &&& itlb_miss)
  let itlb_phys_addr := (Signal.mux (Signal.mux itlb0Hit tlb0Mega (Signal.mux itlb1Hit tlb1Mega (Signal.mux itlb2Hit tlb2Mega (itlb3Hit &&& tlb3Mega)))) (((· ++ ·) <$> VdfgTmp_h184f0194__0 <*> (Signal.pure 0#12)) + ((BitVec.zeroExtend 32) <$> ((BitVec.extractLsb' 0 22) <$> fetchPC))) ((· ++ ·) <$> VdfgTmp_h184f0194__0 <*> ((BitVec.extractLsb' 0 12) <$> fetchPC)))
  let dTLBMiss := (VdfgTmp_h88d03c83__0 &&& ((idex_memRead ||| idex_memWrite) &&& ((~~~anyTLBHit) &&& (isMMUIdle &&& ptwIsIdle))))
  let ifetchPageFault := (VdfgTmp_h88d03c83__0 &&& ifetchFaultPending)
  let pageFault := (VdfgTmp_h88d03c83__0 &&& isMMUFault)
  let VdfgTmp_h449091ff__0 :=
    hw_cond (Signal.pure 0#32)
    | idex_isEcall => (Signal.mux ((Signal.pure 0#2) === privMode) (Signal.pure 8#32) (Signal.mux ((Signal.pure 1#2) === privMode) (Signal.pure 9#32) (Signal.pure 11#32)))
    | pageFault => (Signal.mux (pageFault &&& dMissIsStore) (Signal.pure 15#32) (Signal.pure 13#32))
    | timerIntEnabled => (Signal.pure 2147483655#32)
    | swIntEnabled => (Signal.pure 2147483651#32)
  let VdfgTmp_h806edf84__0 := (~~~dTLBMiss)
  let trap_out := (idex_isEcall ||| (pageFault ||| (timerIntEnabled ||| (swIntEnabled ||| ifetchPageFault))))
  let trap_cause_out := (Signal.mux ifetchPageFault (Signal.pure 12#32) VdfgTmp_h449091ff__0)
  let itlb_ptw_req := (itlb_miss &&& (ptwIsIdle &&& (VdfgTmp_h806edf84__0 &&& isMMUIdle)))
  (pc_out, uart_tx_valid, uart_tx_data, trap_out, trap_cause_out, trap_pc_out, itlb_need_translate, itlb_hit, itlb_miss, itlb_stall, itlb_ptw_req, itlb_phys_addr, itlb_fetch_pc)

end SparkleFV.Rv32i_soc
