# 06 — Round-Robin Arbiter (T1.4): `axi_lite_arbiter.sv`

Acceptance: *2-master arbiter truth table*. Two AXI4-Lite masters (the two D-cache managers) share one
downstream slave port (into the address decoder, doc 07). Rules from the TRD §3.5:

- Arbitration: **round-robin** ("grant the master that has been waiting longest").
- **Grant is held until the master's transaction completes** (one AW+W+B or one AR+R per grant).
- Deadlock-free: every transaction has bounded completion.

---

## 6.1 Interface

| Signal | Dir | Description |
|--------|-----|-------------|
| `req0`, `req1` | in | master N wants the bus (cache mgr `bus_req`, held from MISS_READ/HIT_WRITE until transaction end) |
| `awvalid0/1…rready0/1` | in | each master's full AXI4-Lite master port (5 channels) |
| `awvalid_s…rready_s` | out | shared downstream AXI4-Lite slave port |
| `grant0`, `grant1` | out | 1-hot grant; also routes slave `*ready` back to the granted master and its `bvalid/rvalid/bresp/rresp` back |

## 6.2 Arbitration truth table (the T1.4 deliverable)

`pref` = preference pointer (which master is granted on a simultaneous request).
**Reset value `pref = 0`** → at boot, simultaneous requests go to **core 0** (TRD Scenario B:
"deterministic winner, e.g., Core 0"), then the pointer alternates after every completed transaction —
true round-robin fairness.

| req1 | req0 | pref | grant1 | grant0 | comment |
|------|------|------|--------|--------|---------|
| 0 | 0 | × | 0 | 0 | idle |
| 0 | 1 | × | 0 | **1** | only master 0 |
| 1 | 0 | × | **1** | 0 | only master 1 |
| 1 | 1 | 0 | 0 | **1** | simultaneous → core 0 wins (also at reset) |
| 1 | 1 | 1 | **1** | 0 | simultaneous → core 1 wins (fairness flip) |

Equations:

```
grant0 =  req0 && (!req1 || (pref == 0))
grant1 =  req1 && (!req0 || (pref == 1))
// invariant: exactly one grant when any req is high
```

`pref` update: `pref <= ~pref` **on completion of the granted transaction** (not on grant — a granted
master keeps the bus for its whole transaction and wins any re-request race... actually with
grant-held semantics, `pref` must flip only when the bus returns to idle, so a master that finishes
and immediately re-requests does not monopolize).

## 6.3 FSM

```
              rst
               ▼
         ┌──────────┐  grant0 (=req0&&(!req1||pref==0))     ┌──────────┐
         │ ARB_IDLE │ ────────────────────────────────────► │ ARB_G0   │
         │          │ ◄──────────────────────────────────── │ hold txn │
         │          │      done0 (B or R handshake of m0)   └──────────┘
         │          │  grant1 (=req1&&(!req0||pref==1))          │ pref←0
         │          │ ────────────────────────────────────► ┌──────────┐
         └──────────┘                                       │ ARB_G1   │
              ▲   ◄───────────────────────────────────────  │ hold txn │
              │          done1 (B or R handshake of m1)     └──────────┘
              │                                                  │ pref←1
              └──────────────────────────────────────────────────┘
```

| State | Encoding | Condition | Next | Actions |
|-------|----------|-----------|------|---------|
| ARB_IDLE | 2'b00 (reset) | `grant0` | ARB_G0 | mux master 0 → slave |
| ARB_IDLE | | `!grant0 && grant1` | ARB_G1 | mux master 1 → slave |
| ARB_IDLE | | else | ARB_IDLE | slave idle (`awvalid_s/arvalid_s = 0`) |
| ARB_G0 | 2'b01 | `done0` | ARB_IDLE | `pref ← 0` (flip to other) |
| ARB_G0 | | else | ARB_G0 | hold |
| ARB_G1 | 2'b10 | `done1` | ARB_IDLE | `pref ← 1` |
| ARB_G1 | | else | ARB_G1 | hold |

`done_m = (bvalid_m && bready_s) || (rvalid_m && rready_s)` — the *final* handshake of the granted
master's transaction (Lite: B ends a write, R ends a read; there is exactly one of each per
transaction).

## 6.4 Mux wiring (complete, both directions)

```
// request side (per channel): granted master drives the slave port
awvalid_s = grant0 ? awvalid0 : awvalid1;      awaddr_s = grant0 ? awaddr0 : awaddr1;
wvalid_s  = grant0 ? wvalid0   : wvalid1;      wdata_s  = grant0 ? wdata0  : wdata1;
wstrb_s   = grant0 ? wstrb0    : wstrb1;       arvalid_s= grant0 ? arvalid0: arvalid1;
araddr_s  = grant0 ? araddr0   : araddr1;
// response side: slave ready & responses go to the granted master only
awready0 = grant0 && awready_s;   awready1 = grant1 && awready_s;
wready0  = grant0 && wready_s;    wready1  = grant1 && wready_s;
bvalid0  = grant0 && bvalid_s;    bvalid1  = grant1 && bvalid_s;   // bresp/bdata likewise
arready0 = grant0 && arready_s;   arready1 = grant1 && arready_s;
rvalid0  = grant0 && rvalid_s;    rvalid1  = grant1 && rvalid_s;   // rdata/rresp likewise
bready_s = grant0 ? bready0 : bready1;   rready_s = grant0 ? rready0 : rready1;
```

All outputs have reset values of 0; `pref` resets to 0.

## 6.5 Deadlock-freedom argument

1. A granted master always completes: every downstream slave responds in bounded cycles
   (shared SRAM 1–4 cycles; MMIO/UART/GPIO 1–3 cycles; DECERR slave 1–3 cycles — doc 07/08/09),
   so `done` is guaranteed.
2. ARB_IDLE always resolves within 1 cycle when any request is pending (pure truth table), and both
   masters' requests are levels held until their transaction completes (doc 04 §4.7) — no request is
   lost.
3. The invalidation sideband does **not** pass through the arbiter (D8), so an in-flight invalidation
   never blocks or waits on bus traffic.
4. Coherence `write_notify` fires **after** B completes (mgr has already released the bus need), so
   coherence processing never holds the arbiter.

⇒ Every transaction is bounded; the arbiter cannot starve a master longer than one other transaction
(true round-robin). Corollary used in doc 04 §4.10: while master A holds the grant, master B's writes
cannot complete, so B's `write_notify` (and hence any invalidation aimed at A's in-flight line) cannot
be raised mid-A-transaction.

## 6.6 Assertions

- `!(grant0 && grant1)` — one-hot grants (track doc).
- `req_m && !grant_m |=> req_m until grant_m` — requests are never dropped.
- `grant_m |=> grant_m until done_m` — grant held for the whole transaction.
- Fairness: between two consecutive grants of master m, master o was granted at least once if it kept
  `req_o` high (round-robin property; checked by UVM sequences).
