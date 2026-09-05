# 09 — Peripherals: `mmio_regs.sv`, `uart_core.sv`, `gpio_led.sv`

All three are AXI4-Lite slaves built on the doc 07 §7.5 response template. Names/offsets follow the
corrected TRD register maps (see 00_README "TRD table corrections").

---

## 9.1 MMIO registers (`mmio_regs.sv`) — base `0x0001_0000`

| Offset | Name | Access | Width | Description |
|--------|------|--------|-------|-------------|
| 0x00 | COH_STATUS | RO | 16 (in 32) | 8 × 2-bit coherence mirror (doc 05 §5.2) |
| 0x04 | INV_COUNT | RO | 32 | total invalidations dispatched (increment on `inv_fire`) |
| 0x08 | HIT_COUNT | RO | 32 | total d-cache hits (increment on `hit0\|hit1`) |
| 0x0C | MISS_COUNT | RO | 32 | total d-cache misses (increment on `miss0\|miss1`) |
| 0x10 | DOORBELL | RW | 32 | core-to-core doorbell value (software protocol, below) |
| 0x14 | CONTROL | RW | 32 | bit0 `coh_enable` (reset 1), bit1 `cnt_clear` (write-1 pulse), bit2 `err_clear` (write-1 pulse) |
| — | ERR_STICKY | RO | 1 | exposed as CONTROL-adjacent status or top bit of COH_STATUS: sticky, set by `err_event`, cleared by `err_clear` (R5/O3) |

Logic:

- Read mux is combinational over the register values; response per template (rvalid next cycle).
- Counter increments are synchronous: `HIT_COUNT <= HIT_COUNT + (hit0|hit1)` etc. Reset → 0;
  `cnt_clear` pulse → 0 (takes priority).
- `coh_enable` resets to 1; a write of bit0 replaces it.
- DOORBELL is a plain RW register. **Software protocol** (documented for demo SW): core 0 writes a
  nonzero token to signal core 1; core 1 polls until nonzero, then writes 0 to acknowledge. (No
  per-core interrupts exist in scope.)

## 9.2 UART (`uart_core.sv`) — base `0x0001_0100`, 115200 8N1

Register map:

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | TX_DATA | W | write byte to transmit (ignored if TX busy) |
| 0x04 | TX_STATUS | R | bit0 = TX ready (1 = idle, new byte accepted) |
| 0x08 | RX_DATA | R | last received byte (read clears RX valid) |
| 0x0C | RX_STATUS | R | bit0 = RX valid (byte pending) |

### Baud generator

50 MHz / 115200 = 434.03 → divider `BAUD_DIV = 434`, 10-bit counter. Same counter (÷16 oversample
phase) is reused by RX for mid-bit sampling: sample point = 8/16 of the bit period after the start-bit
edge, then every full bit period.

### TX FSM (2-bit state + 4-bit bit-counter + 8-bit shift reg)

| State | Encoding | Condition | Next | Actions |
|-------|----------|-----------|------|---------|
| TX_IDLE | 00 (reset) | TX_DATA written & ready | TX_START | load shift = {1'b1 (stop), tx_byte, 1'b0 (start)} = 10 bits |
| TX_IDLE | else | TX_IDLE | — | `tx=1` (line idle high), TX_STATUS.ready=1 |
| TX_START | 01 | baud tick | TX_DATA_F | shift out bit0 (start bit) |
| TX_DATA_F | 10 | baud tick ×8 | TX_STOP | shift data bits LSB-first, `tx = shift[0]` |
| TX_STOP | 11 | baud tick | TX_IDLE | `tx = 1` (stop bit) |

Reset: state TX_IDLE, `tx=1`, ready=1.

### RX FSM (2-bit state + sample counter)

| State | Condition | Next | Actions |
|-------|-----------|------|---------|
| RX_IDLE | `rx==0` detected (2-sample majority for glitch filter) | RX_START | arm sample counter |
| RX_START | mid-bit sample point | RX_DATA | verify `rx==0` (else back to IDLE); reset counter |
| RX_DATA | 8 mid-bit samples | RX_STOP | collect bits LSB-first into rx_byte |
| RX_STOP | mid-bit sample | RX_IDLE | if `rx==1`: `RX_DATA←rx_byte, rx_valid←1` (framing error otherwise: set sticky UART status bit, drop byte) |

Reset: RX_IDLE, `rx_valid=0`. Synchronize the `rx` pin through 2 FFs (doc 12 §12.4).

## 9.3 GPIO / LED (`gpio_led.sv`) — base `0x0001_0200`

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | LED_REG | RW | bits[7:6] drive LED7–LED6 (software); bits[5:0] read back 0 |

## 9.4 LED mapping (R8) — merged in `gpio_led` or top

| LED | Source | Behavior |
|-----|--------|----------|
| LED0 | core0 heartbeat | `dmem_ack0` stretched to 2²² cycles (≈84 ms @ 50 MHz) |
| LED1 | core1 heartbeat | `dmem_ack1` stretched |
| LED2 | coherence event | `inv_fire` stretched |
| LED3 | cache hit | `hit0\|hit1` stretched |
| LED4 | cache miss | `miss0\|miss1` stretched |
| LED5 | error | `err_sticky` (level) |
| LED6–7 | SW | LED_REG[7:6] |

Stretcher: on event pulse → counter load 2²²−1 → count down → LED high while counter ≠ 0. This makes
blink-rate human-visible and gives the FPGA demo its "activity + events" channel (FR-6.3, NFR-5.3).

## 9.5 Reset values

All peripheral registers reset to 0 except: TX line idle high, `coh_enable=1`, TX ready=1.
