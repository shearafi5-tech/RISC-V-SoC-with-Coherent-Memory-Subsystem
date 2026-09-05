# Gate-Level Circuit: Coherence Controller FSM

Source: `05_coherence_fsm.md` §5.1–§5.8  
Logisim sub-circuit names: **`CoherenceCtrl`**, **`CohMirror`**, **`DispatchLogic`**

One controller serves both cores. It tracks per-line, per-core coherence state in an 8-entry mirror, accepts write notifications, and dispatches invalidations to the remote core's cache manager over the sideband.

---

## 1. State Encoding (2-bit)

| State | Encoding | Role |
|-------|----------|------|
| COH_IDLE | 2'b00 | Wait for write_notify from either core |
| PROCESS_WRITE | 2'b01 | Update mirror[N][idx]←M; decide dispatch |
| INVALIDATE_OTHER | 2'b10 | Assert inv_valid to remote, pulse inv_fire |
| WAIT_INV_ACK | 2'b11 | Hold inv_valid until inv_ack arrives |

---

## 2. Pin List

### Inputs

| Pin | Bits | Description |
|-----|------|-------------|
| `CLK` | 1 | Clock (tunnel) |
| `RST_N` | 1 | Async reset (tunnel) |
| `WRITE_NOTIFY0` | 1 | Core 0 write-through complete (held until coh_accept) |
| `WRITE_ADDR0` | 32 | Address written by core 0 |
| `WRITE_NOTIFY1` | 1 | Core 1 write-through complete |
| `WRITE_ADDR1` | 32 | Address written by core 1 |
| `FILL_NOTIFY0` | 1 | Core 0 filled a line to S (1-cycle pulse) |
| `FILL_IDX0` | 2 | Line index of core 0 fill |
| `FILL_NOTIFY1` | 1 | Core 1 filled a line to S |
| `FILL_IDX1` | 2 | Line index of core 1 fill |
| `INV_ACK0` | 1 | Core 0 performed invalidation |
| `INV_ACK1` | 1 | Core 1 performed invalidation |
| `STATE0_I` | 8 | Actual coh_state of core 0 lines [3:0], 2 bits each (R6) |
| `VALID0_I` | 4 | Actual valid bits of core 0 lines [3:0] (R6) |
| `STATE1_I` | 8 | Actual coh_state of core 1 lines [3:0] |
| `VALID1_I` | 4 | Actual valid bits of core 1 lines [3:0] |
| `COH_ENABLE` | 1 | CONTROL bit 0; suppresses invalidation dispatch when 0 |

### Outputs

| Pin | Bits | Description |
|-----|------|-------------|
| `COH_ACCEPT0` | 1 | 1-cycle pulse: core 0 notify accepted |
| `COH_ACCEPT1` | 1 | 1-cycle pulse: core 1 notify accepted |
| `INV_VALID0` | 1 | Invalidate request to core 0 (held until inv_ack0) |
| `INV_IDX0` | 2 | Line index for core 0 invalidation |
| `INV_VALID1` | 1 | Invalidate request to core 1 |
| `INV_IDX1` | 2 | Line index for core 1 invalidation |
| `INV_FIRE` | 1 | 1-cycle pulse: invalidation dispatched (→INV_COUNT) |
| `COH_STATUS` | 16 | 8×2-bit mirror export for MMIO |

---

## 3. Sub-circuit: `CohMirror` — 8-Entry Coherence State Mirror

### 3.1 Purpose

Stores `mirror[core][line]` for 2 cores × 4 lines = 8 entries, each 2 bits.  
Updated by three events: write_notify accepted (→M), inv_ack (→I), fill_notify (→S).  
Exported as `COH_STATUS[15:0]`.

### 3.2 Structure

```
8 registers of 2 bits each (one per mirror[core][line]):
  Naming: MR_c_l where c ∈ {0,1}, l ∈ {0,1,2,3}

  MR_0_0 = mirror[0][line0]   MR_0_1 = mirror[0][line1]
  MR_0_2 = mirror[0][line2]   MR_0_3 = mirror[0][line3]
  MR_1_0 = mirror[1][line0]   MR_1_1 = mirror[1][line1]
  MR_1_2 = mirror[1][line2]   MR_1_3 = mirror[1][line3]
```

