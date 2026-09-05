# Gate-Level Circuit: Address Decoder & DECERR Slave

Source: `07_decoder_and_bus_fabric.md` §7.1–§7.6  
Logisim sub-circuit names: **`AddrDecoder`**, **`DECERRSlave`**

Pure combinational address decode plus a small FSM to return proper AXI error responses to unmapped accesses.

---

## 1. Sub-circuit: `AddrDecoder` — Combinational Address Decode

### 1.1 Purpose

Decodes the 32-bit AXI address on the shared slave port into four mutually exclusive select lines, plus DECERR for anything outside the known ranges.

### 1.2 Address Map

| Range | Size | Target | `sel_*` |
|-------|------|--------|---------|
| `0x0000_0000 – 0x0000_0FFF` | 4 KB | Shared SRAM | `SEL_SRAM` |
| `0x0001_0000 – 0x0001_00FF` | 256 B | MMIO Regs | `SEL_MMIO` |
| `0x0001_0100 – 0x0001_01FF` | 256 B | UART | `SEL_UART` |
| `0x0001_0200 – 0x0001_02FF` | 256 B | GPIO/LED | `SEL_GPIO` |
| anything else | — | DECERR | `SEL_DECERR` |

### 1.3 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `ADDR` | In | 32 | AXI address (from arbiter shared port) |
| `SEL_SRAM` | Out | 1 | Address is in SRAM range |
| `SEL_MMIO` | Out | 1 | Address is in MMIO range |
| `SEL_UART` | Out | 1 | Address is in UART range |
| `SEL_GPIO` | Out | 1 | Address is in GPIO range |
| `SEL_DECERR` | Out | 1 | Address is unmapped |

### 1.4 Field extraction

```
Splitter on ADDR[31:0]:
  Output A: ADDR[31:12] → ADDR_UPPER_20[19:0]   (for SRAM check)
  Output B: ADDR[31:16] → ADDR_UPPER_16[15:0]   (for peripheral check)
  Output C: ADDR[15:8]  → ADDR_MID_8[7:0]       (for sub-region select)

Logisim: one Splitter (fan-out, 32-bit input) extracting the three fields above.
```

### 1.5 SEL_SRAM

```
SRAM occupies 0x0000_0000 – 0x0000_0FFF: addr[31:12] == 20'h00000

Comparator (20-bit):
  Input A: ADDR_UPPER_20[19:0]
  Input B: Constant(0x00000, 20 bits) = 20'd0
  A == B output: SEL_SRAM
```

### 1.6 SEL_MMIO, SEL_UART, SEL_GPIO (peripheral decodes)

All three peripherals share the upper 16 bits `addr[31:16] == 16'h0001`.  
They are distinguished by `addr[15:8]`:

```
IS_PERIPH_RANGE:
  Comparator (16-bit):
    Input A: ADDR_UPPER_16[15:0]
    Input B: Constant(0x0001, 16 bits)
    A == B: IS_PERIPH_RANGE

Sub-region decode (addr[15:8]):
  IS_MMIO_REG: Comparator(8b): ADDR_MID_8 == 8'h00 → IS_MMIO_SUB
  IS_UART_REG: Comparator(8b): ADDR_MID_8 == 8'h01 → IS_UART_SUB
  IS_GPIO_REG: Comparator(8b): ADDR_MID_8 == 8'h02 → IS_GPIO_SUB

Final select signals:
  SEL_MMIO = IS_PERIPH_RANGE AND IS_MMIO_SUB
  SEL_UART = IS_PERIPH_RANGE AND IS_UART_SUB
  SEL_GPIO = IS_PERIPH_RANGE AND IS_GPIO_SUB

Logisim:
  3× AND gate (2-in, 1-bit):
    SEL_MMIO: AND(IS_PERIPH_RANGE, IS_MMIO_SUB)
    SEL_UART: AND(IS_PERIPH_RANGE, IS_UART_SUB)
    SEL_GPIO: AND(IS_PERIPH_RANGE, IS_GPIO_SUB)
```

### 1.7 SEL_DECERR

```
SEL_DECERR = NOT(SEL_SRAM OR SEL_MMIO OR SEL_UART OR SEL_GPIO)

Logisim:
  OR gate (4-in, 1-bit):
    Inputs: SEL_SRAM, SEL_MMIO, SEL_UART, SEL_GPIO
    Output: ANY_VALID
  NOT gate: ANY_VALID → SEL_DECERR
```

### 1.8 One-hot invariant probe

