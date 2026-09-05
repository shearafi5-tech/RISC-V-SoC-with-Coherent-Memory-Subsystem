# 07 — Address Decoder, DECERR Slave, and the AXI4-Lite Fabric Contract

`axi_lite_decoder.sv` routes the arbiter's shared slave port to exactly one of four slaves (or DECERR).
Pure combinational decode + a tiny DECERR responder FSM. This doc also fixes the AXI4-Lite usage rules
every module obeys and the common slave response template that shared SRAM / MMIO / UART / GPIO follow.

---

## 7.1 Address decode equations

```
sel_sram  = (addr[31:12] == 20'h00000)                    // 0x0000_0000–0x0000_0FFF (4 KB)
sel_mmio  = (addr[31:16] == 16'h0001) && (addr[15:8]  == 8'h00)   // 0x0001_0000–0x0001_00FF
sel_uart  = (addr[31:16] == 16'h0001) && (addr[15:8]  == 8'h01)   // 0x0001_0100–0x0001_01FF
sel_gpio  = (addr[31:16] == 16'h0001) && (addr[15:8]  == 8'h02)   // 0x0001_0200–0x0001_02FF
sel_decerr = !(sel_sram | sel_mmio | sel_uart | sel_gpio)
```

(Decode exact ranges; do not decode address bits below `addr[7:0]` for the peripherals — register
offsets are handled inside each slave.)

## 7.2 Decode truth table

| Address range | Size | Target | Response code |
|---------------|------|--------|---------------|
| `0x0000_0000–0x0000_0FFF` | 4 KB | Shared data SRAM | OKAY |
| `0x0001_0000–0x0001_00FF` | 256 B | MMIO registers | OKAY |
| `0x0001_0100–0x0001_01FF` | 256 B | UART registers | OKAY |
| `0x0001_0200–0x0001_02FF` | 256 B | GPIO / LED | OKAY |
| anything else | — | **DECERR slave** | **DECERR (2'b11)** |

All four selects are mutually exclusive by construction. Reads AND writes use the same address decode
(AXI-Lite: AW and AR addresses decoded independently but never concurrent — arbiter guarantees one
transaction at a time).

## 7.3 DECERR slave FSM (`inside axi_lite_decoder` or as a tiny slave)

Purpose: give unmapped accesses a proper AXI response instead of a hang (FR-5.4, directed test 9).

```
Write: ARB-side AW + W must both be accepted before B is issued.
Read:  AR accepted → R issued next cycle.
```

| State | Condition | Next | Actions |
|-------|-----------|------|---------|
| DEC_W_IDLE (reset) | `awvalid_s` | DEC_W_GOTAW | `aw_got←1` |
| DEC_W_IDLE | `!awvalid_s && wvalid_s` | DEC_W_GOTW | `w_got←1` |
| DEC_W_IDLE | else | DEC_W_IDLE | `awready_s=1, wready_s=1` |
| DEC_W_GOTAW | `wvalid_s` | DEC_B_RESP | `w_got←1` |
| DEC_W_GOTW | `awvalid_s` | DEC_B_RESP | `aw_got←1` |
| DEC_B_RESP | (entry) | DEC_W_IDLE | `bvalid_s=1, bresp_s=DECERR` until `bready_s` |

Read path (independent, since one transaction at a time): on `arvalid_s && arready_s` → next cycle
`rvalid_s=1, rdata_s=32'h0, rresp_s=DECERR`, held until `rready_s`.

## 7.4 AXI4-Lite usage contract (what every master/slave here must obey)

1. Five independent channels; **no bursts** — no `awlen/awsize/awburst/wlast/rlast` signals exist.
2. Valid/ready handshake on every channel; **valid must not wait for ready** (no combinational
   dependency of `*valid` on `*ready` — prevents protocol deadlock).
3. Masters here sequence AW→W→B and AR→R strictly (legal subset; slaves must accept W-before-AW or
   AW-before-W — the SRAM/DECERR slaves do).
4. `wstrb[3:0]` byte enables; slaves write only masked bytes.
5. One outstanding transaction per master, enforced by the arbiter grant.
6. Response codes: OKAY `2'b00`, SLVERR `2'b10`, DECERR `2'b11` (per TRD §3.6; SLVERR reserved for
   slave-internal errors — none used by default; DECERR for decode misses).
7. All signals reset to 0.

## 7.5 Common slave response template (used by SRAM / MMIO / UART / GPIO)

Every slave is a 1-to-3-cycle responder with the same skeleton:

```
Write: awready=1, wready=1 (always ready; one outstanding txn guaranteed by arbiter)
       on (awvalid&&awready && wvalid&&wready)  →  perform write (masked bytes)
                                                 →  bvalid=1, bresp=OKAY, hold until bready
Read:  arready=1
       on (arvalid&&arready) → capture offset → next cycle rvalid=1, rdata=<reg>, rresp=OKAY,
                              hold until rready
```

The shared SRAM's read data is available the cycle after `ar` (register-array sync read, doc 08),
which matches this template exactly; MMIO/UART/GPIO read muxes are combinational but are registered
into `rdata` at the same point to keep one uniform timing.

## 7.6 Assertions (fabric-level)

- `awvalid_s |-> awvalid_s until awready_s` (and W/AR/B/R likewise) — track-doc handshake check.
- `sel_sram + sel_mmio + sel_uart + sel_gpio + sel_decerr == 1` — decode is complete and one-hot
  whenever the bus is active.
- Unmapped address ⇒ `rresp==DECERR || bresp==DECERR` (test 9).
