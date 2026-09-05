# 12 — Complete Integration Logic (`riscv_soc_top.sv` design)

This is the wiring design for the top level: every module instance, every signal bundle between them,
the reset/clock plan, and the event plumbing. Use it as the checklist while writing `riscv_soc_top.sv`
(Day 3 T3.1) — every row here is one wiring obligation.

---

## 12.1 Instance list

| Instance | Module | Parameters | Count |
|----------|--------|-----------|-------|
| `u_core0/u_core1` | `rv32i_core` | `RESET_PC=0x0` | 2 |
| `u_isram0/u_isram1` | `i_sram` | `DEPTH=256, ASYNC_READ=1` | 2 |
| `u_dcache0/u_dcache1` | `d_cache` + `d_cache_mgr` | `LINES=4, CORE_ID=0/1` | 2 |
| `u_coh` | `coherence_ctrl` | `LINES=4` | 1 |
| `u_arb` | `axi_lite_arbiter` | `MASTERS=2` | 1 |
| `u_dec` | `axi_lite_decoder` (+DECERR) | — | 1 |
| `u_sram` | `shared_sram` | `DEPTH=1024` | 1 |
| `u_mmio` | `mmio_regs` | — | 1 |
| `u_uart` | `uart_core` | `BAUD_DIV=434` | 1 |
| `u_gpio` | `gpio_led` | — | 1 |
| `u_rst_sync` | reset synchronizer (2 FF) | — | 1 |

Generate-loop recommendation: one `generate for (genvar c=0; c<2; c++)` block instantiating
core + isram + dcache + per-core sideband arrays — halves the wiring text and cannot desynchronize
the two domains.

## 12.2 Full inter-module wiring table

Signals are grouped by bundle; "→" gives source → sink. Prefixes: `c0_`/`c1_` per-core, `m0_/m1_`
AXI masters, `s_` shared AXI, `coh_` coherence sideband.

### Core domains (per core c ∈ {0,1})

| Signal | Source → Sink | Width |
|--------|---------------|-------|
| `c{c}_imem_addr` | core → i_sram | 32 |
| `c{c}_imem_rdata` | i_sram → core | 32 |
| `c{c}_dmem_req/we/addr/wdata/wmask` | core → d_cache_mgr | 1/1/32/32/4 |
| `c{c}_dmem_rdata/ack/err` | d_cache_mgr → core | 32/1/1 |

### AXI fabric

| Signal | Source → Sink | Notes |
|--------|---------------|-------|
| `m0_/m1_ {awvalid,awaddr,awready,wvalid,wdata,wstrb,wready,bvalid,bresp,bready,arvalid,araddr,arready,rvalid,rdata,rresp,rready}` | d_cache_mgr ⇄ arbiter (per doc 06 §6.4 mux rules) | 2 bundles |
| `m0_bus_req`, `m1_bus_req` | d_cache_mgr → arbiter | arbitration requests |
| `s_{...}` (same 17 signals) | arbiter → decoder → selected slave | shared port |
| `sel_sram/mmio/uart/gpio` | decoder → each slave | combinational |
| Slave AXI ports | shared_sram, mmio_regs, uart_core, gpio_led ⇄ decoder | 4 bundles + internal DECERR |

### Coherence sideband

| Signal | Source → Sink | Width |
|--------|---------------|-------|
| `coh_write_notify0/1` | d_cache_mgr → coherence_ctrl | 1 |
| `coh_write_addr0/1` | d_cache_mgr → coherence_ctrl | 32 |
| `coh_accept0/1` | coherence_ctrl → d_cache_mgr | 1 |
| `coh_fill_notify0/1`, `coh_fill_idx0/1` | d_cache_mgr → coherence_ctrl | 1 / 2 |
| `coh_inv_valid0/1`, `coh_inv_idx0/1` | coherence_ctrl → d_cache_mgr | 1 / 2 |
| `coh_inv_ack0/1` | d_cache_mgr → coherence_ctrl | 1 |
| `coh_state0_i[0..3]`, `coh_valid0_i[0..3]` (and `1_`) | d_cache line regs → coherence_ctrl | 8 / 4 per core (R6 dispatch truth) |

### Events / control / status plumbing

| Signal | Source → Sink | Purpose |
|--------|---------------|---------|
| `hit0, hit1, miss0, miss1, err0, err1` | d_cache_mgrs → mmio_regs | HIT/MISS counters, ERR_STICKY |
| `inv_fire` | coherence_ctrl → mmio_regs | INV_COUNT, LED2 |
| `coh_status[15:0]` | coherence_ctrl → mmio_regs | COH_STATUS reg |
| `coh_enable`, `cnt_clear`, `err_clear` | mmio_regs (CONTROL) → coherence_ctrl / counters / err_sticky | control |
| `err_sticky` | mmio_regs → LED5 (via event merge) | R5 |
| `dmem_ack0/1` (taps) | d_cache_mgrs → LED stretchers | LED0/LED1 heartbeats |
| `led[7:0]` | gpio_led (event merge + LED_REG[7:6]) → pins | FPGA demo |
| `uart_tx, uart_rx` | uart_core ⇄ pins | demo console |

## 12.3 Clock & reset plan

- Single clock `clk` (ASIC: 20 MHz SDC, 50 ns; FPGA: MMCM 100 MHz → 50 MHz `core_clk` in `fpga_top`,
  never the raw board clock — T5).
- Reset: raw `rst_n` (async assert) → 2-FF synchronizer (both FFs async-cleared by `rst_n`, clocked by
  `clk`) → `rst_sync_n` distributed to **every** module. All sequential logic:
  `always_ff @(posedge clk or negedge rst_sync_n)`.
- Global reset values (AC-9 / directed test 1): all cache lines I; all FSMs IDLE
  (core=RUN, mgr=IDLE, coh=COH_IDLE, arb=ARB_IDLE, slaves idle); `PC=0`; counters=0; mirror=I;
  `pref=0` (core 0 arbitration winner); `coh_enable=1`; `err_sticky=0`; UART TX idle-high;
  `LED_REG=0`.

## 12.4 CDC notes

None required internally — single clock domain. The only asynchronous inputs are the board reset
button and `uart_rx` pin: reset handled by the synchronizer above; `uart_rx` through a 2-FF
synchronizer inside `uart_core` (doc 09 §9.2). FPGA `fpga_top` also synchronizes MMCM `locked` into
the reset release.

## 12.5 Integration order & unit-smoke mapping (Day 2–3 plan support)

| Step | Integrate | Smoke test (from implementation plan) |
|------|-----------|----------------------------------------|
| 1 | core + i_sram | `tb_core_smoke`: ADDI/ADD/LW/SW/BEQ (LW/SW against a fake 1-cycle memory model) |
| 2 | d_cache + mgr alone | `tb_cache_smoke`: hit returns data, miss fetches via AXI, write updates SRAM (BFM slave) |
| 3 | coherence_ctrl alone | `tb_coh_smoke`: write from core 0 invalidates core 1 line |
| 4 | arbiter + decoder | back-to-back requests from 2 BFMs, unmapped → DECERR |
| 5 | full top | directed TB tests 1–10 (doc 13 §13.10) |

## 12.6 Synthesis hygiene gates (Yosys smoke, Day 3)

- No latches: every `always_comb` assigns all outputs in all branches (FSM tables in docs 03–07 are
  written full-case on purpose).
- No `initial`/`$display`/delays in RTL; memory init lives in TB wrappers / FPGA init files.
- Every register has the async reset value listed in its logic doc.
- Parameters for all widths/depths; no magic numbers.
- Names in this doc match the RTL port names 1:1 to avoid wiring typos.