### 3.3 Update rule per entry

Three events drive writes to each mirror entry `MR_c_l`:

```
Event A — write_notify accepted from core c, written to line l:
  Signal: WRITE_NOTIFY_c AND PROC_IDX==l AND IN_PROC_WRITE
          (IN_PROC_WRITE = FSM in PROCESS_WRITE state, for core c)
  Value written: 2'b10 = M

Event B — inv_ack from core c, for line l:
  Signal: INV_ACK_c AND INV_TARGET==c AND PROC_IDX==l
          (INV_TARGET is the core being invalidated, latched at INVALIDATE_OTHER)
  Value written: 2'b00 = I

Event C — fill_notify from core c, fill_idx == l:
  Signal: FILL_NOTIFY_c AND FILL_IDX_c == l   (1-cycle pulse)
  Value written: 2'b01 = S

Priority (when simultaneous — from §5.6): write > fill (M supersedes S)
  If both Event A and Event C fire for same [c][l]: write M wins.
```

### 3.4 Logisim implementation per entry (example for MR_0_0)

```
Conditions that select a write-data value (2-bit) for this entry:

  SET_M_0_0 = (PROC_CORE==0) AND (PROC_IDX==2'b00) AND IN_PROCESS_WRITE
              ← means: core 0's notify accepted, and the written line index = 0
  SET_I_0_0 = INV_ACK0 AND (INV_TARGET==0) AND (PROC_IDX==2'b00)
              ← invalidation ack back to core 0 for line 0
  SET_S_0_0 = FILL_NOTIFY0 AND (FILL_IDX0==2'b00)
              ← core 0 filled line 0 to S

  Priority MUX for write data:
    Mux (2b, 2-sel):
      Input 0 (00): current value (hold — no write)
      Input 1 (01): 2'b01 (S)
      Input 2 (10): 2'b10 (M)  ← M overrides S when both fire
      Input 3 (11): 2'b10 (M)  ← M wins on any M-conflict
      select[1]: SET_M_0_0
      select[0]: SET_S_0_0 AND NOT(SET_M_0_0)   ← S only if no M
    Output: NEXT_MR_0_0[1:0]

    ← For I (invalidation): separate enable gates that force output to 00:
    Actually: treat SET_I as another source with value 2'b00.
    3-way priority: M > I > S > hold

    Simplified: use a 4:1 MUX with 2-bit priority:
      sel[1] = SET_M_0_0
      sel[0] = SET_I_0_0 AND NOT(SET_M_0_0)
      Input 00 (hold): MR_0_0.Q
      Input 01 (I):    2'b00
      Input 10 (M):    2'b10
      Input 11 (M):    2'b10   ← both M and I: M wins
    Add SET_S_0_0 as a third enable:
      Complete: 3 enables → use a priority encoder or 3-level MUX chain.

  Practical Logisim: 3 cascaded 2:1 MUXes (lowest priority first):
    L1 MUX (S): sel=SET_S_0_0
      In0: MR_0_0.Q (hold)
      In1: 2'b01 (S)
    L2 MUX (I): sel=SET_I_0_0
      In0: L1.out
      In1: 2'b00 (I)
    L3 MUX (M): sel=SET_M_0_0    ← M wins over everything
      In0: L2.out
      In1: 2'b10 (M)
    Output: NEXT_MR_0_0[1:0]

  Register(2b):
    D  = NEXT_MR_0_0
    EN = SET_M_0_0 OR SET_I_0_0 OR SET_S_0_0  (write on any event)
    CLR = NOT(RST_N)  → reset to 2'b00 = I ✓
    Q  = MR_0_0[1:0]

Repeat for all 8 entries (MR_0_0 through MR_1_3).
```

### 3.5 Index comparators for entry selection

