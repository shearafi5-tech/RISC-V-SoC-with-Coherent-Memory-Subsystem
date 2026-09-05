# Gate-Level Circuit: D-Cache Manager FSM (Logisim Sub-circuit `DCacheMgrFSM`)

Source: `04_dcache_fsm.md` §4.4–§4.8  
Logisim sub-circuit name: **`DCacheMgrFSM`**  
Contains helper sub-circuits: **`StateReg`** (latched request registers), **`NextStateLogic`**, **`OutputLogic`**

This is the largest and most complex single FSM in the SoC — 13 states, 34 transition rows, and two orthogonal control paths (AXI read and AXI write) sharing the same state register.

---

## 1. State Encoding (4-bit)

| State | Encoding | Role |
|-------|----------|------|
| IDLE | 4'd0 | Wait; service inv_valid with priority |
| CHECK | 4'd1 | Decode latched request (hit/miss/uncached) |
| HIT_READ | 4'd2 | Return cache data, assert ack |
| MISS_READ | 4'd3 | Assert bus_req, wait for AXI grant |
| AXI_AR | 4'd4 | Send AR channel, wait arready |
| AXI_R | 4'd5 | Wait rvalid, capture read data |
| FILL | 4'd6 | Write line to cache, return data or proceed to write |
| HIT_WRITE | 4'd7 | Merge & update line to M, proceed to AXI write |
| AXI_AW | 4'd8 | Send AW channel, wait awready |
| AXI_W | 4'd9 | Send W channel, wait wready |
| AXI_B | 4'd10 | Wait bvalid, handle OKAY/ERR |
| NOTIFY_COH | 4'd11 | Hold write_notify until coh_accept |
| WAIT_INVALIDATE | 4'd12 | Service inv_valid immediately, remember notify_pending |

---

## 2. Pin List

### Inputs

| Pin | Bits | Description |
|-----|------|-------------|
| `CLK` | 1 | Clock (tunnel) |
| `RST_N` | 1 | Async reset (tunnel) |
| `DMEM_REQ` | 1 | Core request (level) |
| `DMEM_WE` | 1 | 1=store, 0=load |
| `DMEM_ADDR` | 32 | Byte address |
| `DMEM_WDATA` | 32 | Store data (lane-rotated) |
| `DMEM_WMASK` | 4 | Byte enables |
| `CACHE_HIT` | 1 | From HitLogic (combinational) |
| `HIT_DATA` | 32 | From HitLogic (combinational) |
| `HIT_STATE` | 2 | From HitLogic |
| `AXI_ARREADY` | 1 | AR channel ready from slave |
| `AXI_RVALID` | 1 | R channel valid from slave |
| `AXI_RDATA` | 32 | Read data from slave |
| `AXI_RRESP` | 2 | Read response (OKAY=00, ERR≠00) |
| `AXI_AWREADY` | 1 | AW channel ready |
| `AXI_WREADY` | 1 | W channel ready |
| `AXI_BVALID` | 1 | B channel valid |
| `AXI_BRESP` | 2 | Write response |
| `BUS_GRANT` | 1 | Arbiter grant for this master |
| `COH_ACCEPT` | 1 | Coherence controller accepted write_notify |
| `INV_VALID` | 1 | Incoming invalidation request |
| `INV_IDX` | 2 | Index of line to invalidate |

### Outputs

