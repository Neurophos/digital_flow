/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

class msic_env extends uvm_env;
    `uvm_component_utils(msic_env)

    msic_env_cfg      cfg;
    fabio_agent       fabio_agnt;
    qspi_agent        qspi_agnt;
    gpio_agent        gpio_agnt;
    uart_agent        uart_agnt;
    tb_ctrl_agent     tb_ctrl_agnt;
    jtag_agent        jtag_agnt;
    msic_scoreboard   scoreboard;
    fabio_cmd_handler cmd_handler;
    gpio_bfm_handler  gpio_bfm_hdlr;
    uart_cmd_handler  uart_cmd_hdlr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(msic_env_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = msic_env_cfg::type_id::create("cfg");
            `uvm_info("ENV", "No cfg found in config_db — using defaults", UVM_MEDIUM)
        end

        fabio_agnt = fabio_agent::type_id::create("fabio_agnt", this);
        fabio_agnt.is_active = cfg.fabio_is_active;

        qspi_agnt = qspi_agent::type_id::create("qspi_agnt", this);
        qspi_agnt.is_active = cfg.qspi_is_active;

        gpio_agnt = gpio_agent::type_id::create("gpio_agnt", this);
        gpio_agnt.is_active = cfg.gpio_is_active;

        uart_agnt = uart_agent::type_id::create("uart_agnt", this);
        uart_agnt.is_active = cfg.uart_is_active;

        jtag_agnt = jtag_agent::type_id::create("jtag_agnt", this);
        jtag_agnt.is_active = cfg.jtag_is_active;

        tb_ctrl_agnt  = tb_ctrl_agent::type_id::create("tb_ctrl_agnt", this);
        cmd_handler   = fabio_cmd_handler::type_id::create("cmd_handler", this);
        gpio_bfm_hdlr = gpio_bfm_handler::type_id::create("gpio_bfm_hdlr", this);
        uart_cmd_hdlr = uart_cmd_handler::type_id::create("uart_cmd_hdlr", this);

        if (cfg.has_scoreboard)
            scoreboard = msic_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Wire both handlers to tb_ctrl commands (analysis port broadcasts to all)
        tb_ctrl_agnt.command_ap.connect(cmd_handler.cmd_fifo.analysis_export);
        tb_ctrl_agnt.command_ap.connect(gpio_bfm_hdlr.cmd_fifo.analysis_export);
        tb_ctrl_agnt.command_ap.connect(uart_cmd_hdlr.cmd_fifo.analysis_export);
        gpio_bfm_hdlr.slave     = tb_ctrl_agnt.slave;
        uart_cmd_hdlr.uart_seqr = uart_agnt.sequencer;
        fabio_agnt.t2c_txn_ap.connect(cmd_handler.t2c_rsp_fifo.analysis_export);
        fabio_agnt.t2c_txn_ap.connect(cmd_handler.t2c_vio_fifo.analysis_export);
        cmd_handler.fabio_seqr = fabio_agnt.sequencer;
        cmd_handler.tb_slave   = tb_ctrl_agnt.slave;

        if (cfg.has_scoreboard) begin
            fabio_agnt.c2t_txn_ap.connect(scoreboard.fabio_c2t_txn_fifo.analysis_export);
            fabio_agnt.t2c_txn_ap.connect(scoreboard.fabio_t2c_txn_fifo.analysis_export);
            uart_agnt.ap.connect(scoreboard.uart_fifo.analysis_export);
        end
    endfunction
endclass
