# 03 — Core Datapath, Control Decode, and the Core FSM

The RV32I single-cycle core (`rtl/core/rv32i_core.sv` = ALU + reg_file + control_unit + PC + data
interface). Every non-memory instruction completes in one clock; loads/stores stall the core until the
private D-cache manager returns `dmem_ack`. This document defines the decode truth table (needed before
`control_unit.sv`), the datapath wiring, PC logic, register file, store/load lane logic, and the small
core FSM.

---

## 1. Datapath block diagram

```
                     ┌───────────────────────────────────────────────────────────┐
                     │                        rv32i_core                         │
                     │                                                           │
  imem_addr ◄────────┤ PC ──►(PC+4 / target mux)◄── branchTaken/jal/jalr ─┐      │
      ▲              │  │                                                 │      │
      │              │  └──► instr[31:0] ◄──────────── imem_rdata ──────────┼──────┤ (from private I-SRAM)
                     │        │                                             │      │
                     │   ┌────▼──────────┐   control signals                  │      │
                     │   │ control_unit  │───────────────┐                    │      │
                     │   └────┬──────────┘               │                    │      │
                     │        │ rs1/rs2/rd/funct3/imm    ▼                    │      │
                     │   ┌────▼─────┐   ┌──────────┐  ┌─────▼─────┐   ┌──────┴───┐  │
                     │   │ reg_file │──►│  ALU     │◄─│ imm / rs2 │   │ load     │  │
                     │   │ 32×32 2R1W│  │ (doc 02) │  │   mux     │   │ resize   │  │
                     │   └────┬─────┘   └────┬─────┘  └───────────┘   └──────▲───┘  │
                     │        │              │res                            │      │
                     │        │         ┌────▼─────────── writeback mux ◄────┤      │
                     │        └─────────► (ALU / PC+4 / MEM / LUI)            │      │
                     │                 └──────────────────────────────────────┘      │
                     │                                                               │
   dmem_req/we/addr ─┤► data-if (holds req until ack)  ◄── dmem_ack / dmem_err ──────┤
   dmem_wdata/wmask ─┤► (to private D-cache mgr)       ──► dmem_rdata ─────────────►│
                     └───────────────────────────────────────────────────────────┘
```

## 2. Register file (`reg_file.sv`)

- 32 × 32-bit, **2 asynchronous read ports, 1 synchronous write port** (single-cycle needs comb read).
- `x0` hardwired zero: read returns 0; writes to `x0` are ignored.
- Write-first behavior is automatic: the write lands on the clock edge; the next instruction's
  combinational read sees it next cycle — no hazard logic needed.
- During a memory stall (`STALL_MEM`), `rd_wen` is held low until `dmem_ack` (the commit edge, §3.5).

## 3. Control unit — full RV32I decode table

Instruction fields: `opcode = instr[6:0]`, `rd = instr[11:7]`, `funct3 = instr[14:12]`,
`rs1 = instr[19:15]`, `rs2 = instr[24:20]`, `funct7 = instr[31:25]`.

Immediate extraction (per format):

```
imm_i = {{20{instr[31]}}, instr[31:20]}
imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]}
imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
imm_u = {instr[31:12], 12'b0}
imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
```

Control signals:

| Signal | Meaning |
|--------|---------|
| `alu_src_a` | 0 = rs1, 1 = PC |
| `alu_src_b` | 0 = rs2, 1 = imm |
| `alu_op[3:0]` | doc 02 §2 encoding |
| `br_sel[2:0]` | branch condition select (doc 02 §5) |
| `br_taken` | 1 = instruction is a branch (target chosen if condition true) |
| `jump` | JAL/JALR: unconditionally redirect PC |
| `jalr` | JALR: target = (rs1+imm)&~1 instead of PC+imm |
| `reg_wen` | write rd |
| `wb_sel[1:0]` | 00 = ALU, 01 = PC+4, 10 = MEM (load), 11 = LUI imm |
| `mem_re` / `mem_we` | load / store (implies `dmem_req`) |
| `ld_size[1:0]` | 00=byte 01=half 10=word |
| `ld_sext` | sign-extend load |
| `st_size[1:0]` | 00=byte 01=half 10=word (mask generation) |

### Decode truth table (all RV32I, 39 instructions)

