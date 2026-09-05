# Gate-Level Circuit: Peripherals

Source: `09_peripherals.md` §9.1–§9.5  
Logisim sub-circuit names: **`MMIORegs`**, **`UartCore`**, **`BaudGen`**, **`TxFSM`**, **`RxFSM`**, **`GPIOLed`**, **`LEDStretcher`**

All three peripherals are AXI4-Lite slaves using the standard 1-to-3-cycle response template.

---

## 1. Sub-circuit: `MMIORegs` — MMIO Register File AXI Slave

Base address: `0x0001_0000`

### 1.1 Register Map

| Offset | Name | Access | Width | Source |
|--------|------|--------|-------|--------|
| 0x00 | COH_STATUS | RO | 16 | coherence_ctrl.coh_status[15:0] |
| 0x04 | INV_COUNT | RO | 32 | inv_fire counter |
| 0x08 | HIT_COUNT | RO | 32 | hit0\|hit1 counter |
| 0x0C | MISS_COUNT | RO | 32 | miss0\|miss1 counter |
| 0x10 | DOORBELL | RW | 32 | software R/W register |
| 0x14 | CONTROL | RW | 32 | b0=coh_enable, b1=cnt_clear, b2=err_clear |
| — | ERR_STICKY | RO sticky | 1 | set by err_event, cleared by err_clear |

### 1.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock |
| `RST_N` | In | 1 | Async reset |
| AXI slave pins | In/Out | — | Standard AXI4-Lite slave (S_AWVALID…S_RRESP) |
| `COH_STATUS_I` | In | 16 | From coherence controller |
| `INV_FIRE` | In | 1 | Invalidation event pulse |
| `HIT0` | In | 1 | Cache 0 hit event |
| `HIT1` | In | 1 | Cache 1 hit event |
| `MISS0` | In | 1 | Cache 0 miss event |
| `MISS1` | In | 1 | Cache 1 miss event |
| `ERR0` | In | 1 | Cache 0 error event |
| `ERR1` | In | 1 | Cache 1 error event |
| `COH_ENABLE` | Out | 1 | CONTROL[0] → CoherenceCtrl |
| `CNT_CLEAR` | Out | 1 | CONTROL[1] write-1 pulse |
| `ERR_CLEAR` | Out | 1 | CONTROL[2] write-1 pulse |
| `ERR_STICKY` | Out | 1 | Sticky error flag → LED5 |
| `LED_DMEM_ACK0` | In | 1 | Core 0 dmem_ack → LED0 heartbeat |
| `LED_DMEM_ACK1` | In | 1 | Core 1 dmem_ack → LED1 heartbeat |

### 1.3 Counter registers

#### INV_COUNT (32-bit up-counter)

```
Component: Arithmetic > Counter (32-bit)
  CLK: CLK tunnel
  CLR: NOT(RST_N) OR CNT_CLEAR
       OR gate (2-in): NOT(RST_N), CNT_CLEAR → COUNTER_CLR
  EN:  INV_FIRE   (increment on invalidation event pulse)
  Direction: Up
  Maximum: 0xFFFFFFFF (wrap)
  Output Q: INV_COUNT[31:0]

Logisim: Counter component
  Data bits: 32
  Action on enable: count up by 1
  Clear input: COUNTER_CLR
```

#### HIT_COUNT (32-bit up-counter)

```
Same structure.
  EN: HIT0 OR HIT1
  OR gate (2-in): HIT0, HIT1 → HIT_EVENT
  Counter EN = HIT_EVENT
  CLR: same COUNTER_CLR
```

#### MISS_COUNT (32-bit up-counter)

```
  EN: MISS0 OR MISS1 → MISS_EVENT
  CLR: COUNTER_CLR
```

### 1.4 DOORBELL register (32-bit RW)

```
Component: Memory > Register, 32 bits
  CLK: CLK tunnel
  CLR: NOT(RST_N)
  EN:  AXI write to offset 0x10 (see AXI decode below)
  D:   S_WDATA[31:0]
  Q:   DOORBELL_REG[31:0]
```

### 1.5 CONTROL register (32-bit RW, write-driven outputs)