| Pin | Bits | Description |
|-----|------|-------------|
| `DMEM_RDATA` | 32 | Load return data |
| `DMEM_ACK` | 1 | Commit pulse |
| `DMEM_ERR` | 1 | Error pulse (with ack) |
| `BUS_REQ` | 1 | Arbiter request |
| `AXI_ARVALID` | 1 | AR valid |
| `AXI_ARADDR` | 32 | AR address |
| `AXI_RREADY` | 1 | R ready |
| `AXI_AWVALID` | 1 | AW valid |
| `AXI_AWADDR` | 32 | AW address |
| `AXI_WVALID` | 1 | W valid |
| `AXI_WDATA` | 32 | W data |
| `AXI_WSTRB` | 4 | W byte strobes |
| `AXI_BREADY` | 1 | B ready |
| `WRITE_NOTIFY` | 1 | Coherence notify (held) |
| `WRITE_ADDR` | 32 | Address notified |
| `INV_ACK` | 1 | Invalidation acknowledge pulse |
| `FILL_NOTIFY` | 1 | Fill-to-S pulse (R2) |
| `FILL_IDX` | 2 | Line index of fill |
| `HIT_EVENT` | 1 | Hit counter pulse |
| `MISS_EVENT` | 1 | Miss counter pulse |
| `ERR_EVENT` | 1 | Error event pulse |
| `WR_EN` | 1 | Write enable to DCacheStore |
| `WR_IDX` | 2 | Line index to write |
| `WR_VALID` | 1 | Valid bit to write |
| `WR_TAG` | 28 | Tag to write |
| `WR_DATA` | 32 | Data to write |
| `WR_STATE` | 2 | Coherence state to write |

---

## 3. State Register (4-bit)

```
Component: Memory > Register, 4 bits
  CLK: CLK tunnel
  CLR: NOT(RST_N)     → async reset to 0 = IDLE
  EN:  1 (always — state always updates)
  D:   NEXT_STATE[3:0]
  Q:   CURR_STATE[3:0]

Reset value: 4'd0 = IDLE ✓
```

---

## 4. Internal Latched Registers (captured at IDLE→CHECK transition)

Four registers latch the core's request when entering CHECK:

```
Latch-enable signal:
  INTO_CHECK = (CURR_STATE == IDLE) AND DMEM_REQ AND NOT(INV_VALID)
  ← this is the condition from transition row #2 of §4.6 in the source doc

Logisim: AND gate (3-in): (STATE==IDLE), DMEM_REQ, NOT(INV_VALID) → LATCH_EN

Registers (all synchronous, enabled by LATCH_EN):

  L_ADDR  : Register(32b, EN=LATCH_EN), D=DMEM_ADDR,  Q=l_addr[31:0]
  L_WDATA : Register(32b, EN=LATCH_EN), D=DMEM_WDATA, Q=l_wdata[31:0]
  L_WMASK : Register(4b,  EN=LATCH_EN), D=DMEM_WMASK, Q=l_wmask[3:0]
  L_WE    : Register(1b,  EN=LATCH_EN), D=DMEM_WE,    Q=l_we
  L_UNCACHED: Register(1b, EN=LATCH_EN), D=UNCACHED_FLAG, Q=l_uncached
    (UNCACHED_FLAG: combinational — see §5 below)

All reset to 0 via NOT(RST_N)→CLR.
```

### Derived latched fields (combinational from l_addr)

```
l_idx[1:0]  = l_addr[3:2]   ← Splitter on L_ADDR.Q, bits [3:2]
l_tag[27:0] = l_addr[31:4]  ← Splitter on L_ADDR.Q, bits [31:4]
```

### UNCACHED_FLAG (R9 — combinational)

```
Uncached if address is outside shared-SRAM range (0x00000_000–0x00000_FFF):
  UNCACHED_FLAG = NOT(DMEM_ADDR[31:12] == 20'h00000)

Logisim:
  Splitter: DMEM_ADDR[31:12] → 20-bit field
  Comparator(20b): Input A = above, Input B = Constant(0, 20b)
    A==B output → IS_SRAM_RANGE
  NOT gate: IS_SRAM_RANGE → UNCACHED_FLAG
```

### Internal flag registers (single-bit, set/cleared by FSM)