```
For each of the 8 entries, the "PROC_IDX==l" and "FILL_IDX==l" checks are 2-bit comparators:

  PROC_IDX_IS[l]  = (PROC_IDX_REG == l)   for l=0..3   ← 4× Comparator(2b)
  FILL0_IDX_IS[l] = (FILL_IDX0 == l)      for l=0..3   ← 4× Comparator(2b)
  FILL1_IDX_IS[l] = (FILL_IDX1 == l)      for l=0..3

PROC_CORE_IS[c]  = (PROC_CORE_REG == c)   for c=0,1   ← 2× Comparator(1b) or simple NOT/wire
INV_TARGET_IS[c] = (INV_TARGET_REG == c)

These reusable outputs feed all 8 entry update circuits above.
```

### 3.6 COH_STATUS export

```
COH_STATUS[15:0] = {MR_1_3, MR_1_2, MR_1_1, MR_1_0,
                    MR_0_3, MR_0_2, MR_0_1, MR_0_0}

Logisim: Splitter (combine mode, 16-bit output)
  bits [1:0]  = MR_0_0.Q
  bits [3:2]  = MR_0_1.Q
  bits [5:4]  = MR_0_2.Q
  bits [7:6]  = MR_0_3.Q
  bits [9:8]  = MR_1_0.Q
  bits [11:10]= MR_1_1.Q
  bits [13:12]= MR_1_2.Q
  bits [15:14]= MR_1_3.Q
Output: COH_STATUS[15:0] → output pin
```

---

## 4. Sub-circuit: `DispatchLogic` — Remote Copy Detection

### 4.1 Purpose

Determines whether the remote core has a copy of the written line — used in PROCESS_WRITE to decide if an invalidation should be dispatched (doc 05 §5.3, R6).

### 4.2 Pin List

| Pin | Dir | Bits | Description |
|-----|-----|------|-------------|
| `PROC_CORE` | In | 1 | Which core just wrote (0 or 1) |
| `PROC_IDX` | In | 2 | Line index of the write |
| `MR_0_0..MR_1_3` | In | 2 each | All 8 mirror entries |
| `STATE0_I` | In | 8 | Actual states of core 0 lines |
| `VALID0_I` | In | 4 | Actual valid bits of core 0 |
| `STATE1_I` | In | 8 | Actual states of core 1 lines |
| `VALID1_I` | In | 4 | Actual valid bits of core 1 |
| `COH_ENABLE` | In | 1 | Global enable |
| `REMOTE_HAS_COPY` | Out | 1 | Dispatch needed |
| `OTHER_CORE` | Out | 1 | = NOT(PROC_CORE) |

### 4.3 Other-core derivation

```
OTHER_CORE = NOT(PROC_CORE)
NOT gate (1-in): PROC_CORE → OTHER_CORE
```

### 4.4 Mirror-based remote copy check

```
Remote mirror entry for line PROC_IDX in the other core:

  When PROC_CORE=0, remote core = 1:
    Remote mirror entry = MR_1_l  for l == PROC_IDX
  When PROC_CORE=1, remote core = 0:
    Remote mirror entry = MR_0_l  for l == PROC_IDX

  Select remote mirror value via 2-level MUX:
  
  Step 1: Pick which core's mirror to read (4:1 MUX on PROC_IDX within each core)
    MUX_MR_C0 (2b, 2-sel): sel=PROC_IDX
      Input 0: MR_0_0.Q,  Input 1: MR_0_1.Q
      Input 2: MR_0_2.Q,  Input 3: MR_0_3.Q
      Output: MR_CORE0_SELECTED[1:0]

    MUX_MR_C1 (2b, 2-sel): sel=PROC_IDX
      Input 0: MR_1_0.Q,  Input 1: MR_1_1.Q
      Input 2: MR_1_2.Q,  Input 3: MR_1_3.Q
      Output: MR_CORE1_SELECTED[1:0]

  Step 2: Pick the OTHER core's mirror entry:
    MUX_MR_REMOTE (2b, 1-sel): sel=PROC_CORE (NOT → OTHER_CORE as sel signal)
      When PROC_CORE=0 → other is 1 → sel=1 → take MR_CORE1_SELECTED
      When PROC_CORE=1 → other is 0 → sel=0 → take MR_CORE0_SELECTED
      
      MUX (2b, 1-sel): sel=PROC_CORE
        Input 0 (core0 wrote → remote is core1): MR_CORE1_SELECTED
        Input 1 (core1 wrote → remote is core0): MR_CORE0_SELECTED
      Output: REMOTE_MIRROR[1:0]

  Mirror-based remote copy exists if REMOTE_MIRROR != I (2'b00):
    MR_REMOTE_NI = REMOTE_MIRROR[1] OR REMOTE_MIRROR[0]
    OR gate (2-in): REMOTE_MIRROR[1], REMOTE_MIRROR[0] → MR_REMOTE_NI
```

