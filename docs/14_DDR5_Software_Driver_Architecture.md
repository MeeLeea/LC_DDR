# DDR5 IP - Software Driver Architecture (Part 14)

> Resolves review blocking issue **B-07** (complete absence of driver design,
> init flow, and API). This document defines the bare-metal + RTOS driver
> layers, the initialization/training sequence, the runtime API, and the
> interrupt/error handling policy that pairs with the RTL in Parts 01–13.

## 14.1 Layered Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Application / Filesystem / Network stack                     │
├──────────────────────────────────────────────────────────────┤
│  DDR5 Memory Service  (ddr5_mem_alloc/free, flush, self-refresh)│   ← portable
├──────────────────────────────────────────────────────────────┤
│  DDR5 Driver API      (ddr5_init / read / write / irq)        │   ← stable ABI
├──────────────────────────────────────────────────────────────┤
│  HAL / Register Access (ddr5_reg_read/write, bit-field ops)   │   ← SoC-specific
├──────────────────────────────────────────────────────────────┤
│  Bus transport: APB3 / AXI-Lite  (mmio base = 0x_0000_0000)   │   ← SoC-specific
└──────────────────────────────────────────────────────────────┘
                          │  MMIO
                  ┌───────▼────────┐
                  │  DDR5 IP (RTL)  │  ddr5_controller.sv
                  └────────────────┘
```

| Layer | Responsibility | Portability |
|-------|----------------|-------------|
| Register Access (HAL) | 32-bit MMIO read/write, bit-field set/clear, memory barriers | SoC-specific |
| Driver API | init/training sequence, read/write, power mgmt, IRQ dispatch | Stable |
| Memory Service | buffer alloc over DDR region, cache flush, self-refresh on idle | Portable |
| Application | consumes memory service only | — |

## 14.2 Register Access HAL

```c
/* ddr5_hal.h — SoC-specific glue */
#define DDR5_BASE            0x40000000u          /* APB window base */
#define DDR5_REG(off)        (DDR5_BASE + (off))  /* off from Part 07 */

static inline uint32_t ddr5_rd(uint32_t off) {
    volatile uint32_t *p = (volatile uint32_t *)DDR5_REG(off);
    uint32_t v = *p; __asm__ volatile("dmb sy" ::: "memory"); return v;   /* barrier */
}
static inline void ddr5_wr(uint32_t off, uint32_t v) {
    volatile uint32_t *p = (volatile uint32_t *)DDR5_REG(off);
    *p = v; __asm__ volatile("dmb sy" ::: "memory");
}
static inline void ddr5_set(uint32_t off, uint32_t mask) { ddr5_wr(off, ddr5_rd(off) |  mask); }
static inline void ddr5_clr(uint32_t off, uint32_t mask) { ddr5_wr(off, ddr5_rd(off) & ~mask); }
```

> **Rule**: every MMIO access is followed by a data memory barrier; the IP is
> reached through a strongly-ordered device region (`Device-nGnRE`).

## 14.3 Initialization & Training Flow

The bring-up sequence is the contract between software and the RTL state
machines (Part 02 / Part 03). Steps are strictly ordered; each polls a status
bit with a timeout (the same timeout philosophy as B-03).

```
ddr5_init()
  │
  ├─ 1. Reset        : write CTRL.soft_reset=1, poll STATUS.ready
  ├─ 2. Configure    : TIMING_0..9  ← from SPD / board file (tRCD,tRP,tRC,tRFC,tREFI,CL,CWL…)
  ├─ 3. Geometry     : CAPABILITY read → set data_rate, refresh_mode, ecc_en, dual_ch
  ├─ 4. Refresh      : REFRESH_CTRL.auto_ref_en=1, credit_threshold
  ├─ 5. ECC/CRC      : ECC_CTRL.enable, CRC enable (if CAPABILITY.ecc_sup)
  ├─ 6. IRQ setup    : IRQ_ENABLE = {deadlock, ecc_dbe, train_done, train_err, ref_overflow}
  ├─ 7. Training     : CTRL.train_start=1
  │                     poll IRQ_STATUS.train_done  (timeout = T_TRAIN_MAX)
  │                     read TRAINING_RESULT (per-bit delay, Vref)
  ├─ 8. DFI align    : poll STATUS for phy_init_complete
  └─ 9. Enable       : CTRL.enable=1 → memory path live
```

Failure at any step returns a negative error code and leaves the IP in reset
(never enables traffic on a failed training).

## 14.4 Runtime API (stable ABI)

```c
/* ddr5_drv.h */
typedef enum { DDR5_OK=0, DDR5_ETIMEOUT=-1, DDR5_EIO=-2,
               DDR5_EDBE=-3, DDR5_EDEADLOCK=-4, DDR5_EBADARG=-5 } ddr5_err_t;

ddr5_err_t ddr5_init(const ddr5_config_t *cfg);   /* full bring-up (14.3) */
ddr5_err_t ddr5_read (uintptr_t ddr_addr, void *buf, size_t len);
ddr5_err_t ddr5_write(uintptr_t ddr_addr, const void *buf, size_t len);