```
PENDING_STORE_REG : Register(1b)
  SET: when transitioning to MISS_READ with l_we=1 (store miss)
  CLR: RST_N or on transition back to IDLE/CHECK

NOTIFY_PENDING_REG : Register(1b)
  SET: when entering NOTIFY_COH (transition from AXI_B OKAY)
  CLR: when coh_accept received (exit NOTIFY_COH to IDLE)
  Used in WAIT_INVALIDATE to decide return destination.

BYPASS_REG : Register(1b)
  SET: when l_uncached=1 in CHECK
  CLR: RST_N

AXI_ERR_REG : Register(1b)
  SET: captured at AXI_R (rresp≠OKAY) or AXI_B (bresp≠OKAY)
  CLR: RST_N or re-entering IDLE

AXI_RDATA_REG : Register(32b)
  Captures AXI_RDATA when rvalid=1 in AXI_R state.

All controlled by NextStateLogic output signals (enable pulses per transition).
```

---

## 5. Next-State Logic — State Comparator Bank + Condition Gates

### 5.1 State comparators (one per state)

```
For each state S ∈ {0..12}:
  Component: Comparator (4-bit)
    Input A: CURR_STATE[3:0]
    Input B: Constant(S, 4 bits)
    A==B: IN_S{name}    e.g., IN_IDLE, IN_CHECK, IN_HIT_READ, ...

13 comparators total.
```

### 5.2 Condition signals (combinational)

```
All are 1-bit wires derived from inputs and latched registers:

  GRANTED     = BUS_GRANT
  AR_READY    = AXI_ARREADY AND GRANTED
  R_VALID     = AXI_RVALID
  AW_READY    = AXI_AWREADY AND GRANTED
  W_READY     = AXI_WREADY  AND GRANTED
  B_VALID     = AXI_BVALID
  RESP_OK_R   = NOT(AXI_RRESP[1] OR AXI_RRESP[0])   ← OKAY = 2'b00
  RESP_OK_B   = NOT(AXI_BRESP[1] OR AXI_BRESP[0])
  RESP_ERR_R  = NOT(RESP_OK_R)
  RESP_ERR_B  = NOT(RESP_OK_B)
  PS          = PENDING_STORE_REG   (pending_store flag)
  NP          = NOTIFY_PENDING_REG  (notify_pending flag)
  BP          = BYPASS_REG          (bypass/uncached flag)
  L_WE_Q      = l_we
  L_UC_Q      = l_uncached
  HIT_Q       = CACHE_HIT           (combinational from HitLogic)
```

### 5.3 Next-state derivation (one equation per target state)

Each target state is reached if any of its entry conditions is true. All equations below are OR-of-products, directly mapping the 34-row transition table.