```
Component: Memory > Register, 32 bits
  CLR: NOT(RST_N) → reset = 0x00000001 (coh_enable=1 at reset)
  Logisim: set register initial value to 1.
  EN:  AXI write to offset 0x14
  D:   S_WDATA[31:0]
  Q:   CONTROL_REG[31:0]

Extracted outputs:
  COH_ENABLE = CONTROL_REG[0]   (via 1-bit Splitter on CONTROL_REG)
  CNT_CLEAR  = CONTROL_REG[1] AND (AXI write to offset 0x14)  ← write-1 pulse
  ERR_CLEAR  = CONTROL_REG[2] AND (AXI write to offset 0x14)

  Logisim:
    Splitter on CONTROL_REG[31:0]: extract [0], [1], [2]
    [0] → COH_ENABLE output (direct wire, level)
    [1] AND CONTROL_WR_EN → CNT_CLEAR (AND gate, 1-cycle pulse on write)
    [2] AND CONTROL_WR_EN → ERR_CLEAR

  CONTROL_WR_EN: AXI write accepted to address offset 0x14 (see AXI decode)
```

### 1.6 ERR_STICKY register (1-bit, set/clear)

```
SET:  ERR0 OR ERR1
CLR:  ERR_CLEAR pulse OR RST_N

NEXT_ERR_STICKY = (ERR0 OR ERR1) OR (ERR_STICKY AND NOT(ERR_CLEAR))

Logisim:
  OR  gate (2-in): ERR0, ERR1 → ANY_ERR
  NOT gate: ERR_CLEAR → N_ERR_CLEAR
  AND gate (2-in): ERR_STICKY, N_ERR_CLEAR → HOLD_ERR
  OR  gate (2-in): ANY_ERR, HOLD_ERR → NEXT_ERR_STICKY
  D-FF (1b): D=NEXT_ERR_STICKY, CLR=NOT(RST_N), Q=ERR_STICKY → output pin
```

### 1.7 AXI address decode (offset selection)

```
The AXI slave receives address S_AWADDR or S_ARADDR.
Register offset = addr[7:0] (lower 8 bits within the peripheral's 256-byte range).
Since registers are 4-byte aligned: offset[7:2] selects the register (6-bit index = 0..5).

Splitter on addr[7:0]: extract [7:2] → REG_SEL[5:0]

Register comparators (6-bit):
  IS_COH_STATUS = (REG_SEL == 6'd0)    offset 0x00
  IS_INV_COUNT  = (REG_SEL == 6'd1)    offset 0x04
  IS_HIT_COUNT  = (REG_SEL == 6'd2)    offset 0x08
  IS_MISS_COUNT = (REG_SEL == 6'd3)    offset 0x0C
  IS_DOORBELL   = (REG_SEL == 6'd4)    offset 0x10
  IS_CONTROL    = (REG_SEL == 6'd5)    offset 0x14

6× Comparator (6-bit), Input B = Constant(0..5, 6b)
```

### 1.8 AXI write path (template §7.5)

```
Write path: always-ready slave (AWREADY=1, WREADY=1 combinationally).
When both AWVALID and WVALID arrive and handshake:
  BOTH_VALID = S_AWVALID AND S_WVALID AND S_AWREADY AND S_WREADY
  = S_AWVALID AND S_WVALID   (since AWREADY=WREADY=1 always)

  Per-register write enable:
    DOORBELL_WR = BOTH_VALID AND IS_DOORBELL   (AND gate on BOTH_VALID + IS_DOORBELL)
    CONTROL_WR  = BOTH_VALID AND IS_CONTROL    ← also used as CONTROL_WR_EN above

  Address for decode: S_AWADDR[7:0] → Splitter → REG_SEL

B response:
  Register B_VALID_REG (1b): set on BOTH_VALID, clear when BREADY accepted.
  D-FF: D = (BOTH_VALID AND NOT(B_VALID_REG)) OR (B_VALID_REG AND NOT(S_BREADY))
        Q = S_BVALID
  S_BVALID = B_VALID_REG
  S_BRESP  = Constant(2'b00)  ← OKAY
  S_AWREADY = 1  (Constant)
  S_WREADY  = 1  (Constant)
```

### 1.9 AXI read path (template §7.5)