| Instr | opcode | funct3/funct7 | alu_src_a | alu_src_b | alu_op | reg_wen | wb_sel | mem | br/jump |
|-------|--------|---------------|-----------|-----------|--------|---------|--------|-----|---------|
| ADDI  | 0010011 | 000 | 0 | imm | ADD | 1 | ALU | — | — |
| SLTI  | 0010011 | 010 | 0 | imm | SLT | 1 | ALU | — | — |
| SLTIU | 0010011 | 011 | 0 | imm | SLTU | 1 | ALU | — | — |
| XORI  | 0010011 | 100 | 0 | imm | XOR | 1 | ALU | — | — |
| ORI   | 0010011 | 110 | 0 | imm | OR | 1 | ALU | — | — |
| ANDI  | 0010011 | 111 | 0 | imm | AND | 1 | ALU | — | — |
| SLLI  | 0010011 | 001/f7=0 | 0 | imm | SLL | 1 | ALU | — | — |
| SRLI  | 0010011 | 101/f7=0 | 0 | imm | SRL | 1 | ALU | — | — |
| SRAI  | 0010011 | 101/f7=0100000 | 0 | imm | SRA | 1 | ALU | — | — |
| ADD   | 0110011 | 000/f7=0 | 0 | rs2 | ADD | 1 | ALU | — | — |
| SUB   | 0110011 | 000/f7=0100000 | 0 | rs2 | SUB | 1 | ALU | — | — |
| SLL   | 0110011 | 001 | 0 | rs2 | SLL | 1 | ALU | — | — |
| SLT   | 0110011 | 010 | 0 | rs2 | SLT | 1 | ALU | — | — |
| SLTU  | 0110011 | 011 | 0 | rs2 | SLTU | 1 | ALU | — | — |
| XOR   | 0110011 | 100 | 0 | rs2 | XOR | 1 | ALU | — | — |
| SRL   | 0110011 | 101/f7=0 | 0 | rs2 | SRL | 1 | ALU | — | — |
| SRA   | 0110011 | 101/f7=0100000 | 0 | rs2 | SRA | 1 | ALU | — | — |
| OR    | 0110011 | 110 | 0 | rs2 | OR | 1 | ALU | — | — |
| AND   | 0110011 | 111 | 0 | rs2 | AND | 1 | ALU | — | — |
| LB    | 0000011 | 000 | 0 | imm | ADD | 1 | MEM | re, byte,  sext | — |
| LH    | 0000011 | 001 | 0 | imm | ADD | 1 | MEM | re, half,  sext | — |
| LW    | 0000011 | 010 | 0 | imm | ADD | 1 | MEM | re, word | — |
| LBU   | 0000011 | 100 | 0 | imm | ADD | 1 | MEM | re, byte,  zext | — |
| LHU   | 0000011 | 101 | 0 | imm | ADD | 1 | MEM | re, half,  zext | — |
| SB    | 0100011 | 000 | 0 | imm | ADD | 0 | — | we, byte | — |
| SH    | 0100011 | 001 | 0 | imm | ADD | 0 | — | we, half | — |
| SW    | 0100011 | 010 | 0 | imm | ADD | 0 | — | we, word | — |
| BEQ   | 1100011 | 000 | 0 | rs2 | SUB | 0 | — | — | br(BEQ) |
| BNE   | 1100011 | 001 | 0 | rs2 | SUB | 0 | — | — | br(BNE) |
| BLT   | 1100011 | 100 | 0 | rs2 | SUB | 0 | — | — | br(BLT) |
| BGE   | 1100011 | 101 | 0 | rs2 | SUB | 0 | — | — | br(BGE) |
| BLTU  | 1100011 | 110 | 0 | rs2 | SUB | 0 | — | — | br(BLTU) |
| BGEU  | 1100011 | 111 | 0 | rs2 | SUB | 0 | — | — | br(BGEU) |
| JAL   | 1101111 | — | PC | imm | ADD | 1 | PC+4 | — | jump |
| JALR  | 1100111 | 000 | 0 | imm | ADD | 1 | PC+4 | — | jump+jalr |
| LUI   | 0110111 | — | — | — | — | 1 | LUI | — | — |
| AUIPC | 0010111 | — | PC | imm | ADD | 1 | ALU | — | — |
| ECALL | 1110011 | — | — | — | — | 0 | — | — | nop |
| EBREAK| 1110011 | — | — | — | — | 0 | — | — | nop |