```
NS_IDLE =
    IN_WAIT_INVALIDATE AND NOT(NP)              -- row 4, notify_pending=0
  | IN_HIT_READ                                 -- row 11
  | IN_FILL AND NOT(PS) AND NOT(BP) AND NOT(AXI_ERR_REG)  -- row 17 load cached ok
  | IN_FILL AND NOT(PS) AND BP AND NOT(AXI_ERR_REG)       -- row 18 load uncached ok
  | IN_FILL AND AXI_ERR_REG                               -- row 19 load error
  | IN_FILL AND PS AND AXI_ERR_REG                        -- row 21 store-miss error
  | IN_AXI_B AND B_VALID AND RESP_OK_B AND BP             -- row 29 uncached store ok
  | IN_AXI_B AND B_VALID AND RESP_ERR_B                   -- row 30 any write error
  | IN_NOTIFY_COH AND NOT(INV_VALID) AND COH_ACCEPT       -- row 33

NS_CHECK =
    IN_IDLE AND NOT(INV_VALID) AND DMEM_REQ     -- row 2

NS_HIT_READ =
    IN_CHECK AND NOT(L_WE_Q) AND NOT(L_UC_Q) AND HIT_Q   -- row 9

NS_MISS_READ =
    IN_CHECK AND L_WE_Q AND NOT(L_UC_Q) AND NOT(HIT_Q)   -- row 7 store miss
  | IN_CHECK AND NOT(L_WE_Q) AND L_UC_Q                  -- row 8 uncached load
  | IN_CHECK AND NOT(L_WE_Q) AND NOT(L_UC_Q) AND NOT(HIT_Q)  -- row 10 load miss

NS_AXI_AR =
    IN_MISS_READ                                -- row 12

NS_AXI_R =
    IN_AXI_AR AND GRANTED AND AXI_ARREADY       -- row 13

NS_FILL =
    IN_AXI_R AND R_VALID                        -- row 15

NS_HIT_WRITE =
    IN_CHECK AND L_WE_Q AND L_UC_Q              -- row 5 uncached store
  | IN_CHECK AND L_WE_Q AND NOT(L_UC_Q) AND HIT_Q         -- row 6 store hit

NS_AXI_AW =
    IN_FILL AND PS AND NOT(BP) AND NOT(AXI_ERR_REG)  -- row 20 store-alloc proceed
  | IN_HIT_WRITE                                     -- rows 22+23

NS_AXI_W =
    IN_AXI_AW AND GRANTED AND AXI_AWREADY       -- row 24

NS_AXI_B =
    IN_AXI_W AND GRANTED AND AXI_WREADY         -- row 26

NS_NOTIFY_COH =
    IN_AXI_B AND B_VALID AND RESP_OK_B AND NOT(BP)   -- row 28 cached store ok
  | IN_WAIT_INVALIDATE AND NP                          -- row 4 return path

NS_WAIT_INVALIDATE =
    IN_IDLE AND INV_VALID                              -- row 1
  | IN_NOTIFY_COH AND INV_VALID                        -- row 32 escape

NEXT_STATE[3:0]:
  Priority-encoded using a 13:1 MUX or OR tree on the NS_* signals:
  Since states are mutually exclusive (only one IN_* is true at a time),
  NEXT_STATE = (NS_IDLE     ? 4'd0  : 0)
             | (NS_CHECK    ? 4'd1  : 0)
             | (NS_HIT_READ ? 4'd2  : 0)
             ... etc.

Logisim recommended implementation:
  For each bit b of NEXT_STATE[3:0]:
    NEXT_STATE[b] = OR of all NS_* where state encoding has bit b = 1

  Bit 0 (LSB):
    States with bit0=1: CHECK(1), HIT_READ(2→no), MISS_READ(3), HIT_WRITE(7), AXI_R(5), AXI_W(9), AXI_B(10→no), NOTIFY_COH(11), WAIT_INV(12→no)
    NEXT_STATE[0] = NS_CHECK | NS_MISS_READ | NS_FILL | NS_HIT_WRITE | NS_AXI_R | NS_AXI_W | NS_NOTIFY_COH | ...
    (Derive from the binary encoding of each target state.)

  Full derivation:
    Encoding table for OR-of-products per bit:
    State          4b enc  b3 b2 b1 b0
    IDLE           0000     0  0  0  0
    CHECK          0001     0  0  0  1
    HIT_READ       0010     0  0  1  0
    MISS_READ      0011     0  0  1  1
    AXI_AR         0100     0  1  0  0
    AXI_R          0101     0  1  0  1
    FILL           0110     0  1  1  0
    HIT_WRITE      0111     0  1  1  1
    AXI_AW         1000     1  0  0  0
    AXI_W          1001     1  0  0  1
    AXI_B          1010     1  0  1  0
    NOTIFY_COH     1011     1  0  1  1
    WAIT_INV       1100     1  1  0  0

    NEXT_STATE[0] = NS_CHECK | NS_MISS_READ | NS_AXI_R | NS_HIT_WRITE | NS_AXI_W | NS_NOTIFY_COH
    NEXT_STATE[1] = NS_HIT_READ | NS_MISS_READ | NS_FILL | NS_HIT_WRITE | NS_AXI_B | NS_NOTIFY_COH | NS_WAIT_INVALIDATE
    NEXT_STATE[2] = NS_AXI_AR | NS_AXI_R | NS_FILL | NS_HIT_WRITE | NS_AXI_AW | NS_AXI_W | NS_AXI_B | NS_NOTIFY_COH | NS_WAIT_INVALIDATE
    NEXT_STATE[3] = NS_AXI_AW | NS_AXI_W | NS_AXI_B | NS_NOTIFY_COH | NS_WAIT_INVALIDATE

  Each bit: one OR gate with multiple inputs (number = count of 1s above).
  Logisim: multi-input OR gates on the NS_* 1-bit signals.
```

