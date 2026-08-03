/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
Proprietary and confidential
-------------------------------------------------------------------------------
Bridges UART_RX_DRIVE commands (CTRL[7:0] = 0x20) from tb_ctrl to the uart_driver.

When firmware writes a UART_RX_DRIVE command this handler injects serial
characters on the requested UART RX line so the CPU can receive them — there is
no TB UART loopback, so RX-side firmware tests need this bridge.  Mirrors
gpio_bfm_handler (both subscribe to tb_ctrl_agnt.command_ap).

Command encoding (firmware writes ADDR/DATA_OUT/DEBUG0 before CTRL):
  CTRL[7:0]   = 0x20        (UART_RX_DRIVE opcode)
  ADDR[1:0]   = channel     (0 = uart0_rx, 2 = uart2_rx)
  DATA_OUT[7:0] = payload byte (successive chars increment, see inject seq)
  DEBUG0[7:0] = count       (1 = single receive; >1 back-to-back forces RX overrun)

Non-blocking: STATUS is NOT raised (is_blocking_cmd leaves 0x20 out), so the
firmware polls RXBF / RXOR — or waits on the RX interrupt — for completion.
Other CTRL codes are handled by fabio_cmd_handler / gpio_bfm_handler and ignored
here.
*//////////////////////////////////////////////////////////////////////////////

`ifndef UART_CMD_HANDLER_SV
`define UART_CMD_HANDLER_SV

class uart_cmd_handler extends uvm_component;
    `uvm_component_utils(uart_cmd_handler)

    uvm_tlm_analysis_fifo #(tb_ctrl_cmd) cmd_fifo;

    // Assigned by msic_env.connect_phase
    uart_sequencer uart_seqr;

    localparam logic [7:0] CMD_UART_RX_DRIVE = 8'h20;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cmd_fifo = new("cmd_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
        tb_ctrl_cmd cmd;
        if (uart_seqr == null)
            `uvm_fatal("UART_HDL", "uart_seqr not assigned by env — check connect_phase")
        forever begin
            cmd_fifo.get(cmd);
            if (cmd.ctrl[7:0] == CMD_UART_RX_DRIVE) begin
                uart_rx_inject_seq seq = uart_rx_inject_seq::type_id::create("rx_inject");
                seq.channel  = cmd.addr[1:0];
                seq.data     = cmd.data_out[7:0];
                seq.count    = (cmd.debug0[7:0] == 0) ? 1 : cmd.debug0[7:0];
                seq.baud_div = 868;
                `uvm_info("UART_HDL",
                    $sformatf("UART_RX_DRIVE ch=%0d data=0x%02X count=%0d",
                              seq.channel, seq.data, seq.count), UVM_LOW)
                seq.start(uart_seqr);
            end
        end
    endtask
endclass

`endif // UART_CMD_HANDLER_SV