```
S_ARREADY = 1 (always ready)
Capture read address on AR handshake:
  AR_ADDR_REG (8b): EN = S_ARVALID (and ARREADY=1 → always enabled when valid)
    D = S_ARADDR[7:0], Q = AR_ADDR_REG[7:0]

  AR_VALID_REG (1b): set by AR handshake, cleared when R accepted.
    D = (S_ARVALID AND NOT(AR_VALID_REG)) OR (AR_VALID_REG AND NOT(S_RREADY))
    Q = S_RVALID

Read data mux (7 sources → 1 output):
  REG_SEL from AR_ADDR_REG → register comparators → read mux select

  RDATA_MUX (32b, 3-sel, 8:1):
    Input 0: {16'b0, COH_STATUS_I[15:0]}   (zero-pad to 32b)
    Input 1: INV_COUNT[31:0]
    Input 2: HIT_COUNT[31:0]
    Input 3: MISS_COUNT[31:0]
    Input 4: DOORBELL_REG[31:0]
    Input 5: CONTROL_REG[31:0]
    Input 6: {31'b0, ERR_STICKY}            (ERR_STICKY as bit 0)
    Input 7: 32'b0                           (unused)
    Select: REG_SEL_ENCODED[2:0] from priority encoder on register select signals

  S_RDATA  = RDATA_MUX output
  S_RRESP  = Constant(2'b00)
```

---

## 2. Sub-circuit: `BaudGen` — UART Baud Rate Generator

### 2.1 Purpose

Generates a `BAUD_TICK` pulse every 434 clock cycles (50 MHz / 115200 baud ≈ 434).

### 2.2 Circuit

```
Component: Arithmetic > Counter (10-bit, counts 0 to 433)
  CLK: CLK tunnel
  CLR: RST or when count reaches 433 (self-resetting)
  Max value: 433
  Overflow: wrap to 0

BAUD_TICK = (COUNT == 433)

  Comparator (10-bit): Input A = COUNT, Input B = Constant(433)
  A==B → BAUD_TICK (1-cycle pulse at baud rate)

  Self-reset: BAUD_TICK feeds the counter CLR pin → counter resets to 0 on tick.
  Logisim Counter: set "Maximum value" = 433, "On overflow: load constant 0" — 
    this auto-wraps without needing separate CLR logic.

Optional 16× oversampling tick for RX (mid-bit sampling):
  Same structure with OVERSAMPLE_DIV = 434/16 ≈ 27:
    Counter (5-bit, max=26): tick every 27 cycles = ~16× baud rate
    SAMPLE_TICK output used by RxFSM for mid-bit sampling.
```

---

## 3. Sub-circuit: `TxFSM` — UART TX State Machine

### 3.1 State Encoding (2-bit)

| State | Encoding | Role |
|-------|----------|------|
| TX_IDLE | 2'b00 | Line idle; ready for new byte |
| TX_START | 2'b01 | Transmit start bit (0) |
| TX_DATA | 2'b10 | Shift out 8 data bits LSB-first |
| TX_STOP | 2'b11 | Transmit stop bit (1) |

### 3.2 Internal registers

```
TX_SHIFT_REG (10-bit):  Holds {stop_bit=1, data[7:0], start_bit=0}
  EN: when entering TX_START state (load) and on each BAUD_TICK in TX_DATA (shift)
  D (load): {1'b1, TX_BYTE[7:0], 1'b0}   ← assembled as 10-bit value
  D (shift): {1'b1, TX_SHIFT_REG[9:1]}   ← right-shift, fill MSB with 1 (stop)

TX_BYTE (8-bit):  Holds byte received from AXI write to TX_DATA register
  EN: AXI write to TX_DATA offset AND TX_IDLE

BIT_COUNT (4-bit counter 0..9):  Tracks how many bits have been sent
  Reset when entering TX_START.
```

### 3.3 State register (2-bit)

```
Register (2b, CLR=NOT(RST_N))
  Reset → TX_IDLE (2'b00)
```

### 3.4 State comparators

```
IN_TX_IDLE  = (TX_STATE == 2'b00)
IN_TX_START = (TX_STATE == 2'b01)
IN_TX_DATA  = (TX_STATE == 2'b10)
IN_TX_STOP  = (TX_STATE == 2'b11)
```