---

## 6. Output Logic — Moore-Style (combinational from CURR_STATE + conditions)

All outputs are combinational. Each output is high when the FSM is in the corresponding state(s) as listed in doc 04 §4.7.

```
DMEM_ACK   = IN_HIT_READ
           | (IN_FILL AND (NOT(PS) OR (PS AND NOT(AXI_ERR_REG))) AND NOT(PS AND NOT(AXI_ERR_REG) AND NOT(BP)) )
             Simplified: DMEM_ACK asserted in:
               HIT_READ (row 11)
               FILL, load path, ok   (rows 17,18)
               FILL, error           (row 19, with err)
               AXI_B, OKAY           (rows 28,29)
               AXI_B, ERR            (row 30, with err)

  Logisim OR gate collecting conditions:
    IN_HIT_READ
    IN_FILL AND NOT(AXI_ERR_REG)   (load ok — cached or uncached)
    IN_FILL AND AXI_ERR_REG        (load error)
    IN_AXI_B AND B_VALID           (store complete — ok or error)
  = IN_HIT_READ | (IN_FILL) | (IN_AXI_B AND B_VALID)

DMEM_ERR   = (IN_FILL AND AXI_ERR_REG)
           | (IN_AXI_B AND B_VALID AND RESP_ERR_B)

DMEM_RDATA = selected by MUX:
  IN_HIT_READ         → HIT_DATA[31:0]    (from HitLogic)
  IN_FILL AND NOT(AXI_ERR_REG) → AXI_RDATA_REG[31:0]
  else                → 32'b0

  MUX (32b, 2-sel):
    sel[1:0]:
      00 = default (0)
      01 = HIT_READ path: sel = IN_HIT_READ
      10 = FILL path: sel = IN_FILL AND NOT(AXI_ERR_REG)
    Use priority-encoded 3:1 MUX or nested 2:1 MUXes.

BUS_REQ    = IN_MISS_READ | IN_AXI_AR | IN_AXI_R
           | IN_HIT_WRITE | IN_AXI_AW | IN_AXI_W | IN_AXI_B
  7-input OR gate on IN_* signals.

AXI_ARVALID = IN_AXI_AR
AXI_ARADDR  = l_addr[31:0] when IN_AXI_AR  (else 0; use AND32 gate: IN_AXI_AR fan-out × 32)
              Logisim: 32-bit AND gate — each bit of l_addr AND IN_AXI_AR (1-bit replicated)
              Use: Logisim AND gate, 32 bits, Input0=l_addr, Input1=IN_AXI_AR replicated

AXI_RREADY  = IN_AXI_R

AXI_AWVALID = IN_AXI_AW
AXI_AWADDR  = l_addr[31:0] when IN_AXI_AW  (same AND32 technique)
AXI_WVALID  = IN_AXI_W
AXI_WDATA   = l_wdata[31:0] when IN_AXI_W
AXI_WSTRB   = l_wmask[3:0]  when IN_AXI_W
AXI_BREADY  = IN_AXI_B

WRITE_NOTIFY = IN_NOTIFY_COH
WRITE_ADDR   = l_addr[31:0] when IN_NOTIFY_COH

INV_ACK      = IN_WAIT_INVALIDATE   (pulse for the one cycle in that state)

FILL_NOTIFY  = IN_FILL AND NOT(PS) AND NOT(BP) AND NOT(AXI_ERR_REG)
               (only for cached load fill to S, not uncached, not error — R2)
FILL_IDX     = l_idx[1:0] when FILL_NOTIFY (else 0)

HIT_EVENT    = IN_HIT_READ
MISS_EVENT   = IN_MISS_READ         (first cycle entering MISS_READ)
               Strictly: should be a 1-cycle pulse on entry, not held.
               Implementation: AND(IN_MISS_READ, NOT(WAS_MISS_READ))
               where WAS_MISS_READ is a 1-bit register fed by IN_MISS_READ — detects the rising edge.
               Logisim: D-FF, D=IN_MISS_READ, Q=WAS_MISS_READ; MISS_EVENT = IN_MISS_READ AND NOT(WAS_MISS_READ)

ERR_EVENT    = DMEM_ERR  (same signal, different name for counter)
```