### 4.5 Actual-state remote copy check (R6)

```
Same logic applied to the actual cache line states read directly from the cache registers.

  Step 1a: Mux actual state for the other core at PROC_IDX (core 0 lines, indexed by PROC_IDX)
    STATE0_I is 8 bits = 4 lines × 2 bits each.
    Extract per-line pairs via Splitter:
      ACTUAL_STATE0_L[l] = STATE0_I[2l+1:2l]  for l=0..3

    MUX_ACT_C0 (2b, 2-sel): sel=PROC_IDX
      Inputs: ACTUAL_STATE0_L[0..3]
      Output: ACTUAL_STATE0_SEL[1:0]

    MUX_ACT_C1 (2b, 2-sel): sel=PROC_IDX
      Inputs: ACTUAL_STATE1_L[0..3]
      Output: ACTUAL_STATE1_SEL[1:0]

    MUX_ACT_REMOTE (2b, 1-sel): sel=PROC_CORE
      Input 0: ACTUAL_STATE1_SEL  (core1 actual, when core0 wrote)
      Input 1: ACTUAL_STATE0_SEL  (core0 actual, when core1 wrote)
      Output: ACTUAL_REMOTE_STATE[1:0]

  Step 1b: Mux actual valid bit for the other core at PROC_IDX:
    VALID0_I is 4 bits. Extract bit l = VALID0_I[l].
    MUX_VLD_C0 (1b, 2-sel): sel=PROC_IDX
      Inputs: VALID0_I[3:0] individual bits
      Output: ACTUAL_VALID0_SEL

    MUX_VLD_C1, MUX_VLD_REMOTE: same structure
    Output: ACTUAL_REMOTE_VALID

  Actual remote copy exists:
    ACTUAL_REMOTE_NI = ACTUAL_REMOTE_VALID
                     AND (ACTUAL_REMOTE_STATE[1] OR ACTUAL_REMOTE_STATE[0])
    (valid AND not-I)
    AND gate (2-in):
      Input 0: ACTUAL_REMOTE_VALID
      Input 1: OR(ACTUAL_REMOTE_STATE[1], ACTUAL_REMOTE_STATE[0])
    Output: ACTUAL_REMOTE_NI
```

### 4.6 Final dispatch decision

```
REMOTE_HAS_COPY = (MR_REMOTE_NI OR ACTUAL_REMOTE_NI) AND COH_ENABLE
  (Either mirror or actual state shows a copy AND coherence is enabled)

Logisim:
  OR gate (2-in): MR_REMOTE_NI, ACTUAL_REMOTE_NI → COPY_EXISTS
  AND gate (2-in): COPY_EXISTS, COH_ENABLE → REMOTE_HAS_COPY
```

---

## 5. Main FSM: `CoherenceCtrl`

### 5.1 State register (2-bit)

```
Component: Memory > Register, 2 bits
  CLK: CLK tunnel
  CLR: NOT(RST_N)   → reset to 2'b00 = COH_IDLE ✓
  EN:  1 (always enabled)
  D:   NEXT_STATE[1:0]
  Q:   CURR_STATE[1:0]
```

### 5.2 State comparators

```
4× Comparator (2-bit):
  IN_COH_IDLE       = (CURR_STATE == 2'b00)
  IN_PROCESS_WRITE  = (CURR_STATE == 2'b01)
  IN_INVALIDATE_OTHER = (CURR_STATE == 2'b10)
  IN_WAIT_INV_ACK   = (CURR_STATE == 2'b11)
```

### 5.3 Captured registers (latched at COH_IDLE→PROCESS_WRITE)

