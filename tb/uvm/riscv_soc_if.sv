/**
 * @file riscv_soc_if.sv
 * @brief Virtual Interface for RISC-V SoC Verification
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @date Day 4, Task T4.3
 * 
 * Virtual interface connecting UVM testbench to DUT via modport definitions.
 * Enables monitor, sequencer, and driver to access DUT signals safely.
 * 
 * Security: All signal access type-safe and bounded (no uncontrolled casting).
 */

`ifndef RISCV_SOC_IF_SV
`define RISCV_SOC_IF_SV

import uvm_pkg::*;

interface riscv_soc_if (
    input logic clk,
    input logic rst_n
);

    // =====================================================================
    // CLOCK & RESET
    // =====================================================================
    logic clk_local;
    logic rst_n_local;
    
    assign clk_local = clk;
    assign rst_n_local = rst_n;
    
    // =====================================================================
    // CORE DOMAIN SIGNALS (Per-Core)
    // =====================================================================
    
    // Core 0 instruction memory
    logic [31:0] c0_imem_addr;
    logic [31:0] c0_imem_rdata;
    
    // Core 0 data memory interface
    logic        c0_dmem_req;
    logic        c0_dmem_we;
    logic [31:0] c0_dmem_addr;
    logic [31:0] c0_dmem_wdata;
    logic [3:0]  c0_dmem_wmask;
    logic [31:0] c0_dmem_rdata;
    logic        c0_dmem_ack;
    logic        c0_dmem_err;
    
    // Core 1 instruction memory
    logic [31:0] c1_imem_addr;
    logic [31:0] c1_imem_rdata;
    
    // Core 1 data memory interface
    logic        c1_dmem_req;
    logic        c1_dmem_we;
    logic [31:0] c1_dmem_addr;
    logic [31:0] c1_dmem_wdata;
    logic [3:0]  c1_dmem_wmask;
    logic [31:0] c1_dmem_rdata;
    logic        c1_dmem_ack;
    logic        c1_dmem_err;
    
    // =====================================================================
    // CACHE SIGNALS (Per-Core)
    // =====================================================================
    
    logic        c0_cache_hit;
    logic        c0_cache_miss;
    logic        c1_cache_hit;
    logic        c1_cache_miss;
    
    // =====================================================================
    // COHERENCE SIGNALS
    // =====================================================================
    
    logic        coh_inv_fire;
    logic [15:0] coh_status;
    
    // =====================================================================
    // AXI4-Lite SIGNALS (Arbiter Output)
    // =====================================================================
    
    logic        s_awvalid;
    logic [31:0] s_awaddr;
    logic        s_awready;
    logic        s_wvalid;
    logic [31:0] s_wdata;
    logic [3:0]  s_wstrb;
    logic        s_wready;
    logic        s_bvalid;
    logic [1:0]  s_bresp;
    logic        s_bready;
    logic        s_arvalid;
    logic [31:0] s_araddr;
    logic        s_arready;
    logic        s_rvalid;
    logic [31:0] s_rdata;
    logic [1:0]  s_rresp;
    logic        s_rready;
    
    // =====================================================================
    // EVENT SIGNALS
    // =====================================================================
    
    logic        c0_hit_event;
    logic        c0_miss_event;
    logic        c1_hit_event;
    logic        c1_miss_event;
    logic        err_event;
    
    // =====================================================================
    // PERIPHERAL SIGNALS
    // =====================================================================
    
    logic        uart_tx;
    logic        uart_rx;
    logic [7:0]  led;
    
    // =====================================================================
    // MODPORT: MONITOR (Passive Observation)
    // =====================================================================
    
    modport monitor (
        input clk_local, rst_n_local,
        // Core 0 read-only
        input c0_imem_addr, c0_imem_rdata,
        input c0_dmem_req, c0_dmem_we, c0_dmem_addr, c0_dmem_wdata, c0_dmem_wmask,
        input c0_dmem_rdata, c0_dmem_ack, c0_dmem_err,
        // Core 1 read-only
        input c1_imem_addr, c1_imem_rdata,
        input c1_dmem_req, c1_dmem_we, c1_dmem_addr, c1_dmem_wdata, c1_dmem_wmask,
        input c1_dmem_rdata, c1_dmem_ack, c1_dmem_err,
        // Cache signals
        input c0_cache_hit, c0_cache_miss, c1_cache_hit, c1_cache_miss,
        // Coherence
        input coh_inv_fire, coh_status,
        // AXI
        input s_awvalid, s_awaddr, s_awready, s_wvalid, s_wdata, s_wstrb, s_wready,
        input s_bvalid, s_bresp, s_bready, s_arvalid, s_araddr, s_arready,
        input s_rvalid, s_rdata, s_rresp, s_rready,
        // Events
        input c0_hit_event, c0_miss_event, c1_hit_event, c1_miss_event, err_event,
        // Peripherals
        input uart_tx, uart_rx, led
    );
    
    // =====================================================================
    // MODPORT: DRIVER (Active Stimulus)
    // =====================================================================
    
    modport driver (
        input clk_local, rst_n_local,
        // Core 0 drive
        output c0_imem_rdata,
        output c0_dmem_rdata, c0_dmem_ack, c0_dmem_err,
        // Core 1 drive
        output c1_imem_rdata,
        output c1_dmem_rdata, c1_dmem_ack, c1_dmem_err,
        // UART/GPIO
        output uart_tx, led
    );
    
    // =====================================================================
    // MODPORT: TESTBENCH (Full Access, Internal Use Only)
    // =====================================================================
    
    modport tb (
        inout clk_local, rst_n_local,
        inout c0_imem_addr, c0_imem_rdata,
        inout c0_dmem_req, c0_dmem_we, c0_dmem_addr, c0_dmem_wdata, c0_dmem_wmask,
        inout c0_dmem_rdata, c0_dmem_ack, c0_dmem_err,
        inout c1_imem_addr, c1_imem_rdata,
        inout c1_dmem_req, c1_dmem_we, c1_dmem_addr, c1_dmem_wdata, c1_dmem_wmask,
        inout c1_dmem_rdata, c1_dmem_ack, c1_dmem_err,
        inout c0_cache_hit, c0_cache_miss, c1_cache_hit, c1_cache_miss,
        inout coh_inv_fire, coh_status,
        inout s_awvalid, s_awaddr, s_awready, s_wvalid, s_wdata, s_wstrb, s_wready,
        inout s_bvalid, s_bresp, s_bready, s_arvalid, s_araddr, s_arready,
        inout s_rvalid, s_rdata, s_rresp, s_rready,
        inout c0_hit_event, c0_miss_event, c1_hit_event, c1_miss_event, err_event,
        inout uart_tx, uart_rx, led
    );

endinterface : riscv_soc_if

`endif // RISCV_SOC_IF_SV
