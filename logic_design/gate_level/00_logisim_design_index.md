# Gate-Level Circuit Design — Logisim Master Index

**Project:** Dual-Core RV32I SoC with Coherent Memory Subsystem  
**Purpose:** Complete gate-level (Logisim-ready) circuit design for every component.  
**Convention:** All circuits are described exactly as they would be laid out and wired in Logisim Evolution. Each sub-document gives: (1) the Logisim sub-circuit name, (2) all input/output pins with bit widths, (3) the internal logic primitives and their connections, (4) a structured ASCII wiring diagram, and (5) any Logisim component settings (bit widths, initial values, etc.).

---

## Sub-circuit map

| File | Sub-circuit(s) | Source logic doc |
|------|----------------|-----------------|
| [01_alu_gate_level.md](01_alu_gate_level.md) | `ALU`, `Adder32`, `BarrelShifter32`, `Comparator32`, `ZeroDetect32` | 02_alu_logic.md |
| [02_regfile_pc_gate_level.md](02_regfile_pc_gate_level.md) | `RegFile32`, `PCLogic` | 03_core_datapath |
| [03_control_unit_gate_level.md](03_control_unit_gate_level.md) | `ControlUnit`, `ImmGen`, `CoreFSM`, `LoadResize`, `StoreRotate` | 03_core_datapath |
| [04_dcache_store_gate_level.md](04_dcache_store_gate_level.md) | `DCacheStore`, `TagCompare`, `HitLogic` | 04_dcache_fsm |
| [05_dcache_mgr_fsm_gate_level.md](05_dcache_mgr_fsm_gate_level.md) | `DCacheMgrFSM` (13-state) | 04_dcache_fsm |
| [06_coherence_fsm_gate_level.md](06_coherence_fsm_gate_level.md) | `CoherenceCtrl`, `CohMirror`, `DispatchLogic` | 05_coherence_fsm |
| [07_arbiter_gate_level.md](07_arbiter_gate_level.md) | `AXIArbiter`, `ArbFSM`, `AXIMux` | 06_arbiter_logic |
| [08_decoder_gate_level.md](08_decoder_gate_level.md) | `AddrDecoder`, `DECERRSlave` | 07_decoder_and_bus_fabric |
| [09_memory_gate_level.md](09_memory_gate_level.md) | `SharedSRAM`, `ISRAM`, `SRAMRegArray` | 08_memory_subsystem |
| [10_peripherals_gate_level.md](10_peripherals_gate_level.md) | `MMIORegs`, `UartCore`, `TxFSM`, `RxFSM`, `BaudGen`, `GPIOLed`, `LEDStretcher` | 09_peripherals |
| [11_soc_top_gate_level.md](11_soc_top_gate_level.md) | `ResetSync`, `RiscVSoCTop`, `FpgaTop` | 10/11/12 |

---

## Logisim global settings used throughout

| Setting | Value |
|---------|-------|
| Simulation speed | 1 tick = 1 clock cycle |
| Gate delay | 1 (normalized; for timing analysis use 5 ns/gate on sky130) |
| Bus splitters | Bidirectional (Logisim "appears: left") for all multi-bit buses |
| Registers | All D flip-flops, negative-edge clear (maps to async active-low `rst_n`) |
| Clock | Single `CLK` pin, distributed via tunnel labels named `CLK` |
| Reset | Single `RST_N` pin, distributed via tunnel labels named `RST_N` |
| Bit ordering | Big-endian in Logisim display; port [31] = MSB = leftmost |

---

## How to reconstruct in Logisim

1. Create a new project `riscv_soc.circ`.
2. Add each sub-circuit listed above as a new circuit inside the project (right-click on circuit list → Add Circuit).
3. Wire them in the order listed (bottom-up): primitives first, then top-level.
4. Use **Tunnels** (Wiring → Tunnel) for `CLK`, `RST_N`, and long buses that cross multiple components — avoids spaghetti wiring.
5. Use **Splitters** to fan out / merge wide buses. Set "Appears Facing" to match the data-flow direction (left-to-right).
6. The top-level `RiscVSoCTop` circuit instantiates all sub-circuits as components.

---

## Component primitive count summary

