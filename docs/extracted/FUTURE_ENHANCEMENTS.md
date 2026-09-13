# Future Enhancements: RISC-V Dual-Core SoC with Coherent Memory Subsystem

**Project**: Dual-Core RV32I SoC with Coherent Memory Subsystem  
**Document Type**: Future Enhancements & Commercial Readiness Roadmap  
**Version**: 1.0  
**Date**: September 7, 2026  
**Author**: arafi (shearafi5-tech)  
**Status**: Post-Capstone Enhancement Planning

---

## 1. Executive Summary

The current capstone implementation successfully delivers a functionally correct,
well-verified dual-core RV32I SoC with a coherent memory subsystem. All architectural
requirements have been met: RV32I ISA compliance, 4-state I/S/M coherence protocol,
AXI4-Lite bus fabric, write-through cache, and a full peripheral set (UART, GPIO, MMIO).

This document outlines the path from the current **academically complete** design to a
**commercially deployable** SoC. The enhancements are organized into four phases aligned
with industry practice: Security Hardening, Performance Scaling, Verification Closure,
and Long-Term Architecture Evolution. None of these enhancements modify the existing
verified architecture — they extend it.

**Current Status Assessment**

| Dimension            | Current Score | Target (Commercial) |
|----------------------|:-------------:|:-------------------:|
| Functional Correctness | 10/10       | 10/10               |
| Security             | 4/10          | 9/10                |
| Performance          | 5/10          | 8/10                |
| Verification         | 6/10          | 9/10                |
| Code Quality         | 9/10          | 10/10               |
| **Overall**          | **7.5/10**    | **9.5/10**          |

---

## 2. Phase 1 — Security Hardening (Highest Priority)

Security is the largest gap between the current design and production readiness.
The following enhancements address the four primary security threat categories
identified in the project's threat model: memory safety, access control,
side-channel leakage, and denial-of-service.

### 2.1 Memory Protection Unit (MPU)

**Priority**: Critical for any real deployment  
**Estimated Effort**: 3–5 days RTL + 2 days verification  
**Threat Addressed**: Privilege escalation, unauthorized memory access, code injection

**Description**:  
The current design allows any core to read or write any address in the system memory
map without restriction. A hardware MPU enforces region-based access control at the
bus level.

**Proposed Implementation**:
- 8-region MPU table per core, stored in MMIO-accessible registers
- Each region: `{base_addr[31:4], size_log2[4:0], R, W, X, privilege_level[1:0]}`
- Permission check inserted between the core's AXI master output and the bus arbiter
- Violation generates a precise exception (trap to machine mode handler)
- Supervisor mode can reconfigure regions; user mode cannot

**RTL Insertion Point**:  
A new module `mpu_checker.sv` inserted between `rv32i_core.sv` AXI outputs and
`axi_lite_arbiter.sv` input. Zero changes to existing verified modules.

```
rv32i_core → [mpu_checker] → axi_lite_arbiter → axi_lite_decoder → slaves
```

**Key Registers** (added to `mmio_regs.sv` address map):

| Register         | Address     | Description                        |
|------------------|-------------|------------------------------------|
| `MPU_CTRL`       | `0x0001_0080`| Enable/disable MPU per core        |
| `MPU_REGION_n`   | `0x0001_0090`+| 8 region descriptors per core     |
| `MPU_FAULT_ADDR` | `0x0001_00B0`| Address that triggered last fault  |
| `MPU_FAULT_TYPE` | `0x0001_00B4`| Fault type (R/W/X violation)       |

---

### 2.2 Cache Timing Side-Channel Mitigation

**Priority**: Required for any cryptographic use case  
**Estimated Effort**: 2–3 days RTL  
**Threat Addressed**: Cache timing attacks (Flush+Reload, Prime+Probe style)

**Description**:  
The current cache hit path completes in 1 cycle; a miss takes 10+ cycles. An
attacker co-located on the other core can measure execution time to infer which
cache lines the victim core is accessing — a well-known attack vector against
cryptographic implementations.

**Proposed Mitigations**:

