# Gate-Level Circuit: AXI4-Lite Round-Robin Arbiter

Source: `06_arbiter_logic.md` §6.1–§6.6  
Logisim sub-circuit names: **`AXIArbiter`**, **`ArbFSM`**, **`GrantLogic`**, **`AXIMux`**

Two D-cache manager masters (M0, M1) share one downstream AXI4-Lite slave port.  
Grant is held for the entire transaction. Preference pointer flips after every completed grant.

---

## 1. State Encoding (2-bit)

| State | Encoding | Role |
|-------|----------|------|
| ARB_IDLE | 2'b00 | No active grant; evaluate requests |
| ARB_G0 | 2'b01 | Master 0 granted; hold until done |
| ARB_G1 | 2'b10 | Master 1 granted; hold until done |

---

## 2. Pin List

### Inputs

| Pin | Bits | Description |
|-----|------|-------------|
| `CLK` | 1 | Clock (tunnel) |
| `RST_N` | 1 | Async reset (tunnel) |
| `REQ0` | 1 | Master 0 bus request (held) |
| `REQ1` | 1 | Master 1 bus request (held) |
| `M0_AWVALID` | 1 | Master 0 AW valid |
| `M0_AWADDR` | 32 | Master 0 AW address |
| `M0_WVALID` | 1 | Master 0 W valid |
| `M0_WDATA` | 32 | Master 0 W data |
| `M0_WSTRB` | 4 | Master 0 W strobe |
| `M0_BREADY` | 1 | Master 0 B ready |
| `M0_ARVALID` | 1 | Master 0 AR valid |
| `M0_ARADDR` | 32 | Master 0 AR address |
| `M0_RREADY` | 1 | Master 0 R ready |
| `M1_AWVALID` | 1 | Master 1 AW valid |
| `M1_AWADDR` | 32 | Master 1 AW address |
| `M1_WVALID` | 1 | Master 1 W valid |
| `M1_WDATA` | 32 | Master 1 W data |
| `M1_WSTRB` | 4 | Master 1 W strobe |
| `M1_BREADY` | 1 | Master 1 B ready |
| `M1_ARVALID` | 1 | Master 1 AR valid |
| `M1_ARADDR` | 32 | Master 1 AR address |
| `M1_RREADY` | 1 | Master 1 R ready |
| `S_AWREADY` | 1 | Shared slave AW ready |
| `S_WREADY` | 1 | Shared slave W ready |
| `S_BVALID` | 1 | Shared slave B valid |
| `S_BRESP` | 2 | Shared slave B response |
| `S_ARREADY` | 1 | Shared slave AR ready |
| `S_RVALID` | 1 | Shared slave R valid |
| `S_RDATA` | 32 | Shared slave R data |
| `S_RRESP` | 2 | Shared slave R response |

### Outputs

| Pin | Bits | Description |
|-----|------|-------------|
| `GRANT0` | 1 | Grant to master 0 |
| `GRANT1` | 1 | Grant to master 1 |
| `S_AWVALID` | 1 | Shared slave AW valid |
| `S_AWADDR` | 32 | Shared slave AW address |
| `S_WVALID` | 1 | Shared slave W valid |
| `S_WDATA` | 32 | Shared slave W data |
| `S_WSTRB` | 4 | Shared slave W strobe |
| `S_BREADY` | 1 | Shared slave B ready |
| `S_ARVALID` | 1 | Shared slave AR valid |
| `S_ARADDR` | 32 | Shared slave AR address |
| `S_RREADY` | 1 | Shared slave R ready |
| `M0_AWREADY` | 1 | AW ready back to master 0 |
| `M0_WREADY` | 1 | W ready back to master 0 |
| `M0_BVALID` | 1 | B valid to master 0 |
| `M0_BRESP` | 2 | B response to master 0 |
| `M0_ARREADY` | 1 | AR ready to master 0 |
| `M0_RVALID` | 1 | R valid to master 0 |
| `M0_RDATA` | 32 | R data to master 0 |
| `M0_RRESP` | 2 | R response to master 0 |
| `M1_AWREADY` | 1 | AW ready back to master 1 |
| `M1_WREADY` | 1 | W ready back to master 1 |
| `M1_BVALID` | 1 | B valid to master 1 |
| `M1_BRESP` | 2 | B response to master 1 |
| `M1_ARREADY` | 1 | AR ready to master 1 |
| `M1_RVALID` | 1 | R valid to master 1 |
| `M1_RDATA` | 32 | R data to master 1 |
| `M1_RRESP` | 2 | R response to master 1 |

