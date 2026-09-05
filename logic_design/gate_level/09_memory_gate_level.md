# Gate-Level Circuit: Memory Subsystem

Source: `08_memory_subsystem.md` §8.1–§8.5  
Logisim sub-circuit names: **`SRAMRegArray`**, **`ISRAM`**, **`SharedSRAM`**

All memories are register arrays — no macros. The generic primitive `SRAMRegArray` is instantiated by both `ISRAM` and `SharedSRAM` with different parameters.

---

## 1. Sub-circuit: `SRAMRegArray` — Generic Parameterized Register Array

### 1.1 Parameters (set per instance in Logisim via sub-circuit attributes or constants)

| Parameter | ISRAM value | SharedSRAM value |
|-----------|-------------|-----------------|
| DEPTH | 256 | 1024 |
| WIDTH | 32 | 32 |
| ASYNC_READ | 1 (async) | 0 (sync, 1-cycle latency) |
| ADDR_BITS | 8 (log2 256) | 10 (log2 1024) |

### 1.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock (tunnel) |
| `WE` | In | 1 | Write enable |
| `WADDR` | In | 10 | Write address (upper bits unused for smaller depths) |
| `WDATA` | In | 32 | Write data |
| `WMASK` | In | 4 | Byte-write enables |
| `RADDR` | In | 10 | Read address |
| `RDATA` | Out | 32 | Read data |

### 1.3 Write logic — synchronous, byte-masked

```
The memory array is stored in Logisim using a RAM component with byte-enable support,
OR as a register array in simulation mode.

Logisim recommended component: Memory > RAM
  Data bits:      32
  Address bits:   8 (ISRAM) or 10 (SharedSRAM)
  Triggered by:   Rising edge (synchronous write)
  Separate load:  No
  Byte-enables:   Yes (4 × 1-bit enables, one per byte)

RAM component ports:
  A[9:0]   = WADDR (write address) during write; RADDR during read
  D[31:0]  = WDATA
  sel      = WE
  be[3:0]  = WMASK    (byte enables)
  clk      = CLK
  out[31:0]= read output

Note: Logisim's RAM supports combined read/write with a single address port.
For the shared SRAM (AXI slave with separate read/write addresses), we need
separate addressing. Use two separate address MUXes gated by active operation.
See §1.5 below.
```

### 1.4 Read logic — ASYNC_READ = 1 (for ISRAM)

```
For I-SRAM, read must be combinational (same-cycle fetch for single-cycle core).

Logisim: Use Memory > ROM (read-only) for the instruction memory.
  - ROM is inherently asynchronous read in Logisim (output = contents[address] combinationally).
  - Data bits: 32, Address bits: 8
  - Contents loaded via Logisim's "Edit Contents" or $readmemh equivalent via file load.
  - Address input: IMEM_ADDR[9:2] (word-addressed, 8 bits)
  - Output: IMEM_RDATA[31:0]

For simulation with writable init (TB writes program):
  Use RAM with async-read mode:
    Logisim RAM has a "synchronous read" checkbox — uncheck it for async behavior.
    This maps to ASYNC_READ=1.
```

### 1.5 Read logic — ASYNC_READ = 0 (for SharedSRAM)

```
For shared SRAM, read has 1-cycle latency (sync read).
The AXI slave FSM (§3 below) issues the read address on cycle N and reads
the data on cycle N+1, which matches this latency exactly.

Logisim: RAM with synchronous read (check "synchronous read" in settings).
  The Q output is the registered read result, valid one cycle after address.
```

### 1.6 Byte-masked write — gate-level detail

```
Since Logisim's RAM supports byte-enables directly, the implementation is:

  RAM.be[0] = WE AND WMASK[0]   (byte 0 enable)
  RAM.be[1] = WE AND WMASK[1]
  RAM.be[2] = WE AND WMASK[2]
  RAM.be[3] = WE AND WMASK[3]

  4× AND gate (2-in, 1-bit each):
    Input 0: WE (same for all 4)
    Input 1: WMASK[b]
    Output: RAM.be[b]

  WMASK Splitter: fan-out WMASK[3:0] into 4 individual bits → 4 AND gates above.
```