1. **Cache Flush on Context Switch**:  
   Add a `CACHE_FLUSH` command to `mmio_regs.sv`. When written, the cache manager
   FSM transitions through a flush sequence that invalidates all lines before
   returning to IDLE. Cost: 4 cycles minimum. Triggered by OS on any privilege
   level change.

2. **Constant-Time Cache Access Option**:  
   Add a `CONST_TIME` bit to the per-core cache control register. When set,
   the cache manager always takes the same number of cycles regardless of hit/miss
   (padding hit path with bubble cycles to match miss latency). Used only when
   running security-sensitive code.

3. **Cache Partitioning**:  
   Long-term: replace the 4-line direct-mapped cache with a 2-way set-associative
   design where each core is locked to its own way. Cross-core cache eviction is
   eliminated by hardware partition enforcement.

---

### 2.3 Bus Transaction Authentication

**Priority**: Medium (relevant for multi-tenant or DMA-capable systems)  
**Estimated Effort**: 2–3 days RTL  
**Threat Addressed**: Unauthorized bus mastering, transaction spoofing

**Description**:  
The AXI4-Lite bus carries no identity information. In a system with DMA engines or
additional bus masters, any master can access any slave. Adding a transaction ID
and privilege level to the bus fabric enables per-slave access control.

**Proposed Implementation**:

- Extend the AXI USER sideband field (AXI4 spec allows this) to carry:
  - `master_id[3:0]` — identity of the originating master
  - `priv_level[1:0]` — privilege level of the originating transaction (M/S/U)
- Each slave module receives these sideband signals
- `mmio_regs.sv` and peripheral modules check `priv_level` against a configurable
  access policy register before completing transactions
- Violations return AXI SLVERR response (not DECERR) with a fault logged to MMIO

**RTL Insertion Point**:  
Sideband wires added to `axi_lite_arbiter.sv`, `axi_lite_decoder.sv`, and slave
port declarations. Existing handshake logic unchanged.

---

### 2.4 Debug Interface Security

**Priority**: Required for silicon tape-out or production FPGA deployment  
**Estimated Effort**: 2–3 days  
**Threat Addressed**: Physical attacks, firmware extraction, production lock

**Description**:  
JTAG/TAP debug access provides full visibility into register state, memory contents,
and execution flow. Without authentication, physical access equals full compromise.

**Proposed Implementation**:

1. **Debug Authentication Register**:  
   A one-time-programmable (OTP) or fuse-based 128-bit key. Debug access requires
   a challenge-response protocol (HMAC-SHA256 or similar) before the TAP controller
   is enabled.

2. **Debug Lockout**:  
   After 3 failed authentication attempts, a sticky bit disables all debug access
   until the next power cycle. The sticky bit is in a register that can only be
   cleared by a full power-on reset, not a soft reset.

3. **Secure Boot Integration**:  
   The reset synchronizer in `riscv_soc_top.sv` can be extended to check a
   `BOOT_SECURE` fuse. If set, the boot ROM address is locked and cannot be
   redirected via debug.

---

### 2.5 UART Input Validation & Buffer Overflow Prevention

**Priority**: Medium  
**Estimated Effort**: 1–2 days RTL  
**Threat Addressed**: DoS via UART flooding, buffer overflow

**Description**:  
The current `uart_core.sv` receiver has no FIFO. If the software doesn't read the
received byte before the next byte arrives, the first byte is silently overwritten.
At high baud rates or under software load, this is a data-loss vulnerability that
can also be exploited for DoS.

**Proposed Implementation**:
- Replace the single-register RX path with a 16-deep synchronous FIFO
- Add an `RX_OVERFLOW` status bit in the UART status register
- Add an `RX_THRESHOLD` interrupt (interrupt when FIFO depth > N)
- The overflow bit is sticky — cleared only by explicit software write
- FIFO occupancy exposed as a read-only MMIO register for software flow control

---

## 3. Phase 2 — Performance Scaling

These enhancements improve throughput and latency without changing the verified
coherence protocol or bus fabric architecture.

### 3.1 Increase Cache Capacity