---

## 3. Sub-circuit: `GrantLogic` — Arbitration Truth Table

### 3.1 Purpose

Pure combinational. Computes `GRANT0` and `GRANT1` from `REQ0`, `REQ1`, and the `PREF` register (preference pointer). Implements the truth table from §6.2 exactly.

### 3.2 Equations

```
GRANT0 = REQ0 AND (NOT(REQ1) OR (PREF == 0))
GRANT1 = REQ1 AND (NOT(REQ0) OR (PREF == 1))

Since PREF is 1-bit (0=prefer master 0, 1=prefer master 1):
  PREF == 0  =  NOT(PREF)
  PREF == 1  =  PREF

Expanded:
  GRANT0 = REQ0 AND (NOT(REQ1) OR NOT(PREF))
  GRANT1 = REQ1 AND (NOT(REQ0) OR PREF)
```

### 3.3 Gate-level implementation

```
NOT gate: REQ1  → N_REQ1
NOT gate: REQ0  → N_REQ0
NOT gate: PREF  → N_PREF    (PREF from ArbFSM register Q)

GRANT0:
  OR  gate (2-in): N_REQ1, N_PREF   → COND0
  AND gate (2-in): REQ0, COND0      → GRANT0

GRANT1:
  OR  gate (2-in): N_REQ0, PREF     → COND1
  AND gate (2-in): REQ1, COND1      → GRANT1

Logisim components:
  3× NOT gate (1-bit)
  2× OR  gate (2-in, 1-bit)
  2× AND gate (2-in, 1-bit)
```

### 3.4 Invariant check (for Logisim probe)

```
BOTH_GRANT = GRANT0 AND GRANT1  → should always be 0

Logisim: AND gate (2-in): GRANT0, GRANT1 → BOTH_GRANT
         Place a Probe on BOTH_GRANT labeled "ASSERT:!both_grant"
         (Non-zero value during simulation flags a bug)
```

---

## 4. Sub-circuit: `ArbFSM` — 3-State Arbiter FSM + PREF Register

### 4.1 State register (2-bit)

```
Component: Memory > Register, 2 bits
  CLK: CLK tunnel
  CLR: NOT(RST_N)   → reset to 2'b00 = ARB_IDLE ✓
  EN:  1
  D:   NEXT_STATE[1:0]
  Q:   CURR_STATE[1:0]
```

### 4.2 PREF register (1-bit)

```
Component: Memory > Register, 1 bit
  CLK: CLK tunnel
  CLR: NOT(RST_N)   → reset to 0 (prefer master 0 at boot) ✓
  EN:  PREF_UPDATE  (see below)
  D:   NEXT_PREF
  Q:   PREF
```

### 4.3 State comparators

```
3× Comparator (2-bit):
  IN_ARB_IDLE = (CURR_STATE == 2'b00)
  IN_ARB_G0   = (CURR_STATE == 2'b01)
  IN_ARB_G1   = (CURR_STATE == 2'b10)
```

### 4.4 Transaction-done signals

```
A transaction is done when the final handshake of the granted master completes:
  For a write: B channel: bvalid AND bready
  For a read:  R channel: rvalid AND rready

Since the arbiter sees the *shared slave* port, "done" for master N means
the last handshake on the slave side while master N is granted:

  DONE0 = (IN_ARB_G0) AND ((S_BVALID AND M0_BREADY) OR (S_RVALID AND M0_RREADY))
  DONE1 = (IN_ARB_G1) AND ((S_BVALID AND M1_BREADY) OR (S_RVALID AND M1_RREADY))

Logisim for DONE0:
  AND gate (2-in): S_BVALID, M0_BREADY → BHANDSHAKE0
  AND gate (2-in): S_RVALID, M0_RREADY → RHANDSHAKE0
  OR  gate (2-in): BHANDSHAKE0, RHANDSHAKE0 → LAST_HS0
  AND gate (2-in): IN_ARB_G0, LAST_HS0 → DONE0

Same structure for DONE1.
```

### 4.5 Next-state logic