| Sub-circuit | Key Logisim primitives | Approx count |
|-------------|------------------------|-------------|
| ALU | Adder(32b), MUX(32b,4-sel), NOT/AND/OR/XOR(32b), BarrelMUX(32b,1-sel)×10 | ~60 |
| RegFile32 | Register(32b)×31, Decoder(5b), AND(1b)×31, MUX(32b,5-sel)×2 | ~100 |
| PCLogic | Adder(32b)×4, MUX(32b,1-sel)×3, AND/NOT gates | ~20 |
| ImmGen | Splitters×6, BitExtender(→32b)×4, Combine Splitters×5 | ~25 |
| ControlUnit | Comparator(7b)×10 + (3b)×8 + (7b)×2, ROM(128×4), OR/AND/NOT gates | ~50 |
| CoreFSM | DFF(1b)×1, AND/OR/NOT gates | ~12 |
| DCacheStore | Register(63b)×4, Decoder(2b), AND(1b)×4, Splitter(63b) | ~15 |
| TagCompare | Splitter(63b), Comparator(28b), OR(1b), AND(3-in) | ~6 |
| HitLogic | 4× TagCompare instances, MUX(1/32/2/1b,2-sel)×4 | ~20 |
| CacheLineMux | MUX(8b,1-sel)×4, Combine Splitter(32b) | ~6 |
| DCacheMgrFSM | Register(4b+32b×4+4b×1+1b×5), Comparator(4b)×13, OR/AND/NOT gates, MUXes | ~120 |
| CoherenceCtrl | Register(2b+1b×4+2b×2), Comparator(2b)×4+(2b)×12, MUX chains×8 entries | ~100 |
| AXIArbiter | Register(2b+1b), Comparator(2b)×3, AND/OR/NOT, MUX(1/32/4b,1-sel)×7 | ~50 |
| AddrDecoder | Splitter, Comparator(20/16/8b)×5, AND×3, OR(4-in), NOT | ~15 |
| DECERRSlave | Register(2b+1b), Comparator(2b)×4, gates, Constants | ~30 |
| SharedSRAM | RAM(1024×32b), Register(32/32/4b), DFF, Adder-free, MUX(10b) | ~20 |
| ISRAM | RAM(256×32b, async), Splitter | ~5 |
| MMIORegs | Counter(32b)×3, Register(32b×2+1b), Comparator(6b)×6, MUX(32b,3-sel) | ~40 |
| UartCore | Counter(10b+5b+4b), Register(10/8/8b), DFF×4, gates | ~60 |
| GPIOLed | Register(8b), Splitter, Counter(22b)×5, OR(22-in)×5 | ~20 |
| ResetSync | DFF(1b)×2, NOT(1b), Constant(1) | ~4 |
| **TOTAL** | | **~778 primitives** |

---

## Key design decisions reflected in every gate-level document

| Decision | Gate-level consequence |
|----------|----------------------|
| D1: Single-cycle core + req/ack stall | CoreFSM is 1-bit (2 states); all timing flows from dcmgr ack |
| D2: AXI4-Lite only | No burst logic; every AXI interface uses exactly 5 channels |
| D3: Write-through + write-allocate | DCacheMgrFSM has both AXI-read AND AXI-write paths for store-miss (R3) |
| D4: I/S/M 3-state coherence | CohMirror stores 2-bit state per entry; dispatch gated by state≠I |
| D5: Direct-mapped, 4 lines | TagCompare uses 2-bit IDX, 28-bit tag; HitLogic uses 4:1 MUXes on IDX |
| D6: Async assert / sync release reset | ResetSync produces RST_SYNC_N; all registers use async CLR |
| D7: Register arrays (no macros) | Logisim RAM components directly; ISRAM async, SharedSRAM sync |
| R1: coh_accept handshake | DCacheMgrFSM holds WRITE_NOTIFY until COH_ACCEPT; NOTIFY_COH state exists |
| R2: fill_notify for S-fills | DCacheMgrFSM outputs FILL_NOTIFY/IDX; CohMirror has S-path update |
| R6: Actual state read for dispatch | DispatchLogic has second MUX tree reading real cache line STATE/VALID registers |
| R9: Uncached bypass | UNCACHED_FLAG comparator in DCacheMgrFSM gates fill/notify outputs |
