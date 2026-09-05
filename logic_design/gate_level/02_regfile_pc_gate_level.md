# Gate-Level Circuit: Register File & PC Logic (Logisim Sub-circuits `RegFile32` + `PCLogic`)

Source: `03_core_datapath_and_control.md` §2, §4, §6  
Logisim sub-circuit names: **`RegFile32`**, **`PCLogic`**, **`WritebackMux`**, **`LoadResize`**, **`StoreRotate`**

---

## 1. Sub-circuit: `RegFile32` — 32 × 32-bit Register File

### 1.1 Specification recap
- 32 registers × 32 bits each
- **2 asynchronous read ports** (RS1, RS2): output is combinational from the address
- **1 synchronous write port** (RD): write on rising edge of CLK, only when WEN=1
- x0 is hardwired zero: reads always return 0; writes to address 0 are silently ignored

### 1.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `RS1_ADDR` | In | 5 | Read port 1 address |
| `RS2_ADDR` | In | 5 | Read port 2 address |
| `RD_ADDR` | In | 5 | Write port address |
| `RD_WDATA` | In | 32 | Write data |
| `RD_WEN` | In | 1 | Write enable (synchronous) |
| `CLK` | In | 1 | Clock (via tunnel) |
| `RST_N` | In | 1 | Async reset (not applied to contents — see note) |
| `RS1_RDATA` | Out | 32 | Read data port 1 (combinational) |
| `RS2_RDATA` | Out | 32 | Read data port 2 (combinational) |

### 1.3 Internal Structure

#### Register array (32 × 32-bit D flip-flop banks)

```
For each register r = 1 to 31  (r=0 is hardwired, no register needed):

  Component: Memory > Register, 32 bits
    CLK     → CLK tunnel
    D[31:0] → write-enable gated data (see below)
    Q[31:0] → reg_out[r][31:0]  (connect to read mux)

  Write-enable gating per register:
    addr_match[r] = (RD_ADDR == r)    ← 5-bit comparator
    Logisim: Comparator component
      Input A: RD_ADDR[4:0]
      Input B: Constant(r, 5 bits)
      Output: addr_match[r]

    wen_r[r] = RD_WEN AND addr_match[r]
    Logisim: AND gate (2 inputs)
      Input 0: RD_WEN
      Input 1: addr_match[r]
      Output: wen_r[r]  → connect to register CLK-enable pin (EN)

    Note: In Logisim, the Register component has an enable pin (EN).
    Set D = RD_WDATA (shared bus to all registers), EN = wen_r[r].
    This is the efficient way — one shared D bus, 31 separate enables.
```

#### x0 hardwire

```
Register x0 is NOT a flip-flop. It is a Constant component:
  Logisim: Wiring > Constant
    Value: 0x00000000
    Bit width: 32
  This constant feeds into the read mux at position 0.
```

#### Read Port 1 — Combinational Multiplexer

```
Component: Plexers > Multiplexer
  Data bits:   32
  Select bits: 5
  Inputs:      32  (one per register)

  Input  0: Constant(0, 32)        ← x0 = always zero
  Input  1: reg_out[1][31:0]
  Input  2: reg_out[2][31:0]
  ...
  Input 31: reg_out[31][31:0]
  Select:   RS1_ADDR[4:0]
  Output:   RS1_RDATA[31:0]
```

#### Read Port 2 — Identical structure

```
Component: Plexers > Multiplexer (second instance, same connections)
  Select:   RS2_ADDR[4:0]
  Output:   RS2_RDATA[31:0]
```

### 1.4 Logisim Layout Notes

```
Layout strategy (top to bottom):
  ┌─────────────────────────────────────────────────────────┐
  │  RS1_ADDR[4:0] ──► Read MUX 1 (32:1, 32b) ──► RS1_RDATA│
  │  RS2_ADDR[4:0] ──► Read MUX 2 (32:1, 32b) ──► RS2_RDATA│
  │                                                          │
  │  RD_WDATA[31:0] ──────────────────────── (shared D bus) │
  │                         ↓  (fan out to all 31 registers) │
  │  RD_ADDR[4:0] ──► 31× Comparator ──► AND(+WEN) ──► EN  │
  │                    (one per register r=1..31)            │
  │                                                          │
  │  Registers x1..x31: Column of 31 Register(32b) cells    │
  │  x0: Constant(0, 32b) ──► Read MUX inputs [0]           │
  └─────────────────────────────────────────────────────────┘

Tip: In Logisim, use the "5-bit Address Decoder" approach:
  - Place a 5-to-32 Decoder (Plexers > Decoder, 5-bit select)
  - Its output bit r is 1 when RD_ADDR == r
  - AND each output bit with RD_WEN → EN for register r
  - This replaces 31 individual comparators with a single Decoder component.
```

