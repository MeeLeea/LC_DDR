# DDR5 IP - Verification Plan (Part 15)

> Resolves review blocking issue **B-08** (no UVM methodology, coverage
> targets, or test scenarios). This plan upgrades the existing directed
> testbenches (`test/tb_*.sv`, `doc/verification_report.md`) into a layered
> verification flow with explicit coverage goals and sign-off criteria.

## 15.1 Verification Strategy

Layered, **directed-first → constrained-random → UVM** so the existing 24
directed testbenches remain the regression backbone while UVM adds coverage
closure.

| Level | Scope | Method | Owner |
|-------|-------|--------|-------|
| Unit | single module | directed SV TB (current) + SVA | module owner |
| Block | ui / ctrl / dfi / phy | UVM agent + scoreboard | block DV |
| Subsystem | ctrl_core (sched+FSM+refresh+ECC) | UVM + reference model | subsystem DV |
| Top | `ddr5_controller` | UVM system TB + AXI VIP | top DV |
| Formal | CDC, arbitration fairness, deadlock | FPV / model-checking | formal |

## 15.2 UVM Testbench Architecture

```
                        ┌─────────────────────────────┐
                        │       tb_top (uvm_test)      │
                        └──────────────┬──────────────┘
        AXI4 VIP ──► ui_agent ─┐       │       ┌─ DFI agent ──► dfi_monitor
   (master+slave sequencer)    │       │       │  (passive, protocol chk)
                               ▼       ▼       ▼
                        ┌─────────────────────────────┐
                        │   ddr5_env (uvm_env)         │
                        │  ┌────────┐   ┌──────────┐  │
                        │  │score-  │   │ coverage │  │
                        │  │board   │   │ collector│  │
                        │  └────────┘   └──────────┘  │
                        │  ┌──────────────────────┐   │
                        │  │ reference model (C / │   │
                        │  │ SV behavioral DDR5)  │   │
                        │  └──────────────────────┘   │
                        └──────────────┬──────────────┘
                                       ▼
                              DUT: ddr5_controller
                          + APB cfg agent + IRQ monitor
```

Components:
- **AXI4 VIP**: drives `s_axi_*` (incl. `awlock`/`arlock` for B-02), checks
  `AXI4-Lite/Full` protocol via embedded assertions.
- **DFI agent**: passive monitor on `dfi_*` (incl. B-04 signals), protocol
  checker for 1:2 phase relationship.
- **Reference model**: golden DDR5 memory array; scoreboard compares read
  data, `BRESP`/`RRESP`, ECC-corrected data, and command ordering.
- **Coverage collector**: binds `ddr5_covergroups.sv` + functional covergers.

## 15.3 Coverage Targets

| Type | Target | Notes |
|------|--------|-------|
| Line | ≥ 98 % | exclude unreachable default arms |
| Toggle | ≥ 95 % | all ports, incl. new DFI 5.1 / lock signals |
| FSM state+arc | 100 % | every state, every transition |
| Functional | 100 % | covergroups below |
| Assertion | 100 % pass + ≥1 hit each | no vacuous passes |

### 15.3.1 Functional Covergroups (per blocking issue)

| Covergroup | Bins | Links |
|------------|------|-------|
| `cg_exclusive` | ARLOCK×AWLOCK, EXOKAY/OKAY, reservation hit/miss/snoop-clear | B-02 |
| `cg_deadlock` | cmd-stall, ref-stall, force-refresh, recovery-clear | B-03 |
| `cg_dfi_phase` | phycsel, dram_clk_disable, freq_ratio, rddata_dnv | B-04 |
| `cg_subchannel` | sub_ch=0/1, DUAL_CH_BROADCAST on/off, cs_n encodings | B-05 |
| `cg_gearbox` | phase0/phase1 split, read/write dir, backpressure | B-01 |
| `cg_refresh` | 1x/2x/4x, same-bank, overflow, credit thresholds | Part 02 |
| `cg_ecc` | SBE, DBE, clean, inject positions | Part 02 |
| `cg_arb` | priority order, page-hit/empty/conflict, starvation | Part 02a |

## 15.4 Test Scenario Matrix