Note: TRD lists "37 instructions" but enumerates 39 (incl. ecall/ebreak). All 39 are decoded here;
`fence` is out of scope per the TRD list. Illegal opcodes decode to a NOP (no state change) — never
leave control signals unassigned.

## 4. PC logic

```
reset:            pc <= RESET_PC            // 0x0000_0000, async rst_n
normal:           pc <= pc + 4
branch taken:     pc <= pc + imm_b
JAL:              pc <= pc + imm_j
JALR:             pc <= (rs1_val + imm_i) & 32'hFFFF_FFFE
STALL_MEM:        pc holds (no update — instruction not yet committed)
```

One `pc` register; next-PC mux priority: `STALL_MEM → hold`, else `jump ? (jalr ? jalr_t : pc+imm_j)`
, else `br_taken && cond ? pc+imm_b : pc+4`.

## 5. Core FSM (the only sequential control in the core)

Single-cycle core = 2 states. Everything except loads/stores finishes in RUN within one cycle.

```
        rst_n=0
          │
          ▼
      ┌───────┐   mem_re|mem_we (dmem_req=1, wait)   ┌────────────┐
      │  RUN  │ ───────────────────────────────────► │ STALL_MEM  │
      │       │                                      │ (pc, ctrl  │
      │       │ ◄─────────────────────────────────── │  held)     │
      └───────┘      dmem_ack (commit edge)          └────────────┘
```

### Transition table

| State | Condition | Next state | Actions |
|-------|-----------|------------|---------|
| RUN   | `!(mem_re\|mem_we)` | RUN | full commit this edge: `pc<=next_pc`, `reg_wen&&rd!=0 → rd_wdata`, no dmem outputs |
| RUN   | `mem_re\|mem_we` | STALL_MEM | assert `dmem_req/we/addr/wdata/wmask` (registers, stable); hold `pc` |
| STALL_MEM | `!dmem_ack` | STALL_MEM | hold all dmem outputs & control (pc frozen) |
| STALL_MEM | `dmem_ack && !dmem_err && load` | RUN | commit: `rd <= load_resize(dmem_rdata, addr[1:0], size, sext)`; `pc<=next_pc` |
| STALL_MEM | `dmem_ack && !dmem_err && store` | RUN | nothing to write; `pc<=next_pc` (R5: err does not matter for store commit) |
| STALL_MEM | `dmem_ack && dmem_err && load` | RUN | **no register writeback** (R5/O3); `pc<=next_pc`; sticky err bit is set at the MMIO by the mgr's err event |

### Transition table (encodings)

| State | Encoding |
|-------|----------|
| RUN | 1'b0 (reset) |
| STALL_MEM | 1'b1 |

## 6. Store lane rotation / load resize (sub-word)

Both are **core-side** so the cache and AXI `wstrb` see plain byte lanes:

```
// store (core → cache): rotate into byte lane
dmem_wdata = rs2_val << (8 * dmem_addr[1:0])
dmem_wmask = (st_size==byte) ? 4'b0001 : (st_size==half) ? 4'b0011 : 4'b1111) << (8 * dmem_addr[1:0])
// (SH requires addr[1:0]==00 or 10 — natural alignment, per RV32I)

// load (cache → core): extract lane + extend
byte  = dmem_rdata[8*addr[1:0] +: 8]
half  = dmem_rdata[16*addr[1]   +: 16]
res   = word                                   (LW)
      = {{24{byte[7]}},  byte}                 (LB)
      = {{16{half[15]}}, half}                 (LH)
      = {24'b0, byte} / {16'b0, half}          (LBU/LHU)
```

Misaligned accesses are not decoded specially (no exception support in scope); programs are
naturally aligned.

## 7. Reset values

| Register | Reset value |
|----------|-------------|
| `pc` | `RESET_PC` = 0x0000_0000 |
| core FSM | RUN |
| reg_file | (contents X on FPGA/ASIC are acceptable; TB never reads uninit regs — all demo programs write before read) |
| dmem outputs | 0 |

## 8. RTL translation notes

- `always_ff @(posedge clk or negedge rst_n)` for pc/core-fsm/dmem-output regs; `always_comb` for decode.
- The I-SRAM is **asynchronous read** (doc 08) — `imem_rdata` is valid in the same cycle as `imem_addr`,
  which is what makes non-memory instructions truly single-cycle.
- Instruction fetch never touches AXI or coherence (FR-5.1) — a completely private path.
