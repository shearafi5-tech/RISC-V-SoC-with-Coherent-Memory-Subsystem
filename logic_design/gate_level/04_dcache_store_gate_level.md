# Gate-Level Circuit: D-Cache Storage, Tag Compare & Hit Logic

Source: `04_dcache_fsm.md` §4.1–§4.2, §4.3 (interface), §4.10  
Logisim sub-circuit names: **`DCacheStore`**, **`TagCompare`**, **`HitLogic`**, **`CacheLineMux`**

These sub-circuits represent the *storage* half of the D-cache (`d_cache.sv`).  
The FSM that controls them is in document 05. Together they form the complete private D-cache per core.

---

## 1. Cache Geometry Review

```
Lines  : 4 (direct-mapped)
Width  : 1 word = 32 bits data + 28-bit tag + 1-bit valid + 2-bit coh_state = 63 bits per line
States : I=2'b00  S=2'b01  M=2'b10

Address breakdown:
  addr[31:4]  = tag  (28 bits)
  addr[3:2]   = idx  (2 bits → selects one of 4 lines)
  addr[1:0]   = byte lane (used by core, not by cache storage)

Line structure (packed, 63 bits total):
  [62]      valid
  [61:34]   tag[27:0]
  [33:2]    data[31:0]
  [1:0]     coh_state[1:0]
```

---

## 2. Sub-circuit: `DCacheStore` — 4-Line Cache Register Array

### 2.1 Purpose

Stores the 4 cache lines as registers. Supports synchronous write (on FSM write commands) and combinational read of all 4 lines simultaneously. The FSM (doc 05) drives the write-enable and write-data for each line.

### 2.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock (tunnel) |
| `RST_N` | In | 1 | Async reset (tunnel) |
| `WR_IDX` | In | 2 | Which line to write (0–3) |
| `WR_EN` | In | 1 | Write enable (from FSM) |
| `WR_VALID` | In | 1 | New valid bit |
| `WR_TAG` | In | 28 | New tag |
| `WR_DATA` | In | 32 | New data word |
| `WR_STATE` | In | 2 | New coherence state (I/S/M) |
| `LINE0_Q` | Out | 63 | Line 0 full contents (combinational) |
| `LINE1_Q` | Out | 63 | Line 1 full contents |
| `LINE2_Q` | Out | 63 | Line 2 full contents |
| `LINE3_Q` | Out | 63 | Line 3 full contents |

### 2.3 Per-line register structure

Each line is stored as a single 63-bit register. The write-enable for each line is individually gated using a 2-to-4 decoder driven by `WR_IDX`.

#### Write-enable decoder

```
Component: Plexers > Decoder
  Select bits: 2
  Outputs:     4 (one-hot)

  WR_IDX[1:0] → Decoder → {WR_EN_3, WR_EN_2, WR_EN_1, WR_EN_0}
  (out[i] = 1 when WR_IDX == i)

Per-line final enable:
  LINE_WEN[i] = Decoder.out[i] AND WR_EN
  Logisim: 4× AND gate (2-in), one per line
    Input 0: Decoder.out[i]
    Input 1: WR_EN
    Output: LINE_WEN[i] → Register[i].EN
```

#### Write data assembly (63-bit combiner)

```
Assemble WR_VALID, WR_TAG, WR_DATA, WR_STATE into a 63-bit write bus.

Logisim: Splitter (combine mode, 63-bit output)
  Bits [62]:    WR_VALID[0]
  Bits [61:34]: WR_TAG[27:0]
  Bits [33:2]:  WR_DATA[31:0]
  Bits [1:0]:   WR_STATE[1:0]
  Output: WR_LINE[62:0]
```

#### Per-line registers (×4)

```
For each line i ∈ {0,1,2,3}:

  Component: Memory > Register, 63 bits
    CLK: CLK tunnel
    CLR: NOT(RST_N)  → all bits clear to 0 on reset
          (valid=0, state=I=00, tag=0, data=0 — correct reset state per §12.3)
    EN:  LINE_WEN[i]
    D:   WR_LINE[62:0]   (shared write bus — all 4 see same data, gated by EN)
    Q:   LINE{i}_Q[62:0] → output pin LINE{i}_Q
```

