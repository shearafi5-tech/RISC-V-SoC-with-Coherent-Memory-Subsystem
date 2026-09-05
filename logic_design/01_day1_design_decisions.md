# Day-1 Design Decisions (T1.6)

Task T1.6 requires "7 decisions documented". Section 1 lists those 7, locked in `docs/DECISIONS.md`
(D1–D8) and the Day-1 analysis. Section 2 lists **refinements R1–R8**: decisions this paper design had
to make to close gaps in the source specs — each one is load-bearing for correctness and appears in the
FSMs of docs 04–07.

---

## 1. The 7 locked Day-1 decisions

| # | Decision | Choice | Consequence for the logic design |
|---|----------|--------|----------------------------------|
| 1 | Core | **RV32I single-cycle** with req/ack stall on data memory | Non-memory instructions complete in 1 cycle; loads/stores stall the core in a 2-state FSM (doc 03 §3.5). Critical path must be watched: IF → decode → RF read → ALU → cache tag compare (doc 02 §6). |
| 2 | Bus | **AXI4-Lite** (5 channels, no bursts, 32-bit) | Arbiter + decoder designed around AW/W/B and AR/R handshakes only (docs 06, 07). Never full AXI4 — no `awlen/awsize/wlast/rlast`. |
| 3 | Write policy | **Write-through + write-allocate** | Shared SRAM is always the single source of truth; no dirty writeback anywhere. Store always produces an AXI write; store-miss additionally produces an AXI read first (R3). |
| 4 | Coherence | **3-state I/S/M, invalidation-on-write, sideband dispatch** | Coherence FSM (doc 05) sends invalidations over dedicated sideband wires, never over AXI. NOT MESI/MOESI; no snooping bus; M needs no writeback because writes go through. |
| 5 | Cache | **Direct-mapped, 4 lines, 1 word/line, private per core** | `idx = addr[3:2]`, `tag = addr[31:4]`; line = `{valid, tag[27:0], data[31:0], coh_state[1:0]}` (doc 04 §4.2). |
| 6 | Reset | **Async active-low `rst_n`, 2-FF synchronized release, single domain** | Reset values: all cache lines → I, all FSMs → IDLE, PC → RESET_PC (0x0000_0000), counters → 0, arbiter preference → core 0 (doc 12 §12.3). |
| 7 | Memories | **Register arrays** (`sram_reg_array`) for I-SRAMs and shared SRAM — no OpenRAM macros | I-SRAM uses **asynchronous read** so the core stays single-cycle; shared SRAM uses synchronous read (1-cycle latency) absorbed by the cache FSM. FPGA: arrays may map to BRAM/LUTRAM, same RTL (doc 08). |

## 2. Refinements R1–R8 (spec gaps closed during paper design)

These are new decisions, not in DECISIONS.md. Each cites the gap it closes.

### R1 — `coh_accept`: lossless write-notify handshake
**Gap:** TRD §3.4 defines `write_notify/write_core_id/write_addr` as one-way inputs with no flow
control. A real interleaving (TRD Scenario B): core 0's write completes → coherence starts processing →
core 1's write completes *while the coherence FSM is still waiting for an `inv_ack`*. If the coherence
FSM samples `write_notify` only in its IDLE state, core 1's notify is silently lost and core 1's line
never reaches M in the mirror.
**Decision:** `coh_accept` (1-cycle pulse, coherence_ctrl → each cache mgr). The cache mgr's
`NOTIFY_COH` state **holds `write_notify` until `coh_accept`**, and escapes to service an invalidation
first if `inv_valid` arrives while holding (prevents a 3-way deadlock — doc 04 §4.6). The coherence FSM
accepts a notify only in IDLE.
**Cost:** 1 sideband wire per core.

### R2 — `fill_notify`: the tracker must learn about S-fills
**Gap:** FR-3.4 requires per-line state for both cores, and TRD §3.4's dispatch table acts on the
remote core's state being S vs I. But nothing in the TRD tells the coherence controller when a cache
*fills a line to S* (load miss / refetch after invalidation). If the mirror stays I, a later write by
the other core would see "remote = I" and **skip the invalidation while the remote actually holds a
stale S copy** — exactly the failure directed test 5/6 must catch.
**Decision:** cache mgr pulses `fill_notify` (+ `fill_idx[1:0]`) in its FILL state (load fill only,
state → S). Coherence sets mirror[core][idx] = S on it. Additionally (belt and braces, per O4) the
dispatch decision reads the **actual** remote cache line state, not only the mirror (doc 05 §5.4).
**Cost:** 3 sideband wires per core (pulse + 2-bit idx).