| ID | Scenario | Level | Key check |
|----|----------|-------|-----------|
| TC-01 | Sequential read/write burst | Block | data integrity, BRESP/RRESP |
| TC-02 | Random AXI traffic w/ backpressure | Subsystem | no deadlock, ordering |
| TC-03 | **Exclusive read/write + snoop clear** | Unit/Block | EXOKAY vs OKAY (B-02) |
| TC-04 | **Deadlock inject (stall cmd/ref)** | Unit | timeout→detect→recover (B-03) |
| TC-05 | **DFI 5.1 signal toggle** | Unit | phycsel/dnv/freq_ratio propagate (B-04) |
| TC-06 | **Dual-channel addr decode** | Unit/Block | sub_channel + cs_n (B-05) |
| TC-07 | **Gearbox 2:1 pack/unpack** | Unit | 256↔2×128 phase split (B-01) |
| TC-08 | Refresh storm / overflow | Subsystem | priority, no starvation |
| TC-09 | ECC error injection sweep | Block | correct SBE, flag DBE |
| TC-10 | Power: self-refresh enter/exit | Top | data retention |
| TC-11 | Training fail → init abort | Top | error code, reset held |
| TC-12 | Full regression (all directed TBs) | Unit | lint-clean + all pass |

## 15.5 Assertions

`test/ddr5_assertions.sv` already encodes AXI stability, FIFO no-overrun,
reset propagation, command-stall limit, and BRESP latency. Add for the new
features:

```systemverilog
// B-02: EXOKAY only when a reservation existed and matched
p_exokay_needs_res: assert property (@(posedge ui_clk)
    disable iff(!rst_n) (s_axi_bvalid && bresp==EXOKAY) |-> $past(res_valid && addr_match));

// B-03: a sustained stall must eventually raise deadlock
p_stall_leads_detect: assert property (@(posedge clk)
    (cmd_in_valid && !cmd_in_ready) [*CMD_TIMEOUT] |-> ##[1:4] deadlock_detected);

// B-05: broadcast mode never selects a single chip-select
p_broadcast_cs: assert property (@(posedge ctrl_clk)
    DUAL_CH_BROADCAST |-> (dfi_cs_n == 2'b00));
```

## 15.6 Existing vs. Planned Coverage (gap closure)

| Module | Directed TB today | UVM/coverage gap |
|--------|-------------------|------------------|
| AXI4 rd/wr slave, ui_axi4, arbiter | ✅ | add random + covergroups |
| addr_mapper, protocol_fsm, scheduler | ✅ (B-05 updated) | add cg_subchannel |
| exclusive_monitor | ✅ new (B-02) | add cg_exclusive |
| deadlock_monitor | ✅ new (B-03) | add cg_deadlock + FPV |
| dfi_bridge, phy_digital | ✅ (B-04 ports) | add cg_dfi_phase |
| ctrl_core (ECC/refresh/timing) | partial | **add UVM + ref model** |
| gearbox | none | **add TC-07 unit TB** |
| top controller | ✅ | add system scoreboard |

## 15.7 Sign-off Criteria

1. `verilator --lint-only -Wall` clean on all `src/` (Part 13 §13.9).
2. All 24+ directed testbenches pass in regression.
3. Coverage meets §15.3 targets; every covergroup 100 % with ≥1 hit/bin.
4. All assertions pass and are non-vacuous (each hit ≥1 time).
5. Formal: CDC clean (Part 13 §13.4), deadlock-freedom proof for
   `ddr5_deadlock_monitor` recovery path.
6. No open Severity-1/2 bugs; B-01…B-08 each traced to a passing test.

## 15.8 Traceability Matrix

| Blocking issue | RTL | Directed TB | Covergroup | Test ID |
|----------------|-----|-------------|-----------|---------|
| B-01 Gearbox | `ddr5_gearbox.sv` | (add) | cg_gearbox | TC-07 |
| B-02 Exclusive | `ddr5_exclusive_monitor.sv` | `tb_ddr5_exclusive_monitor.sv` | cg_exclusive | TC-03 |
| B-03 Deadlock | `ddr5_deadlock_monitor.sv` | `tb_ddr5_deadlock_monitor.sv` | cg_deadlock | TC-04 |
| B-04 DFI 5.1 | `ddr5_dfi_bridge.sv` | `tb_ddr5_dfi_bridge.sv` | cg_dfi_phase | TC-05 |
| B-05 Dual-ch | `ddr5_addr_mapper.sv` | `tb_ddr5_addr_mapper.sv` | cg_subchannel | TC-06 |
| B-06 Coding | — | lint gate | — | TC-12 |
| B-07 Driver | — | SW test harness | — | TC-11 |
| B-08 Plan | this doc | — | all | all |