#### Decoder-based write enable (recommended Logisim approach)

```
Component: Plexers > Decoder
  Select bits: 5
  Output: 32 one-hot outputs (out[0]..out[31])

  out[r] = 1 when RD_ADDR == r (else 0)

For r = 1..31:
  AND gate (2-in):
    Input 0: out[r]
    Input 1: RD_WEN
    Output: wen_r[r] → Register[r].EN

For r = 0:
  Ignore out[0] — x0 is constant, no register.

Note: out[0] AND WEN would write to x0, but since x0 has no register, simply leave
this signal unconnected (or connect to a probe for debug).
```

### 1.5 Complete ASCII block diagram

```
  RS1_ADDR[4:0] ────────────────────────────────────────────────────┐
  RS2_ADDR[4:0] ──────────────────────────────────────────────────┐ │
                                                                   │ │
  RD_ADDR[4:0] ──► Decoder(5-to-32) ──┬── out[1..31] ──► AND ─► EN│ │
  RD_WEN ──────────────────────────── ┤                          │ │ │
                                       └── out[0] (unused)       │ │ │
                                                                  │ │ │
  RD_WDATA[31:0] ──────────────────────────────────────────────► D │ │
                                                                  │ │ │
  CLK (tunnel) ─────────────────────────────────────────────────►CLK│ │
                                                                  │ │ │
  [31 × Register(32b) cells: reg_out[1..31]]                      │ │ │
                 ↑                                                 │ │ │
                 └── Q[31:0] ──► Read MUX 1 inputs [1..31] ◄──────┘ │ │
                              └► Read MUX 2 inputs [1..31] ◄────────┘ │
                                                                       │
  Constant(0, 32b) ──────────► MUX1.input[0]  MUX2.input[0]          │
                                                                       │
  MUX1.select ◄── RS1_ADDR[4:0] ◄───────────────────────────────────┘
  MUX2.select ◄── RS2_ADDR[4:0]

  MUX1.out ──► RS1_RDATA[31:0]
  MUX2.out ──► RS2_RDATA[31:0]
```

---

## 2. Sub-circuit: `PCLogic` — Program Counter with Priority Mux

### 2.1 Specification recap (doc 03 §4)

```
Priority (highest first):
  1. RST_N=0  → PC ← 0x0000_0000  (async reset)
  2. STALL    → PC holds (no update)
  3. JUMP && JALR → PC ← (RS1_VAL + IMM_I) & ~1  (clear bit 0)
  4. JUMP && !JALR → PC ← PC + IMM_J
  5. BRANCH_TAKEN → PC ← PC + IMM_B
  6. default  → PC ← PC + 4
```

### 2.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock (tunnel) |
| `RST_N` | In | 1 | Async reset (tunnel) |
| `STALL` | In | 1 | 1 = STALL_MEM state (hold PC) |
| `JUMP` | In | 1 | JAL or JALR instruction |
| `JALR` | In | 1 | JALR (use rs1+imm target) |
| `BR_TAKEN` | In | 1 | Branch condition true |
| `RS1_VAL` | In | 32 | rs1 register value |
| `IMM_I` | In | 32 | I-type immediate |
| `IMM_B` | In | 32 | B-type immediate |
| `IMM_J` | In | 32 | J-type immediate |
| `PC_OUT` | Out | 32 | Current PC value |
| `PC_PLUS4` | Out | 32 | PC + 4 (for JAL/JALR writeback) |

### 2.3 Internal Structure

#### PC register

```
Component: Memory > Register, 32 bits
  CLK:  CLK tunnel
  RST:  RST_N (async, active-low → connect to CLR pin on Logisim register)
        Logisim Register: CLR is active-high; use a NOT gate on RST_N → CLR
  EN:   PC_EN (see below)
  D:    NEXT_PC[31:0]
  Q:    PC_CURR[31:0]
```

#### PC enable (suppress write on STALL)

```
PC_EN = NOT(STALL)
  NOT gate (1-in): Input = STALL, Output = PC_EN → Register.EN
```

#### PC + 4 adder

```
Component: Arithmetic > Adder, 32 bits, no carry-in
  Input A: PC_CURR[31:0]
  Input B: Constant(4, 32 bits)
  Output:  PC_PLUS4[31:0]   ← also drives output pin PC_PLUS4
```

#### PC + IMM_B adder (branch target)

```
Component: Arithmetic > Adder, 32 bits, no carry-in
  Input A: PC_CURR[31:0]
  Input B: IMM_B[31:0]
  Output:  PC_BRANCH[31:0]
```