```
PROC_CORE_REG (1-bit Register):
  Captures which core's notify was accepted.
  EN  = IN_COH_IDLE AND (WRITE_NOTIFY0 OR WRITE_NOTIFY1)
  D   = WRITE_NOTIFY1 AND NOT(WRITE_NOTIFY0)
        (0 if core0 notified [has priority], 1 if only core1 notified)
  Logisim:
    NOT gate: WRITE_NOTIFY0 → N_WN0
    AND gate: WRITE_NOTIFY1, N_WN0 → ONLY_WN1   (core1 only)
    Register(1b, EN=above): D=ONLY_WN1, Q=PROC_CORE_REG

PROC_IDX_REG (2-bit Register):
  Captures line index of the write address.
  EN = same as PROC_CORE_REG
  D  = MUX(WRITE_NOTIFY0, WRITE_ADDR0[3:2], WRITE_ADDR1[3:2])
       (if core0 notified: use addr0's index; else addr1's)
  MUX(2b, 1-sel): sel=WRITE_NOTIFY0
    Input 0: WRITE_ADDR1[3:2]  (only if core0 not notifying)
    Input 1: WRITE_ADDR0[3:2]  (core0 has priority)
  Register(2b, EN=above): D=MUX output, Q=PROC_IDX_REG

INV_TARGET_REG (1-bit Register):
  Captures the core to be invalidated (= NOT(PROC_CORE)).
  Set when transitioning from PROCESS_WRITE to INVALIDATE_OTHER.
  EN  = IN_PROCESS_WRITE AND REMOTE_HAS_COPY
  D   = NOT(PROC_CORE_REG)
  Register(1b, EN=above): Q=INV_TARGET_REG

INV_IDX_REG (2-bit Register):
  Captures PROC_IDX_REG at the same time as INV_TARGET (same EN).
  EN  = same as INV_TARGET_REG
  D   = PROC_IDX_REG
  Register(2b, EN=above): Q=INV_IDX_REG
```

### 5.4 Next-state logic

```
NS_COH_IDLE =
    IN_PROCESS_WRITE AND NOT(REMOTE_HAS_COPY)     -- no remote copy → skip invalidation
  | IN_WAIT_INV_ACK AND INV_ACK_FOR_TARGET        -- ack received

  INV_ACK_FOR_TARGET:
    MUX(1b, sel=INV_TARGET_REG):
      Input 0: INV_ACK0
      Input 1: INV_ACK1
    Output: INV_ACK_FOR_TARGET

NS_PROCESS_WRITE =
    IN_COH_IDLE AND (WRITE_NOTIFY0 OR WRITE_NOTIFY1)

NS_INVALIDATE_OTHER =
    IN_PROCESS_WRITE AND REMOTE_HAS_COPY

NS_WAIT_INV_ACK =
    IN_INVALIDATE_OTHER   (always advance — 1-cycle state)
  | IN_WAIT_INV_ACK AND NOT(INV_ACK_FOR_TARGET)  (hold until ack)

Bit derivation:
  NEXT_STATE[1] = NS_INVALIDATE_OTHER | NS_WAIT_INV_ACK
  NEXT_STATE[0] = NS_PROCESS_WRITE    | NS_WAIT_INV_ACK

Logisim:
  OR gate (2-in): NS_INVALIDATE_OTHER, NS_WAIT_INV_ACK → NEXT_STATE[1]
  OR gate (2-in): NS_PROCESS_WRITE, NS_WAIT_INV_ACK    → NEXT_STATE[0]
```

### 5.5 Output logic