---

## 7. Flag Register Update Logic

### PENDING_STORE_REG

```
Set when:  CURR_STATE==CHECK AND l_we AND NOT(l_uncached) AND NOT(HIT_Q)  → entering MISS_READ for store
Clear when: CURR_STATE==FILL (any outcome) or CURR_STATE==IDLE

SET_PS  = IN_CHECK AND L_WE_Q AND NOT(L_UC_Q) AND NOT(HIT_Q)
CLR_PS  = IN_FILL | IN_IDLE

NEXT_PS = SET_PS | (PENDING_STORE_REG AND NOT(CLR_PS))

Register(1b): D=NEXT_PS, EN=1, CLR=NOT(RST_N)
```

### NOTIFY_PENDING_REG

```
Set when:  entering NOTIFY_COH from AXI_B (not from WAIT_INVALIDATE return)
Clear when: coh_accept received (exiting NOTIFY_COH)

SET_NP  = IN_AXI_B AND B_VALID AND RESP_OK_B AND NOT(BP)   (transition to NOTIFY_COH)
CLR_NP  = IN_NOTIFY_COH AND NOT(INV_VALID) AND COH_ACCEPT

NEXT_NP = SET_NP | (NOTIFY_PENDING_REG AND NOT(CLR_NP))
Register(1b): D=NEXT_NP, EN=1, CLR=NOT(RST_N)
```

### BYPASS_REG

```
Set when:  entering CHECK and l_uncached=1
Clear when: returning to IDLE

SET_BP  = LATCH_EN AND UNCACHED_FLAG    (same enable as latching l_uncached)
CLR_BP  = NS_IDLE (going to IDLE)

NEXT_BP = SET_BP | (BYPASS_REG AND NOT(NS_IDLE))
Register(1b): D=NEXT_BP, CLR=NOT(RST_N)
```

### AXI_ERR_REG

```
Set when: AXI_R rvalid AND rresp≠OKAY, OR AXI_B bvalid AND bresp≠OKAY
Clear when: returning to IDLE

SET_ERR  = (IN_AXI_R AND R_VALID AND RESP_ERR_R)
          | (IN_AXI_B AND B_VALID AND RESP_ERR_B)
CLR_ERR  = NS_IDLE

NEXT_ERR = SET_ERR | (AXI_ERR_REG AND NOT(NS_IDLE))
Register(1b): D=NEXT_ERR, CLR=NOT(RST_N)
```

### AXI_RDATA_REG

```
Capture rdata when rvalid arrives in AXI_R:
  EN = IN_AXI_R AND R_VALID
  D  = AXI_RDATA[31:0]
  Q  = AXI_RDATA_REG[31:0]

Register(32b, EN=above), CLR=NOT(RST_N)
```

---

## 8. Cache Write Control (drives DCacheStore inputs)

The FSM drives `WR_EN`, `WR_IDX`, `WR_VALID`, `WR_TAG`, `WR_DATA`, `WR_STATE` based on the current state transition.

