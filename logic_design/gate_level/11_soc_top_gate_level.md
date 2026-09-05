# Gate-Level Circuit: System Top Level

Source: `10_system_block_diagram.md`, `11_memory_map.md`, `12_integration_logic.md`  
Logisim sub-circuit names: **`ResetSync`**, **`RiscVSoCTop`**, **`FpgaTop`**

This document describes the complete integration layer — every module instance, every wire, the reset synchronizer, and the FPGA top wrapper.

---

## 1. Sub-circuit: `ResetSync` — 2-FF Async-Assert / Sync-Release Reset Synchronizer

### 1.1 Purpose

Takes the raw asynchronous `RST_N` button input and produces `RST_SYNC_N` that:
- Asserts asynchronously (immediately when RST_N goes low)
- Releases synchronously (waits 2 clock edges after RST_N goes high)

This prevents metastability from the button de-bounce hitting a flip-flop setup time.

### 1.2 Circuit

```
Two D flip-flops in series. Both async-cleared by NOT(RST_N).

FF1:
  D   = 1'b1               (constant 1 — feeds stable data into the chain)
  CLK = CLK
  CLR = NOT(RST_N)          (async clear: output → 0 immediately when RST_N=0)
  Q   = FF1_Q

FF2:
  D   = FF1_Q
  CLK = CLK
  CLR = NOT(RST_N)          (same async clear)
  Q   = RST_SYNC_N          (synchronized release signal)

Reset behavior:
  RST_N = 0: both FFs async-clear → RST_SYNC_N = 0 immediately
  RST_N = 1: FF1.D=1 → after 1 edge FF1_Q=1 → after 2nd edge RST_SYNC_N=1

Logisim:
  2× D Flip-Flop (1-bit)
    FF1: D = Constant(1), CLK = CLK, CLR = NOT(RST_N)
    FF2: D = FF1.Q,       CLK = CLK, CLR = NOT(RST_N)
  NOT gate: RST_N → NOT_RST → CLR input of both FFs
  Constant(1, 1b) → FF1.D
  FF2.Q → RST_SYNC_N output pin
```

### 1.3 ASCII Diagram

```
RST_N ──► NOT ──────────────────────────────────────────┐
                                                        │
Constant(1) ──► FF1.D     FF1.CLK ◄── CLK              │
               FF1.CLR ◄──────────────────────────────── ┤ (shared CLR)
               FF1.Q ──► FF2.D    FF2.CLK ◄── CLK       │
                         FF2.CLR ◄────────────────────── ┘
                         FF2.Q ──► RST_SYNC_N
```

---

## 2. Sub-circuit: `RiscVSoCTop` — Full SoC Integration

### 2.1 Instance list

| Instance name | Sub-circuit | Key parameters |
|---------------|-------------|---------------|
| `u_rst_sync` | ResetSync | — |
| `u_core0` | RV32ICore (ALU + RegFile + PCLogic + ControlUnit + ImmGen + CoreFSM) | CORE_ID=0 |
| `u_core1` | RV32ICore | CORE_ID=1 |
| `u_isram0` | ISRAM | DEPTH=256 |
| `u_isram1` | ISRAM | DEPTH=256 |
| `u_dcache0` | DCacheStore + HitLogic + CacheLineMux | LINES=4, CORE_ID=0 |
| `u_dcache1` | DCacheStore + HitLogic + CacheLineMux | LINES=4, CORE_ID=1 |
| `u_dcmgr0` | DCacheMgrFSM | CORE_ID=0 |
| `u_dcmgr1` | DCacheMgrFSM | CORE_ID=1 |
| `u_coh` | CoherenceCtrl (CohMirror + DispatchLogic) | LINES=4 |
| `u_arb` | AXIArbiter (GrantLogic + ArbFSM + AXIMux) | MASTERS=2 |
| `u_dec` | AddrDecoder + DECERRSlave + slave routing | — |
| `u_sram` | SharedSRAM | DEPTH=1024 |
| `u_mmio` | MMIORegs | — |
| `u_uart` | UartCore (BaudGen + TxFSM + RxFSM) | BAUD_DIV=434 |
| `u_gpio` | GPIOLed + 5×LEDStretcher | — |

### 2.2 Global clock and reset distribution

```
Logisim approach: use Tunnel components named "CLK" and "RST_SYNC_N" inside every sub-circuit.
  - Top-level CLK input pin → Tunnel("CLK") fanout to all instances
  - RST_N input → u_rst_sync → RST_SYNC_N → Tunnel("RST_SYNC_N") fanout

  Every sub-circuit reads CLK and RST_N via Tunnel, not via explicit port wiring.
  This models the global distribution without drawing hundreds of crossing wires.
```