**Priority**: High (biggest return for lowest effort)  
**Estimated Effort**: < 1 day (parameter change + verification rerun)  
**Performance Impact**: 3–10× cache hit rate improvement for typical workloads

**Description**:  
The current cache is 4 lines × 1 word = 16 bytes per core. This is intentionally
minimal for the capstone demonstration of the coherence protocol. For any real
workload, a 16-byte cache has a miss rate approaching 100%.

**Proposed Changes**:

| Parameter       | Current | Near-term | Production |
|-----------------|:-------:|:---------:|:----------:|
| `LINES`         | 4       | 64        | 256        |
| Words per line  | 1       | 1         | 4          |
| Total per core  | 16 B    | 256 B     | 4 KB       |
| Total (2 cores) | 32 B    | 512 B     | 8 KB       |

The `LINES` parameter change in `d_cache.sv` is a single line edit. Increasing
words per line requires a cache line refill burst in `d_cache_mgr.sv` (see §3.3).

**No coherence protocol changes required** — the I/S/M state is tracked per line
regardless of line size.

---

### 3.2 Cache Associativity (2-Way Set-Associative)

**Priority**: Medium  
**Estimated Effort**: 2–3 days RTL  
**Performance Impact**: 20–40% hit rate improvement over direct-mapped for same capacity

**Description**:  
Direct-mapped caches suffer from conflict misses when two frequently-accessed
addresses map to the same line. A 2-way set-associative design adds a second
"way" to each set, allowing two lines with the same index to coexist.

**Proposed Implementation**:
- `d_cache.sv` extended to `WAYS = 2` parameter
- LRU (Least Recently Used) replacement policy: 1 bit per set tracks which way
  was most recently accessed; evict the other way on miss
- Hit detection checks both ways in parallel (no latency increase)
- `d_cache_mgr.sv` fill path selects the LRU way for replacement
- Coherence controller receives `way_id` alongside `line_idx` for precise
  invalidation targeting

---

### 3.3 AXI4 Burst Support for Cache Line Fill

**Priority**: Medium  
**Estimated Effort**: 2–3 days RTL  
**Performance Impact**: Reduces cache fill latency by 60–80% for multi-word lines

**Description**:  
The current AXI4-Lite interface supports only single-word transfers. When cache
lines grow beyond one word (§3.1 near-term target), each fill requires multiple
sequential AR/R transactions. AXI4 full (not AXI4-Lite) supports bursts of up
to 256 beats in a single address transaction.

**Proposed Changes**:
- Upgrade `d_cache_mgr.sv` AXI master from AXI4-Lite to AXI4 (add `arlen`,
  `arsize`, `arburst` signals; add `rlast` handling)
- `axi_lite_decoder.sv` renamed `axi_decoder.sv`; burst fields forwarded to SRAM
- `shared_sram.sv` upgraded to handle `wlast`/`rlast` sequencing
- AXI4-Lite peripheral slaves (MMIO, UART, GPIO) unchanged — they are wrapped
  with a burst-to-single adapter (standard AXI4 infrastructure pattern)

**Burst fill sequence** (4-word line, INCR burst):
```
Cycle 1: AR: addr=BASE, len=3, burst=INCR
Cycle 2: R:  data[0], rlast=0
Cycle 3: R:  data[1], rlast=0
Cycle 4: R:  data[2], rlast=0
Cycle 5: R:  data[3], rlast=1  → transition to FILL state
```
4 words filled in 5 cycles vs. 4 × 4 = 16 cycles with single transactions.

---

### 3.4 5-Stage Pipeline for RV32I Core

**Priority**: Medium (significant effort, significant return)  
**Estimated Effort**: 4–6 days RTL + 3 days verification  
**Performance Impact**: 2–4× IPC improvement; enables future ISA extensions

**Description**:  
The current single-cycle core executes one instruction per clock but stalls on
every memory access. A classic 5-stage pipeline (IF/ID/EX/MEM/WB) with forwarding
and hazard detection achieves near-1 IPC on arithmetic workloads.

**Pipeline Stages**:

