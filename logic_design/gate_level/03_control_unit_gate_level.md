# Gate-Level Circuit: Control Unit, Immediate Generator & Core FSM

Source: `03_core_datapath_and_control.md` §3, §5  
Logisim sub-circuit names: **`ControlUnit`**, **`ImmGen`**, **`CoreFSM`**

---

## 1. Sub-circuit: `ImmGen` — Immediate Generator

### 1.1 Purpose

Extracts and sign-extends the five RV32I immediate formats (I, S, B, U, J) from the 32-bit instruction word. Pure combinational logic — all done with Splitters and Bit Extenders in Logisim.

### 1.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `INSTR` | In | 32 | Full instruction word |
| `IMM_I` | Out | 32 | I-type: `{{20{inst[31]}}, inst[31:20]}` |
| `IMM_S` | Out | 32 | S-type: `{{20{inst[31]}}, inst[31:25], inst[11:7]}` |
| `IMM_B` | Out | 32 | B-type: `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` |
| `IMM_U` | Out | 32 | U-type: `{inst[31:12], 12'b0}` |
| `IMM_J` | Out | 32 | J-type: `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` |

### 1.3 Field extraction — Splitter placement

All extraction is done purely with Logisim **Splitters**. Each Splitter "fans out" specific bit ranges from `INSTR[31:0]`.

```
Primary Splitter on INSTR[31:0] — extract these named fields:

  Field          Bits            Wire name
  ─────────────────────────────────────────
  sign_bit       [31]            SIGN
  funct7_6       [31]            (same as sign — aliased)
  imm_i_raw      [31:20]         IMM_I_RAW   (12 bits)
  funct7         [31:25]         FUNCT7      (7 bits)
  rs2            [24:20]         RS2_F       (5 bits, used by decoder)
  rs1            [19:15]         RS1_F       (5 bits)
  funct3         [14:12]         FUNCT3      (3 bits)
  rd             [11:7]          RD_F        (5 bits)
  s_lo           [11:7]          S_LO        (5 bits — same bits as RD, used for S-imm)
  opcode         [6:0]           OPCODE      (7 bits)
  b_bit_11       [7]             B11         (1 bit, B-imm bit 11)
  b_bits_4_1     [11:8]          B_4_1       (4 bits, B-imm bits 4:1)
  b_bits_10_5    [30:25]         B_10_5      (6 bits, B-imm bits 10:5)
  b_bit_12       [31]            B12         (1 bit — same as SIGN)
  j_bits_19_12   [19:12]         J_19_12     (8 bits)
  j_bit_11       [20]            J11         (1 bit)
  j_bits_10_1    [30:21]         J_10_1      (10 bits)
  u_upper        [31:12]         U_UPPER     (20 bits)

Use multiple Splitters from INSTR[31:0]:
  Splitter A: input=32b, outputs individual fields above
  (Logisim allows a single fan-out Splitter to route any subset of bits)
```

### 1.4 IMM_I construction

```
Bit layout: [31:20] = sign-extended inst[31], [19:12] = sign, [11:0] = inst[31:20]

Logisim: Bit Extender
  Input:      IMM_I_RAW[11:0]   (= INSTR[31:20])
  Output:     32 bits
  Extension:  Signed (replicates bit 11 = INSTR[31] to positions 12..31)
  Result:     IMM_I[31:0]
```

### 1.5 IMM_S construction

```
Bit layout: inst[31:25] concatenated with inst[11:7], then sign-extended

Step 1: Concatenate FUNCT7[6:0] and S_LO[4:0] → 12-bit raw S-imm
  Use a Splitter in "combine" mode (Logisim: set "Appears Facing" = right, 
  combine bits 0..4 from S_LO, bits 5..11 from FUNCT7)
  Output: S_RAW[11:0]

Step 2: Sign-extend to 32 bits
  Bit Extender: Input = S_RAW[11:0], Output = 32b, Signed
  Result: IMM_S[31:0]
```

### 1.6 IMM_B construction