---

## 2. Sub-circuit: `ISRAM` — Private Instruction SRAM (×2, one per core)

### 2.1 Purpose

256 × 32-bit register array, asynchronous read. Provides instruction words to the core combinationally (same cycle as address), keeping the single-cycle core property intact.

### 2.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `IMEM_ADDR` | In | 32 | Full byte address from core |
| `IMEM_RDATA` | Out | 32 | Instruction word (combinational) |
| `INIT_WE` | In | 1 | TB init write enable (not used in RTL runtime) |
| `INIT_ADDR` | In | 8 | TB init write address |
| `INIT_DATA` | In | 32 | TB init write data |

### 2.3 Address extraction

```
Instruction words are 32-bit aligned. Word index = addr[9:2] (8 bits for 256 words).

Splitter on IMEM_ADDR[31:0]:
  bits [1:0]  → discard (byte lane, always 00 for aligned fetch)
  bits [9:2]  → WORD_ADDR[7:0] → RAM.A[7:0]
  bits [31:10] → upper bits (should always be 0 in legal use; ignored)
```

### 2.4 Logisim layout

```
Component: Memory > RAM
  Data bits:    32
  Address bits: 8
  Synchronous read: NO  (async read = same-cycle output)
  Byte-enables: No (instruction fetch is full-word only)

  A[7:0]    = WORD_ADDR[7:0]   (from IMEM_ADDR splitter)
  D[31:0]   = INIT_DATA        (init port, tied to 0 in normal use)
  sel       = INIT_WE
  out[31:0] = IMEM_RDATA

Runtime: INIT_WE = 0 → RAM is read-only during execution.
  In Logisim simulation: load the program via "Edit Contents" before running.
```

### 2.5 ASCII Block Diagram (ISRAM)

```
IMEM_ADDR[31:0]
    │
    └─ Splitter ──── [9:2] (8b) ──────────────────────► RAM.A[7:0]
                   (bits [1:0] discarded)               │
                                                        │ (async read)
INIT_WE   ──────────────────────────────────────────── ► RAM.sel
INIT_ADDR ──────────────────────────────────────────── ► RAM.A (init path, shared)
INIT_DATA ──────────────────────────────────────────── ► RAM.D[31:0]
CLK ─────────────────────────────────────────────────── ► RAM.clk (for write path only)

RAM.out[31:0] ──────────────────────────────────────── ► IMEM_RDATA[31:0]
```

---

## 3. Sub-circuit: `SharedSRAM` — Shared Data SRAM AXI4-Lite Slave

### 3.1 Purpose

1024 × 32-bit synchronous RAM with a complete AXI4-Lite slave interface. One read port and one write port, both AXI-addressed. Responds OKAY to all accesses within range. 1-cycle read latency absorbed by the AXI_R → FILL sequence in the D-cache manager.