| Stage | Function                          | New Hardware                     |
|-------|-----------------------------------|----------------------------------|
| IF    | Fetch instruction from I-SRAM     | PC register, I-SRAM interface    |
| ID    | Decode, read register file        | IF/ID pipeline register          |
| EX    | ALU, branch resolution            | ID/EX pipeline register, forward mux |
| MEM   | Data cache access                 | EX/MEM pipeline register, stall logic |
| WB    | Write back to register file       | MEM/WB pipeline register         |

**Hazard Handling**:
- Data hazards: forwarding paths EX→EX, MEM→EX, WB→EX
- Load-use hazard: 1-cycle stall (insert bubble between LD and dependent instruction)
- Branch hazard: flush IF/ID on taken branch (1-cycle penalty), static predict-not-taken
- Structural hazard: cache manager stall signal propagates as pipeline freeze

**Coherence Integration**:  
The coherence controller interfaces only with the MEM stage. No changes to
`coherence_ctrl.sv` required — the pipeline simply presents memory requests
to the cache manager from the MEM stage exactly as the current core does from
its single execution stage.

---

### 3.5 Write Buffer for Write-Through Cache

**Priority**: Low–Medium  
**Estimated Effort**: 1–2 days RTL  
**Performance Impact**: Eliminates write-stall penalty on sequential stores

**Description**:  
The current write-through cache blocks the core during every store until the AXI
write transaction completes (AW → W → B channel). A write buffer decouples the
core from the bus: the core posts the write to a small FIFO and continues
executing; the buffer drains to SRAM in the background.

**Proposed Implementation**:
- 4-entry write buffer FIFO: `{addr[31:0], data[31:0], strb[3:0]}`
- Core gets immediate `dmem_ack` after posting to the buffer (if not full)
- `d_cache_mgr.sv` drains buffer entries when the bus is idle
- On a load that hits a pending write-buffer entry, the data is forwarded
  directly (store-to-load forwarding) — prevents stale read on recent write

---

### 3.6 Branch Prediction

**Priority**: Low  
**Estimated Effort**: 1–2 days RTL (static); 3–4 days (dynamic 2-bit saturating)  
**Performance Impact**: Eliminates 1-cycle branch penalty on predicted-correct branches

**Description**:  
The current core resolves all branches in the EX stage (single-cycle) or the MEM
stage (pipelined), always causing a 1-cycle flush of the fetch stage. Static
predict-not-taken is trivially correct for loop exit branches; a 2-bit saturating
counter (bimodal predictor) achieves 80–90% accuracy on typical integer workloads.

**Proposed Static Predictor** (minimal effort):
- Backward branches (negative immediate offset): predict taken (loops)
- Forward branches (positive immediate offset): predict not taken (if-then)
- Flush IF stage only when prediction is wrong
- Expected penalty reduction: from 1 cycle/branch to ~0.2 cycles/branch on
  typical code

---

## 4. Phase 3 — Verification Closure

Bringing verification from the current ~45% code coverage to the 85%+ required
for commercial sign-off.

### 4.1 SystemVerilog Assertions for Coherence Protocol

**Priority**: High  
**Estimated Effort**: 1–2 days  
**Coverage Impact**: Closes the biggest functional verification gap

**Description**:  
The coherence protocol invariants must hold at all times. SVA properties make
these invariants machine-checkable and can be verified in both simulation and
formal tools.

**Key Assertions**:

```systemverilog
// Property: A line cannot be M in both cores simultaneously
assert_no_dual_modified: assert property (
    @(posedge clk) disable iff (!rst_n)
    !(mirror[0][line] == M && mirror[1][line] == M)
) else $error("Coherence violation: line %0d M in both cores", line);

// Property: inv_valid must be held until inv_ack
assert_inv_held: assert property (
    @(posedge clk) disable iff (!rst_n)
    (inv_valid1 && !inv_ack1) |=> inv_valid1
) else $error("inv_valid1 dropped before inv_ack1");

// Property: coh_accept is a 1-cycle pulse only
assert_accept_pulse: assert property (
    @(posedge clk) disable iff (!rst_n)
    coh_accept0 |=> !coh_accept0
) else $error("coh_accept0 held for more than 1 cycle");

// Property: FSM must not stay in INVALIDATE_OTHER indefinitely
assert_inv_terminates: assert property (
    @(posedge clk) disable iff (!rst_n)
    (coh_state == INVALIDATE_OTHER) |-> ##[1:32] (coh_state == COH_IDLE)
) else $error("Coherence deadlock: stuck in INVALIDATE_OTHER");
```