```
COH_ACCEPT0:
  = IN_COH_IDLE AND WRITE_NOTIFY0
  AND gate (2-in): IN_COH_IDLE, WRITE_NOTIFY0 → COH_ACCEPT0

COH_ACCEPT1:
  = IN_COH_IDLE AND NOT(WRITE_NOTIFY0) AND WRITE_NOTIFY1
  NOT: WRITE_NOTIFY0 → N_WN0
  AND (3-in): IN_COH_IDLE, N_WN0, WRITE_NOTIFY1 → COH_ACCEPT1

INV_VALID0 (held in INVALIDATE_OTHER and WAIT_INV_ACK while target=0):
  = (IN_INVALIDATE_OTHER OR IN_WAIT_INV_ACK) AND NOT(INV_TARGET_REG)
  OR (2-in): IN_INVALIDATE_OTHER, IN_WAIT_INV_ACK → DISPATCHING
  NOT: INV_TARGET_REG → TARGET_IS_0
  AND (2-in): DISPATCHING, TARGET_IS_0 → INV_VALID0

INV_VALID1:
  = DISPATCHING AND INV_TARGET_REG
  AND (2-in): DISPATCHING, INV_TARGET_REG → INV_VALID1

INV_IDX0 = INV_IDX_REG when INV_VALID0 (else 0)
  AND32-like (2-bit AND, 2-in): INV_IDX_REG AND {2{INV_VALID0}} → INV_IDX0
  Logisim: 2-bit AND gate, Input0=INV_IDX_REG, Input1=INV_VALID0 replicated 2 bits

INV_IDX1 = INV_IDX_REG when INV_VALID1
  Same structure → INV_IDX1

INV_FIRE:
  1-cycle pulse on entry to WAIT_INV_ACK (= rising edge of IN_INVALIDATE_OTHER transition)
  = IN_INVALIDATE_OTHER  (since this state is held for exactly 1 cycle — it always transitions out)
  Direct wire: INV_FIRE = IN_INVALIDATE_OTHER
  (The FSM always exits INVALIDATE_OTHER in one cycle → it's a natural 1-cycle pulse)
```

### 5.6 Mirror update in CohMirror — FSM-driven enable signals

```
The CohMirror sub-circuit is fed these enable signals from CoherenceCtrl:

For mirror[PROC_CORE_REG][PROC_IDX_REG] ← M:
  MIRROR_WR_M_EN = IN_PROCESS_WRITE   (write M for the notifying core's line)
  MIRROR_WR_CORE = PROC_CORE_REG
  MIRROR_WR_IDX  = PROC_IDX_REG

For mirror[INV_TARGET_REG][PROC_IDX_REG] ← I:
  MIRROR_WR_I_EN = IN_WAIT_INV_ACK AND INV_ACK_FOR_TARGET
  MIRROR_WR_CORE (for I) = INV_TARGET_REG
  MIRROR_WR_IDX  (for I) = PROC_IDX_REG  (same line)

For mirror[FILL_CORE][FILL_IDX] ← S (asynchronous to FSM state, R2):
  Core 0: FILL_NOTIFY0 pulse → mirror[0][FILL_IDX0] ← S
  Core 1: FILL_NOTIFY1 pulse → mirror[1][FILL_IDX1] ← S
  These feed directly into the CohMirror entry update logic, independent of FSM state.
```

---

## 6. Complete ASCII Block Diagram