```
Bit layout (RV32I B-format):
  [12]    = inst[31]  (B12)
  [11]    = inst[7]   (B11)
  [10:5]  = inst[30:25] (B_10_5)
  [4:1]   = inst[11:8]  (B_4_1)
  [0]     = 0 (always, LSB of branch offset = 0 for 2-byte alignment)

  Assemble 13-bit vector using a combine Splitter (13 inputs → 1 output):
    bit 0:    Constant(0, 1b)
    bits 4:1: B_4_1[3:0]
    bits 10:5: B_10_5[5:0]
    bit 11:   B11
    bit 12:   B12
    Output: B_RAW[12:0]

  Sign-extend to 32 bits:
    Bit Extender: Input = B_RAW[12:0], Output = 32b, Signed (bit 12 = sign)
  Result: IMM_B[31:0]
```

### 1.7 IMM_U construction

```
Bit layout: upper 20 bits in [31:12], lower 12 bits = 0

  Combine Splitter (32-bit output):
    bits 11:0  = Constant(0, 12b)
    bits 31:12 = U_UPPER[19:0]
  Result: IMM_U[31:0]

  (No sign extension — U-type immediate is already 32-bit aligned)
```

### 1.8 IMM_J construction

```
Bit layout (RV32I J-format):
  [20]    = inst[31]  (sign)
  [19:12] = inst[19:12] (J_19_12)
  [11]    = inst[20]  (J11)
  [10:1]  = inst[30:21] (J_10_1)
  [0]     = 0

  Assemble 21-bit vector via combine Splitter (21 inputs):
    bit 0:    Constant(0, 1b)
    bits 10:1: J_10_1[9:0]
    bit 11:   J11
    bits 19:12: J_19_12[7:0]
    bit 20:   SIGN
    Output: J_RAW[20:0]

  Sign-extend to 32 bits:
    Bit Extender: Input = J_RAW[20:0], Output = 32b, Signed (bit 20 = sign)
  Result: IMM_J[31:0]
```

### 1.9 ASCII Layout

```
INSTR[31:0]
     │
     └──► Splitter (fan-out) ──┬──► [31:20] ──► Bit Extender(12→32, signed) ──► IMM_I
                               ├──► [31:25]+[11:7] → Combine → Bit Extender ──► IMM_S
                               ├──► {[31],[7],[30:25],[11:8],0} → Combine → BitExt ► IMM_B
                               ├──► {[31:12], 12'b0} → Combine ──────────────────► IMM_U
                               └──► {[31],[19:12],[20],[30:21],0} → Combine → BitExt► IMM_J
```

---

## 2. Sub-circuit: `ControlUnit` — RV32I Instruction Decoder

### 2.1 Purpose

Pure combinational logic. Takes `INSTR[31:0]` and produces all control signals for the datapath. Implemented in Logisim as a structured network of comparators, AND/OR gates, and output multiplexers — one per control signal.

### 2.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `INSTR` | In | 32 | Full instruction word |
| `ALU_SRC_A` | Out | 1 | 0=rs1, 1=PC |
| `ALU_SRC_B` | Out | 1 | 0=rs2, 1=imm |
| `ALU_OP` | Out | 4 | ALU operation select |
| `REG_WEN` | Out | 1 | Write enable for register file |
| `WB_SEL` | Out | 2 | Writeback mux: 00=ALU 01=PC+4 10=MEM 11=LUI |
| `MEM_RE` | Out | 1 | Load (data memory read) |
| `MEM_WE` | Out | 1 | Store (data memory write) |
| `LD_SIZE` | Out | 2 | Load size: 00=byte 01=half 10=word |
| `LD_SEXT` | Out | 1 | Sign-extend load |
| `ST_SIZE` | Out | 2 | Store size |
| `BR_SEL` | Out | 3 | Branch condition: funct3 |
| `BR_TAKEN_EN` | Out | 1 | Instruction is a branch (gated by condition) |
| `JUMP` | Out | 1 | JAL or JALR |
| `JALR` | Out | 1 | Is JALR (use rs1+imm target) |
| `IMM_SEL` | Out | 3 | Which immediate to forward (I/S/B/U/J) |
| `RS1_ADDR` | Out | 5 | rs1 field [19:15] |
| `RS2_ADDR` | Out | 5 | rs2 field [24:20] |
| `RD_ADDR` | Out | 5 | rd field [11:7] |