```
TOTAL = SEL_SRAM + SEL_MMIO + SEL_UART + SEL_GPIO + SEL_DECERR
Should always equal 1 when the bus is active.

Logisim: place a 5-input OR and XOR probe:
  5-input OR(SEL_*) → SOME_SEL  (should be 1 if bus active)
  If NOT(SOME_SEL) when awvalid or arvalid → logic error
  Place as a Probe labeled "ASSERT:one_hot"
```

### 1.9 ASCII Block Diagram (AddrDecoder)

```
ADDR[31:0]
    │
    └─ Splitter ──┬─ [31:12] (20b) ──► Comparator(20b, ==0) ────────────────► SEL_SRAM
                  │
                  ├─ [31:16] (16b) ──► Comparator(16b, ==0x0001) ─► IS_PERIPH
                  │                                                      │
                  └─ [15:8]  (8b)  ──► Comparator(8b, ==0x00) ─► AND ──► SEL_MMIO
                                    ├─► Comparator(8b, ==0x01) ─► AND ──► SEL_UART
                                    └─► Comparator(8b, ==0x02) ─► AND ──► SEL_GPIO
                                                               IS_PERIPH ─┘ (shared)

SEL_SRAM + SEL_MMIO + SEL_UART + SEL_GPIO ──► OR(4) ──► NOT ──► SEL_DECERR
```

---

## 2. Sub-circuit: `DECERRSlave` — AXI4-Lite Error Responder FSM

### 2.1 Purpose