### 2.3 Complete inter-module wiring table

#### Core domain wires (per core, shown for core 0; core 1 identical with subscript 1)

```
u_isram0.IMEM_ADDR  ← u_core0.PC_OUT           (32b, instruction fetch)
u_core0.IMEM_RDATA  ← u_isram0.IMEM_RDATA      (32b, async)

u_dcmgr0.DMEM_REQ   ← u_core0.DMEM_REQ         (1b)
u_dcmgr0.DMEM_WE    ← u_core0.DMEM_WE          (1b)
u_dcmgr0.DMEM_ADDR  ← u_core0.DMEM_ADDR        (32b)
u_dcmgr0.DMEM_WDATA ← u_core0.DMEM_WDATA       (32b)
u_dcmgr0.DMEM_WMASK ← u_core0.DMEM_WMASK       (4b)
u_core0.DMEM_RDATA  ← u_dcmgr0.DMEM_RDATA      (32b)
u_core0.DMEM_ACK    ← u_dcmgr0.DMEM_ACK        (1b)
u_core0.DMEM_ERR    ← u_dcmgr0.DMEM_ERR        (1b)

u_dcmgr0.CACHE_HIT  ← u_dcache0.HitLogic.CACHE_HIT  (1b)
u_dcmgr0.HIT_DATA   ← u_dcache0.HitLogic.HIT_DATA   (32b)
u_dcmgr0.HIT_STATE  ← u_dcache0.HitLogic.HIT_STATE  (2b)
u_dcache0.REQ_ADDR  ← u_dcmgr0.DMEM_ADDR (or latched l_addr) (32b)

u_dcache0.WR_EN     ← u_dcmgr0.WR_EN           (1b)
u_dcache0.WR_IDX    ← u_dcmgr0.WR_IDX          (2b)
u_dcache0.WR_VALID  ← u_dcmgr0.WR_VALID        (1b)
u_dcache0.WR_TAG    ← u_dcmgr0.WR_TAG          (28b)
u_dcache0.WR_DATA   ← u_dcmgr0.WR_DATA         (32b)
u_dcache0.WR_STATE  ← u_dcmgr0.WR_STATE        (2b)
```

#### AXI fabric wires

```
u_arb.REQ0       ← u_dcmgr0.BUS_REQ             (1b)
u_arb.REQ1       ← u_dcmgr1.BUS_REQ             (1b)
u_arb.BUS_GRANT  → u_dcmgr0.BUS_GRANT (when GRANT0=1)
                 → u_dcmgr1.BUS_GRANT (when GRANT1=1)

AXI master 0 (17 signals from doc 06 §6.4):
  u_arb.M0_AWVALID ← u_dcmgr0.AXI_AWVALID  ... (all M0 AXI signals)
  u_dcmgr0.AXI_AWREADY ← u_arb.M0_AWREADY  ... (all response signals)

AXI master 1: identical wiring to u_dcmgr1 via M1 ports.

Shared slave port (arbiter → decoder):
  u_dec.S_* ← u_arb.S_*   (all 17 shared slave AXI signals, both directions)

Decoder → slaves:
  u_sram.S_*  ← u_dec gated by SEL_SRAM (all AXI signals)
  u_mmio.S_*  ← u_dec gated by SEL_MMIO
  u_uart.S_*  ← u_dec gated by SEL_UART
  u_gpio.S_*  ← u_dec gated by SEL_GPIO
  u_dec internal DECERR slave handles SEL_DECERR

Slave responses back to decoder → arbiter:
  u_dec collects all slave responses via priority encoder + MUX (doc 08 §3)
```

#### Coherence sideband wires

```
u_coh.WRITE_NOTIFY0  ← u_dcmgr0.WRITE_NOTIFY    (1b)
u_coh.WRITE_ADDR0    ← u_dcmgr0.WRITE_ADDR      (32b)
u_dcmgr0.COH_ACCEPT  ← u_coh.COH_ACCEPT0        (1b)
u_coh.FILL_NOTIFY0   ← u_dcmgr0.FILL_NOTIFY     (1b)
u_coh.FILL_IDX0      ← u_dcmgr0.FILL_IDX        (2b)
u_dcmgr0.INV_VALID   ← u_coh.INV_VALID0         (1b)
u_dcmgr0.INV_IDX     ← u_coh.INV_IDX0           (2b)
u_coh.INV_ACK0       ← u_dcmgr0.INV_ACK         (1b)

(Core 1 sideband: identical with subscript 1)

R6 actual-state wires:
u_coh.STATE0_I[7:0]  ← {u_dcache0.LINE3_Q[1:0], u_dcache0.LINE2_Q[1:0],
                          u_dcache0.LINE1_Q[1:0], u_dcache0.LINE0_Q[1:0]}
  Logisim: Combine Splitter (8 inputs of 2b each → 8b output)
    Each LINE{n}_Q[1:0] extracted via Splitter from the 63b line register output.

u_coh.VALID0_I[3:0]  ← {LINE3_Q[62], LINE2_Q[62], LINE1_Q[62], LINE0_Q[62]}
  Logisim: Combine Splitter (4 × 1b → 4b)
    Each valid bit extracted via Splitter [62:62] from LINE{n}_Q.

(Same for core 1 / STATE1_I / VALID1_I)
```