### 2.3 Field extraction

```
All fields extracted from INSTR via a single Splitter:

  Splitter on INSTR[31:0]:
    Output A: OPCODE[6:0]  = INSTR[6:0]
    Output B: RD_ADDR[4:0] = INSTR[11:7]
    Output C: FUNCT3[2:0]  = INSTR[14:12]
    Output D: RS1_ADDR[4:0]= INSTR[19:15]
    Output E: RS2_ADDR[4:0]= INSTR[24:20]
    Output F: FUNCT7[6:0]  = INSTR[31:25]

  RD_ADDR, RS1_ADDR, RS2_ADDR pass straight to output pins.
  FUNCT3 passes straight to BR_SEL output and is used in decode logic below.
```

### 2.4 Opcode decode — comparator bank

Each opcode group gets a dedicated 7-bit comparator producing a 1-bit "group active" signal.

```
Logisim component: Comparator
  Data bits: 7
  One comparator per opcode group:

  Name          Constant   Condition
  ─────────────────────────────────────────
  IS_OP_IMM     0b0010011  OPCODE == 0x13  → I-type arithmetic (ADDI..SRAI)
  IS_OP_REG     0b0110011  OPCODE == 0x33  → R-type arithmetic (ADD..AND)
  IS_LOAD       0b0000011  OPCODE == 0x03  → Load (LB..LHU)
  IS_STORE      0b0100011  OPCODE == 0x23  → Store (SB..SW)
  IS_BRANCH     0b1100011  OPCODE == 0x63  → Branch (BEQ..BGEU)
  IS_JAL        0b1101111  OPCODE == 0x6F  → JAL
  IS_JALR       0b1100111  OPCODE == 0x67  → JALR
  IS_LUI        0b0110111  OPCODE == 0x37  → LUI
  IS_AUIPC      0b0010111  OPCODE == 0x17  → AUIPC
  IS_SYSTEM     0b1110011  OPCODE == 0x73  → ECALL/EBREAK (NOP decode)

  Each comparator:
    Input A: OPCODE[6:0]
    Input B: Constant(value, 7 bits)
    Output: A==B → named signal above
```

### 2.5 Funct3 decode (for ALU op and shift disambiguation)

```
F3 comparators (3-bit, reused across multiple groups):

  F3_000  = (FUNCT3 == 3'b000)
  F3_001  = (FUNCT3 == 3'b001)
  F3_010  = (FUNCT3 == 3'b010)
  F3_011  = (FUNCT3 == 3'b011)
  F3_100  = (FUNCT3 == 3'b100)
  F3_101  = (FUNCT3 == 3'b101)
  F3_110  = (FUNCT3 == 3'b110)
  F3_111  = (FUNCT3 == 3'b111)

Each: Comparator (3 bits), Input A = FUNCT3, Input B = Constant
```

### 2.6 FUNCT7 decode (for R-type SUB/SRA/SRLI disambiguation)

```
  F7_0        = (FUNCT7 == 7'b0000000)
  F7_ALT      = (FUNCT7 == 7'b0100000)  → SUB, SRA, SRLI vs SRAI

  Two 7-bit comparators.
```

### 2.7 Control signal derivation — gate-level equations

#### REG_WEN (write enable)

```
REG_WEN = IS_OP_IMM OR IS_OP_REG OR IS_LOAD OR IS_JAL OR IS_JALR OR IS_LUI OR IS_AUIPC

Logisim: 7-input OR gate
  Inputs: IS_OP_IMM, IS_OP_REG, IS_LOAD, IS_JAL, IS_JALR, IS_LUI, IS_AUIPC
  Output: REG_WEN
```

#### ALU_SRC_A (0=rs1, 1=PC)

```
ALU_SRC_A = IS_AUIPC OR IS_JAL
  (JAL: PC+imm_j; AUIPC: PC+imm_u; all others use rs1)

Logisim: 2-input OR gate → ALU_SRC_A
```

#### ALU_SRC_B (0=rs2, 1=imm)