### 2.4 Reset behavior

```
RST_N = 0 (async):
  NOT(RST_N) → CLR = 1 on all 4 registers
  All 63 bits → 0:
    valid  = 0
    tag    = 28'b0
    data   = 32'b0
    state  = 2'b00 = I ✓

All lines reset to Invalid state as required by AC-9.
```

### 2.5 ASCII Block Diagram

```
WR_IDX[1:0] ──► Decoder(2→4) ──┬── out[0] ──► AND ──► LINE_WEN[0] ──► Reg0.EN
                                 ├── out[1] ──► AND ──► LINE_WEN[1] ──► Reg1.EN
                                 ├── out[2] ──► AND ──► LINE_WEN[2] ──► Reg2.EN
WR_EN ──────────────────────────┴── out[3] ──► AND ──► LINE_WEN[3] ──► Reg3.EN
                  (AND gate per line shares WR_EN)

WR_VALID[0] ─┐
WR_TAG[27:0] ─┤
WR_DATA[31:0]─┤── Splitter(combine→63b) ──► WR_LINE[62:0] ──┬──► Reg0.D
WR_STATE[1:0]─┘                                              ├──► Reg1.D
                                                             ├──► Reg2.D
                                                             └──► Reg3.D

CLK (tunnel) ──────────────────────────────────────────────► Reg0/1/2/3.CLK
RST_N ──► NOT ─────────────────────────────────────────────► Reg0/1/2/3.CLR

Reg0.Q ──► LINE0_Q[62:0]
Reg1.Q ──► LINE1_Q[62:0]
Reg2.Q ──► LINE2_Q[62:0]
Reg3.Q ──► LINE3_Q[62:0]
```

---

## 3. Sub-circuit: `TagCompare` — Tag & State Extraction + Comparison

### 3.1 Purpose

Takes one cache line's 63-bit register contents and a request address, extracts fields, and computes whether there is a valid, non-Invalid cache hit on that line.