### 3.5 Next-state logic

```
NEW_BYTE = AXI write to TX_DATA AND IN_TX_IDLE AND BAUD_TICK (optional: latch byte first, then send)
  Simplified: trigger on write to TX_DATA when idle.

NS_TX_IDLE  = IN_TX_STOP AND BAUD_TICK
NS_TX_START = IN_TX_IDLE AND NEW_BYTE_EN    (new byte ready to send)
NS_TX_DATA  = IN_TX_START AND BAUD_TICK     (start bit sent, move to data)
            | IN_TX_DATA AND BAUD_TICK AND NOT(BIT_COUNT==7)  ← still data bits
NS_TX_STOP  = IN_TX_DATA AND BAUD_TICK AND (BIT_COUNT==7)    ← all 8 bits sent

NEW_BYTE_EN: Register (1b, set by AXI TX_DATA write, cleared on NS_TX_START)
  Acts as a "byte pending" flag.

Bit derivation:
  NEXT_TX[1] = NS_TX_DATA | NS_TX_STOP
  NEXT_TX[0] = NS_TX_START | NS_TX_STOP

Logisim: 4 OR gates for NS_* signals; 2 OR gates for NEXT_TX bits.
```

### 3.6 Shift register operation

```
LOAD = transitioning to TX_START (NS_TX_START AND NOT(IN_TX_START))
SHIFT = IN_TX_DATA AND BAUD_TICK

TX_SHIFT_REG (10-bit register, EN = LOAD OR SHIFT):
  D = LOAD ? {1'b1, TX_BYTE, 1'b0} : {1'b1, TX_SHIFT_REG[9:1]}

MUX (10b, 1-sel): sel = LOAD
  Input 0 (shift): {1'b1, TX_SHIFT_REG[9:1]}
    Logisim: Splitter extract [9:1] (9 bits), combine with Constant(1,1) at MSB → 10b
  Input 1 (load):  {1'b1, TX_BYTE[7:0], 1'b0}
    Logisim: Combine Splitter: [0]=0, [8:1]=TX_BYTE, [9]=1
  Register(10b, EN = LOAD OR SHIFT): D = MUX output
```

### 3.7 BIT_COUNT (4-bit counter)

```
Component: Counter (4-bit)
  CLR: LOAD (reset to 0 on load)
  EN:  IN_TX_DATA AND BAUD_TICK (count each data bit)
  Output: BIT_COUNT[3:0]

BIT7_DONE = (BIT_COUNT == 4'd7)
  Comparator(4b): A=BIT_COUNT, B=Constant(7) → BIT7_DONE
```

### 3.8 Outputs

```
TX_READY = IN_TX_IDLE   (= UART TX_STATUS.bit0)
UART_TX  = TX_SHIFT_REG[0]   (LSB of shift register is current output bit)
           During TX_IDLE: TX = 1 (line idle high)
           Use MUX: sel=IN_TX_IDLE, In0=TX_SHIFT_REG[0], In1=1'b1 → UART_TX
```

---

## 4. Sub-circuit: `RxFSM` — UART RX State Machine

### 4.1 State Encoding (2-bit)

| State | Encoding | Role |
|-------|----------|------|
| RX_IDLE | 2'b00 | Wait for start bit (rx=0) |
| RX_START | 2'b01 | Verify start bit at mid-bit sample point |
| RX_DATA | 2'b10 | Sample 8 data bits at mid-bit points |
| RX_STOP | 2'b11 | Sample stop bit; validate framing |

### 4.2 Input synchronization

```
The raw UART_RX pin must be synchronized to CLK via 2 D flip-flops:
  FF1: D = UART_RX_PIN, CLK = CLK → FF1_Q
  FF2: D = FF1_Q,       CLK = CLK → RX_SYNC (clean synchronized rx)

Two D Flip-Flops (1-bit, no reset needed — just sync).
```

### 4.3 Internal registers