```
WR_EN:
  = (IN_FILL AND NOT(AXI_ERR_REG) AND NOT(L_UC_Q))      -- load fill: write S line
  | (IN_FILL AND PS AND NOT(AXI_ERR_REG) AND NOT(BP))    -- store-alloc: write M line
  | (IN_HIT_WRITE AND NOT(BP))                           -- store hit: write M line
  | (IN_WAIT_INVALIDATE)                                  -- invalidation: write I line

WR_IDX:
  IN_WAIT_INVALIDATE → INV_IDX[1:0]    (invalidate the specified line)
  else               → l_idx[1:0]

  MUX (2b, 1-sel): IN_WAIT_INVALIDATE selects INV_IDX vs l_idx

WR_VALID:
  IN_WAIT_INVALIDATE → 0   (invalidation clears valid)
  else               → 1   (fills/writes make line valid)
  MUX (1b, 1-sel)

WR_TAG:
  Always l_tag[27:0] (no MUX needed — even during invalidation tag is overwritten but
  valid=0 so it doesn't matter; simplify: always drive l_tag)

WR_DATA:
  IN_FILL, load: AXI_RDATA_REG[31:0]
  IN_FILL, store-alloc (FILL→AXI_AW): MERGED_DATA[31:0]  (from CacheLineMux)
  IN_HIT_WRITE: MERGED_DATA[31:0]
  IN_WAIT_INVALIDATE: don't care (valid=0)
  MUX (32b, 2-sel):
    sel decode via IN_* signals
    preferred: 3-way MUX with sel = {IN_HIT_WRITE | (IN_FILL AND PS), IN_FILL AND NOT(PS)}

WR_STATE:
  Load fill (FILL, !PS, !bypass): S = 2'b01
  Store paths (FILL+PS or HIT_WRITE): M = 2'b10
  Invalidation (WAIT_INVALIDATE): I = 2'b00
  MUX (2b, 2-sel) or priority gate:
    IN_WAIT_INVALIDATE → 2'b00
    (IN_FILL AND PS) | IN_HIT_WRITE → 2'b10
    else → 2'b01
```

---

## 9. CacheLineMux Integration

```
The MERGED_DATA is computed by the CacheLineMux sub-circuit (doc 04):
  OLD_DATA: MUX between HIT_DATA (hit-write path) and AXI_RDATA_REG (fill-store path)
    MUX (32b, 1-sel):
      sel = PS (pending_store flag)
      Input 0 (hit-write): HIT_DATA (from HitLogic)
      Input 1 (store-alloc fill): AXI_RDATA_REG
    Output → CacheLineMux.OLD_DATA

  WR_DATA  → CacheLineMux.WR_DATA = l_wdata
  WMASK    → CacheLineMux.WMASK   = l_wmask
  Output   → CacheLineMux.MERGED  → FSM WR_DATA mux and AXI_WDATA
```

---

## 10. Full ASCII Block Diagram