```
ALU_SRC_B = IS_OP_IMM OR IS_LOAD OR IS_STORE OR IS_BRANCH OR IS_JAL OR IS_JALR OR IS_LUI OR IS_AUIPC
  (Everything except R-type uses an immediate operand)
  NOT(IS_OP_REG) is equivalent — simpler:
  
ALU_SRC_B = NOT(IS_OP_REG)
  Exception: IS_BRANCH uses rs2 for comparison (ALU_SRC_B=0 in the table)
  Corrected: ALU_SRC_B = NOT(IS_OP_REG OR IS_BRANCH)

Logisim:
  OR gate (2-in): IS_OP_REG, IS_BRANCH → REG_OR_BR
  NOT gate: REG_OR_BR → ALU_SRC_B
```

#### MEM_RE, MEM_WE

```
MEM_RE  = IS_LOAD
MEM_WE  = IS_STORE
  Direct wires from comparator outputs.
```

#### JUMP, JALR

```
JUMP = IS_JAL OR IS_JALR
JALR = IS_JALR

Logisim:
  OR gate (2-in): IS_JAL, IS_JALR → JUMP
  Wire IS_JALR directly to JALR output.
```

#### BR_TAKEN_EN (is a branch instruction)

```
BR_TAKEN_EN = IS_BRANCH
  Direct wire.
```

#### WB_SEL[1:0] — 4-option writeback select

```
Encoding: 00=ALU, 01=PC+4, 10=MEM, 11=LUI

WB_SEL[1] = IS_LOAD OR IS_LUI
WB_SEL[0] = IS_JAL OR IS_JALR OR IS_LUI

Logisim:
  WB_SEL[1]: OR gate (IS_LOAD, IS_LUI)
  WB_SEL[0]: OR gate (IS_JAL, IS_JALR, IS_LUI)   ← 3-input OR
```

#### LD_SIZE[1:0], LD_SEXT

```
LD_SIZE[1:0] encodes load width:
  00 = byte  (funct3 = 000 or 100)
  01 = half  (funct3 = 001 or 101)
  10 = word  (funct3 = 010)

  LD_SIZE[1] = F3_010                    (word: funct3=010)
  LD_SIZE[0] = F3_001 OR F3_101          (half: funct3=001 or 101)

  Logisim:
    LD_SIZE[1]: direct wire from F3_010
    LD_SIZE[0]: OR gate (F3_001, F3_101)

LD_SEXT: sign-extend for LB (000) and LH (001); zero-extend for LBU (100), LHU (101)
  LB/LH → sign (funct3[2]=0), LBU/LHU → zero (funct3[2]=1)
  LD_SEXT = NOT(FUNCT3[2])
  
  Logisim: Splitter to extract FUNCT3[2] → NOT gate → LD_SEXT
```

#### ST_SIZE[1:0]

```
  Same encoding as LD_SIZE but for stores (funct3: SB=000, SH=001, SW=010):
  ST_SIZE[1] = F3_010
  ST_SIZE[0] = F3_001
  Same gate structure as LD_SIZE.
```

#### ALU_OP[3:0] — the most complex decode

```
Encoding from doc 02 §2:
  ADD=0000, SUB=0001, SLL=0010, SLT=0011, SLTU=0100, XOR=0101,
  SRL=0110, SRA=0111, OR=1000, AND=1001

ALU_OP is derived from a priority-encoded MUX over instruction type:

Case 1: R-type (IS_OP_REG=1)
  Subcase by funct3 and funct7:
    F3_000 & F7_0    → ADD  (0000)
    F3_000 & F7_ALT  → SUB  (0001)
    F3_001           → SLL  (0010)
    F3_010           → SLT  (0011)
    F3_011           → SLTU (0100)
    F3_100           → XOR  (0101)
    F3_101 & F7_0    → SRL  (0110)
    F3_101 & F7_ALT  → SRA  (0111)
    F3_110           → OR   (1000)
    F3_111           → AND  (1001)

Case 2: I-type arithmetic (IS_OP_IMM=1)
  Same funct3 mapping, but no F7 for most; SRAI uses F7_ALT bit 30.
  Identical to R-type except SUB does not exist and shifts use imm[10] for arithmetic.

Case 3: LOAD/STORE/JAL/JALR/AUIPC → always ADD (0000) for address calc
Case 4: BRANCH → always SUB (0001) for comparison
Case 5: LUI → ALU not used (WB_SEL=11 bypasses ALU), but set ADD as default

Implementation: use a 4-bit output priority MUX tree.
```