```
RX_SHIFT_REG (8-bit):  Accumulates received bits LSB-first.
  EN: IN_RX_DATA AND SAMPLE_TICK
  D:  {RX_SYNC, RX_SHIFT_REG[7:1]}   ← right-shift in new MSB from RX line
  Register(8b, EN=above)

SAMPLE_COUNT (5-bit counter): counts SAMPLE_TICKs to find mid-bit and bit boundaries.
  Used to detect: 8 sample ticks = half-bit (start bit center)
                  16 sample ticks = one full bit period
RX_BIT_COUNT (4-bit counter): counts received data bits (0..7).
```

### 4.4 State register (2-bit)

```
Register(2b, CLR=NOT(RST_N)) → reset to RX_IDLE
```

### 4.5 Next-state logic

```
START_DETECTED = NOT(RX_SYNC)   (falling edge on idle line = start bit)
  Glitch filter: require 2 consecutive sample ticks of 0:
    GLITCH_FF: D=START_DETECTED, Q=PREV_SD
    CLEAN_START = START_DETECTED AND PREV_SD

IN_IDLE_START = IN_RX_IDLE AND CLEAN_START

NS_RX_IDLE  = IN_RX_STOP AND SAMPLE_TICK
            | IN_RX_START AND SAMPLE_TICK AND MID_BIT AND RX_SYNC   ← bad start bit
NS_RX_START = IN_RX_IDLE AND CLEAN_START
            | IN_RX_START AND NOT(SAMPLE_TICK AND MID_BIT)
NS_RX_DATA  = IN_RX_START AND SAMPLE_TICK AND MID_BIT AND NOT(RX_SYNC)  ← valid start
            | IN_RX_DATA AND NOT(BIT_DONE)
NS_RX_STOP  = IN_RX_DATA AND BIT_DONE AND SAMPLE_TICK

MID_BIT = (SAMPLE_COUNT == 5'd8)   ← 8 sample ticks after start-bit edge = mid-bit
BIT_DONE = (RX_BIT_COUNT == 4'd7) AND SAMPLE_TICK
```

### 4.6 Outputs

```
RX_DATA_REG (8-bit): captured when valid stop bit received
  EN = IN_RX_STOP AND SAMPLE_TICK AND RX_SYNC   (valid stop = rx=1)
  D  = RX_SHIFT_REG[7:0]
  Register(8b, EN=above, CLR=NOT(RST_N))

RX_VALID_REG (1-bit): set when byte captured, cleared when AXI reads RX_DATA
  D = (EN above) OR (RX_VALID_REG AND NOT(AXI_RX_READ))
  D-FF: set/clear logic as OR-AND combination

RX_STATUS = RX_VALID_REG   (= UART RX_STATUS.bit0)
UART_TX_DATA_OUT = RX_DATA_REG[7:0]  (connected to UART RX_DATA AXI register)
```

---

## 5. Sub-circuit: `UartCore` — Top-Level UART

Integrates `BaudGen`, `TxFSM`, `RxFSM`, and AXI slave register interface.

```
AXI register map (all gated by SEL_UART from decoder):
  Offset 0x00: TX_DATA (W)  → write to TxFSM.TX_BYTE, set NEW_BYTE_EN
  Offset 0x04: TX_STATUS(R) → {31'b0, TX_READY}
  Offset 0x08: RX_DATA (R)  → {24'b0, RX_DATA_REG}; read clears RX_VALID (R9)
  Offset 0x0C: RX_STATUS(R) → {31'b0, RX_VALID_REG}

AXI slave follows same pattern as MMIORegs:
  AWREADY = WREADY = ARREADY = 1 (constant)
  Write decode: addr[3:2] = 2'b00 → TX_DATA write
  Read decode:  addr[3:2] selects TX_STATUS/RX_DATA/RX_STATUS
  BVALID/RVALID registered on handshake, cleared on bready/rready.
```

---

## 6. Sub-circuit: `GPIOLed` — GPIO / LED Register

Base: `0x0001_0200`

```
LED_REG (8-bit RW register):
  AXI write to offset 0x00 → update LED_REG[7:0]
  Read returns LED_REG[7:0] zero-padded to 32 bits.
  Only LED_REG[7:6] drive LED outputs (SW-driven LEDs 7 and 6).
  LED_REG[5:0] read as 0 (wired to constant 0 in read mux).

LED_SW[1:0] = LED_REG[7:6]   (output pins driving LED7, LED6)
```

---