**Formal Verification Target**:  
The above properties are directly usable in Synopsys VC Formal or Cadence
JasperGold for bounded model checking. Proof depth of 20 cycles is sufficient
to cover all reachable coherence protocol paths.

---

### 4.2 AXI4-Lite Protocol Compliance Assertions

**Priority**: High  
**Estimated Effort**: 1–2 days  
**Coverage Impact**: Catches handshake violations that are invisible in directed tests

```systemverilog
// AXI rule: once valid is asserted, it must be held until ready
assert_aw_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    (awvalid_m && !awready_m) |=> awvalid_m
) else $error("AXI violation: awvalid_m dropped before awready_m");

// AXI rule: wdata must be stable while wvalid && !wready
assert_wdata_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    (wvalid_m && !wready_m) |=> $stable(wdata_m)
) else $error("AXI violation: wdata_m changed while wvalid && !wready");

// AXI rule: no write response before write data accepted
assert_b_after_w: assert property (
    @(posedge clk) disable iff (!rst_n)
    bvalid_m |-> $past(wvalid_m && wready_m, 1)
) else $error("AXI violation: bvalid before wready handshake");
```

---

### 4.3 UVM Constrained-Random Verification Completion

**Priority**: Medium  
**Estimated Effort**: 2–3 days  
**Coverage Impact**: Brings functional coverage from ~30% to 80%+

**Coverage Goals**:

| Covergroup                | Target | Current |
|---------------------------|:------:|:-------:|
| Coherence state transitions | 100%  | ~40%    |
| Simultaneous dual-core writes | 100% | ~20%  |
| AXI channel simultaneous activity | 100% | ~30% |
| Cache hit/miss/eviction sequences | 100% | ~50% |
| UART edge cases (framing error, overrun) | 100% | ~10% |
| Reset during mid-transaction | 100% | 0%    |

**New UVM Sequences Required**:
- `coherence_stress_seq`: Both cores write to the same line repeatedly, alternating
  which core has M state. Verifies round-robin arbitration and mirror correctness.
- `simultaneous_channel_seq`: Drive AXI write and read transactions to different
  slaves in the same cycle. Verifies BUG-007 fix holds under stress.
- `reset_mid_txn_seq`: Assert `rst_n` at random points in the AXI transaction
  sequence. Verify all FSMs return to their idle states with correct register values.
- `uart_flood_seq`: Send bytes faster than the software reader; verify overflow flag
  behavior (post-UART enhancement, §2.5).

---

### 4.4 Formal Verification of Critical Paths

**Priority**: Medium  
**Estimated Effort**: 1–2 days setup + tool runtime  
**Coverage Impact**: Proves absence of deadlocks and protocol violations exhaustively

**Targets for Formal**:

1. **Coherence Controller** (`coherence_ctrl.sv`):  
   - Prove liveness: FSM always eventually returns to COH_IDLE
   - Prove safety: no line is simultaneously M in two cores
   - Bounded proof depth: 20 cycles

2. **AXI Decoder** (`axi_lite_decoder.sv`):  
   - Prove channel independence: write-channel outputs depend only on `awaddr_m`
   - Prove DECERR liveness: all unmapped transactions eventually receive a response
   - Bounded proof depth: 10 cycles

3. **Cache Manager** (`d_cache_mgr.sv`):  
   - Prove no NBA in any always_comb block (lint-level, already verified)
   - Prove fill_data_q is always valid when FILL state is active
   - Bounded proof depth: 15 cycles

---

### 4.5 Code Coverage Closure Plan