```
NS_ARB_IDLE =
    IN_ARB_G0 AND DONE0
  | IN_ARB_G1 AND DONE1
  | IN_ARB_IDLE AND NOT(GRANT0) AND NOT(GRANT1)  ← no requests

NS_ARB_G0 =
    IN_ARB_IDLE AND GRANT0
  | IN_ARB_G0 AND NOT(DONE0)                      ← hold

NS_ARB_G1 =
    IN_ARB_IDLE AND GRANT1 AND NOT(GRANT0)         ← GRANT0 has priority if simultaneous
  | IN_ARB_G1 AND NOT(DONE1)

Note: IN_ARB_IDLE AND GRANT0 always wins over GRANT1 in the same cycle
because GrantLogic ensures mutual exclusion.

Bit derivation:
  NEXT_STATE[1] = NS_ARB_G1
  NEXT_STATE[0] = NS_ARB_G0

Logisim:
  NS_ARB_G0: OR gate inputs:
    (IN_ARB_IDLE AND GRANT0)
    (IN_ARB_G0 AND NOT(DONE0))

  NS_ARB_G1: OR gate inputs:
    (IN_ARB_IDLE AND NOT(GRANT0) AND GRANT1)
    (IN_ARB_G1 AND NOT(DONE1))

  NEXT_STATE[1] = NS_ARB_G1 (direct wire)
  NEXT_STATE[0] = NS_ARB_G0 (direct wire)
```

### 4.6 PREF register update

```
PREF flips when a transaction completes (master returns bus to IDLE):
  PREF_UPDATE = DONE0 OR DONE1

  NEXT_PREF:
    When DONE0 (master 0 finished): pref ← 1  (next time prefer master 1)
    When DONE1 (master 1 finished): pref ← 0  (next time prefer master 0)
    (they cannot both be done simultaneously — only one is ever granted)

  NEXT_PREF = DONE1   (if done1 → set pref=0 i.e., prefer core0 next; if done0 → set pref=1)

  Wait — check: after master 0 done, pref should flip to 1 to favor master 1 next:
    After DONE0: NEXT_PREF = 1
    After DONE1: NEXT_PREF = 0
    So NEXT_PREF = DONE0 (set to 1 when master0 done, set to 0 otherwise/when master1 done)

  MUX (1b, 1-sel): sel=DONE0
    Input 0 (DONE1 path): 1'b0   (master 1 done → pref back to 0)
    Input 1 (DONE0 path): 1'b1   (master 0 done → pref flips to 1)
  Output: NEXT_PREF → PREF register D

  Simpler: NEXT_PREF = DONE0   (when DONE0=1 → 1; when DONE1=1 → 0; only one can be 1)

  PREF Register:
    D  = DONE0   (1 when master 0 just finished, else 0 on DONE1)
    EN = PREF_UPDATE = DONE0 OR DONE1
    CLR = NOT(RST_N) → 0

  Logisim:
    OR  gate (2-in): DONE0, DONE1 → PREF_UPDATE → PREF_REG.EN
    Wire DONE0 directly to PREF_REG.D
```

---

## 5. Sub-circuit: `AXIMux` — Full Bidirectional AXI4-Lite Mux

### 5.1 Purpose

Routes all 5 AXI4-Lite channels in both directions between 2 masters and 1 slave, controlled by `GRANT0` and `GRANT1`.

### 5.2 Request direction (Master → Slave)

Each signal to the slave is selected from the granted master's corresponding signal.

```
Rule: Use GRANT0 as a 1-bit selector for each signal.
  When GRANT0=1: slave sees master 0's signals
  When GRANT1=1 (GRANT0=0): slave sees master 1's signals
  When neither granted: slave sees 0 (idle)

For 1-bit signals:
  S_sig = (GRANT0 AND M0_sig) OR (GRANT1 AND M1_sig)
  Logisim: 2× AND gates + 1× OR gate

For multi-bit signals (N bits):
  Use N-bit AND gates (IN0=M0_sig, IN1=GRANT0 replicated N times)
  and N-bit OR gate to combine:
  Practical Logisim: MUX (N-bit, 1-bit select):
    Input 0: M1_sig  (when GRANT0=0)
    Input 1: M0_sig  (when GRANT0=1)
    Select:  GRANT0
    Output:  S_sig

  Note: when neither is granted, GRANT0=0 → MUX selects M1_sig.
  M1_sig will be 0 in AXI because the cache mgr only drives valid signals
  when it has a grant (bus_req → MISS_READ state asserts signals only after grant).
  So the output is safely 0. This is correct AXI behavior.
```

#### AW channel (master → slave)

```
MUX (1-bit, 1-sel): S_AWVALID  sel=GRANT0: In0=M1_AWVALID, In1=M0_AWVALID
MUX (32-bit, 1-sel): S_AWADDR  sel=GRANT0: In0=M1_AWADDR,  In1=M0_AWADDR
```

#### W channel (master → slave)

