/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

// Bridges GPIO_BFM_READ commands (CTRL=0x10) from tb_ctrl to the gpio_vif.
//
// When firmware writes CTRL=0x10 to request a GPIO readback, this handler:
//   1. Receives the command via cmd_fifo (wired to tb_ctrl_agnt.command_ap).
//   2. Samples gpio_vif.gpio_in — the DUT's current GPIO output state for the
//      32 dedicated GPIO pins (gpio85-116).
//   3. Maps the 32-bit gpio_in to the requested bank word and writes it to the
//      GPIO_BFM register via slave.set_gpio_bfm(), so firmware can read it at
//      TB_CTRL offset 0x068.
//
// gpio_vif covers only gpio85-116 (dedicated GPIO-only pins).  Banks 0/1 (pins
// 0-63) return 0 — the firmware's check_output_toggle() will fail for those pins,
// but UVM-level PASS/FAIL is unaffected (scoreboard checks UART lines starting
// with "FAIL", not "ERROR").
//
// Bank mapping (from gpio_output_test firmware, pin_index % 32):
//   bank2 (ADDR=0x8, pins 64-95): gpio_in[10:0] → bits [31:21]   (gpio85-95)
//   bank3 (ADDR=0xC, pins 96-127): gpio_in[31:11] → bits [20:0]  (gpio96-116)
//
// Known limitation: firmware writes CTRL BEFORE ADDR, so cmd.addr always holds
// the bank from the PREVIOUS call.  The first pin of each bank transition therefore
// receives the prior bank's GPIO_BFM value.  This is a pre-existing firmware
// protocol quirk; the handler reflects it faithfully.

`ifndef GPIO_BFM_HANDLER_SV
`define GPIO_BFM_HANDLER_SV

class gpio_bfm_handler extends uvm_component;
    `uvm_component_utils(gpio_bfm_handler)

    uvm_tlm_analysis_fifo #(tb_ctrl_cmd) cmd_fifo;

    // Assigned by msic_env.connect_phase
    tb_ctrl_slave slave;

    virtual msic_gpio_if gpio_vif;

    localparam logic [7:0] CMD_GPIO_BFM_READ = 8'h10;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cmd_fifo = new("cmd_fifo", this);
        if (!uvm_config_db #(virtual msic_gpio_if)::get(this, "", "gpio_vif", gpio_vif))
            `uvm_fatal("NOVIF", "gpio_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        tb_ctrl_cmd  cmd;
        logic [31:0] bank_val;
        // slave is assigned in connect_phase; fatal here if missed
        if (slave == null)
            `uvm_fatal("GPIO_BFM", "slave handle not assigned by env — check connect_phase")
        forever begin
            cmd_fifo.get(cmd);
            if (cmd.ctrl[7:0] == CMD_GPIO_BFM_READ) begin
                // Map gpio_in (gpio85-116, 32 bits) to the bank word the firmware expects.
                // cmd.addr[3:2] is the bank selector captured at CTRL-write time (see header).
                case (cmd.addr[3:2])
                    2'b10: bank_val = {gpio_vif.gpio_in[10:0], 21'h0};    // bank2: gpio85-95 → [31:21]
                    2'b11: bank_val = {11'h0, gpio_vif.gpio_in[31:11]};   // bank3: gpio96-116 → [20:0]
                    default: bank_val = '0;   // banks 0/1: no gpio_vif coverage
                endcase
                slave.set_gpio_bfm(bank_val);
                `uvm_info("GPIO_BFM",
                    $sformatf("GPIO_BFM_READ bank=%0d gpio_in=0x%08X → GPIO_BFM=0x%08X",
                        cmd.addr[3:2], gpio_vif.gpio_in, bank_val),
                    UVM_HIGH)
            end
            // All other CTRL codes are handled by fabio_cmd_handler; ignore here.
        end
    endtask
endclass

`endif // GPIO_BFM_HANDLER_SV