```
                 ┌──────────────────────────────────────────────────────────┐
                 │                   CoherenceCtrl                          │
                 │                                                          │
 WRITE_NOTIFY0 ─►│  ┌──────────────────────────────────────────────┐       │
 WRITE_ADDR0   ─►│  │  PROC_CORE_REG (1b)  PROC_IDX_REG (2b)       │       │
 WRITE_NOTIFY1 ─►│  │  INV_TARGET_REG(1b)  INV_IDX_REG  (2b)       │       │
 WRITE_ADDR1   ─►│  └──────────────────────────┬───────────────────┘       │
                 │                             │                            │
 CLK ───────────►│  ┌─────────────────────────┐│                            │
 RST_N→NOT→CLR ─►│  │ State Reg (2b D-FF)     ││                            │
                 │  │ Q→CURR_STATE            ││                            │
                 │  └────────────┬────────────┘│                            │
                 │               │             │                            │
                 │   4×Comparator(2b)          │                            │
                 │   IN_COH_IDLE..IN_WAIT_INV  │                            │
                 │               │             │                            │
                 │   DispatchLogic◄────────────┤                            │
                 │   (mirror+actual state MUXes│                            │
                 │    R6 dispatch decision)    │                            │
                 │   REMOTE_HAS_COPY ──────────┤                            │
                 │                             │                            │
                 │   Next-state equations      │                            │
                 │   (NS_* OR-of-products) ────► NEXT_STATE[1:0]            │
                 │                             │                            │
                 │   Output equations:         │                            │
                 │   COH_ACCEPT0/1 ◄───────────┤                            │
                 │   INV_VALID0/1  ◄───────────┤                            │
                 │   INV_IDX0/1    ◄───────────┤                            │
                 │   INV_FIRE      ◄───────────┘                            │
                 └──────────────────────────────────────────────────────────┘
                         │  Mirror write enables + core/idx
                         ▼
                 ┌──────────────────────────────────────────────────────────┐
                 │                    CohMirror                             │
                 │  8× Register(2b): MR_0_0..MR_1_3                        │
                 │  Per-entry: 3-level priority MUX (M>I>S>hold)            │
                 │  Index comparators (4+4+4 comparators, 2-bit)            │
                 │  Combine Splitter(16b) → COH_STATUS[15:0]               │
                 └──────────────────────────────────────────────────────────┘

External sideband connections:
  WRITE_NOTIFY0/1, WRITE_ADDR0/1 ← D-Cache Mgr 0/1
  COH_ACCEPT0/1                  → D-Cache Mgr 0/1
  FILL_NOTIFY0/1, FILL_IDX0/1    ← D-Cache Mgr 0/1
  INV_VALID0/1, INV_IDX0/1       → D-Cache Mgr 0/1
  INV_ACK0/1                     ← D-Cache Mgr 0/1
  STATE0_I, VALID0_I             ← D-Cache 0 line registers (actual, R6)
  STATE1_I, VALID1_I             ← D-Cache 1 line registers
  INV_FIRE                       → MMIO INV_COUNT counter
  COH_STATUS[15:0]               → MMIO COH_STATUS register
  COH_ENABLE                     ← MMIO CONTROL register
```

---

## 7. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| State register | Data bits | 2 |
| State register | CLR async | Active high → NOT(RST_N) |
| State comparators (×4) | Data bits | 2 |
| PROC_CORE_REG | Data bits | 1; Enable yes |
| PROC_IDX_REG | Data bits | 2; Enable yes |
| INV_TARGET_REG | Data bits | 1; Enable yes |
| INV_IDX_REG | Data bits | 2; Enable yes |
| Mirror registers (×8) | Data bits | 2; Enable yes; CLR async |
| Mirror MUXes (×8 × 3 levels) | Data bits | 2; Select bits 1 (each level) |
| Mirror index comparators | Data bits | 2 |
| MUX_MR_C0, MUX_MR_C1 | Data bits | 2; Select bits 2 |
| MUX_MR_REMOTE | Data bits | 2; Select bits 1 |
| MUX_ACT_C0/C1/REMOTE | Data bits | 2; Select bits 2 (or 1) |
| MUX_VLD_C0/C1/REMOTE | Data bits | 1; Select bits 2 (or 1) |
| COH_STATUS Splitter | Output | 16 bits; combine from 8×2 |
| INV_IDX gate | Data bits | 2; AND with 1-bit enable replicated |
| All single-bit gates | Data bits | 1 |

---

## 8. Layout Notes for Logisim

- Place `CoherenceCtrl` FSM at center-left, `CohMirror` below it, `DispatchLogic` to the right.
- Use Tunnel labels: `IN_COH_IDLE`, `IN_PROCESS_WRITE`, `IN_INVALIDATE_OTHER`, `IN_WAIT_INV_ACK`, `PROC_CORE_REG`, `PROC_IDX_REG`, `REMOTE_HAS_COPY`.
- The 8 mirror registers in `CohMirror` can be arranged in a 2-row × 4-column grid (row=core, col=line).
- The 3-level priority MUX chain per entry is compact: 3 cascaded 2:1 MUXes, total 6 components per entry = 48 MUXes total for all 8 entries.
- `DispatchLogic` is a sub-circuit instance inside `CoherenceCtrl`, keeping the top level clean.
- Export `ACTUAL_REMOTE_NI` and `MR_REMOTE_NI` as labeled probe points for TB assertion A5 (mirror == actual).