```
MUX (1-bit):  S_WVALID  sel=GRANT0
MUX (32-bit): S_WDATA   sel=GRANT0
MUX (4-bit):  S_WSTRB   sel=GRANT0
```

#### B channel: slave → master (BREADY goes master→slave; BVALID/BRESP go slave→master)

```
Slave-to-master direction:
  M0_BVALID = GRANT0 AND S_BVALID
  M1_BVALID = GRANT1 AND S_BVALID
  M0_BRESP  = S_BRESP when GRANT0 (else don't care — cache mgr ignores if !grant)
  M1_BRESP  = S_BRESP when GRANT1

  Logisim for BVALID:
    AND gate (2-in): GRANT0, S_BVALID → M0_BVALID
    AND gate (2-in): GRANT1, S_BVALID → M1_BVALID

  For BRESP (2-bit):
    AND gate (2-bit): S_BRESP AND {2{GRANT0}} → M0_BRESP
    AND gate (2-bit): S_BRESP AND {2{GRANT1}} → M1_BRESP
    Logisim: 2-bit AND gate, Input0=S_BRESP, Input1=GRANT0 (1-bit, Logisim fans it)

Master-to-slave direction (BREADY):
  S_BREADY = (GRANT0 AND M0_BREADY) OR (GRANT1 AND M1_BREADY)
  AND (2-in): GRANT0, M0_BREADY → B0
  AND (2-in): GRANT1, M1_BREADY → B1
  OR  (2-in): B0, B1 → S_BREADY
```

#### AR channel (master → slave)

```
MUX (1-bit):  S_ARVALID  sel=GRANT0
MUX (32-bit): S_ARADDR   sel=GRANT0
```

#### AR ready (slave → master)

```
M0_ARREADY = GRANT0 AND S_ARREADY
M1_ARREADY = GRANT1 AND S_ARREADY
  2× AND gate (2-in, 1-bit)
```

#### R channel (slave → master)

```
M0_RVALID = GRANT0 AND S_RVALID
M1_RVALID = GRANT1 AND S_RVALID

M0_RDATA = S_RDATA AND {32{GRANT0}}  → 32-bit AND or MUX
M1_RDATA = S_RDATA AND {32{GRANT1}}

Logisim for RDATA:
  AND gate (32-bit, 2-in): Input0=S_RDATA, Input1=GRANT0 → M0_RDATA
  AND gate (32-bit, 2-in): Input0=S_RDATA, Input1=GRANT1 → M1_RDATA
  (Logisim allows 1-bit Input1 to AND with 32-bit Input0 when the gate is set to 32-bit
   and the 1-bit wire is automatically replicated — set gate Data Bits = 32)

M0_RRESP = S_RRESP AND {2{GRANT0}}   (2-bit AND)
M1_RRESP = S_RRESP AND {2{GRANT1}}

RREADY back to slave:
  S_RREADY = (GRANT0 AND M0_RREADY) OR (GRANT1 AND M1_RREADY)
  Same OR-AND structure as BREADY.
```

#### AW ready (slave → master)

```
M0_AWREADY = GRANT0 AND S_AWREADY
M1_AWREADY = GRANT1 AND S_AWREADY
```

#### W ready (slave → master)

```
M0_WREADY = GRANT0 AND S_WREADY
M1_WREADY = GRANT1 AND S_WREADY
```

---

## 6. Top-Level `AXIArbiter` Integration

```
AXIArbiter instantiates:
  1× GrantLogic    (inputs: REQ0, REQ1, PREF from ArbFSM; outputs: GRANT0, GRANT1)
  1× ArbFSM        (inputs: CLK, RST_N, GRANT0, GRANT1, DONE0, DONE1; outputs: PREF, CURR_STATE)
  1× AXIMux        (inputs: all M0/M1/S AXI signals + GRANT0, GRANT1; routes all channels)

Signal routing:
  PREF from ArbFSM.Q → GrantLogic.PREF
  GRANT0, GRANT1 from GrantLogic → ArbFSM (DONE computation) AND AXIMux (routing)
  DONE0, DONE1 computed in ArbFSM from GRANT0/1 + slave handshakes
```

---

## 7. Full ASCII Block Diagram

