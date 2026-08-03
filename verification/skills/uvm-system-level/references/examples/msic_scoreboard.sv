/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

// Central scoreboard.
//
// FabIO checking: subscribes to the monitor's transaction-level analysis ports
// (c2t_txn_ap / t2c_txn_ap).  One C2T transaction item is matched to one T2C
// response item.  Per-response checks:
//   • ID round-trip: rsp.resp_id == req.xact_id
//   • Response code: rsp.resp_code == OKAY (2'b00)
//   • Beat count (B2): for read responses, rsp.burst_len == req.burst_len —
//     catches off-by-one in the AHB burst counter (the RTL bug fixed in
//     fabio_tgt.sv line 836 was detectable by exactly this check)
//   • Read data: rsp.burst_rdata[i] == mem_model[addr+4i] for written addresses
// Raw beat ports are NOT connected here — they remain available on fabio_agent
// for other subscribers.  See category3_porting.md §5.7.
//
// UART checking: accumulates character items into line buffers per channel;
// declares failure if any line starts with "FAIL".

class msic_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(msic_scoreboard)

    // Transaction-level FIFOs — one item per complete FabIO transaction
    uvm_tlm_analysis_fifo #(fabio_seq_item) fabio_c2t_txn_fifo;
    uvm_tlm_analysis_fifo #(fabio_seq_item) fabio_t2c_txn_fifo;
    uvm_tlm_analysis_fifo #(uart_seq_item)  uart_fifo;

    virtual msic_clk_rst_if clk_rst_vif;

    int unsigned fabio_errors    = 0;
    int unsigned uart_errors     = 0;
    int unsigned rdata_checks    = 0;  // words checked against mem_model
    int unsigned beat_chk_count  = 0;  // read transactions with beat-count verified

    // Write-tracking reference model.
    // Key = FabIO bus address; value = last word written to that address.
    // Populated on confirmed writes (resp_code == OKAY); used to verify read data.
    // Addresses never written (e.g. ROM) are absent and reads at those addresses
    // are silently skipped — the firmware's own CPU readback covers ROM correctness.
    logic [31:0] mem_model[logic [31:0]];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        fabio_c2t_txn_fifo = new("fabio_c2t_txn_fifo", this);
        fabio_t2c_txn_fifo = new("fabio_t2c_txn_fifo", this);
        uart_fifo          = new("uart_fifo",           this);
        if (!uvm_config_db #(virtual msic_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst_vif))
            `uvm_fatal("NOVIF", "clk_rst_vif not found in config_db")
    endfunction

    // Addresses in 0x8xxx_xxxx are unmapped in both AHB busmatrix decoders
    // (SYS and FIO) and route to the default slave, which returns an AHB ERROR.
    // A FabIO access there is expected to error — used by busmatrix_error_test
    // to exercise the default-slave / decoder error-response paths.
    function bit err_expected_addr(bit [31:0] addr);
        return (addr[31:28] == 4'h8);
    endfunction

    task run_phase(uvm_phase phase);
        fork
            _check_fabio();
            _log_uart();
        join
    endtask

    task _check_fabio();
        fabio_seq_item req, rsp;
        forever begin
            // One complete C2T transaction from the monitor FSM
            fabio_c2t_txn_fifo.get(req);

            // VIO commands produce no T2C response
            if (req.kind == FABIO_TXN_VIO) continue;

            // Use fork-join_any + disable fork to avoid the disable-named-block race
            // condition where disable fires before the timeout branch registers its
            // first @(posedge clk) event-wait.  rsp=null is the timeout sentinel.
            rsp = null;
            fork
                begin : wait_rsp
                    fabio_seq_item t;
                    do begin
                        fabio_t2c_txn_fifo.get(t);
                    end while (t.kind == FABIO_TXN_VIO);  // skip T2C VIO — not a cmd response
                    rsp = t;
                end
                begin : rsp_timeout
                    repeat (1000) @(posedge clk_rst_vif.clk);
                    // rsp stays null — checked after join_any
                end
            join_any
            disable fork;

            if (rsp === null) begin
                `uvm_error("SB", $sformatf(
                    "FabIO timeout: no T2C response for %s addr=0x%08X xact_id=%0h",
                    req.kind.name(), req.addr, req.xact_id))
                fabio_errors++;
            end else begin
                // Transaction ID must round-trip unchanged
                if (rsp.resp_id !== req.xact_id) begin
                    `uvm_error("SB", $sformatf(
                        "FabIO ID mismatch: req.xact_id=%0h rsp.resp_id=%0h (%s addr=0x%08X)",
                        req.xact_id, rsp.resp_id, req.kind.name(), req.addr))
                    fabio_errors++;
                end

                // Response code check.  Accesses to a designated unmapped
                // address region (0x8xxx_xxxx — decodes to the AHB busmatrix
                // default slave) are tolerated regardless of resp_code: a FabIO
                // C2T *read* returns the AHB ERROR (resp=0x1) from the default
                // slave, while a *write* is posted and returns OKAY (the
                // downstream bus error is not reflected in the WRRESP).  Both
                // are expected behaviours, so neither fails the test — the point
                // is to exercise the default-slave / decoder error path.  All
                // other addresses must respond OKAY (2'b00).
                if (err_expected_addr(req.addr)) begin
                    `uvm_info("SB", $sformatf(
                        "FabIO unmapped access addr=0x%08X (%s) resp=0x%0h (tolerated)",
                        req.addr, req.kind.name(), rsp.resp_code), UVM_LOW)
                end else if (rsp.resp_code !== 2'b00) begin
                    `uvm_error("SB", $sformatf(
                        "FabIO error response: resp_code=0x%0h for %s addr=0x%08X",
                        rsp.resp_code, req.kind.name(), req.addr))
                    fabio_errors++;
                end

                `uvm_info("SB", $sformatf("FabIO OK: %s addr=0x%08X resp_id=%0h%s",
                    req.kind.name(), req.addr, rsp.resp_id,
                    (rsp.kind == FABIO_RD_RESP) ?
                        $sformatf(" rdata=0x%08X", rsp.rdata) : ""),
                    UVM_HIGH)

                // Beat-count check (B2): the number of T2C RDATA beats the DUT
                // returned must equal the burst_len the C2T request specified.
                // rsp.burst_len is set by the T2C FSM as beat_idx-1 (0-based).
                if (req.kind inside {FABIO_SINGLE_RD, FABIO_BURST_RD}) begin
                    beat_chk_count++;
                    if (rsp.burst_len !== req.burst_len) begin
                        `uvm_error("SB", $sformatf(
                            "FabIO beat count mismatch: req burst_len=%0d got %0d (%s addr=0x%08X)",
                            req.burst_len, rsp.burst_len, req.kind.name(), req.addr))
                        fabio_errors++;
                    end
                end

                // Memory-model: record confirmed writes, verify read data.
                // Only update/check when the response was OKAY to avoid tracking
                // data from a failed transaction.
                if (rsp.resp_code == 2'b00) begin
                    if (req.kind inside {FABIO_SINGLE_WR, FABIO_BURST_WR}) begin
                        // Record each written word (INCR burst: addr+0, addr+4, ...)
                        for (int i = 0; i <= int'(req.burst_len); i++)
                            mem_model[req.addr + 32'(i * 4)] = req.burst_wdata[i];
                    end else if (req.kind inside {FABIO_SINGLE_RD, FABIO_BURST_RD}) begin
                        // Verify each returned word against the model if the address was written.
                        // rsp.burst_rdata[0] == rsp.rdata; covers both single and burst cases.
                        for (int i = 0; i <= int'(rsp.burst_len); i++) begin
                            logic [31:0] chk_addr = req.addr + 32'(i * 4);
                            if (mem_model.exists(chk_addr)) begin
                                rdata_checks++;
                                if (rsp.burst_rdata[i] !== mem_model[chk_addr]) begin
                                    `uvm_error("SB", $sformatf(
                                        "FabIO rdata mismatch[%0d]: addr=0x%08X exp=0x%08X got=0x%08X (%s)",
                                        i, chk_addr, mem_model[chk_addr], rsp.burst_rdata[i],
                                        req.kind.name()))
                                    fabio_errors++;
                                end
                            end
                            // else: address not in model (e.g. ROM) — skip silently
                        end
                    end
                end
            end
        end
    endtask

    task _log_uart();
        uart_seq_item item;
        string line[3];
        forever begin
            uart_fifo.get(item);
            case (item.data)
                8'h04: begin  // EOT — firmware signalling test end
                    if (line[item.channel] != "")
                        `uvm_info("UART_OUT",
                            $sformatf("[ch%0d] %s", item.channel, line[item.channel]),
                            UVM_MEDIUM)
                    `uvm_info("UART_OUT",
                        $sformatf("[ch%0d] (EOT) Test Ended", item.channel), UVM_NONE)
                    line[item.channel] = "";
                    uvm_event_pool::get_global("uart_eot").trigger();
                end
                8'h0D: ;  // carriage return — ignore
                8'h0A: begin  // newline — flush line buffer
                    `uvm_info("UART_OUT",
                        $sformatf("[ch%0d] %s", item.channel, line[item.channel]),
                        UVM_MEDIUM)
                    if (line[item.channel].len() >= 4 &&
                        line[item.channel].substr(0, 3) == "FAIL")
                        uart_errors++;
                    line[item.channel] = "";
                end
                default:
                    line[item.channel] = {line[item.channel], string'(item.data)};
            endcase
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", $sformatf("beat-count checks (B2): %0d  rdata checks: %0d",
                                  beat_chk_count, rdata_checks), UVM_LOW)
        if (fabio_errors == 0 && uart_errors == 0)
            `uvm_info("SB", "*** SCOREBOARD PASSED ***", UVM_NONE)
        else
            `uvm_error("SB", $sformatf(
                "*** SCOREBOARD FAILED: fabio_errors=%0d uart_errors=%0d ***",
                fabio_errors, uart_errors))
    endfunction
endclass
