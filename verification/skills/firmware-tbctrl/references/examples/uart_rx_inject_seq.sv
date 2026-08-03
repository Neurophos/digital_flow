/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
Proprietary and confidential
-------------------------------------------------------------------------------
UART RX injection sequence.

Drives `count` back-to-back serial characters on one UART RX channel using the
existing uart_driver (868 cycles/bit = 115200 baud @ 100 MHz).  Started by
uart_cmd_handler in response to a firmware TB_CTRL request, so a CPU firmware
test can *receive* characters — and force an RX overrun (count > 1 with the CPU
not draining the 1-deep RX buffer) — without any TB loopback.
*//////////////////////////////////////////////////////////////////////////////

`ifndef UART_RX_INJECT_SEQ_SV
`define UART_RX_INJECT_SEQ_SV

class uart_rx_inject_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_rx_inject_seq)

    int unsigned channel  = 0;
    logic [7:0]  data     = 8'h5A;
    int unsigned count    = 1;
    int unsigned baud_div = 868;   // must match the DUT UART BAUDDIV

    function new(string name = "uart_rx_inject_seq");
        super.new(name);
    endfunction

    task body();
        for (int i = 0; i < count; i++) begin
            uart_seq_item req = uart_seq_item::type_id::create(
                                    $sformatf("rx_inj_%0d", i));
            start_item(req);
            req.channel  = channel;
            req.data     = data + i[7:0];   // vary payload per char so RX data toggles
            req.baud_div = baud_div;
            finish_item(req);
        end
    endtask
endclass

`endif // UART_RX_INJECT_SEQ_SV