### R3 — Store-miss write-allocate path
**Gap:** DECISIONS O2 says store-miss = write-allocate ("fill word from SRAM, merge bytes via wmask,
write through"), but the TRD §3.3 FSM drawing shows stores going straight to AXI_AW with no read.
**Decision:** store-miss reuses the load-miss AXI read path with a `pending_store` flag:
`CHECK → MISS_READ(pending_store=1) → AXI_AR → AXI_R → FILL(merge, line→M) → AXI_AW → AXI_W → AXI_B → NOTIFY_COH`.
Store-hit goes `CHECK → HIT_WRITE(merge, line→M) → AXI_AW → AXI_W → AXI_B → NOTIFY_COH`. The core
receives `dmem_ack` at AXI_B (store committed to SRAM), not before. (Doc 04 §4.4.)

### R4 — Coherence notify only on OKAY response
**Gap:** if a store gets SLVERR/DECERR the SRAM was not written; notifying coherence would invalidate
the remote's copy of data that never changed.
**Decision:** `NOTIFY_COH` is entered from `AXI_B` **only when `bresp == OKAY`**. On error the mgr
returns to IDLE with `dmem_ack=1, dmem_err=1`.

### R5 — Error semantics (O3)
**Decision:**
- Any SLVERR/DECERR on a load: `dmem_ack=1, dmem_err=1`, **no register writeback**, line **not filled**
  (stays I), miss counter still counted.
- Any SLVERR/DECERR on a store: `dmem_ack=1, dmem_err=1`, no coherence notify, no local line update on
  the write path (a store-miss allocation that errors does not fill).
- A **sticky error bit** `err_sticky` in MMIO (readable at CONTROL side / dedicated status bit) is set
  by any error event; cleared only by software (CONTROL bit). LED5 shows it. The core itself keeps no
  error state — it simply completes the instruction without writeback and advances PC.

### R6 — Dispatch reads the actual remote line state
**Gap:** TRD's mirror can only be as accurate as the events feeding it. O4 asks for a mirror *plus a
consistency assertion*.
**Decision:** coherence_ctrl receives `state_remote[idx]`/`valid_remote[idx]` (the other cache's real
line registers) as dispatch inputs; the 8-entry mirror remains the MMIO-visible `COH_STATUS` view and is
kept equal to the real states by R1/R2 events; the directed TB asserts `mirror == actual` every cycle
(O4).

### R7 — Notify-accept priority & invalidation priority inside the cache mgr
**Decision:** in the cache mgr, `inv_valid` has priority over a pending core request in IDLE
(invalidation costs 1 cycle and keeps coherence latency bounded), and `NOTIFY_COH` yields to
`inv_valid` (R1 deadlock avoidance). The core is stalled whenever the mgr is not IDLE, so no core
request is ever lost — `dmem_req` is a level held until `dmem_ack`.

### R8 — LED / event derivation
**Gap:** TRD §3.10 assigns LEDs to "heartbeat / events" without defining sources.
**Decision:** LED0/1 = core memory-activity heartbeats (stretch `dmem_ack` pulses from each core to
~2²² cycles ≈ 84 ms @ 50 MHz); LED2 = coherence invalidation-dispatch event (stretched); LED3/LED4 =
hit/miss events (stretched); LED5 = `err_sticky`; LED6–7 = software-driven bits of the GPIO LED_REG.
An 8-bit `LED_REG` slave register coexists with the event LEDs by OR-assignment (doc 09 §9.4).

### R9 — Uncached bypass for everything outside the shared-SRAM range
**Gap:** the TRD routes *all* core data accesses through the D-cache with no address-range check.
MMIO reads then become cacheable: the first read of a register fills a cache line, and every later
read **hits the stale line**. That deadlocks the core-to-core doorbell poll (C1 polls DOORBELL and
re-reads the old value forever) and silently breaks side-effect reads like UART `RX_DATA`
(read-clears-valid). It also mirrors DECERR garbage into a cache line.
**Decision:** the cache mgr latches `l_uncached = (addr[31:12] != 0x00000)` with each request:
- uncached **loads** travel the miss path (AXI read) but never fill the line and never assert
  `fill_notify` (doc 04 rows 8/18);
- uncached **stores** perform the AXI write but never update a line and never enter `NOTIFY_COH`
  (doc 04 rows 5/23/29) — no cached copy of MMIO exists anywhere, so there is nothing to invalidate;
- cached (shared-SRAM) behavior is completely unchanged, and coherence dispatch never sees non-SRAM
  addresses.
**Cost:** one comparison + one flag bit per core. This is the standard "MMIO is uncacheable" rule of
real SoCs; without it the directed doorbell flow and the UART demo cannot work.

### Corrected invariant from the track document
Track doc §4.2 proposes `write_notify |-> ##[1:2] inv_req`. As written it contradicts directed test 8
("no cached copy → no invalidation"). Corrected assertion set (doc 05 §5.8):
- `write_notify && remote_state != I |-> ##[1:2] inv_valid_to_remote`
- `write_notify && remote_state == I |-> ##[1:2] !inv_valid_to_remote`
- `inv_valid |-> inv_valid until inv_ack`
- `!(grant0 && grant1)`, `awvalid |-> awvalid until awready` (etc.)