### 3.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `LINE_Q` | In | 63 | One cache line (from DCacheStore) |
| `REQ_TAG` | In | 28 | Tag field of request address = addr[31:4] |
| `LINE_VALID` | Out | 1 | Extracted valid bit: LINE_Q[62] |
| `LINE_TAG` | Out | 28 | Extracted tag: LINE_Q[61:34] |
| `LINE_DATA` | Out | 32 | Extracted data: LINE_Q[33:2] |
| `LINE_STATE` | Out | 2 | Extracted coh_state: LINE_Q[1:0] |
| `TAG_MATCH` | Out | 1 | LINE_TAG == REQ_TAG |
| `STATE_NI` | Out | 1 | coh_state != I (= coh_state != 2'b00) |
| `HIT` | Out | 1 | valid AND tag_match AND state_NI |

### 3.3 Field extraction (Splitter)

```
Component: Wiring > Splitter (fan-out mode, input = 63 bits)
  Output A: LINE_Q[62]    → LINE_VALID (1 bit)
  Output B: LINE_Q[61:34] → LINE_TAG   (28 bits)
  Output C: LINE_Q[33:2]  → LINE_DATA  (32 bits)
  Output D: LINE_Q[1:0]   → LINE_STATE (2 bits)

All four outputs connect to the corresponding output pins directly.
```

### 3.4 Tag comparison

```
Component: Comparator (28-bit)
  Input A:  LINE_TAG[27:0]
  Input B:  REQ_TAG[27:0]
  A == B output: TAG_MATCH
```

### 3.5 State-not-Invalid check

```
coh_state == I means LINE_STATE[1:0] == 2'b00
STATE_NI = NOT(state is I) = NOT(LINE_STATE[1] == 0 AND LINE_STATE[0] == 0)
         = LINE_STATE[1] OR LINE_STATE[0]

Logisim: OR gate (2-in)
  Input 0: LINE_STATE[1]   (extracted via 1-bit Splitter from LINE_STATE)
  Input 1: LINE_STATE[0]
  Output:  STATE_NI
```

### 3.6 HIT signal

```
HIT = LINE_VALID AND TAG_MATCH AND STATE_NI

Logisim: AND gate (3-in)
  Input 0: LINE_VALID
  Input 1: TAG_MATCH
  Input 2: STATE_NI
  Output:  HIT
```

### 3.7 ASCII Block Diagram

```
LINE_Q[62:0]
     │
     └── Splitter(63→1+28+32+2) ──┬── [62]    → LINE_VALID ──┐
                                   ├── [61:34] → LINE_TAG  ──┬──► Comparator(28b) ──► TAG_MATCH ──┐
                                   ├── [33:2]  → LINE_DATA    │                                    │
                                   └── [1:0]   → LINE_STATE   │   LINE_STATE[1] ──► OR ──► STATE_NI─┤
REQ_TAG[27:0] ──────────────────────────────────────────────► ┘   LINE_STATE[0] ──┘               │
                                                                                                    │
LINE_VALID ─────────────────────────────────────────────────────────────────────────────────► AND(3)─► HIT
TAG_MATCH ──────────────────────────────────────────────────────────────────────────────────►      │
STATE_NI  ──────────────────────────────────────────────────────────────────────────────────►      ┘
```

---

## 4. Sub-circuit: `HitLogic` — 4-Line Hit Resolution

### 4.1 Purpose

Takes the 4 `TagCompare` outputs for all cache lines and the 2-bit index from the request address. Produces the single `CACHE_HIT` signal and routes the correct line's data to the output.

### 4.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `REQ_ADDR` | In | 32 | Full request address |
| `LINE0_Q` | In | 63 | Line 0 register contents |
| `LINE1_Q` | In | 63 | Line 1 register contents |
| `LINE2_Q` | In | 63 | Line 2 register contents |
| `LINE3_Q` | In | 63 | Line 3 register contents |
| `IDX` | Out | 2 | = REQ_ADDR[3:2] (index) |
| `TAG` | Out | 28 | = REQ_ADDR[31:4] (tag) |
| `CACHE_HIT` | Out | 1 | Hit on the indexed line |
| `HIT_DATA` | Out | 32 | Data from the hit line |
| `HIT_STATE` | Out | 2 | Coherence state of the selected line |
| `HIT_VALID` | Out | 1 | Valid bit of the selected line |

### 4.3 Address field extraction

```
Splitter on REQ_ADDR[31:0]:
  Bits [1:0]  → discard (byte lane, not used here)
  Bits [3:2]  → IDX[1:0]       (output pin + drives mux selects)
  Bits [31:4] → TAG[27:0]       (output pin + feeds TagCompare blocks)
```

### 4.4 Four TagCompare instances

```
One TagCompare sub-circuit instantiated per line:

  TC0: LINE_Q = LINE0_Q, REQ_TAG = TAG → HIT0, DATA0, STATE0, VALID0
  TC1: LINE_Q = LINE1_Q, REQ_TAG = TAG → HIT1, DATA1, STATE1, VALID1
  TC2: LINE_Q = LINE2_Q, REQ_TAG = TAG → HIT2, DATA2, STATE2, VALID2
  TC3: LINE_Q = LINE3_Q, REQ_TAG = TAG → HIT3, DATA3, STATE3, VALID3
```

### 4.5 Hit selection (direct-mapped: only the indexed line can hit)

```
In a direct-mapped cache, address[3:2] selects exactly one line.
Only that line's HIT signal is meaningful for a cache hit decision.

CACHE_HIT = MUX4(IDX, HIT0, HIT1, HIT2, HIT3)

Logisim: Plexers > Multiplexer
  Data bits:   1
  Select bits: 2
  Input 0: HIT0
  Input 1: HIT1
  Input 2: HIT2
  Input 3: HIT3
  Select:  IDX[1:0]
  Output:  CACHE_HIT
```

### 4.6 Selected line data, state, valid

```
HIT_DATA  = MUX4(IDX, DATA0,  DATA1,  DATA2,  DATA3)
HIT_STATE = MUX4(IDX, STATE0, STATE1, STATE2, STATE3)
HIT_VALID = MUX4(IDX, VALID0, VALID1, VALID2, VALID3)

Three Multiplexers:
  MUX_DATA  (32-bit, 2-bit select): → HIT_DATA
  MUX_STATE (2-bit,  2-bit select): → HIT_STATE
  MUX_VALID (1-bit,  2-bit select): → HIT_VALID

All three share IDX[1:0] as their Select input.
```

### 4.7 ASCII Block Diagram

```
REQ_ADDR[31:0]
     │
     └─ Splitter ─┬─ [31:4] → TAG[27:0] ──────────► TC0.REQ_TAG, TC1.REQ_TAG, TC2.REQ_TAG, TC3.REQ_TAG
                  └─ [3:2]  → IDX[1:0] (output pin) ─────────────────────────────────────────┐
                                                                                              │
LINE0_Q──► TC0 ──┬── HIT0   ──┐                                                              │
LINE1_Q──► TC1 ──┼── HIT1   ──┤                                                              │
LINE2_Q──► TC2 ──┼── HIT2   ──┤── MUX4(1b) ──► CACHE_HIT                                    │
LINE3_Q──► TC3 ──┼── HIT3   ──┘   sel=IDX ◄────────────────────────────────────────────────┘
                 │                                                                           │
                 ├── DATA0..3 ──► MUX4(32b) ──► HIT_DATA   sel=IDX ◄───────────────────────┤
                 ├── STATE0..3 ─► MUX4(2b)  ──► HIT_STATE  sel=IDX ◄───────────────────────┤
                 └── VALID0..3 ─► MUX4(1b)  ──► HIT_VALID  sel=IDX ◄───────────────────────┘
```

---

## 5. Sub-circuit: `CacheLineMux` — Merge-Write Helper

### 5.1 Purpose

Implements the byte-masked "merge" operation used during write-allocate (store hit and store-miss fill path):  
`merged[byte] = wdata[byte]  if  wmask[byte]=1`  
`merged[byte] = old[byte]    if  wmask[byte]=0`

This is purely combinational and is called from the FSM data path.

### 5.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `OLD_DATA` | In | 32 | Existing line data (from cache or AXI read) |
| `WR_DATA` | In | 32 | Store data (already lane-rotated by core) |
| `WMASK` | In | 4 | Byte enables (lane-rotated by core) |
| `MERGED` | Out | 32 | Byte-merged result |

### 5.3 Gate-level structure (per byte lane)

```
For each byte lane b ∈ {0,1,2,3} (each covering 8 bits):

  Let HI = b*8+7, LO = b*8

  OLD_B[7:0]  = OLD_DATA[HI:LO]
  WR_B[7:0]   = WR_DATA[HI:LO]
  MASK_B      = WMASK[b]           (single bit)

  Per-bit (for each bit k = 0..7 within the byte):
    MERGED[LO+k] = (MASK_B AND WR_B[k]) OR (NOT(MASK_B) AND OLD_B[k])

  This is a 2:1 MUX per bit where Select=MASK_B:
    MUX1b: Input0=OLD_B[k], Input1=WR_B[k], Select=MASK_B → MERGED[LO+k]

  In Logisim: use a single 8-bit MUX per byte lane (more compact):
    MUX_BYTEb (8-bit, 1-bit select):
      Input 0: OLD_DATA[(b*8+7):(b*8)]
      Input 1: WR_DATA[(b*8+7):(b*8)]
      Select:  WMASK[b]
      Output:  MERGED[(b*8+7):(b*8)]
```

### 5.4 Final assembly

```
Four 8-bit MUXes, one per byte, combine into MERGED[31:0] via a Splitter (combine mode):
  Splitter: 4 × 8-bit inputs → 1 × 32-bit output
    bits [7:0]   = MUX_BYTE0.out
    bits [15:8]  = MUX_BYTE1.out
    bits [23:16] = MUX_BYTE2.out
    bits [31:24] = MUX_BYTE3.out
  Output: MERGED[31:0]
```

### 5.5 ASCII Block Diagram

```
OLD_DATA[31:0] ─── Splitter ──┬── [7:0]   → MUX_B0.in0  ─►─┐
WR_DATA[31:0]  ─── Splitter ──┼── [7:0]   → MUX_B0.in1   ─►─┤
WMASK[3:0]     ─── Splitter ──┼── [0]     → MUX_B0.sel   ─►─┤ MUX_B0 (8b) → [7:0]  ─┐
                               │                              │                        │
                               ├── [15:8]  → MUX_B1.in0  ─►─┤                        │
                               ├── [15:8]  → MUX_B1.in1   ─►─┤ MUX_B1 (8b) → [15:8] ─┤──► Combine ──► MERGED[31:0]
                               ├── [1]     → MUX_B1.sel   ─►─┤                        │    Splitter
                               │                              │                        │
                               ├── [23:16] → MUX_B2.in0  ─►─┤                        │
                               ├── [23:16] → MUX_B2.in1   ─►─┤ MUX_B2 (8b) → [23:16]─┤
                               ├── [2]     → MUX_B2.sel   ─►─┘                        │
                               │                                                       │
                               ├── [31:24] → MUX_B3.in0  ─►─┐                        │
                               ├── [31:24] → MUX_B3.in1   ─►─┤ MUX_B3 (8b) → [31:24]─┘
                               └── [3]     → MUX_B3.sel   ─►─┘
```

---

## 6. Complete `d_cache.sv` Block — How the Sub-circuits Connect

```
This is the "d_cache" module that the FSM (doc 05) sits alongside:

Inputs from FSM (write path):
  WR_EN, WR_IDX[1:0], WR_VALID, WR_TAG[27:0], WR_DATA[31:0], WR_STATE[1:0]
  → DCacheStore

Inputs from core (lookup path):
  REQ_ADDR[31:0]
  → HitLogic (which instantiates 4× TagCompare internally)
  → DCacheStore provides LINE0_Q..LINE3_Q to HitLogic

Merge helper:
  OLD_DATA (from HitLogic.HIT_DATA or AXI read result), WR_DATA, WMASK
  → CacheLineMux → MERGED_DATA
  MERGED_DATA feeds back as WR_DATA into DCacheStore when FSM writes merged line

Outputs to FSM (lookup results):
  HitLogic.CACHE_HIT → used by FSM in CHECK state
  HitLogic.HIT_DATA  → driven to dmem_rdata in HIT_READ state
  HitLogic.IDX       → latched as l_idx
  HitLogic.TAG       → latched as l_tag
  HitLogic.HIT_STATE → used for state tracking

                   ┌─────────────────────────────────────────┐
  REQ_ADDR ──────► │            HitLogic                     │──► CACHE_HIT
                   │  (4× TagCompare internally)             │──► HIT_DATA
    LINE0..3 ◄─────│◄── DCacheStore.LINE{0..3}_Q             │──► HIT_STATE
    (fed back)     └─────────────────────────────────────────┘──► IDX, TAG

  FSM write ─────► DCacheStore.WR_*
  
  OLD_DATA + WR_DATA + WMASK ──► CacheLineMux ──► MERGED ──► DCacheStore.WR_DATA
```

---

## 7. Logisim Component Settings Summary

| Sub-circuit | Component | Setting | Value |
|-------------|-----------|---------|-------|
| DCacheStore | Register (×4) | Data bits | 63 |
| DCacheStore | Register | Trigger | Rising edge |
| DCacheStore | Register | Enable | Yes |
| DCacheStore | Register | CLR (async) | Active high → NOT(RST_N) |
| DCacheStore | Decoder | Select bits | 2 |
| DCacheStore | AND gates (×4) | Inputs | 2; Data 1 bit |
| DCacheStore | Splitter (combine) | Output | 63 bits |
| TagCompare | Splitter (fan-out) | Input | 63 bits; outputs 1+28+32+2 |
| TagCompare | Comparator | Data bits | 28 |
| TagCompare | OR gate | Inputs | 2; Data 1 bit |
| TagCompare | AND gate | Inputs | 3; Data 1 bit |
| HitLogic | Splitter (fan-out) | Input | 32; extracts [31:4] and [3:2] |
| HitLogic | MUX (CACHE_HIT) | Data bits | 1; Select bits 2 |
| HitLogic | MUX (HIT_DATA) | Data bits | 32; Select bits 2 |
| HitLogic | MUX (HIT_STATE) | Data bits | 2; Select bits 2 |
| HitLogic | MUX (HIT_VALID) | Data bits | 1; Select bits 2 |
| CacheLineMux | MUX (×4 byte lanes) | Data bits | 8; Select bits 1 |
| CacheLineMux | Splitter (final combine) | Output | 32 bits from 4×8 |
