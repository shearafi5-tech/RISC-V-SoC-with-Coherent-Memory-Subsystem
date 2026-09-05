# 13 — Working Logic: End-to-End Scenarios and the Directed Test Map

How the integrated system behaves, cycle by cycle, for every scenario the directed TB (and the FPGA
demo) exercises. This is the behavioral truth source: the TB asserts what this page predicts, and the
UVM scoreboard's reference model re-uses the same rules.

Cycle notation: one table row = one clock cycle; the "FSM state" columns show the state **during** that
cycle; registered actions take effect at the edge into the next cycle; outputs listed are valid during
that cycle. "C0"/"C1" = core 0 / core 1. Exact AXI timing assumes un-contended 1-cycle slaves
(contended cases are scenarios B and §13.7). Core `dmem_*` outputs are registered at the RUN→STALL_MEM
edge (doc 03 §5).

## 13.1 Reset (test 1, AC-9)

| Cycle | Events |
|-------|--------|
| 0 | `rst_n=0` asserted (async): every register takes its reset value **immediately** — all 8 cache lines I, mirror=I, FSMs IDLE, `PC0=PC1=0x0`, counters=0, `pref=0`, `coh_enable=1` |
| 1–2 | `rst_n` released; 2-FF synchronizer releases `rst_sync_n` on 2 consecutive clk edges |
| 3+ | Both cores in RUN fetch instruction word 0 from their private I-SRAMs (async read) |

Pass: COH_STATUS reads 0x0000 (all I), counters 0, no AXI activity, no invalidation.

## 13.2 Single-core write + readback (test 2, AC-3)

C0 executes `SW x5, 0(x6)` (x6=0x0000_0000, x5=NEW), then `LW x7, 0(x6)`. Store **miss**
(write-allocate path, worst case).

| Cyc | C0 core | mgr0 | bus / coherence | notes |
|-----|---------|------|-----------------|-------|
| 0 | RUN: SW decoded | IDLE | | at edge: core regs `dmem_req/we/addr/wdata/wmask`, →STALL_MEM |
| 1 | STALL_MEM | IDLE | | `dmem_req=1` level |
| 2 | STALL_MEM | CHECK | | at edge: mgr latches req, →MISS_READ, `pending_store←1` |
| 3 | STALL_MEM | MISS_READ | `bus_req0=1`; arbiter ARB_IDLE → grants m0 (`pref=0`) | `miss_event` pulse; at edge: mgr→AXI_AR, arb→ARB_G0 |
| 4 | STALL_MEM | AXI_AR | `arvalid_s=1, araddr_s=0x0`; slave `arready_s=1` | handshake this cycle; at edge: SRAM regs `rdata_q←mem[0], rvalid←1`; mgr→AXI_R |
| 5 | STALL_MEM | AXI_R | `rvalid_s=1`, OLD word | mgr captures; at edge →FILL |
| 6 | STALL_MEM | FILL | `fill_notify0(L0)` pulse | at edge: `line0←{1,tag,merge(OLD,NEW),M}`, `mirror[0][L0]←S`, mgr→AXI_AW |
| 7 | STALL_MEM | AXI_AW | `awvalid_s=1`; `awready_s=1` | at edge →AXI_W |
| 8 | STALL_MEM | AXI_W | `wvalid_s=1, wdata_s=NEW, wstrb_s=1111`; `wready_s=1` | **SRAM[0]←NEW at edge**; at edge: mgr→AXI_B, SRAM `bvalid←1` |
| 9 | STALL_MEM | AXI_B | `bvalid_s=1, bresp=OKAY` | `dmem_ack=1`; at edge: **core commits SW, PC+4→RUN**; mgr→NOTIFY_COH (`notify_pending←1`) |
| 10 | RUN (LW decoded) | NOTIFY_COH | `write_notify0=1` held; coherence COH_IDLE: `coh_accept0=1` | at edge: coherence→PROCESS_WRITE, `mirror[0][L0]←M`; mgr `notify_pending←0` |
| 11 | STALL_MEM (req reg'd at edge of 10) | IDLE | coherence PROCESS_WRITE: remote mirror[1][L0]=I **and** actual=I → no dispatch | at edge: coherence→COH_IDLE |
| 12 | STALL_MEM | IDLE | coherence COH_IDLE | mgr sees `dmem_req`; at edge: latch, →CHECK |
| 13 | STALL_MEM | CHECK | | hit (`state=M`, tag match); at edge →HIT_READ |
| 14 | STALL_MEM | HIT_READ | | `dmem_rdata=NEW, dmem_ack=1, hit_event` pulse; at edge: **core commits x7=NEW, PC+4→RUN**; mgr→IDLE |

Pass: `x7 == x5`; MISS_COUNT +1; HIT_COUNT +1; INV_COUNT +0; SRAM[0]=NEW.

## 13.3 Load hit vs miss (tests 3–4, AC-2)

- First `LW A` → MISS_READ path (§13.2 cyc 1–5 for the load variant: FILL returns data with
  `fill_notify`), MISS_COUNT++.
- Immediate second `LW A` → CHECK→HIT_READ (1 stall cycle), HIT_COUNT++.
- Eviction case: `LW A` (L0) then `LW B` where `B[3:2]==A[3:2]`, different tag → second access is a
  miss (direct-mapped conflict), old line silently replaced (no writeback — write-through keeps SRAM
  current).

## 13.4 THE coherence demo — Scenario A (tests 5–6, AC-4/AC-5)

Precondition: C1 previously loaded address A (line L: cache1 state S, mirror[1][L]=S).
C0 now stores NEW to A. C0's store follows §13.2 cyc 0–9 exactly (store shown as miss; a store hit is
2 rows shorter and identical from the notify on).

