# 08 — Memory Subsystem: `sram_reg_array.sv`, `i_sram.sv`, `shared_sram.sv`

Decision D7/O1: all memories are parameterized **register arrays** — zero OpenRAM macro integration
pain in OpenLane, fully synthesizable, identical RTL for ASIC and FPGA (FPGA maps them to BRAM/LUTRAM).

---

## 8.1 `sram_reg_array.sv` — the generic primitive

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `DEPTH` | 1024 | words |
| `WIDTH` | 32 | bits |
| `ASYNC_READ` | 0 | 0 = synchronous read (BRAM-friendly), 1 = asynchronous read (LUTRAM, single-cycle fetch) |

```systemverilog
logic [WIDTH-1:0] mem [DEPTH];

// write: synchronous, byte-masked
always_ff @(posedge clk)                       // rst not needed for contents
  if (we) for (int b = 0; b < WIDTH/8; b++)
    if (wmask[b]) mem[addr[...]][8b+:8] <= wdata[8b+:8];

// read
generate if (ASYNC_READ)  assign rdata = mem[raddr[...]];
          else            always_ff @(posedge clk) rdata <= mem[raddr[...]];
```

Ports: `we, waddr, wdata, wmask, raddr, rdata`. No reset on contents (memory arrays don't take async
reset — Yosys would refuse); control logic around them does.

## 8.2 `i_sram.sv` — private instruction SRAM (×2)

| Property | Value |
|----------|-------|
| Size | 1 KB = 256 × 32 (per core) |
| Ports | 1 read port (fetch) + init write port (TB `$readmemh` / FPGA init) |
| Read mode | **`ASYNC_READ = 1`** — same-cycle instruction, keeps the core truly single-cycle (doc 03 §8) |
| Init | sim: `$readmemh("sw/coreN.hex", mem)` inside an `initial` in the **TB wrapper** (not RTL); FPGA: BRAM init from `.mem` via Vivado |
| Addressing | word-addressed by `imem_addr[9:2]` |

Note: TRD allows "1 KB (256 words) per core, configurable". O1 shrinks ASIC sizes if area demands —
parameterize `DEPTH` so the same RTL serves both (O1).

## 8.3 `shared_sram.sv` — the shared data SRAM (AXI-Lite slave)

| Property | Value |
|----------|-------|
| Size | 4 KB = 1024 × 32 |
| Type | `sram_reg_array` with `ASYNC_READ = 0` (1-cycle read latency) |
| Interface | AXI4-Lite slave (doc 07 §7.5 template) |
| Addressing | word index = `s_araddr[11:2]` / `s_awaddr[11:2]` |

Internals:

- Write: on AW+W both accepted → `mem[awaddr[11:2]] <= wdata` with `wstrb` byte masking → `bvalid`,
  `bresp=OKAY`.
- Read: on AR accepted → next cycle `rvalid=1, rdata=mem[araddr[11:2]], rresp=OKAY` (the register
  array's sync read supplies exactly this latency).
- The cache mgr's FSM (doc 04) absorbs this latency — the core only sees `dmem_ack` when the whole
  AXI read/write completed.

## 8.4 Timing summary (memory-related, uncontended; per doc 13 traces)

| Path | Core-visible cycles (req → ack) | Sequence |
|------|---------------------------------|----------|
| Instruction fetch | 0 (async read, same cycle) | — |
| D-cache load **hit** | 3 | req, CHECK, HIT_READ(ack) |
| Load miss (fill) | ~9 | req, CHECK, MISS_READ, AXI_AR, AXI_R, FILL(ack) +arbiter wait |
| Store **hit** | 6 | req, CHECK, HIT_WRITE, AXI_AW, AXI_W, AXI_B(ack) |
| Store miss (allocate + write-through) | ~10 | load-miss path then AW→W→B |

The core is stalled (`STALL_MEM`) for all but the first of these cycles; non-memory instructions still
complete in exactly 1 cycle. Contended bus adds arbiter wait cycles only.

## 8.5 Why register arrays (D7 rationale, recorded for the architecture doc)

- OpenRAM macros would need `.lib/.lef/.gds` + Yosys black-boxing + OpenLane macro placement — days of
  integration risk on a 5-day schedule.
- Sizes are tiny (1 KB + 1 KB + 4 KB = 6 KB ≈ 49k configuration flops at full size — O1 may shrink
  shared SRAM to 256 words for the ASIC run; the RTL parameter makes that a one-line change).
- Timing at 20 MHz is trivial for register arrays; FPGA maps the shared SRAM to BRAM when `ASYNC_READ=0`
  and Vivado recognizes the read-during-write-free pattern.