#### ALU_OP gate-level (per-bit equations)

```
Let us define intermediate signals for each possible op, gated by their condition:

  do_ADD  = (IS_OP_REG & F3_000 & F7_0)
          | (IS_OP_IMM & F3_000)
          | IS_LOAD | IS_STORE | IS_JAL | IS_JALR | IS_AUIPC | IS_LUI | IS_SYSTEM

  do_SUB  = (IS_OP_REG & F3_000 & F7_ALT) | IS_BRANCH

  do_SLL  = (IS_OP_REG | IS_OP_IMM) & F3_001
  do_SLT  = (IS_OP_REG | IS_OP_IMM) & F3_010
  do_SLTU = (IS_OP_REG | IS_OP_IMM) & F3_011
  do_XOR  = (IS_OP_REG | IS_OP_IMM) & F3_100
  do_SRL  = (IS_OP_REG | IS_OP_IMM) & F3_101 & F7_0
  do_SRA  = (IS_OP_REG | IS_OP_IMM) & F3_101 & (F7_ALT | INSTR[30])
               ← for I-type shift: use INSTR[30] directly
  do_OR   = (IS_OP_REG | IS_OP_IMM) & F3_110
  do_AND  = (IS_OP_REG | IS_OP_IMM) & F3_111

ALU_OP bits derived (priority: first match wins via OR-of-products):
  ALU_OP[3] = do_OR  | do_AND
  ALU_OP[2] = do_XOR | do_SRL | do_SRA | do_OR | do_AND   ← bit pattern inspection
  Simpler: use a 4-bit priority encoder driven by do_* signals.

Logisim recommended approach:
  Use a 16-input MUX (4-bit output, 4-bit select = instruction-type+funct3 combination),
  OR use a ROM (Logisim: Memory > ROM) as a lookup table:
    Address input: {IS_OP_REG, IS_OP_IMM, IS_BRANCH, FUNCT3[2:0], FUNCT7[5]}  = 7 bits
    ROM size: 128 × 4 bits
    Pre-programmed with ALU_OP for every combination.

  This is the most practical Logisim implementation for the decoder.
  
ROM programming (key entries, rest = ADD=0000):
  Address bits: [6]=IS_OP_REG, [5]=IS_OP_IMM, [4]=IS_BRANCH, [3:1]=FUNCT3, [0]=FUNCT7[5]

  Addr    Binary       ALU_OP  Instruction
  ──────────────────────────────────────────────
  0x41    1000001      0000    ADD  (R, f3=000, f7=0)
  0x43    1000011      0001    SUB  (R, f3=000, f7=1)
  0x49    1001001      0010    SLL  (R/I, f3=001)
  0x51    1010001      0011    SLT  (R/I, f3=010)
  0x59    1011001      0100    SLTU (R/I, f3=011)
  0x61    1100001      0101    XOR  (R/I, f3=100)
  0x69    1101001      0110    SRL  (f3=101, f7=0)
  0x6B    1101011      0111    SRA  (f3=101, f7=1)
  0x71    1110001      1000    OR   (f3=110)
  0x79    1111001      1001    AND  (f3=111)
  (IS_BRANCH rows → 0001 = SUB)
  (IS_LOAD/STORE/JAL/JALR/AUIPC → 0000 = ADD)
```

### 2.8 ASCII Block Diagram (ControlUnit)

