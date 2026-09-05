# 02 — ALU Logic Table (T1.1)

Acceptance: *all RV32I ops defined with select encoding*. The ALU is pure combinational logic
(`rtl/core/alu.sv`), parameterized width (default 32). This document is the gate-level/truth-table
design for it, plus the operand muxing that lives just outside it and the branch-resolution logic the
control unit applies to ALU flags.

---

## 1. Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `a_i` | in | 32 | Operand A |
| `b_i` | in | 32 | Operand B |
| `op_i` | in | 4 | Operation select (§2) |
| `res_o` | out | 32 | Result |
| `zero_o` | out | 1 | `res == 0` |
| `lt_o` | out | 1 | signed  `a < b` |
| `ltu_o` | out | 1 | unsigned `a < b` |

## 2. Operand sources (mux in front of the ALU — controlled by control unit, doc 03)

`a` mux (2:1): `rs1_value` | `pc` (AUIPC, JAL, branch target calc)
`b` mux (2:1): `rs2_value` | `imm` (all I/S/B/U-format ops except OP-class)

LUI does **not** use the ALU: `wb_sel = LUI` bypasses `imm_u` directly to the writeback mux (doc 03 §3.3).

## 3. Operation select encoding + truth table

`op_i` is 4 bits: 10 used encodings, 6 unused (default to ADD in RTL to avoid latches/X-prop).

| `op_i` | Operation | RTL expression | Used by |
|--------|-----------|----------------|---------|
| 0000 | ADD | `a + b` | ADD/ADDI, LW/SW/JAL/JALR address calc, AUIPC (a=PC) |
| 0001 | SUB | `a - b` | SUB (and branch comparison internally) |
| 0010 | SLL | `a << b[4:0]` | SLL/SLLI |
| 0011 | SLT | signed  `a < b ? 1 : 0` | SLT/SLTI |
| 0100 | SLTU | unsigned `a < b ? 1 : 0` | SLTU/SLTIU |
| 0101 | XOR | `a ^ b` | XOR/XORI |
| 0110 | SRL | `a >> b[4:0]` (logical) | SRL/SRLI |
| 0111 | SRA | `$signed(a) >>> b[4:0]` | SRA/SRAI |
| 1000 | OR | `a \| b` | OR/ORI |
| 1001 | AND | `a & b` | AND/ANDI |
| 1010–1111 | unused | tie to `a + b` | — |

Per-bit truth table (bit level, `c_in` = carry into bit i for ADD/SUB; SUB is `a + ~b + 1`):

| op | result bit i | notes |
|----|--------------|-------|
| ADD | `a[i] ^ b[i] ^ c[i]` | `c[i+1] = a[i]b[i] \| (a[i]^b[i])&c[i]` |
| SUB | `a[i] ^ ~b[i] ^ c[i]` | same carry eq on `~b` → one adder serves both (mux `b` vs `~b`) |
| AND/OR/XOR | `a[i]&b[i]` / `a[i]\|b[i]` / `a[i]^b[i]` | bitwise |
| SLL | `a[i-b[4:0]]` | barrel shifter, left |
| SRL | `a[i+b[4:0]]` (0 fill) | barrel shifter, right, fill = 0 |
| SRA | `a[i+b[4:0]]` (sign fill) | right, fill = `a[31]` |
| SLT/SLTU | `lt_o` / `ltu_o` | single-bit result |

## 4. Flag equations (derived from the same 32-bit adder)

Let `diff = a + ~b + 1` (i.e., SUB) with carry-out `cout`:

```
zero_o = (res == 32'b0)                      // |~res reduced by NOR tree
ltu_o  = ~cout                               // unsigned a<b  ⇔ borrow
lt_o   = (a[31] != b[31]) ? a[31] : diff[31] // signed a<b:
                                             //  differing signs: a<b iff a negative
                                             //  same signs:      a<b iff diff negative
```

`lt_o`/`ltu_o` are computed every cycle from the adder (cheap), regardless of `op_i`; SLT/SLTU select
them into the result. Branches reuse them directly (§5) — no separate comparator needed.

## 5. Branch resolution (in core, driven by ALU flags + `funct3`)

| `funct3` | Branch | Taken = | Equation |
|----------|--------|---------|----------|
| 000 | BEQ  | `eq`    | `eq  = zero_o` (SUB a,b) |
| 001 | BNE  | `!eq`   | |
| 100 | BLT  | `lt`    | `lt = lt_o` |
| 101 | BGE  | `!lt`   | |
| 110 | BLTU | `ltu`   | `ltu = ltu_o` |
| 011/111 | — | 0 (not taken) | illegal funct3: treat as not-taken |

Branch ALU op is always SUB; `br_un` selects which of `lt/ltu` the BGE/BGEU inversion applies to.

## 6. Critical-path analysis (feeds sky130 20 MHz budget)

Longest combinational path in the whole SoC (single-cycle core, load instruction):

```
imem (async read) → decode → RF read → 32-bit ADD (rs1+imm) → D-cache tag compare + state check
                  → hit mux (rdata) → load resize → RF write enable
```

ALU-internal critical path: 32-bit ripple/CLA carry chain (ADD/SUB) → `lt` correction mux → result mux.
At 20 MHz (50 ns) on sky130_fd_sc_hd this closes comfortably with a carry-lookahead or even ripple
adder; if timing tightening to 40 MHz ever fails, the first lever is the adder topology, the second is
the cache tag compare (doc 04 §4.9). The shifter is a 5-stage barrel (2-input muxes per stage), depth 5
— shorter than the adder chain.

## 7. RTL translation notes

- One `always_comb` with a `case (op_i)` over the 10 encodings; all outputs assigned in every branch
  (no latches). `default: ADD`.
- Shifts: mask shift amount to `b[4:0]` — RV32I semantics ignore upper bits.
- Do **not** compute `lt_o` from the SLT case only — flags must be valid whenever a branch uses SUB.
- Keep `zero/lt/ltu` combinational from operands, not registered (single-cycle timing).
