# 11 — Memory Map (T1.5b)

Acceptance: *addresses shown for everything*. Per TRD §5, I-SRAMs are **not** memory-mapped (private
fetch path, FR-5.2).

---

## 11.1 Global map

```
0xFFFF_FFFF ─┐
             │  anything else → DECERR slave (bresp/rresp = 2'b11)      (doc 07)
0x0001_0300 ─┘
0x0001_02FF ─┬─────────────────────────────────────────────
             │  GPIO / LED            0x00 LED_REG (RW, bits[7:6] → LED7–LED6)
0x0001_0200 ─┴─────────────────────────────────────────────
0x0001_01FF ─┬─────────────────────────────────────────────
             │  UART                  0x00 TX_DATA (W)   0x04 TX_STATUS (R: bit0 ready)
             │                        0x08 RX_DATA (R)   0x0C RX_STATUS (R: bit0 valid)
0x0001_0100 ─┴─────────────────────────────────────────────
0x0001_00FF ─┬─────────────────────────────────────────────
             │  MMIO registers        0x00 COH_STATUS (RO, 8×2b states)
             │                        0x04 INV_COUNT  (RO)
             │                        0x08 HIT_COUNT  (RO)
             │                        0x0C MISS_COUNT (RO)
             │                        0x10 DOORBELL   (RW)
             │                        0x14 CONTROL    (RW: b0 coh_enable, b1 cnt_clear, b2 err_clear)
0x0001_0000 ─┴─────────────────────────────────────────────
0x0000_0FFF ─┬─────────────────────────────────────────────
             │  SHARED DATA SRAM      1024 × 32-bit words, byte-writable (wstrb)
             │  = the single source of truth (FR-5.1)
0x0000_0000 ─┴─────────────────────────────────────────────
```

Decode equations: doc 07 §7.1. All bus addresses are byte addresses; SRAM words are selected by
`addr[11:2]`.

## 11.2 Cache / coherence addressing breakdown

```
31        12 11    4 3  2 1 0
┌───────────┬────────┬─────┬─────┐
│  tag[31:4]│ (fixed)│ idx │byte │     shared-SRAM-space address
└───────────┴────────┴─────┴─────┘
      │                 │
      │ 28-bit tag      └─ line index: cache line + coherence mirror line (4 entries)
      └─ compared against lines[idx].tag for the hit decision
```

- Direct-mapped: every shared-SRAM word maps to exactly one cache line = `addr[3:2]`.
- The coherence mirror uses the same 4-line index — one mirror entry per (line, core).
- `addr[1:0]` is the byte lane: used by the core for load resize / store-lane rotation (doc 03 §6) and
  by slaves via `wstrb`.
- Addresses outside `0x0000_0000–0x0000_0FFF` never touch the SRAM (decoder routes them) — so a cache
  line's tag upper bits are always 0 in legal use; storing the full 28-bit tag still makes the hit
  check exact.

## 11.3 Worked examples

| Address | Word idx | Cache line | Tag | Slaves that match |
|---------|----------|-----------|-----|--------------------|
| `0x0000_0000` | 0 | L0 | 0x0 | SRAM |
| `0x0000_0004` | 1 | L1 | 0x0 | SRAM |
| `0x0000_0208` | 0x82 = 130 | L2 (130 mod 4) | 0x20 | SRAM |
| `0x0001_000C` | — | — | — | MMIO (MISS_COUNT) |
| `0x0001_0100` | — | — | — | UART (TX_DATA) |
| `0x0001_0200` | — | — | — | GPIO (LED_REG) |
| `0x0000_1000` | — | — | — | **DECERR** (first unmapped word after SRAM) |
| `0x0002_0000` | — | — | — | **DECERR** |

Demo-program convention (doc 13): shared variables live at `0x0000_0000`–`0x0000_0010`; core
mailboxes at `0x0000_0014` (core1→core0) and `0x0000_0018` (core0→core1) inside the SRAM, or the MMIO
DOORBELL for cross-core signaling.