| Coverage Type       | Current | Target | Action |
|---------------------|:-------:|:------:|--------|
| Line coverage        | ~45%   | 90%    | Add UVM constrained-random sequences |
| Branch coverage      | ~35%   | 85%    | Add directed corner-case tests |
| FSM state coverage   | ~60%   | 100%   | Add explicit state-entry tests |
| Toggle coverage      | ~30%   | 80%    | Enable toggle coverage in simulator |
| Assertion coverage   | ~20%   | 90%    | Add SVA properties (§4.1, §4.2) |
| Functional coverage  | ~30%   | 80%    | Add UVM covergroups per module |

---

## 5. Phase 4 — Long-Term Architecture Evolution

These are architectural directions for a second-generation version of this SoC,
beyond the scope of the current project but worth documenting for continuity.

### 5.1 RISC-V M Extension (Multiply/Divide)

Add hardware multiply and divide to the ALU, enabling RV32IM compliance.
The existing ALU module is cleanly structured for this extension:
- New `alu_func` codes `4'b1000`–`4'b1011` for MUL, MULH, DIV, REM
- Multi-cycle multiply (4 cycles, non-restoring algorithm)
- Divider using iterative subtraction (32 cycles worst case) or a faster radix-4 design

### 5.2 RISC-V A Extension (Atomic Operations)

Add Load-Reserved / Store-Conditional (LR/SC) and AMO instructions for lock-free
synchronization between the two cores. This interacts directly with the coherence
controller — an LR instruction must acquire exclusive ownership (M state) before
the SC can complete. The existing coherence FSM is a natural fit for this extension.

### 5.3 Coherence Protocol Upgrade: MESI

Extend the current I/S/M (3-state) protocol to MESI (Modified/Exclusive/Shared/Invalid).
The Exclusive state allows a single-core read to promote directly to M on a write
without broadcasting an invalidation — reducing coherence bus traffic by up to 50%
on single-reader workloads. The mirror table and FSM would add one state bit and two
new transitions.

### 5.4 L2 Shared Cache

Add a unified L2 cache shared between both cores, interposed between the L1 cache
managers and the shared SRAM. The L2 handles L1 misses locally before going to
DRAM, dramatically reducing traffic on the main memory bus. The coherence controller
would be extended to track L2 inclusion for proper invalidation ordering.

### 5.5 DRAM Controller Integration

Replace the shared SRAM with a DDR3/DDR4 DRAM controller to support larger address
spaces and higher bandwidth. The AXI4 burst support (§3.3) is the prerequisite —
DDR controllers natively accept burst transactions and achieve peak bandwidth only
when bursts are aligned and sequential.

### 5.6 Privilege Levels (RISC-V M/S/U Modes)

Implement the full RISC-V privileged specification:
- Machine mode (M): full hardware access, handles traps
- Supervisor mode (S): OS kernel, manages page tables
- User mode (U): application code, restricted access

This is the foundation for running a real-time OS (FreeRTOS) or a lightweight Linux
kernel on the SoC. The MPU (§2.1) evolves into a full Memory Management Unit (MMU)
with virtual-to-physical address translation.

---

## 6. Implementation Priority Matrix

| Enhancement                  | Effort   | Impact   | Priority | Phase |
|------------------------------|:--------:|:--------:|:--------:|:-----:|
| Memory Protection Unit (MPU) | Medium   | Critical | **P0**   | 1     |
| Cache flush on context switch | Low     | High     | **P0**   | 1     |
| Coherence SVA assertions     | Low      | High     | **P0**   | 3     |
| AXI compliance assertions    | Low      | High     | **P0**   | 3     |
| Increase cache size (LINES)  | Trivial  | High     | **P1**   | 2     |
| UART RX FIFO                 | Low      | Medium   | **P1**   | 1     |
| UVM constrained-random suite | Medium   | High     | **P1**   | 3     |
| Bus transaction authentication| Medium  | Medium   | **P1**   | 1     |
| Debug interface security     | Medium   | High     | **P1**   | 1     |
| AXI4 burst support           | Medium   | High     | **P2**   | 2     |
| 2-way set-associative cache  | Medium   | Medium   | **P2**   | 2     |
| Write buffer                 | Low      | Medium   | **P2**   | 2     |
| Formal verification          | Low      | High     | **P2**   | 3     |
| Cache timing mitigation      | Medium   | Medium   | **P2**   | 1     |
| Branch prediction (static)   | Low      | Low      | **P3**   | 2     |
| 5-stage pipeline             | High     | High     | **P3**   | 2     |
| RISC-V M extension           | Medium   | Medium   | **P3**   | 4     |
| RISC-V A extension           | High     | High     | **P3**   | 4     |
| MESI coherence protocol      | Medium   | Medium   | **P3**   | 4     |
| L2 shared cache              | High     | High     | **P3**   | 4     |
| Privilege levels (M/S/U)     | High     | Critical | **P3**   | 4     |

