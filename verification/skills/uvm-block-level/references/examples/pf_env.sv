/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

class pf_env extends uvm_env;
    `uvm_component_utils(pf_env)

    pf_env_cfg      cfg;
    pf_stream_agent stream_agnt;
    pf_dac_agent    dac_agnt;
    pf_scoreboard   scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(pf_env_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = pf_env_cfg::type_id::create("cfg");
            `uvm_info("PF_ENV", "No cfg in config_db — using defaults", UVM_MEDIUM)
        end

        // Make the pixel-frame ID available to the stream driver and scoreboard.
        uvm_config_db #(int)::set(this, "*", "pf_id", cfg.pf_id);

        stream_agnt = pf_stream_agent::type_id::create("stream_agnt", this);
        stream_agnt.is_active = cfg.stream_is_active;

        dac_agnt = pf_dac_agent::type_id::create("dac_agnt", this);
        dac_agnt.is_active = UVM_PASSIVE;

        if (cfg.has_scoreboard)
            scoreboard = pf_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        if (cfg.has_scoreboard) begin
            // input stream fans out to both the passthrough and program copies
            stream_agnt.in_ap.connect(scoreboard.in_fifo.analysis_export);
            stream_agnt.in_ap.connect(scoreboard.prog_fifo.analysis_export);
            stream_agnt.out_ap.connect(scoreboard.out_fifo.analysis_export);
            dac_agnt.ap.connect(scoreboard.dac_fifo.analysis_export);
        end
    endfunction
endclass