```
INSTR[31:0]
    │
    └── Splitter ──┬── OPCODE[6:0] ──► 10× Comparator(7b) ─┬── IS_OP_IMM
                   │                                         ├── IS_OP_REG
                   │                                         ├── IS_LOAD
                   │                                         ├── IS_STORE
                   │                                         ├── IS_BRANCH
                   │                                         ├── IS_JAL
                   │                                         ├── IS_JALR
                   │                                         ├── IS_LUI
                   │                                         ├── IS_AUIPC
                   │                                         └── IS_SYSTEM
                   │
                   ├── FUNCT3[2:0] ──► 8× Comparator(3b) ─── F3_000..F3_111
                   │                  + direct pass ──────────► BR_SEL[2:0]
                   │
                   ├── FUNCT7[6:0] ──► 2× Comparator(7b) ─── F7_0, F7_ALT
                   │
                   ├── RS1_ADDR[4:0] ─────────────────────────────────────────► RS1_ADDR
                   ├── RS2_ADDR[4:0] ─────────────────────────────────────────► RS2_ADDR
                   └── RD_ADDR[4:0]  ─────────────────────────────────────────► RD_ADDR

IS_* signals ──► Gate network ──► REG_WEN, ALU_SRC_A, ALU_SRC_B, WB_SEL[1:0]
                                   MEM_RE, MEM_WE, JUMP, JALR, BR_TAKEN_EN
                                   LD_SIZE[1:0], LD_SEXT, ST_SIZE[1:0]

IS_* + F3_* + F7_* ──► ROM LUT (128×4) ──► ALU_OP[3:0]
```

---

## 3. Sub-circuit: `CoreFSM` — RUN / STALL_MEM State Machine

### 3.1 Specification (doc 03 §5)

Two states: `RUN` (1'b0) and `STALL_MEM` (1'b1).

| State | Condition | Next state | Key outputs |
|-------|-----------|------------|-------------|
| RUN | `MEM_RE OR MEM_WE` = 0 | RUN | commit instruction (reg write, pc update) |
| RUN | `MEM_RE OR MEM_WE` = 1 | STALL_MEM | assert dmem_req, hold pc |
| STALL_MEM | `DMEM_ACK` = 0 | STALL_MEM | hold all, keep dmem outputs |
| STALL_MEM | `DMEM_ACK` = 1 | RUN | commit (load: write rd; store: no write) |

### 3.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock |
| `RST_N` | In | 1 | Async reset |
| `MEM_RE` | In | 1 | Load request (from control unit) |
| `MEM_WE` | In | 1 | Store request |
| `DMEM_ACK` | In | 1 | Cache ack (commit pulse) |
| `DMEM_ERR` | In | 1 | Cache error (with ack) |
| `IS_LOAD` | In | 1 | Current instruction is a load (for wb decision) |
| `FSM_STATE` | Out | 1 | 0=RUN, 1=STALL_MEM |
| `STALL` | Out | 1 | = FSM_STATE (drives PC enable, reg-write gate) |
| `DMEM_REQ` | Out | 1 | 1 when in STALL_MEM |
| `RD_WEN_GATE` | Out | 1 | Allow reg write: RUN commit OR STALL+ACK+load+!err |

### 3.3 State register (1-bit D flip-flop)

```
Component: Memory > D Flip-Flop (or Register 1-bit)
  CLK: CLK tunnel
  CLR: NOT(RST_N) → CLR  (reset → RUN state = 0)
  D:   NEXT_STATE (see below)
  Q:   CURR_STATE[0]     (1=STALL_MEM)
```

### 3.4 Next-state logic (combinational)

```
MEM_ACTIVE = MEM_RE OR MEM_WE
  OR gate (2-in): MEM_RE, MEM_WE → MEM_ACTIVE

NEXT_STATE logic:
  When CURR_STATE=0 (RUN):
    NEXT = MEM_ACTIVE               (go to STALL if memory op)
  When CURR_STATE=1 (STALL):
    NEXT = NOT(DMEM_ACK)            (stay if no ack, return to RUN on ack)

  Full equation:
    NEXT_STATE = (NOT(CURR_STATE) AND MEM_ACTIVE)
                 OR (CURR_STATE AND NOT(DMEM_ACK))

Logisim:
  NOT gate: CURR_STATE → N_CURR
  AND gate (2-in): N_CURR, MEM_ACTIVE → TERM_A
  NOT gate: DMEM_ACK → N_ACK
  AND gate (2-in): CURR_STATE, N_ACK → TERM_B
  OR  gate (2-in): TERM_A, TERM_B → NEXT_STATE → D of flip-flop
```

### 3.5 Output logic

