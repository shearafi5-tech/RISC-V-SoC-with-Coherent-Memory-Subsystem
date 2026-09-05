# Gate-Level Circuit: ALU (Logisim Sub-circuit `ALU`)

Source: `02_alu_logic.md`  
Logisim sub-circuit name: **`ALU`**  
Contains internal sub-circuits: `Adder32`, `BarrelShiftLeft32`, `BarrelShiftRight32`, `Comparator32`, `ZeroDetect32`

---

## 1. Top-Level ALU — Pin List

| Pin name | Direction | Bits | Logisim pin type | Description |
|----------|-----------|------|-----------------|-------------|
| `A` | Input | 32 | Input Pin | Operand A |
| `B` | Input | 32 | Input Pin | Operand B |
| `OP` | Input | 4 | Input Pin | Operation select (4-bit) |
| `RES` | Output | 32 | Output Pin | Result |
| `ZERO` | Output | 1 | Output Pin | Result == 0 |
| `LT` | Output | 1 | Output Pin | Signed A < B |
| `LTU` | Output | 1 | Output Pin | Unsigned A < B |

---

## 2. Internal Sub-circuit: `Adder32` (32-bit Carry-Lookahead Adder / Subtractor)

This is the arithmetic core. `SUB_SEL=1` inverts B and adds 1 (2's complement subtraction).  
In Logisim, use the built-in **Adder** component set to 32 bits with carry-in wired.

### Pins

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `A_IN` | In | 32 | Operand A |
| `B_IN` | In | 32 | Operand B (already possibly inverted) |
| `C_IN` | In | 1 | Carry-in (= 1 for subtraction, 0 for addition) |
| `SUM` | Out | 32 | Result |
| `C_OUT` | Out | 1 | Carry-out (used for `LTU` flag) |

### Gate-level description

```
For each bit i (0 to 31):
  Full Adder cell:
    s[i]    = A[i] XOR B[i] XOR c[i]
    c[i+1]  = (A[i] AND B[i]) OR ((A[i] XOR B[i]) AND c[i])

  Logisim primitives per bit:
    XOR gate (2-in): A[i], B[i]        → partial_xor[i]
    XOR gate (2-in): partial_xor[i], c[i]  → s[i]  (= SUM[i])
    AND gate (2-in): A[i], B[i]        → g[i]   (generate)
    AND gate (2-in): partial_xor[i], c[i]  → p_c[i] (propagate × carry)
    OR  gate (2-in): g[i], p_c[i]     → c[i+1]

  In Logisim: replace the 32 cascaded Full Adder cells with a single
  "Arithmetic > Adder" component, 32 bits, with carry-in pin wired.
  This is the correct Logisim representation.
```

### SUB/ADD selector (placed immediately before `Adder32`)

```
  For subtraction: B must be inverted and carry-in set to 1.

  Primitives:
    - 32-bit NOT gate (Logisim: Gate > NOT, 32-bit):
        Input:  B[31:0]
        Output: B_INV[31:0]

    - 32-bit 2:1 MUX (Logisim: Plexers > Multiplexer, 32-bit, 1 select):
        Input 0:  B[31:0]        (ADD path)
        Input 1:  B_INV[31:0]   (SUB path)
        Select:   OP[0]          ← op 0001 means SUB; MSB of subtraction ops
        Output:   B_MUX[31:0]

    - Carry-in wire:
        C_IN = OP[0]   (same select bit: 1 for SUB, 0 for ADD)
        ← Use a tunnel wire labeled C_IN from OP[0]
```

### ASCII wiring (Adder32 block)

```
A[31:0] ──────────────────────────────────────────────► Adder32.A
                                                         │
B[31:0] ──► NOT32 ──► B_INV ──► MUX32 ─────────────────► Adder32.B
                 └──────────────┘↑sel=OP[0]
OP[0] ──────────────────────────────────────────────────► Adder32.C_IN
                                                         │
                                                        SUM[31:0] → output
                                                        C_OUT → LTU logic
```

---

## 3. Internal Sub-circuit: `BarrelShiftLeft32`

Implements `A << B[4:0]` (SLL). A 5-stage shift network where each stage either shifts by 2^stage or passes through.

### Structure (5 stages, each a 32-bit 2:1 mux)

```
Stage 0 (shift by 1):
  sel = B[0]
  for bit i:  out[i] = B[0] ? (i>=1 ? in[i-1] : 0) : in[i]
  Logisim: MUX 32-bit, select = B[0]
           Input 0 = in[31:0]
           Input 1 = {in[30:0], 1'b0}  (shift left by 1, fill 0)

Stage 1 (shift by 2):
  sel = B[1]
  Input 0 = stage0_out[31:0]
  Input 1 = {stage0_out[29:0], 2'b00}

Stage 2 (shift by 4):
  sel = B[2]
  Input 1 = {stage1_out[27:0], 4'b0000}

Stage 3 (shift by 8):
  sel = B[3]
  Input 1 = {stage2_out[23:0], 8'b0}

Stage 4 (shift by 16):
  sel = B[4]
  Input 1 = {stage3_out[15:0], 16'b0}

Output: stage4_out[31:0] = A << B[4:0]
```

In Logisim: 5 × Multiplexer (32-bit, 1-bit select), chained. The shifted input for each stage uses **Splitters** to slice and rejoin with zero fill.

---

## 4. Internal Sub-circuit: `BarrelShiftRight32`

Two modes: logical (SRL, fill=0) and arithmetic (SRA, fill=A[31]).

### Structure (5 stages)

```
Stage 0 (shift by 1):
  sel_shift = B[0]
  fill = (SRA_SEL) ? A[31] : 0       ← SRA_SEL is a 1-bit input
  out[i] = B[0] ? (i<=30 ? in[i+1] : fill) : in[i]

  Logisim: separate fill bit using a Multiplexer (1-bit, sel=SRA_SEL)
           Input 0 = 0
           Input 1 = A[31]
           Then each stage's fill is this 1-bit signal.

Stages 1-4: same pattern shifting by 2,4,8,16 respectively, same fill.
```

---

## 5. Internal Sub-circuit: `Comparator32`

Produces `LT` (signed) and `LTU` (unsigned) from A and B.

```
LTU (unsigned less-than):
  = NOT(C_OUT) of SUB(A, B)
  LTU = ~c_out_from_adder
  Wire: C_OUT from Adder32 → NOT gate (1-bit) → LTU output

LT (signed less-than):
  Two cases, controlled by sign bits:
  Case 1: A[31]=1, B[31]=0  → A is negative, B non-negative → A < B = 1
  Case 2: A[31]=0, B[31]=1  → A non-negative, B negative  → A < B = 0
  Case 3: A[31]=B[31]       → same sign: use SUB result sign bit (diff[31])

  Logic:
    signs_differ = A[31] XOR B[31]
    lt_sign_case  = A[31]               (A neg, B pos → lt)
    lt_same_case  = diff[31]            (same sign: sign of difference)
    LT = MUX(signs_differ, lt_same_case, lt_sign_case)
       = (signs_differ AND A[31]) OR (NOT(signs_differ) AND diff[31])

  Logisim primitives:
    XOR gate  (A[31], B[31])            → signs_differ
    AND gate  (signs_differ, A[31])     → lt_if_differ
    NOT gate  (signs_differ)            → same_sign
    AND gate  (same_sign, diff[31])     → lt_if_same
    OR  gate  (lt_if_differ, lt_if_same) → LT

  diff[31] = SUM[31] from Adder32 operating in SUB mode
```

---

## 6. Internal Sub-circuit: `ZeroDetect32`

```
ZERO = NOR(RES[31], RES[30], ... RES[0])
     = NOT(RES[31] OR RES[30] OR ... OR RES[0])

Logisim: 32-input NOR gate → ZERO output
  (Logisim allows multi-input gates: Gate > NOR, Inputs=32)
```

---

## 7. Top-Level ALU Wiring

The top-level ALU sub-circuit wires together all internal components using an output result multiplexer driven by `OP[3:0]`.

### Result Mux (10 operations → 1 result)

```
OP encoding → result source:

  0000 ADD  → SUM from Adder32 (SUB_SEL=0, C_IN=0)
  0001 SUB  → SUM from Adder32 (SUB_SEL=1, C_IN=1)
  0010 SLL  → BarrelShiftLeft32 output
  0011 SLT  → {31'b0, LT}  (zero-extend LT to 32 bits)
  0100 SLTU → {31'b0, LTU}
  0101 XOR  → A XOR B (32-bit XOR gate)
  0110 SRL  → BarrelShiftRight32 (SRA_SEL=0)
  0111 SRA  → BarrelShiftRight32 (SRA_SEL=1)
  1000 OR   → A OR B  (32-bit OR gate)
  1001 AND  → A AND B (32-bit AND gate)
  1010-1111 → ADD (default, same as 0000)
```

### Logisim Multiplexer for result

```
Component: Plexers > Multiplexer
  Data bits:   32
  Select bits: 4
  Inputs:      16 (0000 through 1111)

  Input  0 (0000): ADD_RESULT[31:0]
  Input  1 (0001): SUB_RESULT[31:0]
  Input  2 (0010): SLL_RESULT[31:0]
  Input  3 (0011): {31-bit const 0, LT}   ← use Constant(0,31) + Splitter merge
  Input  4 (0100): {31-bit const 0, LTU}
  Input  5 (0101): XOR_RESULT[31:0]
  Input  6 (0110): SRL_RESULT[31:0]
  Input  7 (0111): SRA_RESULT[31:0]
  Input  8 (1000): OR_RESULT[31:0]
  Input  9 (1001): AND_RESULT[31:0]
  Inputs 10-15:    ADD_RESULT[31:0]  (tie to ADD, default case)
  Select:          OP[3:0]
  Output:          RES[31:0]
```

### Combined Adder (ADD and SUB share one Adder32)

```
One Adder32 instance with:
  A_IN    = A[31:0]
  B_IN    = B_MUX[31:0]  (B or ~B based on OP[0])
  C_IN    = OP[0]         (tunnel from OP splitter)
  SUM     = ADD_OR_SUB[31:0]  (used for both ADD and SUB result mux inputs)
  C_OUT   = COUT
```

### Bitwise operations (separate gate arrays)

```
32-bit XOR gate: A XOR B → XOR_RESULT
32-bit OR  gate: A OR  B → OR_RESULT
32-bit AND gate: A AND B → AND_RESULT
  Logisim: Gate > XOR/OR/AND, set Data Bits = 32, Inputs = 2
```

### SRA_SEL generation

```
OP[3:0] = 0111 for SRA:
  SRA_SEL = OP[3] AND (NOT OP[2]) AND OP[1] AND OP[0]
  Wait — simpler: SRA_SEL = (OP == 4'b0111)

  Logisim: 4-input AND gate with:
    Input 0: NOT(OP[3])  ← no, OP[3]=0 for SRA
    Actually OP=0111: NOT(OP[3]) AND NOT(OP[2]) AND OP[1] AND OP[0]

    NOT gate  (OP[3]) → nOP3
    NOT gate  (OP[2]) → nOP2
    AND gate  (nOP3, nOP2, OP[1], OP[0]) → SRA_SEL
    ← In Logisim: 4-input AND gate
```

### ZERO flag

```
ZeroDetect32 input = RES[31:0]  (output of result MUX)
Output = ZERO
```

### LT and LTU flags

```
LT  and LTU are always computed from the Adder32 in SUB mode:
  The Adder32 is always active with B_MUX and C_IN.
  When OP≠SUB/SLT/SLTU, these flags are valid but unused by the result mux —
  the control unit (doc 03) reads LT/LTU directly for branches using SUB op.

  LTU = NOT(C_OUT)     ← NOT gate on COUT
  LT  = Comparator32 logic (described in §5 above)
```

---

## 8. Full ASCII Block Diagram (ALU top level)

```
         A[31:0]──┬────────────────────────────────────────────────┐
                  │                                                 │
                  │   ┌──NOT32──► B_INV──┐                          │
         B[31:0]──┼───┤                  ├──MUX32──► B_MUX[31:0]    │
                  │   └──────────────────┘↑sel=OP[0]               │
                  │                                                 │
                  │   B_MUX──────────────────────────────────►     │
                  │   OP[0]──────────────────────────────────►  Adder32
                  │                                              │  │
                  │                               SUM[31:0] ────┼──┤  ← ADD/SUB result
                  │                               COUT ─────────┼──┤  ← for LTU
                  │                                             │  │
                  ├──────────────────────────────►  XOR32 ──────┤  │  XOR result
                  │                                             │  │
                  ├──────────────────────────────►  OR32  ──────┤  │  OR result
                  │                                             │  │
                  ├──────────────────────────────►  AND32 ──────┤  │  AND result
                  │                                             │  │
                  ├──────────────────────────────►  BarrelSLL32 ─┤  │  SLL result
                  │                                             │  │
                  ├──────────────────────────────►  BarrelSRL32 ─┤  │  SRL result
                  └──────────────────────────────►  BarrelSRA32 ─┤  │  SRA result
                                                               │  │
B[4:0]  ──────────────────────────────────────────────────────┘  │  (shift amount to all barrel shifters)
                                                                  │
              ┌───────────────── Result MUX 16:1 (32b) ──────────┘
              │   select = OP[3:0]
              │   0000/1010-1111 → ADD_RESULT
              │   0001 → SUB_RESULT
              │   0010 → SLL_RESULT
              │   0011 → {0×31, LT}
              │   0100 → {0×31, LTU}
              │   0101 → XOR_RESULT
              │   0110 → SRL_RESULT
              │   0111 → SRA_RESULT
              │   1000 → OR_RESULT
              │   1001 → AND_RESULT
              └──────────────────────────────────────────────────► RES[31:0]

Flags (always live, wired from Adder32 + Comparator32):
  COUT ──► NOT ──────────────────────────────────────────────────► LTU
  Comparator32 (A[31], B[31], SUM[31]) ─────────────────────────► LT
  ZeroDetect32(RES[31:0]) ──────────────────────────────────────► ZERO
```

---

## 9. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| Adder (Adder32) | Data bits | 32 |
| Adder (Adder32) | Has carry-in | Yes |
| Adder (Adder32) | Has carry-out | Yes |
| MUX B_INV selector | Select bits | 1 |
| MUX B_INV selector | Data bits | 32 |
| MUX result | Select bits | 4 |
| MUX result | Data bits | 32 |
| XOR/OR/AND gates | Data bits | 32 |
| XOR/OR/AND gates | Number of inputs | 2 |
| ZeroDetect NOR | Number of inputs | 32 |
| ZeroDetect NOR | Gate type | NOR |
| All barrel-shift MUXes | Data bits | 32 |
| All barrel-shift MUXes | Select bits | 1 |

---

## 10. Notes for Logisim Layout

- Place `Adder32` at the center-left of the canvas.
- Place barrel shifters (`BarrelSLL32`, `BarrelSRL32/SRA32`) below.
- Place bitwise gates (XOR/OR/AND) in a column to the right of the adder.
- The result MUX sits at the far right, collecting all computed values.
- Use **Splitters** to extract `OP[0]`, `OP[3:0]`, `B[4:0]`, `A[31]`, `B[31]` from their buses.
- Use **Tunnels** labeled `ADD_RESULT`, `SUB_RESULT`, `SLL_RESULT`, etc. to route from each block to the MUX inputs — avoids long crossing wires.
- `LT` and `LTU` outputs sit below the result MUX as separate output pins.
