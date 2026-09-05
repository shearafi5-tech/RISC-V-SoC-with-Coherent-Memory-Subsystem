# Logic Design (on paper) — Project 05

Day-1 Gate-0 deliverable: **"Logic design on paper"** per the Implementation Plan §3.1 (tasks T1.1–T1.6)
and Track Document Stage 1 (exit criteria §2).

Everything here is design, not RTL. Each document is written so it can be translated 1:1 into
SystemVerilog `always_ff` / `always_comb` blocks on Day 1–2: every FSM has a complete state list, a
complete transition table (every state × every input condition), per-state registered actions,
per-state outputs, and explicit reset values.

---

## Document map & Day-1 traceability

| Doc | Contents | Day-1 task |
|-----|----------|-----------|
| [01_day1_design_decisions.md](01_day1_design_decisions.md) | The 7 locked Day-1 decisions + refinements R1–R9 that close spec gaps found during paper design | T1.6 |
| [02_alu_logic.md](02_alu_logic.md) | RV32I ALU truth table, op select encoding, flags, branch resolution, critical path | **T1.1** |
| [03_core_datapath_and_control.md](03_core_datapath_and_control.md) | Full RV32I decode table, single-cycle datapath, PC logic, reg file, core RUN/STALL FSM, load/store lane logic | supports T1.1, Day-1 core RTL |
| [04_dcache_fsm.md](04_dcache_fsm.md) | D-cache geometry, hit/miss equations, the complete 13-state `d_cache_mgr` FSM (transition + output tables), AXI-Lite master sequencing | **T1.2** |
| [05_coherence_fsm.md](05_coherence_fsm.md) | Coherence controller FSM (I/S/M tracking + invalidation dispatch), 8-entry state table, dispatch decision logic | **T1.3** |
| [06_arbiter_logic.md](06_arbiter_logic.md) | 2-master round-robin arbiter: truth table, grant-hold FSM, deadlock-freedom argument | **T1.4** |
| [07_decoder_and_bus_fabric.md](07_decoder_and_bus_fabric.md) | Address decoder equations + truth table, DECERR slave, AXI4-Lite channel contract, common slave response template | supports T1.4/T1.5 |
| [08_memory_subsystem.md](08_memory_subsystem.md) | `sram_reg_array`, `i_sram`, `shared_sram` — port timing, init, byte-write | supports T1.5 |
| [09_peripherals.md](09_peripherals.md) | MMIO register file, UART TX/RX FSMs + baud generator, GPIO/LED event mapping | supports T1.5 |
| [10_system_block_diagram.md](10_system_block_diagram.md) | Full system block diagram — every module and every connection | **T1.5** |
| [11_memory_map.md](11_memory_map.md) | Memory map + cache/coherence address breakdown + all register detail tables | **T1.5** |
| [12_integration_logic.md](12_integration_logic.md) | Complete integration: full inter-module wiring table, reset synchronizer, event/counter plumbing, integration order | integration |
| [13_working_logic_scenarios.md](13_working_logic_scenarios.md) | End-to-end working logic: cycle-by-cycle traces of every scenario (coherence demo, simultaneous writes, errors…) + mapping of the 10 directed tests | working logic |

## Global conventions (used by every document)

| Item | Convention |
|------|-----------|
| Clock | single `clk` (core_clk), all logic synchronous to it |
| Reset | `rst_n`, **async assert, active-low**; synchronous 2-FF release; every register has a reset value |
| Cache addressing | line `idx = addr[3:2]` (4 lines), `tag = addr[31:4]` |
| Coherence states | `I = 2'b00`, `S = 2'b01`, `M = 2'b10` |
| Core ↔ cache interface | req/ack: `dmem_req, dmem_we, dmem_addr, dmem_wdata, dmem_wmask[3:0]` → `dmem_rdata, dmem_ack, dmem_err` |
| AXI4-Lite | strictly Lite: 5 channels, no bursts, 32-bit data; masters named `m0_`/`m1_`, shared bus `s_` |
| Names | TRD §3.3 FSM names are authoritative (IDLE/CHECK/HIT_READ/MISS_READ/AXI_AR/AXI_R/FILL/HIT_WRITE/AXI_AW/AXI_W/AXI_B/NOTIFY_COH/WAIT_INVALIDATE) |

## Spec gaps found and closed during paper design (details in doc 01)

The source PDFs (extracted text) contain four gaps that would break correctness or a directed test
if implemented literally. They are resolved as refinement decisions **R1–R8** and are drawn into the
FSMs here:

1. **R1** `coh_accept` — a cache manager's `write_notify` must be held until accepted, else a notify
   arriving while the coherence FSM is busy is lost (real interleaving, see 05 §5.6).
2. **R2** `fill_notify` — the coherence mirror must learn about S-fills, otherwise cross-core
   invalidation is never dispatched after a plain fill (breaks directed test 5/6).
3. **R3** store-miss path — DECISIONS O2 (write-allocate) + FR-2.5 (store → M) require a read-modify-
   write sequence through the same AXI read path; drawn explicitly in 04 §4.4.
4. **R4/R5** coherence notify fires only on OKAY B-response; error loads do not fill the line; error
   semantics per O3.
5. The track document's assertion `write_notify |-> ##[1:2] inv_req` is **wrong as written** — it must
   be conditioned on the remote copy existing (test 8 requires *no* invalidation). Corrected in 05 §5.8.

## TRD table corrections baked in here

The PDF text extraction of TRD §3.8–§3.10 shifts register *names* one row below their offsets/descriptions.
The corrected alignments used throughout (offset ↔ name ↔ description) are:

- MMIO: `0x00 COH_STATUS RO`, `0x04 INV_COUNT RO`, `0x08 HIT_COUNT RO`, `0x0C MISS_COUNT RO`,
  `0x10 DOORBELL RW`, `0x14 CONTROL RW`
- UART: `0x00 TX_DATA (W)`, `0x04 TX_STATUS (R)`, `0x08 RX_DATA (R)`, `0x0C RX_STATUS (R)`
- LEDs: LED0 = core0 heartbeat, LED1 = core1 heartbeat, LED2 = coherence event, LED3 = hit,
  LED4 = miss, LED5 = error, LED6–7 = spare / SW-driven

## How to use this folder

1. Read 01 (decisions) and 10/11 (block diagram + memory map) first for the shape of the system.
2. Before writing each RTL module on Day 1–2, open its logic doc and copy the transition table into
   the `always_ff` case statement — the tables are written to be transcription-ready.
3. Doc 12 (integration) is the wiring checklist for `riscv_soc_top.sv`; doc 13 is the behavioral
   truth source the directed TB (and later UVM scoreboard) is built against.