```
STALL   = CURR_STATE   (direct wire from Q)
DMEM_REQ = CURR_STATE  (direct wire — request held in STALL)

RD_WEN_GATE:
  Condition to allow register write:
    a) Non-memory instruction in RUN state committing:
       COMMIT_REG = NOT(CURR_STATE) AND NOT(MEM_ACTIVE)
    b) Load completing with ACK and no error:
       LOAD_COMMIT = CURR_STATE AND DMEM_ACK AND IS_LOAD AND NOT(DMEM_ERR)

  RD_WEN_GATE = COMMIT_REG OR LOAD_COMMIT

  Logisim:
    NOT: CURR_STATE → N_STATE
    NOT: MEM_ACTIVE → N_MEM
    AND (2-in): N_STATE, N_MEM → COMMIT_REG

    NOT: DMEM_ERR → N_ERR
    AND (4-in): CURR_STATE, DMEM_ACK, IS_LOAD, N_ERR → LOAD_COMMIT

    OR (2-in): COMMIT_REG, LOAD_COMMIT → RD_WEN_GATE

  This RD_WEN_GATE is then ANDed with REG_WEN from the control unit:
    FINAL_WEN = RD_WEN_GATE AND REG_WEN
    (placed in the top-level core wiring, not inside CoreFSM)
```

### 3.6 ASCII Block Diagram (CoreFSM)

```
RST_N ──► NOT ─────────────────────────────────────────────────► DFF.CLR
CLK ───────────────────────────────────────────────────────────► DFF.CLK

MEM_RE ──┐
          ├── OR ──► MEM_ACTIVE ─────────────────────────────────►─────┐
MEM_WE ──┘                                                             │
                                                                        │
CURR_STATE (Q) ──┬────────────────────────────────────────────────► STALL
                 │                                                  DMEM_REQ
                 │   NOT(CURR_STATE) ──► AND ──► TERM_A ──► OR ──► NEXT_STATE ──► DFF.D
                 │              MEM_ACTIVE ──────┘          ↑
                 │   NOT(DMEM_ACK) ──► AND ──► TERM_B ──────┘
                 └─────────────────────┘

CURR_STATE, DMEM_ACK, IS_LOAD, NOT(DMEM_ERR) ──► AND(4) ──► LOAD_COMMIT ──┐
NOT(CURR_STATE), NOT(MEM_ACTIVE) ──────────────► AND(2) ──► COMMIT_REG  ──┴──► OR ──► RD_WEN_GATE
```

---

## 4. Logisim Component Settings Summary

| Sub-circuit | Component | Setting | Value |
|-------------|-----------|---------|-------|
| ImmGen | Bit Extender (I-imm) | Input bits | 12; Output 32; Signed |
| ImmGen | Bit Extender (S-imm) | Input bits | 12; Output 32; Signed |
| ImmGen | Bit Extender (B-imm) | Input bits | 13; Output 32; Signed |
| ImmGen | Bit Extender (J-imm) | Input bits | 21; Output 32; Signed |
| ImmGen | Splitters (combine) | Bits match fields above | — |
| ControlUnit | Comparators (opcode) | Data bits | 7 |
| ControlUnit | Comparators (f3) | Data bits | 3 |
| ControlUnit | Comparators (f7) | Data bits | 7 |
| ControlUnit | ROM (ALU decode) | Address bits | 7; Data bits | 4 |
| CoreFSM | D Flip-Flop | Bits | 1; Trigger rising edge; CLR async active-high |
| CoreFSM | All gates | As described above | 1-bit |

---

## 5. Top-Level `RV32ICore` Integration Note

The three sub-circuits connect as follows at the core level:

```
INSTR[31:0] ──► ImmGen ──────────────────────────────► IMM_I/S/B/U/J
             └─► ControlUnit ──────────────────────────► all control signals
                                                         │
                           ┌── CoreFSM.MEM_RE/WE ◄──────┘
                           │   CoreFSM.DMEM_ACK ◄── (from d_cache_mgr)
                           │   CoreFSM.DMEM_ERR ◄── (from d_cache_mgr)
                           │
                           └── CoreFSM outputs:
                                 STALL ──► PCLogic.STALL
                                         RegFile.WEN gating
                                 DMEM_REQ ──► d_cache_mgr.dmem_req
                                 RD_WEN_GATE AND REG_WEN ──► RegFile.WEN
```
