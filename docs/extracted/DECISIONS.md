# Decision Record - Project 05

Locked decisions. Every RTL, TB, and flow choice traces back to one of these.
Source documents: PRD / TRD / Implementation Plan / Analysis+Spec / Track Document (see `docs/`).

## 1. Design decisions (from project brief + Day-1 analysis)

| #  | Decision        | Choice                                                    | Rationale |
|----|-----------------|-----------------------------------------------------------|-----------|
| D1 | Core            | RV32I, single-cycle datapath with req/ack stall on memory | Predictable timing, easiest to verify, fastest to close on sky130 |
| D2 | Bus             | AXI4-Lite (5 channels, no bursts)                         | Course-required; strictly Lite, never full AXI4 |
| D3 | Write policy    | Write-through + write-allocate                            | Shared SRAM is always the source of truth; no dirty writeback |
| D4 | Coherence       | 3-state I/S/M, invalidation-on-write, sideband (not bus-routed) | Minimal correct mechanism; explicitly NOT MESI/MOESI |
| D5 | Cache geometry  | Direct-mapped, 4 lines, 1 word/line, per-core private D-cache | Concept demonstration, not performance |
| D6 | Reset           | Single async active-low `rst_n`, 2-flop synchronized release | One policy everywhere; all caches to I, counters to 0 |
| D7 | Memories        | Register arrays (parameterized); FPGA maps to BRAM        | Zero macro-integration pain in OpenLane (no OpenRAM .lib/.lef/.gds) |
| D8 | Invalidation    | Coherence controller dispatches to remote cache only; invalidation interface is sideband | Prevents bus deadlock; write-through already updated SRAM before refetch |

## 2. Toolchain decisions (confirmed by owner, 2026-09-04)

| #  | Item             | Choice                              | Implication |
|----|------------------|-------------------------------------|-------------|
| T1 | FPGA board       | Arty A7-100T (xc7a100t-1csg324)     | .xdc pins fixed to Arty reference design; 100 MHz ref -> MMCM -> 50 MHz core_clk |
| T2 | Simulator        | Commercial simulator (Questa/VCS/Xcelium) | UVM-1.2 works out of the box; coverage + debug tooling available. Makefile SIM variable selects flavor |
| T3 | OpenLane host    | Separate Linux machine              | Repo is rsynced there for the sky130A flow; results copied back into reports/ |
| T4 | ASIC timing      | 20 MHz start (50 ns), tighten if it closes | sky130 conservative start per TRD |
| T5 | FPGA core clock  | 50 MHz via MMCM from 100 MHz board ref | Never run the core on the raw board clock |

## 3. Open items (resolve at Gate 0/1, before or during RTL)

| #  | Item                                   | Working recommendation |
|----|----------------------------------------|------------------------|
| O1 | ASIC SRAM sizes                        | Shrink for the OpenLane run (e.g. 256-word shared SRAM, 128-word I-SRAMs) - flop-based arrays at full 4 KB + 2x1 KB would dominate die area (~50k flops). Keep full size on FPGA. Parameterize so both instantiate from the same RTL |
| O2 | Store-miss policy for sub-word (sb/sh) | Write-allocate uniformly: fill word from SRAM, merge bytes via wmask, write through. Simplest correct choice |
| O3 | Core behavior on dmem_err              | No register writeback; sticky error status bit visible via MMIO. Define before UVM error tests |
| O4 | Coherence controller state mirror      | Keep the 8-entry (4 lines x 2 cores) mirrored table per FR-3.4, plus a consistency assertion against actual cache states |
| O5 | UVM agent placement                    | Agents drive the core-side req/ack interface of each D-cache manager (replacing the cores), monitoring both AXI-Lite and the invalidation sideband |
| O6 | Demo program source format             | Hand-assembled or riscv32-unknown-elf-gcc generated .hex via readmemh (sim) / BRAM init (FPGA) |