#### Event and control wires

```
u_mmio.INV_FIRE     ← u_coh.INV_FIRE             (1b)
u_mmio.COH_STATUS_I ← u_coh.COH_STATUS           (16b)
u_mmio.HIT0         ← u_dcmgr0.HIT_EVENT         (1b)
u_mmio.HIT1         ← u_dcmgr1.HIT_EVENT         (1b)
u_mmio.MISS0        ← u_dcmgr0.MISS_EVENT        (1b)
u_mmio.MISS1        ← u_dcmgr1.MISS_EVENT        (1b)
u_mmio.ERR0         ← u_dcmgr0.ERR_EVENT         (1b)
u_mmio.ERR1         ← u_dcmgr1.ERR_EVENT         (1b)

u_coh.COH_ENABLE    ← u_mmio.COH_ENABLE          (1b)
u_mmio (internal)   ← u_mmio.CNT_CLEAR (self)    (1b, counter clear)
u_mmio (internal)   ← u_mmio.ERR_CLEAR (self)    (1b, sticky clear)

LED events:
u_gpio.LED_DMEM_ACK0 ← u_dcmgr0.DMEM_ACK        (heartbeat for LED0)
u_gpio.LED_DMEM_ACK1 ← u_dcmgr1.DMEM_ACK        (heartbeat for LED1)
u_gpio.INV_FIRE     ← u_coh.INV_FIRE             (LED2)
u_gpio.HIT_EVENT    ← u_mmio.HIT0 OR u_mmio.HIT1 (LED3)
u_gpio.MISS_EVENT   ← u_mmio.MISS0 OR u_mmio.MISS1 (LED4)
u_gpio.ERR_STICKY   ← u_mmio.ERR_STICKY          (LED5, level)
```

#### External pins

```
Top-level input pins:
  CLK    (1b)  → Tunnel("CLK") + u_rst_sync.CLK
  RST_N  (1b)  → u_rst_sync.RST_N + NOT→CLR for both sync FFs

Top-level output pins:
  LED[7:0]  ← u_gpio.LED_OUT[7:0]   (8 LED output pins)
  UART_TX   ← u_uart.UART_TX        (1b, serial out)

Top-level input pins:
  UART_RX   → u_uart.UART_RX        (1b, serial in → 2-FF sync inside TxFSM)
```

### 2.4 ASCII Top-Level Block Diagram

```
CLK ──────────────────────────────────────────────────────────────► (tunnel CLK)
RST_N ──► NOT ──► FF1.CLR, FF2.CLR
          FF1(D=1) → FF2 ──► RST_SYNC_N ──────────────────────────► (tunnel RST_SYNC_N)

         ┌─────────────────────────────────────────────────────────┐
         │              Core 0 Domain                              │
         │  ISRAM0 ◄──► Core0 ◄──► DCacheMgr0 ◄──► DCacheStore0  │
         └──────────────────────────┬──────────────────────────────┘
                          AXI M0   │  Coherence sideband
                                   │
         ┌─────────────────────────│──────────────────────────────┐
         │              Core 1 Domain                             │
         │  ISRAM1 ◄──► Core1 ◄──► DCacheMgr1 ◄──► DCacheStore1  │
         └──────────────────────────┬──────────────────────────────┘
                          AXI M1   │
                                   ▼
                         ┌─────────────────┐
                         │   AXI Arbiter   │──► GRANT0/1
                         └────────┬────────┘
                                  ▼ shared slave port
                         ┌─────────────────┐
                         │ Address Decoder  │──► SEL_SRAM/MMIO/UART/GPIO/DECERR
                         └─────────────────┘
                            │     │     │    │
                          SRAM  MMIO  UART  GPIO+LEDs ──► LED[7:0] pins
                                               UART_TX/RX pins
                                   │
                         ┌─────────────────┐
                         │ CoherenceCtrl   │ ◄──► both cache sideband buses
                         └─────────────────┘
                                   │
                          inv_fire, coh_status, coh_enable
                                   ▼
                            MMIO registers
```

