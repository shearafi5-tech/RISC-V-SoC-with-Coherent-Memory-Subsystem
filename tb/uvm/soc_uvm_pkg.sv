/**
 * @file soc_uvm_pkg.sv
 * @brief UVM Package for RISC-V SoC Verification
 * @project Dual-Core RV32I SoC with Coherent Memory Subsystem
 * @date Day 4, Task T4.4
 * 
 * Contains:
 * - Transaction definitions (mem_txn, coh_event_txn)
 * - Sequencer configurations
 * - Configuration objects
 * - UVM environment base classes
 * 
 * Security: All classes properly encapsulated, no unchecked memory access.
 */

`ifndef SOC_UVM_PKG_SV
`define SOC_UVM_PKG_SV

package soc_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // =====================================================================
    // TRANSACTION: MEMORY ACCESS (mem_txn)
    // =====================================================================
    
    class mem_txn extends uvm_sequence_item;
        `uvm_object_utils(mem_txn)
        
        // Transaction fields (properly typed and bounded)
        rand bit [7:0]   core_id;        // 0 or 1 (2-bit core ID, bounded to 0-1)
        rand bit         is_write;       // 1=write, 0=load
        rand bit [31:0]  addr;           // 32-bit address
        rand bit [31:0]  data;           // Write data or read result
        rand bit [3:0]   wmask;          // Byte write mask
        rand bit         is_cached;      // 1=cached, 0=uncached (MMIO/peripheral)
        rand int unsigned latency;       // Transaction latency (cycles)
        
        // Constraints (security-safe bounds)
        constraint core_id_valid {
            core_id inside {8'h00, 8'h01};  // Only 0 or 1
        }
        
        constraint addr_reasonable {
            // Reasonable address range (not extreme values)
            addr < 32'hFFFF_0000;  // Exclude top 64K for safety
        }
        
        constraint latency_reasonable {
            latency > 0;
            latency < 1000;  // Max 1000 cycles (safety bound)
        }
        
        // Constructor
        function new(string name = "mem_txn");
            super.new(name);
            core_id = 8'h0;
            is_write = 1'b0;
            addr = 32'h0;
            data = 32'h0;
            wmask = 4'hF;
            is_cached = 1'b1;
            latency = 1;
        endfunction
        
        // Convert to string for reporting
        function string convert2string();
            return $sformatf("mem_txn[core=%0d, %s, addr=0x%08x, data=0x%08x, wmask=0x%01x, cached=%b, latency=%0d]",
                           core_id, is_write ? "WRITE" : "READ", addr, data, wmask, is_cached, latency);
        endfunction
        
        // Do copy
        function void do_copy(uvm_object rhs);
            mem_txn rhs_txn;
            if (!$cast(rhs_txn, rhs)) begin
                `uvm_fatal("mem_txn::do_copy", "Cast failed")
            end
            super.do_copy(rhs);
            core_id = rhs_txn.core_id;
            is_write = rhs_txn.is_write;
            addr = rhs_txn.addr;
            data = rhs_txn.data;
            wmask = rhs_txn.wmask;
            is_cached = rhs_txn.is_cached;
            latency = rhs_txn.latency;
        endfunction
    endclass : mem_txn
    
    // =====================================================================
    // TRANSACTION: COHERENCE EVENT (coh_event_txn)
    // =====================================================================
    
    class coh_event_txn extends uvm_sequence_item;
        `uvm_object_utils(coh_event_txn)
        
        typedef enum bit [3:0] {
            HIT,
            MISS,
            INV,
            FILL,
            ERROR
        } event_type_e;
        
        rand event_type_e event_type;    // Type of coherence event
        rand bit [7:0]    core_id;       // Core ID (0 or 1, bounded)
        rand bit [31:0]   addr;          // Address involved
        rand bit [1:0]    old_state;     // Previous coherence state (I/S/M)
        rand bit [1:0]    new_state;     // New coherence state
        rand int unsigned timestamp;     // Cycle timestamp
        
        constraint core_id_valid {
            core_id inside {8'h00, 8'h01};  // Only 0 or 1
        }
        
        constraint state_valid {
            old_state inside {2'b00, 2'b01, 2'b10};  // I, S, or M only
            new_state inside {2'b00, 2'b01, 2'b10};
        }
        
        // Constructor
        function new(string name = "coh_event_txn");
            super.new(name);
            event_type = HIT;
            core_id = 8'h0;
            addr = 32'h0;
            old_state = 2'b00;  // I
            new_state = 2'b00;
            timestamp = 0;
        endfunction
        
        // Convert to string
        function string convert2string();
            string event_str = event_type.name();
            string old_state_str = (old_state == 2'b00) ? "I" : (old_state == 2'b01) ? "S" : "M";
            string new_state_str = (new_state == 2'b00) ? "I" : (new_state == 2'b01) ? "S" : "M";
            return $sformatf("coh_event[%s, core=%0d, addr=0x%08x, %s→%s, t=%0d]",
                           event_str, core_id, addr, old_state_str, new_state_str, timestamp);
        endfunction
        
        // Do copy
        function void do_copy(uvm_object rhs);
            coh_event_txn rhs_txn;
            if (!$cast(rhs_txn, rhs)) begin
                `uvm_fatal("coh_event_txn::do_copy", "Cast failed")
            end
            super.do_copy(rhs);
            event_type = rhs_txn.event_type;
            core_id = rhs_txn.core_id;
            addr = rhs_txn.addr;
            old_state = rhs_txn.old_state;
            new_state = rhs_txn.new_state;
            timestamp = rhs_txn.timestamp;
        endfunction
    endclass : coh_event_txn
    
    // =====================================================================
    // CONFIGURATION OBJECT
    // =====================================================================
    
    class soc_config extends uvm_object;
        `uvm_object_utils(soc_config)
        
        // Configuration parameters
        bit enable_coverage = 1'b1;
        bit enable_checks = 1'b1;
        bit enable_logging = 1'b1;
        int max_transactions = 10000;  // Max txns in random test
        int seed = 1234;               // RNG seed
        
        function new(string name = "soc_config");
            super.new(name);
        endfunction
    endclass : soc_config
    
    // =====================================================================
    // COLLECTOR: Memory Transaction Collector
    // =====================================================================
    
    class mem_collector extends uvm_monitor;
        `uvm_component_utils(mem_collector)
        
        virtual riscv_soc_if vif;
        uvm_analysis_port #(mem_txn) ap_out;
        
        mem_txn txn;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_out = new("ap_out", this);
        endfunction
        
        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual riscv_soc_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("mem_collector::build_phase", "Virtual interface not found")
            end
        endfunction
        
        task run_phase(uvm_run_phase phase);
            forever begin
                @(posedge vif.clk_local);
                
                // Monitor core 0 memory transactions
                if (vif.c0_dmem_ack) begin
                    txn = mem_txn::type_id::create("txn");
                    txn.core_id = 8'h0;
                    txn.is_write = vif.c0_dmem_we;
                    txn.addr = vif.c0_dmem_addr;
                    txn.data = vif.c0_dmem_we ? vif.c0_dmem_wdata : vif.c0_dmem_rdata;
                    txn.wmask = vif.c0_dmem_wmask;
                    txn.is_cached = (vif.c0_dmem_addr[31:12] == 20'h00000) ? 1'b1 : 1'b0;
                    ap_out.write(txn);
                end
                
                // Monitor core 1 memory transactions
                if (vif.c1_dmem_ack) begin
                    txn = mem_txn::type_id::create("txn");
                    txn.core_id = 8'h1;
                    txn.is_write = vif.c1_dmem_we;
                    txn.addr = vif.c1_dmem_addr;
                    txn.data = vif.c1_dmem_we ? vif.c1_dmem_wdata : vif.c1_dmem_rdata;
                    txn.wmask = vif.c1_dmem_wmask;
                    txn.is_cached = (vif.c1_dmem_addr[31:12] == 20'h00000) ? 1'b1 : 1'b0;
                    ap_out.write(txn);
                end
            end
        endtask
    endclass : mem_collector
    
    // =====================================================================
    // SCOREBOARD: Reference Model Comparison
    // =====================================================================
    
    class soc_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(soc_scoreboard)
        
        uvm_analysis_imp #(mem_txn, soc_scoreboard) ap_in;
        
        int hits = 0;
        int misses = 0;
        int invalidations = 0;
        int errors = 0;
        int total_txns = 0;
        
        // Reference model: golden memory
        bit [31:0] golden_mem [bit [31:0]];  // Associative array (safe from overflow)
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_in = new("ap_in", this);
        endfunction
        
        function void write(mem_txn txn);
            total_txns++;
            
            if (txn.is_write) begin
                // Write: update golden memory
                for (int i = 0; i < 4; i++) begin
                    if (txn.wmask[i]) begin
                        if (golden_mem.exists(txn.addr + i)) begin
                            golden_mem[txn.addr + i] = (txn.data >> (i*8)) & 8'hFF;
                        end else begin
                            golden_mem[txn.addr + i] = (txn.data >> (i*8)) & 8'hFF;
                        end
                    end
                end
                `uvm_info("soc_scoreboard", $sformatf("Write: %s", txn.convert2string()), UVM_MEDIUM)
            end else begin
                // Read: compare with golden model
                if (golden_mem.exists(txn.addr)) begin
                    if (golden_mem[txn.addr] == txn.data) begin
                        hits++;
                        `uvm_info("soc_scoreboard", $sformatf("Read HIT: %s", txn.convert2string()), UVM_MEDIUM)
                    end else begin
                        `uvm_error("soc_scoreboard", $sformatf("Data mismatch: %s (expected 0x%08x)", 
                                  txn.convert2string(), golden_mem[txn.addr]))
                    end
                end else begin
                    misses++;
                    `uvm_info("soc_scoreboard", $sformatf("Read MISS: %s", txn.convert2string()), UVM_MEDIUM)
                end
            end
        endfunction
        
        function void report_phase(uvm_report_phase phase);
            super.report_phase(phase);
            `uvm_info("soc_scoreboard", 
                     $sformatf("=== SCOREBOARD REPORT ===\nTotal Transactions: %0d\nHits: %0d\nMisses: %0d\nErrors: %0d",
                              total_txns, hits, misses, errors), UVM_LOW)
        endfunction
    endclass : soc_scoreboard
    
    // =====================================================================
    // ENVIRONMENT
    // =====================================================================
    
    class soc_env extends uvm_env;
        `uvm_component_utils(soc_env)
        
        soc_config cfg;
        mem_collector collector;
        soc_scoreboard scoreboard;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        function void build_phase(uvm_build_phase phase);
            super.build_phase(phase);
            
            if (!uvm_config_db #(soc_config)::get(this, "", "cfg", cfg)) begin
                cfg = soc_config::type_id::create("cfg");
                uvm_config_db #(soc_config)::set(this, "", "cfg", cfg);
            end
            
            collector = mem_collector::type_id::create("collector", this);
            scoreboard = soc_scoreboard::type_id::create("scoreboard", this);
        endfunction
        
        function void connect_phase(uvm_connect_phase phase);
            super.connect_phase(phase);
            collector.ap_out.connect(scoreboard.ap_in);
        endfunction
    endclass : soc_env
    
endpackage : soc_uvm_pkg

`endif // SOC_UVM_PKG_SV