## 7. Sub-circuit: `LEDStretcher` — Event-to-LED Pulse Stretcher (×5)

### 7.1 Purpose

Stretches a 1-cycle event pulse to ~84 ms (2^22 clock cycles at 50 MHz) so LEDs blink visibly.

### 7.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock |
| `RST_N` | In | 1 | Async reset |
| `EVENT` | In | 1 | 1-cycle pulse to stretch |
| `LED_OUT` | Out | 1 | Stretched LED output |

### 7.3 Circuit

```
Component: Arithmetic > Counter (22-bit, down-counter)
  CLK: CLK tunnel
  CLR: NOT(RST_N) → clear to 0
  Load: EVENT = 1 → load 2^22 - 1 = 0x3FFFFF (maximum count)
  EN:   LED_OUT (count down while active)
  Mode: Count down

On EVENT pulse → load 0x3FFFFF → counter counts down → reaches 0 → stops.
LED_OUT = (COUNT != 0)

NONZERO = OR-reduce of COUNT[21:0]
  Logisim: 22-input OR gate
    Inputs: all 22 bits of COUNT
    Output: LED_OUT (= 1 while count ≠ 0 → LED high)

Load enable: EVENT → Counter.Load input
Counter decrement: EN = LED_OUT (count down only while nonzero; stop at 0)
Data input to counter: Constant(0x3FFFFF, 22 bits) → Counter.D
```

### 7.4 Five instances (one per event LED)

```
Stretcher 0 (LED0): EVENT = DMEM_ACK0 (core 0 heartbeat)
Stretcher 1 (LED1): EVENT = DMEM_ACK1 (core 1 heartbeat)
Stretcher 2 (LED2): EVENT = INV_FIRE  (coherence event)
Stretcher 3 (LED3): EVENT = HIT0 OR HIT1
Stretcher 4 (LED4): EVENT = MISS0 OR MISS1
LED5 = ERR_STICKY (level, no stretching needed)
LED6 = LED_REG[7] (SW)
LED7 = LED_REG[6] (SW)

Final LED merge (8-bit output bus):
  LED[0] = Stretcher0.LED_OUT
  LED[1] = Stretcher1.LED_OUT
  LED[2] = Stretcher2.LED_OUT
  LED[3] = Stretcher3.LED_OUT
  LED[4] = Stretcher4.LED_OUT
  LED[5] = ERR_STICKY
  LED[6] = LED_REG[7]
  LED[7] = LED_REG[6]

  Combine Splitter (8 × 1-bit → 8-bit LED bus) → LED[7:0] output pins
```

---

## 8. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| INV/HIT/MISS Counters | Data bits | 32; Up; CLR input yes; EN input yes |
| DOORBELL Register | Data bits | 32; Enable yes |
| CONTROL Register | Data bits | 32; Initial value | 1 (coh_enable=1) |
| ERR_STICKY DFF | Data bits | 1 |
| AXI reg comparators | Data bits | 6 (offset address bits [7:2]) |
| Read RDATA MUX | Data bits | 32; Select bits 3 |
| COH_STATUS pad Splitter | Combines 16b input with 16b zero → 32b |
| BaudGen Counter | Data bits | 10; Max value 433; Overflow → wrap |
| Oversampler Counter | Data bits | 5; Max value 26; Overflow → wrap |
| TX state register | Data bits | 2; CLR async |
| TX_BYTE register | Data bits | 8; Enable yes |
| TX_SHIFT_REG | Data bits | 10; Enable yes |
| BIT_COUNT Counter | Data bits | 4; CLR on load; EN on tick |
| RX sync FFs (×2) | Data bits | 1; No CLR needed |
| RX state register | Data bits | 2; CLR async |
| RX_SHIFT_REG | Data bits | 8; Enable yes |
| RX_DATA_REG | Data bits | 8; Enable yes |
| RX_VALID_REG | Data bits | 1 |
| SAMPLE_COUNT Counter | Data bits | 5 |
| LED_REG Register | Data bits | 8; Enable yes |
| LEDStretcher Counter | Data bits | 22; Down; Load input yes; EN input yes |
| LEDStretcher OR gate | Data bits | 1; Inputs 22 |
| Final LED Combine Splitter | 8 × 1-bit → 8-bit output |