| Cyc | C0 side | coherence | C1 side |
|-----|---------|-----------|---------|
| 0–9 | C0 `SW A` write-through (§13.2): **SRAM[A]←NEW at edge of 8**; core0 ack cyc 9 | | |
| 10 | mgr0 NOTIFY_COH: `write_notify0` held | COH_IDLE: `coh_accept0=1`; at edge →PROCESS_WRITE, `mirror[0][L]←M` | |
| 11 | mgr0 → IDLE | PROCESS_WRITE: remote `mirror[1][L]=S ≠ I` → dispatch | |
| 12 | | INVALIDATE_OTHER: `inv_valid1=1, inv_idx1=L`, `inv_fire` pulse (**INV_COUNT++, LED2**) | mgr1 IDLE (defers nothing — it's idle) |
| 13 | | WAIT_INV_ACK | mgr1 WAIT_INVALIDATE: `inv_ack1` pulse; **at edge: cache1 line L ← I** |
| 14 | | at edge: `mirror[1][L]←I`, `inv_valid1←0` → COH_IDLE | mgr1 → IDLE |
| 15 | | | C1 RUN: `LW A` decoded (req registered at edge) |
| 16 | | | mgr1 IDLE → CHECK (latch) |
| 17 | | | CHECK: `state=I` → **miss** → MISS_READ (`miss_event`) |
| 18 | | | MISS_READ: `bus_req1`; arbiter grants m1 |
| 19 | | | AXI_AR: AR handshake |
| 20 | | | AXI_R: `rvalid`, captures **SRAM[A] = NEW** |
| 21 | | | FILL: cache1 line L ← {1,tag,NEW,S}, `fill_notify1` (`mirror[1][L]←S`), `dmem_rdata=NEW, dmem_ack=1` → **C1 commits x2 = NEW** |

**Pass:** C1's register = C0's stored value, not the stale one. COH_STATUS for L: core0=M, core1=S.
INV_COUNT +1. The refetch read SRAM *after* the write-through landed (edge of 8) and *after* the line
was I (edge of 13) — the D8 ordering guarantee holds by construction.

**The #1 silent bug (analysis doc §14) is designed out here**: coherence only fixes *future* loads.
The demo SW must re-read A after the invalidation (this trace does: C1's `LW` is issued at cyc 15,
after the invalidation completed at cyc 14). A stale register value copied before the write is *not*
coherence's job to fix — the TB demo asserts on a fresh load.

## 13.5 Scenario B — simultaneous writes to the same address (test 7, AC-8)

Both cores issue `SW` to A (line L) in the same cycle; neither has a copy... (generic: both may have S).

| Cyc | Events |
|-----|--------|
| 0 | Both cores assert `dmem_req`; both mgrs reach MISS_READ/HIT_WRITE and raise `bus_req0/1` |
| 1 | Arbiter ARB_IDLE: both reqs, `pref=0` (say) → **grant0** — deterministic winner is core 0 this round |
| 2–8 | mgr0 completes its full write (AR for allocate if miss, then AW→W→B); SRAM[A] = C0's value; mgr0 NOTIFY_COH → coherence: mirror[0][L]←M; C1's copy (S) invalidated: `inv_valid1` → mgr1 services it **after** its own current transaction (it's mid-store — deferral rule doc 04 §4.10) |
| 9 | Arbiter done0 → `pref←1` → ARB_IDLE → **grant1** (round-robin flip) |
| 10–16 | mgr1 completes its write; **SRAM[A] = C1's value (last writer wins)**; mgr1 NOTIFY_COH → coherence: mirror[1][L]←M; C0's copy invalidated (M→I) |
| 17 | Both mgrs service/complete any pending invalidations; both lines end in I for line L |

**Pass:** final SRAM[A] = core 1's value (second writer in arbiter order); both caches' line L = I;
exactly 2 `inv_fire` events; no deadlock, no lost notify (mgr1's notify was held until `coh_accept1`
while coherence processed mgr0's — R1 exercised; see also §13.7).

## 13.6 Scenario C — no cached copy in the other core (test 8)

C0 writes A; C1 never loaded A (mirror[1][L]=I, actual cache1 line I).

- mgr0 write-through completes (§13.2 cyc 0–8), NOTIFY_COH.
- Coherence PROCESS_WRITE: mirror[1][L]=I **and** actual=I → **no invalidation dispatched**
  (dispatch condition doc 05 §5.3), INV_COUNT unchanged.
- mgr0 line L → M (own write). C1 untouched.

**Pass:** no `inv_valid1` pulse at all (assertion A2), INV_COUNT unchanged, SRAM updated.

## 13.7 The R1 stress interleaving (why `coh_accept` exists — TB-level check)

Both cores writing near-simultaneously (as §13.5) with coherence mid-processing:

| Cyc | Events |
|-----|--------|
| t | mgr0 notify raised; coherence accepts (mirror[0][L0]←M), dispatches inv to mgr1 |
| t+1 | mgr1 is busy finishing its own store → cannot service inv yet; coherence waits in WAIT_INV_ACK |
| t+2 | mgr1's store completes → mgr1 enters NOTIFY_COH holding `write_notify1` (coherence NOT idle — cannot accept yet) |
| t+3 | mgr1 sees `inv_valid1` in NOTIFY_COH → **escapes** to WAIT_INVALIDATE (notify still held) → `inv_ack1` |
| t+4 | coherence: mirror[1][L]←I → COH_IDLE → accepts mgr1's notify (`coh_accept1`) → mirror[1][L*]←M for mgr1's write, dispatches inv to mgr0 → completes |
| t+5 | mgr1 → IDLE. No notify lost, no deadlock |

Without R1 (hold + escape), step t+2 would lose mgr1's notify or, with a naive hold-without-escape,
deadlock at t+3. Directed/UVM simultaneous-write tests exercise exactly this.

## 13.8 Error path (test 9, AC-11)

C0 executes `LW x5, 0(x6)` with `x6 = 0x0002_0000` (unmapped):

| Cyc | Events |
|-----|--------|
| 0–1 | core RUN→STALL_MEM; mgr0 CHECK: always miss (no such line in SRAM space... tag check happens against line L=idx; state I → miss) |
| 2–4 | AXI read to 0x0002_0000; decoder: `sel_decerr` → DECERR slave |
| 5 | R response: `rresp=DECERR` → mgr0 FILL(err): **no line fill**, `dmem_ack=1, dmem_err=1`, `err_event` |
| 6 | Core commits: **no register writeback** (R5/O3), PC+4; MMIO ERR_STICKY←1 (LED5) |

Store variant: B response DECERR → `ack+err`, no notify, no invalidation, sticky set.

**Pass:** `x5` unchanged (TB checks against pre-load value), ERR_STICKY=1, counters advanced by the
miss, INV_COUNT unchanged. `CONTROL.err_clear` write returns ERR_STICKY to 0.

## 13.9 Doorbell / MMIO flow (supports the FPGA demo and test 10)

C0: `SW token → MMIO 0x0001_0010 (DOORBELL)` → C1 polls `LW 0x0001_0010` until nonzero →
processes → writes 0. Reads of COH_STATUS/INV_COUNT/HIT_COUNT/MISS_COUNT at 0x0001_0000–C give the
TB and the UART printouts their self-check values (test 10: counters match the event counts observed
in tests 2–8).

## 13.10 Directed test map (10 cases → scenarios above)

| # | Test (track doc §4.1) | Scenario | Self-check |
|---|----------------------|----------|------------|
| 1 | Reset | 13.1 | COH_STATUS=0, counters=0, PCs=0, no bus activity |
| 2 | Single-core access | 13.2 | readback == written; hit+miss counters +1/+1 |
| 3 | Cache hit | 13.3 | HIT_COUNT increments, no AXI activity on 2nd load |
| 4 | Cache miss | 13.3 | MISS_COUNT increments, fill visible (fill_notify) |
| 5 | Cross-core coherence | 13.4 | C1 line → I; C1 refetches new value; INV_COUNT +1 |
| 6 | Stale prevention | 13.4 | C1's value ≠ stale; equals C0's write |
| 7 | Simultaneous write | 13.5 (+13.7) | deterministic winner = last writer in RR order; both lines I; no hang |
| 8 | No cached copy | 13.6 | zero invalidation pulses, INV_COUNT unchanged |
| 9 | Error/unmapped | 13.8 | DECERR observed; no writeback; ERR_STICKY set |
| 10 | Counter verification | all | INV/HIT/MISS counters == events counted by TB monitor |

## 13.11 Minimal demo programs (analysis doc §15, expanded with the re-read rule)

```asm
;; core0.hex (I-SRAM 0)                      ;; core1.hex (I-SRAM 1)
    lui  x6, 0x0          # x6 = shared base     lui  x6, 0x0
    addi x5, x0, 0xDEAD>>shl...                 lw   x10, 0(x6)      # (optional) prime C1's copy -> S
    sw   x5, 0(x6)        # write-through       lw   x9,  0x10(x6)   # poll DOORBELL... (MMIO addr const)
    # coherence: inv dispatched to C1                            beq  x9, x0, -8       # spin
    jal  x0, 0            # halt (self-loop)     # (invalidation happened before this point)
                                                 lw   x11, 0(x6)      # RE-READ after invalidation
                                                 sw   x11, 0x18(x6)   # publish result for TB/UART
                                                 jal  x0, 0           # halt
```

(Real encodings generated Day 3, T3.8–T3.9; the essential rule: **core 1 must re-load after the
invalidation, never trust a register value cached before it.**)

## 13.12 FPGA demo readback (FR-6.2/6.3)

The demo prints over UART (`=== demo` protocol in the track doc §8) driven by the same program flow;
LED0/LED1 blink on memory activity, LED2 pulses per invalidation, LED3/4 on hit/miss, LED5 on error,
LED6–7 from `LED_REG`. A stale read would print the old value → the demo doubles as a live self-check.
