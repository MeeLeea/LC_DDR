# DDR5 IP - RTL Coding Guidelines (Part 13)

> Resolves review blocking issue **B-06** (missing naming conventions and CDC
> coding rules). These rules are enforced by lint (`verilator --lint-only` /
> Spyglass / Ascent) and reviewed at every RTL merge.

## 13.1 Scope & Tooling

| Item | Choice |
|------|--------|
| Language | SystemVerilog-2017 (IEEE 1800-2017), synthesizable subset only |
| Lint gate | `verilator --lint-only -Wall` must be clean before merge |
| Definition file | `src/ddr5_defines.svh` is the **single** source of widths |
| Include guard | every `.svh` uses `ifndef/`define/`endif` |

## 13.2 Naming Conventions

### 13.2.1 Identifiers

| Element | Rule | Example |
|---------|------|---------|
| Module | `snake_case`, prefixed by subsystem where ambiguous | `ddr5_cmd_scheduler` |
| Port | `snake_case`; direction implied by name, not prefix | `cmd_in_valid`, `dfi_cs_n` |
| Signal / var | `snake_case` | `page_hit_cnt` |
| Parameter | `UPPER_SNAKE` | `QUEUE_DEPTH` |
| `` `define `` macro | `DDR5_*` / `DFI_*` prefix | `` `DDR5_ROW_W `` |
| Enum member | `UPPER_SNAKE` with state prefix | `ST_PRECHARGE` |
| Struct type | `*_t` suffix | `cmd_entry_t` |
| Clock | `*_clk` | `ui_clk`, `ctrl_clk`, `dfi_clk` |
| Reset | `*_rst_n` (active-low) | `ctrl_rst_n` |

### 13.2.2 Active-Low & Handshake Suffixes

- Active-low signals **must** end in `_n` (`dfi_cs_n`, `rst_n`, `s_axi_awready_n` if ever used).
- Valid/ready pairs use the **same base name**: `cmd_in_valid` / `cmd_in_ready`.
  The `_valid` signal never depends combinationally on the matching `_ready`
  (AXI4 §A3.2 rule) — see 13.4.
- Next-state combinational value uses `_n` suffix on the **register copy**, and
  the registered value has no suffix: `state` (reg) / `state_n` (next).

### 13.2.3 File & Directory Layout

```
src/
  ddr5_defines.svh          # global widths/enums (single source of truth)
  ui/    ctrl/  dfi/  phy/  top/
test/
  tb_<module>.sv            # one directed testbench per module
docs/
  NN_<Topic>.md             # numbered spec parts
```

Every RTL file contains exactly one module and its name matches the filename.

## 13.3 FSM & Sequential Coding Rules

1. **Three-process FSM** (or two-process with `always_ff` + `always_comb`):
   state register, next-state logic, and output logic are separate.
2. `always_ff` uses **non-blocking** (`<=`) exclusively; `always_comb` uses
   **blocking** (`=`) exclusively. Mixing is a lint error.
3. Every `always_comb` assigns **all** outputs on **every** branch (no inferred
   latch). A `default` arm is mandatory in `case`.
4. No combinational loops; no `assign` driven from two sources (single-driver
   rule — this class of bug was caught during B-05/B-02 integration).
5. Reset is **asynchronous assert / synchronous de-assert**, active-low, and
   resets **all** state registers (including pipeline valid bits).
6. No `initial` values in synthesizable RTL (FPGA init only via vendor attr).
7. Widths come from `` `define `` macros, never hard-coded literals, so a
   change in `ddr5_defines.svh` propagates everywhere.

## 13.4 CDC (Clock Domain Crossing) Rules

The design spans **three** clock domains:

```
ui_clk (400 MHz) ──┐
                   ├── ctrl_clk (400 MHz, synchronous to ui_clk) ──┐
dfi_clk (1.2 GHz) ─┘                                              │
                                                                  ▼
                                                          DDR CK (2.4 GHz)
```

| Rule | Requirement |
|------|-------------|
| CDC-1 | Every signal crossing clock domains passes through a **synchronizer** |
| CDC-2 | Single-bit level: 2-FF synchronizer (`sync_2ff`) |
| CDC-3 | Pulse: toggle-synchronizer or async-FIFO with Gray-coded pointers |
| CDC-4 | Multi-bit bus: **async FIFO** or **Gray code** — never a bare 2-FF |
| CDC-5 | No `assign` of a raw cross-domain signal into a register in the target domain |
| CDC-6 | Synchronizer registers are grouped, named `*_sync`, and marked `(* ASYNC_REG = "TRUE" *)` |
| CDC-7 | A formal CDC sign-off report must be clean before tape-out |

### 13.4.1 Standard 2-FF Synchronizer

```systemverilog
(* ASYNC_REG = "TRUE" *) logic [1:0] x_sync;
always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) x_sync <= 2'b00;
    else            x_sync <= {x_sync[0], src_bit};   // src_bit is single-bit
end
assign dst_bit = x_sync[1];
```

### 13.4.2 Existing CDC Points (audited)

| Crossing | Signal | Method | Module |
|----------|--------|--------|--------|
| dfi→ctrl | `dfi_rddata_dnv` | 2-FF `dfi_rddata_dnv_sync` | `ddr5_dfi_bridge` |
| dfi→ctrl | `dfi_rddata_valid` | 2-FF | `ddr5_dfi_bridge` |
| ui→ctrl | AXI payload | FIFO (async) | `ddr5_ui_axi4` |
| ctrl→dfi | command | FIFO (async) | `ddr5_dfi_bridge` |

> **B-04 note**: the newly added `dfi_rddata_dnv` was routed through a 2-FF
> synchronizer on creation, satisfying CDC-2/CDC-6.

## 13.5 Reset Rules

- One reset per domain; no reset used across domains without synchronization.
- Reset tree documented in Part 04 (`04_DDR5_Clock_Power_Reset.md`).
- Soft reset (`CTRL[1]`) is **synchronous** and must not glitch a CDC FIFO
  pointer — it drains the FIFO first.

## 13.6 Synthesizability & Portability

- No `#delay`, no `fork/join`, no `force/release` in `src/` (test-only).
- No `casex` — use `casez` with explicit `?` or `unique case` + `default`.
- No tri-state except at top-level pads.
- No `initial`-dependent logic; simulation/synthesis must match.
- All `parameter` overridable at instantiation; defaults documented.

## 13.7 Commenting & Traceability

- Every module header states purpose and links the spec part / blocking-issue
  ID it implements (e.g. `// B-05: dual-channel sub-channel decode`).
- Non-obvious timing or protocol decisions get an inline `// RATIONALE:` line.
- `TODO` must carry an owner tag and a tracking issue number.

## 13.8 Lint Waiver Policy

Waivers are recorded in `lint_waivers.txt` with a justification comment.
Blanket `-Wno-fatal` is prohibited. A new waiver requires reviewer approval.

## 13.9 Pre-Merge Checklist

- [ ] `verilator --lint-only -Wall` clean
- [ ] No double-driven nets (grep for repeated `assign` / port drivers)
- [ ] All new ports connected in `ddr5_controller.sv` and every testbench
- [ ] Widths use `` `define ``, not literals
- [ ] CDC points listed in 13.4.2 and synchronized
- [ ] Directed testbench added/updated and passing