#### PC + IMM_J adder (JAL target)

```
Component: Arithmetic > Adder, 32 bits, no carry-in
  Input A: PC_CURR[31:0]
  Input B: IMM_J[31:0]
  Output:  PC_JAL[31:0]
```

#### JALR target: (RS1_VAL + IMM_I) & ~1

```
Step 1: Add
  Component: Arithmetic > Adder, 32 bits
    Input A: RS1_VAL[31:0]
    Input B: IMM_I[31:0]
    Output:  JALR_RAW[31:0]

Step 2: Clear bit 0
  JALR_TARGET[31:0] = JALR_RAW[31:0] AND 0xFFFF_FFFE

  Logisim: AND gate (2 inputs, 32-bit)
    Input 0: JALR_RAW[31:0]
    Input 1: Constant(0xFFFFFFFE, 32 bits)
    Output:  JALR_TARGET[31:0]
```

#### Next-PC selection multiplexer (priority encoded as nested 2:1 MUXes)

```
Priority encoded using 3 cascaded 2:1 MUXes:

  Level 1: Select between PC+4 and BRANCH target
    MUX_L1 (32b, 1-sel):
      Input 0 (sel=0): PC_PLUS4[31:0]
      Input 1 (sel=1): PC_BRANCH[31:0]
      Select:          BR_TAKEN
      Output:          MUX_L1_OUT

  Level 2: Select between L1 and JAL target
    MUX_L2 (32b, 1-sel):
      Input 0 (sel=0): MUX_L1_OUT[31:0]
      Input 1 (sel=1): PC_JAL[31:0]
      Select:          JUMP AND NOT(JALR)    ← need AND + NOT gate
      Output:          MUX_L2_OUT

    NOT gate (1-in): Input = JALR, Output = NOT_JALR
    AND gate (2-in): Input 0 = JUMP, Input 1 = NOT_JALR → JAL_SEL → MUX_L2.Select

  Level 3: Select between L2 and JALR target
    MUX_L3 (32b, 1-sel):
      Input 0 (sel=0): MUX_L2_OUT[31:0]
      Input 1 (sel=1): JALR_TARGET[31:0]
      Select:          JUMP AND JALR          ← AND gate
      Output:          NEXT_PC[31:0]

    AND gate (2-in): Input 0 = JUMP, Input 1 = JALR → JALR_SEL → MUX_L3.Select

  NEXT_PC → PC register D input
```

#### Reset value: async clear to 0

```
The Logisim Register component's CLR pin drives all bits to 0 asynchronously.
Connect: NOT(RST_N) → CLR of the PC register
Reset value = 0x0000_0000 ✓
```

### 2.4 ASCII Block Diagram (PCLogic)

```
CLK ────────────────────────────────────────────────────► PC_REG.CLK
RST_N ──► NOT ──────────────────────────────────────────► PC_REG.CLR

                         ┌────────────────────────────────────────────┐
                         │   PC Register (32-bit, async CLR)          │
STALL ──► NOT ───────────► PC_REG.EN                                  │
NEXT_PC[31:0] ───────────► PC_REG.D                                   │
                         │ PC_REG.Q ──► PC_CURR[31:0] ──────────────── ┼──► PC_OUT
                         └────────────────────────────────────────────┘
                                │
              ┌─────────────────┼──────────────────────────────────────┐
              │                 │                                       │
              ▼                 ▼                                       ▼
         Adder(+4)        Adder(+IMM_B)                          Adder(+IMM_J)
              │                 │                                       │
         PC_PLUS4          PC_BRANCH                              PC_JAL
              │                 │
              └────► MUX_L1 ◄───┘  sel=BR_TAKEN
                        │
                        ▼
              MUX_L2 ◄──────── PC_JAL     sel=(JUMP AND NOT JALR)
                        │
                        ▼
              MUX_L3 ◄──────── JALR_TGT   sel=(JUMP AND JALR)
                        │
                     NEXT_PC ──────────────────────────────────────────► PC_REG.D


RS1_VAL[31:0] ──► Adder ──► JALR_RAW ──► AND(0xFFFFFFFE) ──► JALR_TGT
IMM_I[31:0]  ──► ┘

PC_PLUS4[31:0] ─────────────────────────────────────────────────────► PC_PLUS4 (output pin)
```

---

## 3. Sub-circuit: `WritebackMux` — Writeback Data Selector

Source: doc 03 §3, §5

### 3.1 Purpose

Selects which value is written back to the register file on instruction commit.

