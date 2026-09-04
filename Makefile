# =====================================================================
# Project 05 - Dual-Core RV32I SoC with Coherent Memory Subsystem
# Build & run orchestration
#
# Toolchain (locked 2026-09-04, see docs/DECISIONS.md):
#   Simulation : commercial simulator (SIM=vsim | xrun | vcs), UVM-capable
#   ASIC       : OpenLane on a separate Linux machine (sky130A)
#   FPGA       : Vivado, Arty A7-100T (xc7a100t-1csg324)
#   Smoke sim  : Icarus Verilog / Verilator (fast iteration, optional)
# =====================================================================

SIM      ?= vsim                     # vsim | xrun | vcs
SIM_ARGS ?=
TOP      ?= riscv_soc_top
RUN_DIR  ?= build/sim

RTL_DIRS := rtl/core rtl/memory rtl/cache rtl/coherence rtl/bus rtl/peripheral rtl/top
RTL_SRCS := $(wildcard rtl/core/*.sv) \
            $(wildcard rtl/memory/*.sv) \
            $(wildcard rtl/cache/*.sv) \
            $(wildcard rtl/coherence/*.sv) \
            $(wildcard rtl/bus/*.sv) \
            $(wildcard rtl/peripheral/*.sv) \
            $(wildcard rtl/top/*.sv)

.PHONY: help check-tools lint sim-directed uvm synth-smoke openlane fpga clean

help:
	@echo "Targets:"
	@echo "  check-tools  - verify required tools are on PATH"
	@echo "  lint         - Verilator lint of all RTL (fast syntax/style gate)"
	@echo "  sim-directed - compile + run directed self-checking testbench"
	@echo "  uvm          - compile + run UVM environment"
	@echo "  synth-smoke  - Yosys synthesis smoke test of \$$($(TOP)) (0 errors, 0 latches)"
	@echo "  openlane     - reminder: OpenLane runs on the separate Linux machine"
	@echo "  fpga         - reminder: Vivado project lives in fpga/vivado"
	@echo "  clean        - remove build/ artifacts"

check-tools:
	@echo "== Toolchain sanity =="
	@command -v $(SIM) >/dev/null 2>&1 && echo "[OK] $(SIM)" || echo "[--] $(SIM) not on this machine (run on sim host)"
	@command -v yosys >/dev/null 2>&1 && echo "[OK] yosys" || echo "[--] yosys not on this machine (Linux/OpenLane host)"
	@command -v verilator >/dev/null 2>&1 && echo "[OK] verilator" || echo "[--] verilator not on this machine (optional)"
	@command -v vivado >/dev/null 2>&1 && echo "[OK] vivado" || echo "[--] vivado not on this machine (FPGA host)"
	@command -v riscv32-unknown-elf-gcc >/dev/null 2>&1 && echo "[OK] riscv32-unknown-elf-gcc" || echo "[--] riscv32-unknown-elf-gcc not on this machine"

lint:
	@test -n "$(RTL_SRCS)" || { echo "No RTL sources yet - nothing to lint."; exit 1; }
	verilator --lint-only -Wall --top-module $(TOP) $(RTL_SRCS)

sim-directed:
	@test -f tb/directed/tb_directed.sv || { echo "tb/directed/tb_directed.sv does not exist yet."; exit 1; }
	@test -f rtl/top/$(TOP).sv || { echo "rtl/top/$(TOP).sv does not exist yet."; exit 1; }
	mkdir -p $(RUN_DIR)
	@case "$(SIM)" in \
	  vsim) vlib $(RUN_DIR)/work && vlog -sv $(RTL_SRCS) tb/directed/tb_directed.sv && \
	        vsim -c tb_directed $(SIM_ARGS) -do "run -all; quit" ;; \
	  xrun) xrun -sv $(RTL_SRCS) tb/directed/tb_directed.sv $(SIM_ARGS) ;; \
	  vcs)  vcs -sverilog $(RTL_SRCS) tb/directed/tb_directed.sv && ./simv $(SIM_ARGS) ;; \
	  *)    echo "Unknown SIM=$(SIM)"; exit 1 ;; \
	esac

uvm:
	@test -f tb/uvm/tb_uvm.sv || { echo "tb/uvm/tb_uvm.sv does not exist yet."; exit 1; }
	mkdir -p $(RUN_DIR)
	@echo "NOTE: UVM flags are simulator-specific; fill in per your commercial sim."

synth-smoke:
	@test -f rtl/top/$(TOP).sv || { echo "rtl/top/$(TOP).sv does not exist yet."; exit 1; }
	yosys -p "read_verilog -sv $(RTL_SRCS); hierarchy -check -top $(TOP); proc; opt; synth -top $(TOP); stat"

openlane:
	@echo "OpenLane runs on the dedicated Linux machine (sky130A)."
	@echo "1) rsync the repo there, 2) place openlane/config.json, 3) run the flow,"
	@echo "4) copy reports into reports/ and the GDS screenshot into reports/physical/."

fpga:
	@echo "Create/open the Vivado project under fpga/vivado (top: fpga_top.sv,"
	@echo "constraints: constraints/fpga.xdc, target: xc7a100t-1csg324)."

clean:
	rm -rf build/ work/ xsim.dir/ *.jou transcript simv* csrc/ *.vcd