/* AXI4 Exclusive Access (B-02) — maps to ARLOCK/AWLOCK */
ddr5_err_t ddr5_excl_read (uintptr_t addr, uint32_t *out);   /* sets ARLOCK=1 */
ddr5_err_t ddr5_excl_write(uintptr_t addr, uint32_t val, _Bool *ok); /* EXOKAY? */

/* Power management */
ddr5_err_t ddr5_enter_self_refresh(void);
ddr5_err_t ddr5_exit_self_refresh(void);
ddr5_err_t ddr5_enter_low_power(void);

/* Interrupt / error service (call from ISR top-half or thread bottom-half) */
void       ddr5_irq_handler(void);
ddr5_err_t ddr5_get_last_error(ddr5_error_info_t *info);
```

### 14.4.1 Exclusive Access Mapping (B-02)

| API call | Bus action | Response handling |
|----------|-----------|-------------------|
| `ddr5_excl_read` | issue read with `ARLOCK=1` | `RRESP=EXOKAY` → reservation established |
| `ddr5_excl_write` | issue write with `AWLOCK=1` | `BRESP=EXOKAY` → `*ok=true`; `OKAY` → `*ok=false` (retry) |

Software retry loop for a lock-free CAS:
```c
do {
    ddr5_excl_read(addr, &old);
    new = cmp_swap_fn(old);
    ddr5_excl_write(addr, new, &ok);
} while (!ok);
```

## 14.5 Interrupt & Error Handling

`IRQ_STATUS` (0x0800, W1C) bits and the driver policy for each:

| Bit | Source | Priority | Driver action |
|-----|--------|----------|---------------|
| [0] | ECC SBE | low | log, increment counter, continue (corrected) |
| [1] | ECC DBE | **high** | quarantine page, notify upper layer, `DDR5_EDBE` |
| [3] | train_done | init | complete step 7 of bring-up |
| [4] | train_err | init | abort init, hold reset |
| [5] | ref_overflow | high | force refresh, `DDR5_ETIMEOUT` |
| [10] | **deadlock** (B-03) | **critical** | read `DEADLOCK_STATUS`, drain/reset scheduler, `DDR5_EDEADLOCK` |

ISR skeleton:
```c
void ddr5_irq_handler(void) {
    uint32_t s = ddr5_rd(DDR5_IRQ_STATUS);
    ddr5_wr(DDR5_IRQ_STATUS, s);          /* W1C: clear what we saw */
    if (s & BIT(10)) ddr5_handle_deadlock(s);   /* B-03 */
    if (s & BIT(1))  ddr5_handle_dbe(s);
    if (s & BIT(0))  ddr5_handle_sbe(s);
    if (s & BIT(5))  ddr5_handle_ref_overflow(s);
}
```

### 14.5.1 Deadlock Recovery Procedure (B-03)

When `DEADLOCK_STATUS[0]` is set the driver:
1. Stops issuing new traffic (quiesce the AXI master).
2. Reads `DEADLOCK_STATUS[31:16]` (stall count) into the diagnostic log.
3. Issues a manual refresh (`DEBUG_CTRL.force_refresh`) to break a refresh-starve.
4. If the sticky flag does not self-clear within `T_RECOVER`, performs a
   scheduler soft-reset (`CTRL.soft_reset`) and re-runs steps 4–9 of bring-up.

## 14.6 Data Structures

```c
typedef struct {
    uint16_t tRCD, tRP, tRC, tRFC, tREFI, tWR, CL, CWL;   /* from SPD */
    uint8_t  data_rate;        /* 0:2400 1:3200 2:4800 ... */
    uint8_t  refresh_mode;     /* 0:1x 1:2x 2:4x */
    _Bool    ecc_en, crc_en, dual_channel;
    uintptr_t mem_base, mem_size;
} ddr5_config_t;

typedef struct {
    ddr5_err_t code;
    uint32_t   irq_status;
    uint32_t   ecc_err_addr;
    uint16_t   stall_count;     /* B-03 */
} ddr5_error_info_t;
```

## 14.7 OS Integration

| Environment | Model |
|-------------|-------|
| Bare-metal | polling `ddr5_init`, IRQ via NVIC/GIC vector → `ddr5_irq_handler` |
| RTOS (FreeRTOS/Zephyr) | init in a dedicated thread; IRQ top-half posts to a queue, bottom-half runs recovery |
| Linux | `drivers/memory/ddr5.c` platform driver, devm MMIO, threaded IRQ, EDAC for ECC |

## 14.8 Traceability

| Blocking issue | RTL | Driver section |
|----------------|-----|----------------|
| B-02 Exclusive | `ddr5_exclusive_monitor` | 14.4.1 |
| B-03 Deadlock | `ddr5_deadlock_monitor` | 14.5.1 |
| B-04 DFI 5.1 | `ddr5_dfi_bridge` ports | 14.3 step 8 |
| B-05 Dual-ch | `sub_channel` decode | 14.3 step 3 (`dual_channel`) |