```
                     ┌──────────────────────────────────────────────────────────────┐
                     │                    DCacheMgrFSM                              │
                     │                                                              │
 DMEM_REQ ──────────►│                 ┌──────────────┐                            │
 DMEM_WE  ──────────►│  LATCH_EN ─────►│ L_ADDR/WE/   │ → l_addr, l_we,           │
 DMEM_ADDR ─────────►│                 │ WDATA/WMASK  │   l_wdata, l_wmask         │
 DMEM_WDATA ────────►│                 └──────────────┘   l_idx, l_tag, l_uncached │
 DMEM_WMASK ────────►│                                                              │
                     │  ┌─────────────────────────────────────────────────────┐    │
 CLK (tunnel) ──────►│  │  State Register (4b D-FF, async CLR)                │    │
 RST_N → NOT → CLR ─►│  │  D = NEXT_STATE[3:0]   Q = CURR_STATE[3:0]         │    │
                     │  └────────────────────────┬────────────────────────────┘    │
                     │                           │                                  │
                     │  CURR_STATE ──► 13× Comparator(4b) ──► IN_IDLE..IN_WAIT_INV │
                     │                           │                                  │
                     │  Condition signals ────────┤                                 │
                     │  (AXI channels, flags,     │                                 │
                     │   INV_VALID, COH_ACCEPT)   │                                 │
                     │                            ▼                                 │
                     │  NS_* equations (OR-of-products per target state)            │
                     │  NEXT_STATE[3:0] via 4 OR trees (bit 0..3)                  │
                     │                            │                                 │
                     │  Output logic (Moore):     │                                 │
                     │  DMEM_ACK, DMEM_ERR ◄──────┤                                │
                     │  DMEM_RDATA ◄──────────────┤ (MUX: HIT_DATA vs AXI_RDATA)  │
                     │  BUS_REQ ◄─────────────────┤                                │
                     │  AXI_AR*/R*/AW*/W*/B* ◄────┤                                │
                     │  WRITE_NOTIFY/ADDR ◄────────┤                                │
                     │  INV_ACK ◄─────────────────┤                                │
                     │  FILL_NOTIFY/IDX ◄──────────┤                                │
                     │  WR_EN/IDX/VALID/TAG/ ◄─────┤                                │
                     │  WR_DATA/STATE ◄────────────┤                                │
                     │  HIT/MISS/ERR_EVENT ◄───────┘                                │
                     └──────────────────────────────────────────────────────────────┘

External connections:
  CACHE_HIT, HIT_DATA, HIT_STATE ◄── HitLogic sub-circuit
  WR_EN..WR_STATE ──► DCacheStore sub-circuit
  MERGED_DATA ◄── CacheLineMux sub-circuit
  BUS_REQ ──► AXI Arbiter
  AXI channels ──► AXI Arbiter (muxed through)
  WRITE_NOTIFY/ADDR, FILL_NOTIFY/IDX, INV_ACK ──► CoherenceCtrl sideband
  INV_VALID, INV_IDX, COH_ACCEPT ◄── CoherenceCtrl sideband
```

---

## 11. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| State Register | Data bits | 4 |
| State Register | Trigger | Rising edge |
| State Register | CLR (async) | Active high → NOT(RST_N) |
| State comparators (×13) | Data bits | 4 |
| L_ADDR/WDATA registers | Data bits | 32 |
| L_WMASK register | Data bits | 4 |
| L_WE, L_UNCACHED | Data bits | 1 |
| AXI_RDATA_REG | Data bits | 32; Enable input yes |
| Flag registers (×4) | Data bits | 1 |
| UNCACHED comparator | Data bits | 20 |
| DMEM_RDATA MUX | Data bits | 32; Select bits 2 |
| WR_IDX MUX | Data bits | 2; Select bits 1 |
| WR_DATA MUX | Data bits | 32; Select bits 2 |
| WR_STATE MUX | Data bits | 2; Select bits 2 |
| BUS_REQ OR gate | Inputs | 7 |
| NS_* OR gates | Inputs | Varies per equation (2–7) |
| AXI addr AND32 gates | Data bits | 32; Inputs 2 (addr + enable) |
| MISS_EVENT edge-detect DFF | Data bits | 1 |

---

## 12. Layout Notes for Logisim

- Place the state register in the center-top of the canvas.
- Arrange the 13 state comparators in a vertical column to the left.
- Group next-state OR trees into a "NextState" sub-circuit for cleanliness.
- Place latch registers (l_addr etc.) in a horizontal row below the state register.
- Place flag registers (PENDING_STORE, NOTIFY_PENDING, BYPASS, AXI_ERR) in a cluster.
- Output logic fans rightward from the state comparators.
- Use Tunnel labels for: `IN_IDLE`, `IN_CHECK`, `IN_AXI_AR`, etc. — these are used in many places and tunnels prevent spaghetti wiring.
- AXI channel outputs cluster at the right edge as output pins.
- DCacheStore write signals cluster at the bottom-right.