### 3.2 Pin List (AXI4-Lite slave)

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `CLK` | In | 1 | Clock |
| `RST_N` | In | 1 | Async reset |
| `S_AWVALID` | In | 1 | AW valid |
| `S_AWADDR` | In | 32 | AW address |
| `S_WVALID` | In | 1 | W valid |
| `S_WDATA` | In | 32 | W data |
| `S_WSTRB` | In | 4 | W byte enables |
| `S_BREADY` | In | 1 | B ready |
| `S_ARVALID` | In | 1 | AR valid |
| `S_ARADDR` | In | 32 | AR address |
| `S_RREADY` | In | 1 | R ready |
| `S_AWREADY` | Out | 1 | AW ready |
| `S_WREADY` | Out | 1 | W ready |
| `S_BVALID` | Out | 1 | B valid |
| `S_BRESP` | Out | 2 | B response (always OKAY=2'b00) |
| `S_ARREADY` | Out | 1 | AR ready |
| `S_RVALID` | Out | 1 | R valid |
| `S_RDATA` | Out | 32 | R data |
| `S_RRESP` | Out | 2 | R response (always OKAY=2'b00) |

### 3.3 AXI slave FSM

The shared SRAM uses the standard 1-to-3-cycle responder template (doc 07 §7.5). Two independent paths: write and read.

#### Write path state machine (2-bit, same structure as DECERRSlave write path)

```
States: W_IDLE(00), W_GOTAW(01), W_GOTW(10), W_RESP(11)
  (identical FSM to DECERRSlave write path — see doc 08 gate_level)
  Difference: on completing both AW+W, perform the RAM write, then issue BRESP=OKAY.

State register (2b, CLR=NOT(RST_N)):
  Next-state logic: identical to DECERRSlave §2.4

Internal registers to hold AW/W data until both arrive:
  AW_ADDR_REG (32b, EN = AW accepted): captures S_AWADDR
  W_DATA_REG  (32b, EN = W accepted):  captures S_WDATA
  W_STRB_REG  (4b,  EN = W accepted):  captures S_WSTRB

  AW accepted = (W_STATE == W_IDLE AND S_AWVALID AND NOT(S_WVALID))
              | (W_STATE == W_GOTW AND S_AWVALID)
  W  accepted = (W_STATE == W_IDLE AND S_WVALID AND NOT(S_AWVALID))
              | (W_STATE == W_GOTAW AND S_WVALID)
              | (W_STATE == W_IDLE AND S_AWVALID AND S_WVALID)  ← simultaneous
```

#### Write trigger and RAM write

```
When both AW and W have been captured (entering W_RESP state), perform the write:
  RAM_WE    = transitioning into W_RESP state
            = NS_W_RESP AND NOT(IN_W_RESP)    ← rising edge of W_RESP
  RAM_WADDR = AW_ADDR_REG[11:2]   (word index, 10 bits)
  RAM_WDATA = W_DATA_REG[31:0]
  RAM_WMASK = W_STRB_REG[3:0]

  RAM_WE is a 1-cycle pulse (edge detection using DFF):
    DFF_PREV_RESP: D = IN_W_RESP, Q = PREV_RESP
    RAM_WE = IN_W_RESP AND NOT(PREV_RESP)   ← 1 cycle pulse on entry to W_RESP

  Logisim:
    D Flip-Flop (1b): D=IN_W_RESP, CLR=NOT(RST_N), Q=PREV_RESP
    NOT: PREV_RESP → N_PREV
    AND (2-in): IN_W_RESP, N_PREV → RAM_WE (1-cycle write pulse)
```

#### Write path outputs

```
S_AWREADY = IN_W_IDLE AND NOT(S_WVALID) | IN_W_GOTW    (same as DECERRSlave)
S_WREADY  = IN_W_IDLE AND NOT(S_AWVALID) | IN_W_GOTAW
S_BVALID  = IN_W_RESP
S_BRESP   = Constant(2'b00, 2 bits)   ← OKAY (not DECERR)
```

#### Read path state machine (1-bit)

```
States: R_IDLE(0), R_RESP(1)
  (identical to DECERRSlave read path)

State register (1b, CLR=NOT(RST_N)):
  NEXT_R = (IN_R_IDLE AND S_ARVALID) | (IN_R_RESP AND NOT(S_RREADY))

AR_ADDR_REG (32b): captures S_ARADDR when arvalid accepted
  EN = IN_R_IDLE AND S_ARVALID
  Register(32b, EN=above, CLR=NOT(RST_N)): D=S_ARADDR, Q=AR_ADDR_REG

RAM read address:
  RAM_RADDR = AR_ADDR_REG[11:2]   (word index, 10 bits)
  (The RAM output is valid 1 cycle after address is presented — sync read)
  Since we capture the address when entering R_RESP and the RAM gives data
  the next cycle, we hold R_RESP until the master accepts with RREADY:
    In R_RESP: rvalid=1, rdata=RAM.out (already latched from 1-cycle earlier)
    The RAM address is presented when entering R_RESP → data available next cycle.
    To handle the 1-cycle read latency correctly, insert a register on rdata:
      RDATA_REG (32b): D=RAM.out, EN=1 (always sample), CLR=0
      This register captures the RAM output. Present RVALID one cycle after
      AR is accepted (= when R_STATE transitions from IDLE to RESP, the RAM
      was addressed; next cycle RDATA_REG has the word).
```

#### Read path outputs

```
S_ARREADY = IN_R_IDLE   (NOT R_STATE)
S_RVALID  = IN_R_RESP   (R_STATE)
S_RDATA   = RDATA_REG[31:0]
S_RRESP   = Constant(2'b00, 2 bits)   ← OKAY
```

### 3.4 RAM component (core storage)

```
Component: Memory > RAM
  Data bits:    32
  Address bits: 10   (1024 words)
  Synchronous read: YES  (ASYNC_READ = 0)
  Byte-enables: YES  (4 × 1-bit)

Connections:
  A[9:0]    = MUX(RAM_WE, RAM_RADDR, RAM_WADDR)
              When writing: use write address; when reading: use read address.
              Since only one operation happens per AXI transaction (arbiter),
              MUX (10b, 1-sel): sel=RAM_WE, In0=RAM_RADDR, In1=RAM_WADDR → RAM.A

  D[31:0]   = W_DATA_REG
  sel       = RAM_WE
  be[3:0]   = byte-enable gates (WE AND WMASK[b], 4× AND gate as in §1.6)
  clk       = CLK
  out[31:0] = RAM_OUT → RDATA_REG.D
```

### 3.5 ASCII Block Diagram (SharedSRAM)

```
                    ┌──────────────────────────────────────────────────────┐
                    │                  SharedSRAM                          │
S_AWVALID ─────────►│                                                      │
S_AWADDR  ─────────►│  Write Path FSM (2b)    AW_ADDR_REG(32b)             │
S_WVALID  ─────────►│  W_IDLE→GOTAW/GOTW      W_DATA_REG(32b)             │
S_WDATA   ─────────►│  →W_RESP                W_STRB_REG(4b)              │
S_WSTRB   ─────────►│                          │                           │
S_BREADY  ─────────►│  RAM_WE pulse ──────────►│                           │
                    │  S_AWREADY, S_WREADY ◄───┤                           │
                    │  S_BVALID, S_BRESP=00 ◄──┘                           │
                    │                                                      │
S_ARVALID ─────────►│  Read Path FSM (1b)     AR_ADDR_REG(32b)             │
S_ARADDR  ─────────►│  R_IDLE→R_RESP          RDATA_REG(32b)              │
S_RREADY  ─────────►│                          │                           │
                    │  S_ARREADY ◄─────────────┤                           │
                    │  S_RVALID ◄──────────────┤                           │
                    │  S_RDATA ◄───────────────┘                           │
                    │  S_RRESP=00                                          │
                    │                                                      │
                    │  ┌────────────────────────────────────────────────┐  │
                    │  │  RAM (1024×32b, sync read, byte-enable)        │  │
                    │  │  A=MUX(WE,RADDR,WADDR), D=WDATA, be=WMASK     │  │
                    │  │  out → RDATA_REG                               │  │
                    │  └────────────────────────────────────────────────┘  │
CLK ───────────────►│                                                      │
RST_N → NOT → CLR ─►│                                                      │
                    └──────────────────────────────────────────────────────┘
```

---

## 4. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| ISRAM RAM | Data bits | 32 |
| ISRAM RAM | Address bits | 8 |
| ISRAM RAM | Synchronous read | No (async) |
| ISRAM RAM | Byte-enables | No (full word) |
| SharedSRAM RAM | Data bits | 32 |
| SharedSRAM RAM | Address bits | 10 |
| SharedSRAM RAM | Synchronous read | Yes |
| SharedSRAM RAM | Byte-enables | Yes (4 enables) |
| Write FSM state reg | Data bits | 2; CLR async |
| Read FSM state reg | Data bits | 1; CLR async |
| AW/W data registers | Data bits | 32/32/4; Enable yes |
| AR_ADDR_REG | Data bits | 32; Enable yes |
| RDATA_REG | Data bits | 32; Enable always |
| RAM_WE edge-detect DFF | Data bits | 1 |
| Address splitters | Extract [11:2] (10 bits) from 32b address |
| Address MUX (RAM.A) | Data bits | 10; Select bits 1 |
| Byte-enable ANDs | Data bits | 1; Inputs 2 (×4) |
| BRESP / RRESP constants | Value | 0 (OKAY); Data bits 2 |