---

## 3. Sub-circuit: `FpgaTop` — FPGA Board Wrapper

Wraps `RiscVSoCTop` for the Nexys A7 (or equivalent) FPGA board. In Logisim this is a top-level circuit containing an instance of `RiscVSoCTop` plus any board-specific wiring.

### 3.1 Purpose

- Drives the 50 MHz clock (or MMCM 100→50 MHz on real FPGA)
- Routes physical LED and UART pins
- Handles FPGA-specific reset button polarity

### 3.2 Logisim equivalent

```
FpgaTop contains:
  1× RiscVSoCTop instance
  1× Clock source (Logisim: Wiring > Clock, frequency = 1 tick)
  1× Input pin: RST_BTN (active-high board button, maps to RST_N active-low)
     NOT gate: RST_BTN → RST_N → RiscVSoCTop.RST_N
  8× Output pins: LED[7:0] ← RiscVSoCTop.LED
  1× Output pin:  UART_TX  ← RiscVSoCTop.UART_TX
  1× Input pin:   UART_RX  → RiscVSoCTop.UART_RX

Clock:
  Logisim Clock component → CLK → RiscVSoCTop.CLK (via Tunnel "CLK" inside top)
```

---

## 4. Reset Value Verification Checklist

The following should be confirmed at simulation start (after RST_N pulse):

| Module | Reset state | Expected value |
|--------|-------------|---------------|
| Core FSM (×2) | RUN | state = 0 |
| PC (×2) | 0x0000_0000 | PC = 0 |
| D-Cache lines (×2×4) | Invalid | valid=0, state=I=00 |
| D-Cache Mgr FSM (×2) | IDLE | state = 4'd0 |
| Coherence FSM | COH_IDLE | state = 2'b00 |
| Coherence mirror (8 entries) | I | all = 2'b00 |
| Arbiter FSM | ARB_IDLE | state = 2'b00 |
| Arbiter PREF | core 0 | PREF = 0 |
| MMIO counters (×3) | 0 | INV/HIT/MISS = 0 |
| MMIO CONTROL | coh_enable=1 | CONTROL = 0x00000001 |
| ERR_STICKY | 0 | off |
| UART TX | idle | state = TX_IDLE, UART_TX = 1 |
| LED_REG | 0 | all LEDs off |

Logisim test: set RST_N=0 for 1 tick, then RST_N=1, verify all registers via Probes.

---

## 5. Logisim Component Settings Summary

| Component | Setting | Value |
|-----------|---------|-------|
| ResetSync FF1 | Data bits | 1; Trigger rising; CLR async active-high |
| ResetSync FF2 | Data bits | 1; Trigger rising; CLR async active-high |
| ResetSync Constant | Value | 1 (1-bit) |
| All core sub-circuit instances | Connect CLK, RST_SYNC_N via tunnels | — |
| R6 STATE combine Splitter | 4 × 2b inputs → 8b output (per core) |
| R6 VALID combine Splitter | 4 × 1b inputs → 4b output (per core) |
| VALID bit extraction Splitters | Extract bit [62] from 63b LINE_Q | |
| STATE extraction Splitters | Extract [1:0] from 63b LINE_Q | |
| FpgaTop Clock | Logisim clock component | 1 tick per sim step |
| FpgaTop RST_BTN | Active-high input button → NOT → RST_N | |

---

## 6. Simulation Order for Logisim

Build and verify bottom-up:

1. **ALU**: test all 10 ops with known inputs (verify ZERO, LT, LTU flags).
2. **RegFile + PCLogic**: write x1=5, read x1 back; test PC+4 and branch target.
3. **ControlUnit + ImmGen**: check decoded signals for ADD/LW/BEQ/JAL.
4. **Full Core** (ALU + RF + PC + CU): run ADDI x1,x0,5 → x1=5; LUI x2,1 → x2=0x1000.
5. **DCacheStore + HitLogic**: write a line, verify hit; write different tag, verify miss.
6. **DCacheMgrFSM** (with BFM RAM slave): load miss → fill → ack; store → write-through → ack.
7. **CoherenceCtrl**: core0 write → INV to core1 → inv_ack → mirror update.
8. **AXIArbiter**: simultaneous REQ0+REQ1 → GRANT0 (pref=0), then GRANT1 (pref=1).
9. **AddrDecoder + DECERRSlave**: test all 5 address ranges, verify SEL signals and DECERR response.
10. **SharedSRAM**: AXI write then AXI read, verify data; byte-mask test.
11. **MMIORegs**: write DOORBELL, read back; verify counter increments.
12. **Full RiscVSoCTop**: run coherence scenario (core0 SW → coherence → core1 LW = new value).