### 3.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `ALU_RES` | In | 32 | ALU result |
| `PC_PLUS4` | In | 32 | PC+4 (for JAL/JALR link) |
| `MEM_DATA` | In | 32 | Load data (from cache, after resize) |
| `LUI_IMM` | In | 32 | U-type immediate (for LUI) |
| `WB_SEL` | In | 2 | Writeback select: 00=ALU, 01=PC+4, 10=MEM, 11=LUI |
| `WB_DATA` | Out | 32 | Data to write to register file |

### 3.3 Circuit

```
Component: Plexers > Multiplexer
  Data bits:   32
  Select bits: 2
  Input 0 (00): ALU_RES[31:0]
  Input 1 (01): PC_PLUS4[31:0]
  Input 2 (10): MEM_DATA[31:0]
  Input 3 (11): LUI_IMM[31:0]
  Select:       WB_SEL[1:0]
  Output:       WB_DATA[31:0]
```

---

## 4. Sub-circuit: `LoadResize` — Load Data Lane Extraction + Sign Extension

Source: doc 03 §6

### 4.1 Purpose

Extracts the correct byte or halfword from the 32-bit `dmem_rdata` word, then sign- or zero-extends it to 32 bits.

### 4.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `RDATA` | In | 32 | Raw 32-bit word from cache |
| `ADDR_LSB` | In | 2 | addr[1:0] — byte lane selector |
| `LD_SIZE` | In | 2 | 00=byte 01=half 10=word |
| `LD_SEXT` | In | 1 | 1=sign-extend, 0=zero-extend |
| `LD_OUT` | Out | 32 | Resized load data |

### 4.3 Circuit

#### Step 1: Byte extraction (4:1 MUX on byte lanes)

```
Byte extraction:
  byte_lane0 = RDATA[7:0]
  byte_lane1 = RDATA[15:8]
  byte_lane2 = RDATA[23:16]
  byte_lane3 = RDATA[31:24]

  MUX_BYTE (8b, 2-sel):
    Input 0: RDATA[7:0]
    Input 1: RDATA[15:8]
    Input 2: RDATA[23:16]
    Input 3: RDATA[31:24]
    Select:  ADDR_LSB[1:0]
    Output:  SEL_BYTE[7:0]

  Extract using 4× Splitter or directly address bits via bit extraction from RDATA.
  In Logisim: place four Splitters on RDATA to extract [7:0], [15:8], [23:16], [31:24],
  then feed into a 4:1 MUX (8-bit, 2-bit select).
```

#### Step 2: Halfword extraction (2:1 MUX)

```
  half_lane0 = RDATA[15:0]
  half_lane1 = RDATA[31:16]

  MUX_HALF (16b, 1-sel):
    Input 0: RDATA[15:0]
    Input 1: RDATA[31:16]
    Select:  ADDR_LSB[1]   (bit 1 of address selects upper/lower half)
    Output:  SEL_HALF[15:0]
```

#### Step 3: Sign/zero extension

```
Byte path:
  Sign extension:   BYTE_SEXT[31:0] = {{24{SEL_BYTE[7]}}, SEL_BYTE[7:0]}
  Zero extension:   BYTE_ZEXT[31:0] = {24'b0, SEL_BYTE[7:0]}

  In Logisim: use the "Bit Extender" component
    Component: Wiring > Bit Extender
      Input:  SEL_BYTE[7:0]
      Output: 32 bits
      Type:   Sign-extended (when SEXT=1) OR Zero-extended (when SEXT=0)
    Two instances (one sign, one zero), then pick via MUX:
      MUX_BYTE_EXT (32b, 1-sel):
        Input 0: BYTE_ZEXT[31:0]
        Input 1: BYTE_SEXT[31:0]
        Select:  LD_SEXT
        Output:  BYTE_FINAL[31:0]

Half path:
  Sign extension:   HALF_SEXT[31:0] = {{16{SEL_HALF[15]}}, SEL_HALF[15:0]}
  Zero extension:   HALF_ZEXT[31:0] = {16'b0, SEL_HALF[15:0]}
  MUX_HALF_EXT (32b, 1-sel): same pattern → HALF_FINAL[31:0]

Word path: no extension needed.
  WORD_FINAL = RDATA[31:0]
```

#### Step 4: Size select (3:1 MUX)

```
Component: Plexers > Multiplexer
  Data bits:   32
  Select bits: 2
  Input 0 (00): BYTE_FINAL[31:0]
  Input 1 (01): HALF_FINAL[31:0]
  Input 2 (10): WORD_FINAL[31:0]
  Input 3 (11): WORD_FINAL[31:0]  (unused; tie to word)
  Select:       LD_SIZE[1:0]
  Output:       LD_OUT[31:0]
```