Accepts AXI4-Lite transactions to unmapped addresses and returns `DECERR` (2'b11) responses. Must handle both write (AW+W before B) and read (AR before R) paths.

### 2.2 State Encoding

Write path FSM (3 states, 2-bit):

| State | Encoding | Role |
|-------|----------|------|
| DEC_W_IDLE | 2'b00 | Wait for AW or W |
| DEC_W_GOTAW | 2'b01 | Got AW, waiting for W |
| DEC_W_GOTW | 2'b10 | Got W, waiting for AW |
| DEC_B_RESP | 2'b11 | Have both; issue DECERR B response |

Read path is simpler (2 states, 1-bit):

| State | Encoding | Role |
|-------|----------|------|
| DEC_R_IDLE | 1'b0 | Wait for AR |
| DEC_R_RESP | 1'b1 | Issue DECERR R response |

### 2.3 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock (tunnel) |
| `RST_N` | In | 1 | Async reset (tunnel) |
| `SEL` | In | 1 | This slave is selected (= SEL_DECERR AND bus active) |
| `AWVALID` | In | 1 | AW valid (from shared slave port, gated by SEL) |
| `WVALID` | In | 1 | W valid |
| `BREADY` | In | 1 | B ready (from master) |
| `ARVALID` | In | 1 | AR valid |
| `RREADY` | In | 1 | R ready |
| `AWREADY` | Out | 1 | AW ready |
| `WREADY` | Out | 1 | W ready |
| `BVALID` | Out | 1 | B valid |
| `BRESP` | Out | 2 | = 2'b11 (DECERR) when BVALID |
| `ARREADY` | Out | 1 | AR ready |
| `RVALID` | Out | 1 | R valid |
| `RDATA` | Out | 32 | = 32'b0 (dummy) |
| `RRESP` | Out | 2 | = 2'b11 (DECERR) when RVALID |

### 2.4 Write path FSM

#### State register (2-bit)

```
Component: Register, 2 bits
  CLR: NOT(RST_N)  → 2'b00 = DEC_W_IDLE
  D:   NEXT_W[1:0]
  Q:   W_STATE[1:0]
```

#### State comparators (×4)

```
IN_DEC_W_IDLE  = (W_STATE == 2'b00)
IN_DEC_W_GOTAW = (W_STATE == 2'b01)
IN_DEC_W_GOTW  = (W_STATE == 2'b10)
IN_DEC_B_RESP  = (W_STATE == 2'b11)
```

#### Next-state logic (write path)

```
NS_DEC_W_IDLE =
    IN_DEC_B_RESP AND BREADY          -- B accepted, transaction done
  | IN_DEC_W_IDLE AND NOT(AWVALID) AND NOT(WVALID)  -- nothing arrived

NS_DEC_W_GOTAW =
    IN_DEC_W_IDLE AND AWVALID AND NOT(WVALID)   -- AW arrived, no W yet
  | IN_DEC_W_GOTAW AND NOT(WVALID)              -- waiting for W

NS_DEC_W_GOTW =
    IN_DEC_W_IDLE AND WVALID AND NOT(AWVALID)   -- W arrived, no AW yet
  | IN_DEC_W_GOTW AND NOT(AWVALID)              -- waiting for AW

NS_DEC_B_RESP =
    IN_DEC_W_IDLE  AND AWVALID AND WVALID        -- both arrived simultaneously
  | IN_DEC_W_GOTAW AND WVALID                    -- W arrived to complete
  | IN_DEC_W_GOTW  AND AWVALID                   -- AW arrived to complete
  | IN_DEC_B_RESP  AND NOT(BREADY)               -- hold until master accepts

Bit derivation:
  NEXT_W[1] = NS_DEC_W_GOTW | NS_DEC_B_RESP
  NEXT_W[0] = NS_DEC_W_GOTAW | NS_DEC_B_RESP

Logisim: 4 OR gates building NS_* signals, then 2 OR gates for NEXT_W bits.
```

#### Write path outputs (Moore)

```
AWREADY = IN_DEC_W_IDLE AND NOT(WVALID)
          OR IN_DEC_W_GOTW
  (Accept AW when idle with no W, or when we already have W)
  Logisim:
    NOT: WVALID → N_WVALID
    AND (2-in): IN_DEC_W_IDLE, N_WVALID → READY_IN_IDLE
    OR  (2-in): READY_IN_IDLE, IN_DEC_W_GOTW → AWREADY

WREADY = IN_DEC_W_IDLE AND NOT(AWVALID)
         OR IN_DEC_W_GOTAW
  (Symmetric)
  Logisim:
    NOT: AWVALID → N_AWVALID
    AND (2-in): IN_DEC_W_IDLE, N_AWVALID → W_READY_IDLE
    OR  (2-in): W_READY_IDLE, IN_DEC_W_GOTAW → WREADY

BVALID = IN_DEC_B_RESP
BRESP  = Constant(2'b11, 2 bits) gated by BVALID:
  BRESP = {2{BVALID}} AND 2'b11 = {BVALID, BVALID}
  Logisim: Combine Splitter (2 inputs of 1 bit each = BVALID, BVALID) → BRESP[1:0]
  Or: just wire Constant(3, 2) to BRESP unconditionally (master ignores BRESP when !BVALID)
```

### 2.5 Read path FSM

#### State register (1-bit)

```
Component: Register, 1 bit
  CLR: NOT(RST_N)  → 1'b0 = DEC_R_IDLE
  D:   NEXT_R
  Q:   R_STATE
```

#### Next-state logic (read path)

```
IN_DEC_R_IDLE = NOT(R_STATE)
IN_DEC_R_RESP = R_STATE

NS_DEC_R_IDLE = IN_DEC_R_IDLE AND NOT(ARVALID)
              | IN_DEC_R_RESP AND RREADY          -- R accepted
NS_DEC_R_RESP = IN_DEC_R_IDLE AND ARVALID
              | IN_DEC_R_RESP AND NOT(RREADY)     -- hold until accepted

NEXT_R = NS_DEC_R_RESP
       = (IN_DEC_R_IDLE AND ARVALID) OR (IN_DEC_R_RESP AND NOT(RREADY))

Logisim:
  NOT: R_STATE → IN_DEC_R_IDLE
  AND (2-in): IN_DEC_R_IDLE, ARVALID → TERM_A
  NOT: RREADY → N_RREADY
  AND (2-in): R_STATE, N_RREADY → TERM_B
  OR  (2-in): TERM_A, TERM_B → NEXT_R → Register.D
```

#### Read path outputs

```
ARREADY = IN_DEC_R_IDLE = NOT(R_STATE)   (always accept AR when idle)
RVALID  = IN_DEC_R_RESP = R_STATE
RDATA   = Constant(0, 32 bits)           (tie to zero — unmapped read returns garbage)
RRESP   = Constant(2'b11, 2 bits)        (DECERR — master checks rresp)
```

### 2.6 ASCII Block Diagram (DECERRSlave)

```
                   ┌──────────────────────────────────────────────────┐
                   │                  DECERRSlave                     │
                   │                                                  │
AWVALID ──────────►│  ┌──────────────────────────────────┐            │
WVALID  ──────────►│  │  Write Path FSM (2b state reg)   │            │
BREADY  ──────────►│  │  DEC_W_IDLE → GOTAW/GOTW → B_RESP│            │
                   │  │  NS equations: 4 OR gates        │            │
                   │  │  AWREADY, WREADY, BVALID, BRESP  │──────────► │→ AWREADY/WREADY
                   │  └──────────────────────────────────┘            │→ BVALID/BRESP(11)
                   │                                                  │
ARVALID ──────────►│  ┌──────────────────────────────────┐            │
RREADY  ──────────►│  │  Read Path FSM (1b state reg)    │            │
                   │  │  DEC_R_IDLE → DEC_R_RESP         │            │
                   │  │  ARREADY, RVALID, RDATA=0, RRESP=11│─────────►│→ ARREADY
                   │  └──────────────────────────────────┘            │→ RVALID/RDATA/RRESP(11)
                   │                                                  │
CLK ──────────────►│                                                  │
RST_N → NOT → CLR─►│                                                  │
                   └──────────────────────────────────────────────────┘
```

---

## 3. Slave Port Routing (Decoder + Slaves)

The `AddrDecoder` produces `SEL_*` signals that enable one of the four AXI slaves. The decoder itself is the routing hub:

```
For each slave response signal (AWREADY, WREADY, BVALID, BRESP, ARREADY, RVALID, RDATA, RRESP):
  The shared slave port sees the response from the SELECTED slave.

  Shared response = (SEL_SRAM AND SRAM_resp) | (SEL_MMIO AND MMIO_resp)
                  | (SEL_UART AND UART_resp)  | (SEL_GPIO AND GPIO_resp)
                  | (SEL_DECERR AND DECERR_resp)

For 1-bit responses (AWREADY, WREADY, BVALID, ARREADY, RVALID):
  5× AND(2-in) + 5-input OR gate per signal

For 2-bit responses (BRESP, RRESP):
  5× AND(2-bit, 2-in) + 5-input OR(2-bit) per signal

For 32-bit responses (RDATA):
  5× AND(32-bit) + 5-input OR(32-bit)

Each slave also receives its AXI request signals ONLY when its SEL line is active:
  SRAM_AWVALID = S_AWVALID AND SEL_SRAM  (AND gate)
  MMIO_AWVALID = S_AWVALID AND SEL_MMIO
  etc.
  This prevents unintended multi-slave writes.

Logisim implementation of the slave enable gating (for each request signal):
  AND gate (2-in): S_AWVALID, SEL_SRAM → SRAM_AWVALID
  (repeat for all slaves and all request signals: AWVALID, AWADDR, WVALID, WDATA,
   WSTRB, BREADY, ARVALID, ARADDR, RREADY)
```

### 3.1 Response multiplexer for the shared port (Logisim approach)

```
For multi-bit signals (e.g., RDATA = 32 bits):
  The 5-way OR approach works but is wide.
  Since the selects are one-hot, use a more readable 5:1 MUX structure:

  Alternative: Priority MUX (5:1, 32-bit, 3-bit select encoded from SEL_*)
    Encode the SEL signals to a 3-bit select:
      SEL encode:
        SEL_SRAM=1 → 3'b000
        SEL_MMIO=1 → 3'b001
        SEL_UART=1 → 3'b010
        SEL_GPIO=1 → 3'b011
        SEL_DECERR=1 → 3'b100

    Priority encoder (5-input, 3-bit output):
      Logisim: Plexers > Priority Encoder (5 inputs, 3-bit output)
        Input 0: SEL_SRAM
        Input 1: SEL_MMIO
        Input 2: SEL_UART
        Input 3: SEL_GPIO
        Input 4: SEL_DECERR
      Output: SEL_ENC[2:0]

    Then use 8:1 MUXes on each response signal:
      RDATA_MUX (32b, 3-sel):
        Input 0: SRAM_RDATA
        Input 1: MMIO_RDATA
        Input 2: UART_RDATA
        Input 3: GPIO_RDATA
        Input 4: DECERR_RDATA (=0)
        Inputs 5-7: 0 (unused)
        Select: SEL_ENC[2:0]
```

---

## 4. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| ADDR Splitter | Input | 32 bits; fan-out to [31:12], [31:16], [15:8] |
| SEL_SRAM Comparator | Data bits | 20 |
| SEL_PERIPH Comparator | Data bits | 16 |
| Sub-region comparators (×3) | Data bits | 8 |
| SEL_* AND gates | Data bits | 1; Inputs 2 |
| ANY_VALID OR gate | Data bits | 1; Inputs 4 |
| Write FSM state reg | Data bits | 2; CLR async |
| Read FSM state reg | Data bits | 1; CLR async |
| Write state comparators | Data bits | 2 (×4) |
| All NS OR gates | Data bits | 1; Inputs as needed |
| BRESP, RRESP Constants | Value | 3 (= 2'b11); Data bits 2 |
| RDATA Constant | Value | 0; Data bits 32 |
| Response routing ANDs (1b) | Data bits | 1; Inputs 2 |
| Response routing ANDs (2b) | Data bits | 2; Inputs 2 |
| Response routing ANDs (32b) | Data bits | 32; Inputs 2 |
| Priority Encoder | Inputs | 5; Output bits 3 |
| Response MUXes (32b) | Data bits | 32; Select bits 3 |
| Response MUXes (2b) | Data bits | 2; Select bits 3 |
| Response MUXes (1b) | Data bits | 1; Select bits 3 |