```
                         ┌──────────────────────────────────────────────┐
                         │                AXIArbiter                    │
                         │                                              │
REQ0, REQ1 ─────────────►│  ┌──────────────────────┐                   │
                         │  │    GrantLogic         │                   │
PREF (from ArbFSM) ─────►│  │ GRANT0 = REQ0 AND    │                   │
                         │  │   (N_REQ1 OR N_PREF)  │                   │
                         │  │ GRANT1 = REQ1 AND    │                   │
                         │  │   (N_REQ0 OR PREF)   │                   │
                         │  └───┬──────────┬───────┘                   │
                         │      │GRANT0    │GRANT1                      │
                         │      │          │                            │
                         │  ┌───▼──────────▼────────┐                  │
                         │  │      ArbFSM            │                  │
CLK ────────────────────►│  │  State Reg(2b)         │                  │
RST_N → NOT → CLR ──────►│  │  IN_IDLE/G0/G1         │                  │
                         │  │  DONE0, DONE1           │                  │
                         │  │  PREF Reg(1b)           │◄── S_BVALID     │
                         │  │  PREF_UPDATE            │◄── S_RVALID     │
                         │  └───────────┬─────────────┘    M0/1_BREADY  │
                         │              │PREF               M0/1_RREADY  │
                         │              └──────────────────────────────► │
                         │                             GrantLogic input  │
                         │                                              │
M0 all AXI signals ─────►│  ┌──────────────────────────────────────────►│
M1 all AXI signals ─────►│  │       AXIMux                              │
S  all AXI signals ─────►│  │  Request MUXes (5 MUXes, 1-sel=GRANT0)    │──► S_AWVALID/ADDR
                         │  │  Response AND gates (GRANT0/1 gating)      │──► S_WVALID/DATA/STRB
                         │  │  BREADY/RREADY OR-AND                      │──► S_BREADY
                         │  └──────────────────────────────────────────► │──► S_ARVALID/ADDR
                         │                                               │──► S_RREADY
                         │  M0/1 response outputs from slave:            │
                         │  M0_BVALID/BRESP/AWREADY/WREADY/ARREADY       │◄── S channel signals
                         │  M0_RVALID/RDATA/RRESP (GRANT0-gated)         │
                         │  M1 same (GRANT1-gated)                       │
                         └──────────────────────────────────────────────┘
```

---

## 8. Logisim Component Settings Summary

| Sub-circuit | Component | Setting | Value |
|-------------|-----------|---------|-------|
| GrantLogic | NOT gates (×3) | Data bits | 1 |
| GrantLogic | OR gates (×2) | Data bits | 1; Inputs 2 |
| GrantLogic | AND gates (×2) | Data bits | 1; Inputs 2 |
| GrantLogic | AND (invariant) | Data bits | 1; Inputs 2 |
| ArbFSM — State Reg | Data bits | 2; CLR async; EN always |
| ArbFSM — PREF Reg | Data bits | 1; CLR async; EN=PREF_UPDATE |
| ArbFSM — State comp | Data bits | 2 (×3) |
| ArbFSM — DONE ANDs | Data bits | 1; Inputs 2 |
| ArbFSM — DONE ORs | Data bits | 1; Inputs 2 |
| AXIMux — Request MUXes (1b) | Data bits | 1; Select bits 1 |
| AXIMux — Request MUXes (32b) | Data bits | 32; Select bits 1 |
| AXIMux — Request MUXes (4b) | Data bits | 4; Select bits 1 |
| AXIMux — BVALID/RVALID ANDs | Data bits | 1; Inputs 2 |
| AXIMux — BRESP/RRESP ANDs | Data bits | 2; Inputs 2 |
| AXIMux — RDATA ANDs | Data bits | 32; Inputs 2 |
| AXIMux — BREADY/RREADY | AND×2 + OR×1 | Data bits 1 |
| AXIMux — AWREADY/WREADY/ARREADY | AND×2 per signal | Data bits 1 |

---

## 9. Layout Notes for Logisim

- Place `GrantLogic` top-left (small, 7 gates total).
- Place `ArbFSM` center (state register, PREF register, comparators, DONE logic).
- Place `AXIMux` as the largest block on the right side — it has 17 AXI signals × 2 masters.
- Use Tunnels: `GRANT0`, `GRANT1`, `PREF`, `DONE0`, `DONE1`, `IN_ARB_G0`, `IN_ARB_G1` to connect the three sub-circuits without long crossing wires.
- Group AXI signals into labeled buses using Splitter components at the input and output pins of `AXIMux`.
- The BOTH_GRANT invariant probe should sit at the top of `GrantLogic` as a visual assertion.
- Reset value check: at reset, `CURR_STATE=00=ARB_IDLE`, `PREF=0` (core 0 preferred) — verify by running simulation with RST_N=0 for 1 cycle.