---

## 5. Sub-circuit: `StoreRotate` — Store Lane Rotation

Source: doc 03 §6

### 5.1 Purpose

Rotates store data into the correct byte lane position and generates `wmask`.

### 5.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `RS2_VAL` | In | 32 | Store data (from rs2) |
| `ADDR_LSB` | In | 2 | addr[1:0] |
| `ST_SIZE` | In | 2 | 00=byte 01=half 10=word |
| `WDATA` | Out | 32 | Rotated store data → cache |
| `WMASK` | Out | 4 | Byte enables → cache |

### 5.3 Circuit

#### WDATA rotation

```
Byte store: WDATA = RS2_VAL[7:0] replicated at position addr[1:0]
Half store: WDATA = RS2_VAL[15:0] replicated at position addr[1]

  MUX_ROT (32b, 2-sel):
    Input 0 (byte, addr=0): {24'b0, RS2[7:0]}
    Input 1 (byte, addr=1): {16'b0, RS2[7:0], 8'b0}
    Input 2 (byte, addr=2): {8'b0,  RS2[7:0], 16'b0}
    Input 3 (byte, addr=3): {RS2[7:0], 24'b0}
    For simplicity, 16 inputs (4 sizes × 4 byte positions) reduced to:
    Use ADDR_LSB as shift amount for left barrel shift of byte/half
    
  Pragmatic Logisim approach:
    - For byte: barrel-shift RS2[7:0] left by (ADDR_LSB × 8) within 32 bits
    - For half:  barrel-shift RS2[15:0] left by (ADDR_LSB[1] × 16) within 32 bits
    - For word:  RS2[31:0] as-is

  Implement as a 4:1 MUX on ST_SIZE upper bits combined with ADDR_LSB:
    MUX4 (32b, 2-sel) for ST_SIZE:
      Input 0 (byte):
        MUX4_byte (32b, 2-sel ADDR_LSB):
          0: {24'b0, RS2[7:0]}
          1: {16'b0, RS2[7:0], 8'b0}
          2: {8'b0,  RS2[7:0], 16'b0}
          3: {RS2[7:0], 24'b0}
      Input 1 (half):
        MUX2_half (32b, 1-sel ADDR_LSB[1]):
          0: {16'b0, RS2[15:0]}
          1: {RS2[15:0], 16'b0}
      Input 2 (word): RS2[31:0]
      Input 3 (word): RS2[31:0]
    Output: WDATA[31:0]
```

#### WMASK generation

```
Mask values:
  byte:     4'b0001 << ADDR_LSB  = position-shifted single byte
  half:     4'b0011 << {ADDR_LSB[1], 1'b0}
  word:     4'b1111

  Logisim: 3:1 MUX (4-bit, ST_SIZE select):
    Inner byte MUX (4b, 2-sel ADDR_LSB):
      Input 0: 4'b0001
      Input 1: 4'b0010
      Input 2: 4'b0100
      Input 3: 4'b1000
      → BYTE_MASK[3:0]

    Inner half MUX (4b, 1-sel ADDR_LSB[1]):
      Input 0: 4'b0011
      Input 1: 4'b1100
      → HALF_MASK[3:0]

    Outer MUX (4b, 2-sel ST_SIZE):
      Input 0: BYTE_MASK[3:0]
      Input 1: HALF_MASK[3:0]
      Input 2: 4'b1111
      Input 3: 4'b1111
    Output: WMASK[3:0]
```

---

## 6. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| RegFile — Register cells | Data bits | 32 |
| RegFile — Register cells | Trigger | Rising edge |
| RegFile — Register cells | Enable input | Yes |
| RegFile — Register cells | Clear (async) | Active high (NOT on RST_N) |
| RegFile — Decoder | Select bits | 5 |
| RegFile — Read MUX | Select bits | 5 |
| RegFile — Read MUX | Data bits | 32 |
| PC Register | Data bits | 32 |
| PC Register | Trigger | Rising edge |
| PC Register | Enable input | Yes (NOT STALL) |
| PC Register | Clear async | Active high (NOT RST_N) |
| PC+4 Adder | Data bits | 32 |
| PC+4 Adder | Carry in | No |
| WritebackMux | Select bits | 2 |
| WritebackMux | Data bits | 32 |
| LoadResize — Byte MUX | Select bits | 2; Data bits 8 |
| LoadResize — Half MUX | Select bits | 1; Data bits 16 |
| LoadResize — Size MUX | Select bits | 2; Data bits 32 |
| LoadResize — Bit Extender | Output width | 32 |
| StoreRotate — all MUXes | As described above | 32-bit and 4-bit |
