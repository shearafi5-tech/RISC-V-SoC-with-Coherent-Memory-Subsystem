# RISC-V SoC with Coherent Memory Subsystem — Project 05

Dual-core RV32I SoC in which both processors access shared memory through private
direct-mapped write-through data caches and a simplified 3-state (I/S/M)
invalidation-based coherence controller, connected over AXI4-Lite.

**Status:** scaffolding complete — RTL development not yet started.

## System at a glance

- **Cores:** 2 × RV32I single-cycle (req/ack stall on memory), private instruction SRAMs
- **Coherence:** I/S/M, invalidation-on-write via sideband; write-through keeps shared SRAM as the single source of truth
- **Bus:** AXI4-Lite round-robin arbiter (2 masters) + address decoder (shared SRAM / MMIO / UART / GPIO / DECERR)
- **Verification:** directed self-checking SV testbench (10 cases) + UVM env (agents, scoreboard, coherence monitor, functional + code coverage)
- **ASIC:** OpenLane → sky130A, ≥20 MHz target, DRC/LVS clean, GDS
- **FPGA:** Arty A7-100T (xc7a100t-1csg324), 50 MHz core clock via MMCM, demo via UART + LEDs

## Repository layout

```
rtl/
  core/        rv32i_core, reg_file, alu, control_unit
  memory/      i_sram, shared_sram, sram_reg_array
  cache/       d_cache (line storage), d_cache_mgr (FSM + AXI-Lite master)
  coherence/   coherence_ctrl (per-line state + invalidate dispatcher)
  bus/         axi_lite_arbiter, axi_lite_decoder, axi_lite_if
  peripheral/  mmio_regs, uart_core, gpio_led
  top/         riscv_soc_top, fpga_top (FPGA wrapper + MMCM)
tb/
  directed/    tb_directed.sv (10 self-checking cases)
  uvm/         env, agents, sequences, scoreboard, tb_uvm.sv
sw/            core0/core1 demo programs (.hex via readmemh / BRAM init)
constraints/   soc.sdc (ASIC), fpga.xdc (Arty A7-100T)
openlane/      config.json for the sky130A flow (run on Linux host)
fpga/vivado/   Vivado project
reports/       synthesis, physical, coverage, fpga results
docs/          source PDFs + DECISIONS.md (locked decisions) + architecture.md (to write)
```

## Toolchain

| Stage      | Tool                                            | Host                  |
|------------|--------------------------------------------------|-----------------------|
| Smoke sim  | Icarus Verilog / Verilator (optional)            | local                 |
| DV (UVM)   | Commercial simulator (Questa/VCS/Xcelium)        | sim host              |
| ASIC       | OpenLane (Yosys + OpenROAD + Magic/Netgen), sky130A | separate Linux machine |
| FPGA       | Vivado, Arty A7-100T                             | local                 |
| SW         | riscv32-unknown-elf-gcc                          | sim host              |

See `docs/DECISIONS.md` for all locked design + toolchain decisions and open items.

## Quick start

```bash
make check-tools   # toolchain sanity
make lint          # Verilator lint gate (once RTL exists)
make sim-directed  # directed self-checking TB
make synth-smoke   # Yosys synthesis smoke test (0 errors, 0 latches)
```

## Execution gates (from the implementation plan)

0. Logic design on paper: ALU truth table, D-cache FSM, coherence FSM, arbiter, memory map
1. Core RTL + smoke test (ADDI/ADD/LW/SW/BEQ pass)
2. Cache + coherence + bus RTL, each unit-smoked in isolation
3. **Pivot gate:** top integration + all 10 directed tests pass + clean Yosys smoke — do not proceed otherwise
4. UVM (1000+ random txns, coverage ≥90%) ‖ OpenLane full flow (in parallel)
5. Sign-off (DRC 0 / LVS clean / WNS ≥ 0) + FPGA demo (UART shows coherence, LEDs show events) + architecture doc