---

## 7. Commercial Readiness Checklist

The following checklist defines what "commercial ready" means for this class of SoC.
Items marked ✅ are complete in the current capstone implementation.

### Functional Completeness
- ✅ RV32I ISA — all 37 base instructions implemented and decoded
- ✅ Dual-core operation with coherent shared memory
- ✅ AXI4-Lite bus fabric with address decode and DECERR handling
- ✅ Write-through cache with I/S/M coherence protocol
- ✅ UART, GPIO, MMIO peripheral set
- ✅ Reset synchronization (2-FF metastability protection)
- ⬜ RISC-V M extension (multiply/divide)
- ⬜ RISC-V A extension (atomic operations)
- ⬜ Privileged mode support (M/S/U)

### Security
- ✅ Active-low reset with proper synchronizer
- ✅ No multi-driver signals (all BUG-003 issues fixed)
- ✅ Deterministic reset of all registered state
- ⬜ Memory Protection Unit
- ⬜ Bus transaction authentication
- ⬜ Debug interface authentication and lockout
- ⬜ Cache flush mechanism for context switches
- ⬜ UART overflow protection

### Performance
- ✅ Cache hit path — single-cycle latency
- ✅ Coherence protocol — stall-free on non-conflicting accesses
- ⬜ Cache size ≥ 256 lines per core
- ⬜ Multi-word cache lines with burst fill
- ⬜ Write buffer (decoupled store path)
- ⬜ Branch prediction

### Verification
- ✅ All 7 identified RTL bugs fixed and verified
- ✅ Directed testbench covering primary functionality
- ✅ UVM environment structure in place
- ⬜ Code coverage ≥ 90%
- ⬜ Functional coverage ≥ 80%
- ⬜ Coherence protocol SVA properties proven
- ⬜ AXI protocol compliance assertions
- ⬜ Formal verification of critical FSMs
- ⬜ Reset-during-transaction coverage

### Code Quality
- ✅ Consistent `_d`/`_q` naming convention for registered signals
- ✅ No NBA in always_comb blocks
- ✅ No multi-driver signals
- ✅ Complete module documentation headers
- ✅ Doc-referenced design decisions
- ⬜ SVA assertions embedded in all RTL modules
- ⬜ Linting pragmas for intentional constructs
- ⬜ Synthesis constraints file for all critical paths

---

## 8. Conclusion

The capstone implementation delivers a correct, clean, and well-documented RISC-V
dual-core SoC with a coherent memory subsystem. The architecture is sound and the
implementation quality is high — a strong foundation for commercial extension.

The gap between the current state and commercial deployment is not a matter of
correctness (the design is functionally correct) but of hardening: adding the
security controls, performance margins, and verification depth that production
hardware requires. The enhancements described in this document follow a natural
progression and build on the existing verified architecture without requiring
any redesign.

A realistic commercial timeline:
- **Phase 1 (Security)**: 2–3 weeks
- **Phase 2 (Performance)**: 3–4 weeks
- **Phase 3 (Verification)**: 2–3 weeks
- **Phase 4 (Architecture Evolution)**: 2–3 months

Total path to full commercial readiness: approximately **4 months** of focused
engineering effort from the current capstone baseline.

---

*Document prepared for: Dual-Core RV32I SoC with Coherent Memory Subsystem*  
*Repository: https://github.com/shearafi5-tech/RISC-V-SoC-with-Coherent-Memory-Subsystem*  
*Author: arafi @ shearafi5-tech*  
*Date: September 7, 2026*
