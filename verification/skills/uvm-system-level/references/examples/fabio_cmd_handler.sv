/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

// Bridges tb_ctrl APB commands to FabIO transactions.
//
// Subscribes to:
//   tb_ctrl_agnt.command_ap  → one tb_ctrl_cmd per CTRL register write
//   fabio_agnt.t2c_txn_ap    → one fabio_seq_item per complete T2C response (two FIFOs)
//
// For each command the handler:
//   1. Translates the CPU address to a FabIO bus address (mirrors fabio_pkt.sv).
//   2. Runs a fabio_single_item_seq on fabio_seqr to drive the C2T beats.
//   3. Waits for the matching T2C response (WR_RESP or RD_RESP).
//   4. Calls tb_slave.notify_done(rdata) to deposit DATA_IN and clear STATUS.
//
// T2C VIO packets from the DUT are captured by a separate parallel task (_handle_t2c_vio)
// that deposits the VIO data into the tb_ctrl slave registers so firmware reads at
// TB_CTRL+0x6C/0x70 return the correct value.
//
// fabio_seqr and tb_slave must be assigned by the env in connect_phase.

`ifndef FABIO_CMD_HANDLER_SV
`define FABIO_CMD_HANDLER_SV

class fabio_cmd_handler extends uvm_component;
    `uvm_component_utils(fabio_cmd_handler)

    // Incoming command FIFO — wired to tb_ctrl_agnt.command_ap
    uvm_tlm_analysis_fifo #(tb_ctrl_cmd) cmd_fifo;

    // T2C response FIFO — wired to fabio_agnt.t2c_txn_ap (receives all T2C txns)
    uvm_tlm_analysis_fifo #(fabio_seq_item) t2c_rsp_fifo;

    // T2C VIO capture FIFO — second independent subscriber to t2c_txn_ap.
    // Receives the same items as t2c_rsp_fifo but is drained only for VIO items,
    // so command-response ordering is never perturbed.
    uvm_tlm_analysis_fifo #(fabio_seq_item) t2c_vio_fifo;

    // Set by env.connect_phase
    fabio_sequencer fabio_seqr;
    tb_ctrl_slave   tb_slave;

    virtual msic_clk_rst_if clk_rst_vif;
    virtual msic_fabio_if   fabio_vif;
    int unsigned rsp_timeout = 2000;   // cycles to wait for T2C response

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cmd_fifo     = new("cmd_fifo",     this);
        t2c_rsp_fifo = new("t2c_rsp_fifo", this);
        t2c_vio_fifo = new("t2c_vio_fifo", this);
        if (!uvm_config_db #(virtual msic_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst_vif))
            `uvm_fatal("FABIO_HDL", "clk_rst_vif not found in config_db")
        if (!uvm_config_db #(virtual msic_fabio_if)::get(this, "", "fabio_vif", fabio_vif))
            `uvm_fatal("FABIO_HDL", "fabio_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        tb_ctrl_cmd cmd;
        fork
            forever begin
                cmd_fifo.get(cmd);
                _dispatch(cmd);
            end
            _handle_t2c_vio();
        join
    endtask

    // -------------------------------------------------------------------------
    // Command dispatch
    // -------------------------------------------------------------------------
    task _dispatch(tb_ctrl_cmd cmd);
        `uvm_info("FABIO_HDL", $sformatf("Dispatch %s", cmd.convert2string()), UVM_MEDIUM)
        // The concurrent-write stress command (B4) carries its opcode in
        // ctrl[31:24] (magic 0xA5A10000) — unlike every other command, which
        // encodes it in ctrl[23:16].  Decode it explicitly before the case, or
        // the case (keyed on [23:16]=0xA1) silently ignores it.
        if (cmd.ctrl[31:24] == 8'hA5) begin
            _do_concurrent_wr(cmd);              // 0xA5A10000  concurrent write stress (B4)
            return;
        end
        case (cmd.ctrl[23:16])
            8'h01: _do_single_wr(cmd);          // 0x00010000
            8'h03: _do_single_rd(cmd);          // 0x00030000
            8'h05: _do_burst_wr(cmd);           // 0x00050000  (Tier 3)
            8'h0B: _do_burst_rd(cmd);           // 0x000B0000  (Tier 3)
            8'h0D: _do_c2t_vio(cmd);            // 0x000D0000
            8'h0F: _do_hw_t2c_vio(cmd);         // 0x000F0000  HW T2C VIO injection
            8'h15: _do_burst_wr_c2t_vio(cmd);   // 0x00150000  (Tier 5)
            8'h35: _do_burst_rd_c2t_vio(cmd);   // 0x00350000  (Tier 5)
            8'h45: _do_burst_rd_t2c_vio(cmd);   // 0x00450000  (Tier 5)
            8'h80: _do_seq_go(cmd);             // 0x00800000  (Tier 6 sequencer)
            default: `uvm_info("FABIO_HDL",
                $sformatf("Ignoring unrecognised cmd=0x%08X", cmd.ctrl), UVM_LOW)
        endcase
    endtask

    // -------------------------------------------------------------------------
    // Single write: send SINGLE_WR, wait for WR_RESP, clear STATUS
    // -------------------------------------------------------------------------
    task _do_single_wr(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq = fabio_single_item_seq::type_id::create("wr_seq");
        fabio_seq_item rsp;

        seq.item       = fabio_seq_item::type_id::create("wr_item");
        seq.item.kind  = FABIO_SINGLE_WR;
        seq.item.addr  = translate_addr(cmd.addr);
        seq.item.wdata = cmd.data_out;
        seq.start(fabio_seqr);

        _wait_rsp(FABIO_WR_RESP, rsp);
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // Single read: send SINGLE_RD, wait for RD_RESP, deposit DATA_IN, clear STATUS
    // (STATUS is pre-set to 1 by tb_ctrl_slave when the command is dispatched)
    // -------------------------------------------------------------------------
    task _do_single_rd(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq = fabio_single_item_seq::type_id::create("rd_seq");
        fabio_seq_item rsp;

        seq.item      = fabio_seq_item::type_id::create("rd_item");
        seq.item.kind = FABIO_SINGLE_RD;
        seq.item.addr = translate_addr(cmd.addr);
        seq.start(fabio_seqr);

        _wait_rsp(FABIO_RD_RESP, rsp);
        tb_slave.notify_done(rsp.rdata);
    endtask

    // -------------------------------------------------------------------------
    // Burst write (Tier 3): firmware stores length in DEBUG0[7:0], not ctrl[7:0].
    // -------------------------------------------------------------------------
    task _do_burst_wr(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq = fabio_single_item_seq::type_id::create("bwr_seq");
        fabio_seq_item rsp;
        int burst_len = int'(cmd.debug0[7:0]);

        seq.item           = fabio_seq_item::type_id::create("bwr_item");
        seq.item.kind      = FABIO_BURST_WR;
        seq.item.addr      = translate_addr(cmd.addr);
        seq.item.burst_len = burst_len[7:0];
        for (int i = 0; i <= burst_len; i++)
            seq.item.burst_wdata[i] = cmd.burst_buf[i];
        seq.start(fabio_seqr);

        _wait_rsp(FABIO_WR_RESP, rsp);
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // Burst read (Tier 3): firmware stores length in DEBUG0[7:0], not ctrl[7:0].
    // -------------------------------------------------------------------------
    task _do_burst_rd(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq = fabio_single_item_seq::type_id::create("brd_seq");
        fabio_seq_item rsp;
        int burst_len = int'(cmd.debug0[7:0]);

        seq.item           = fabio_seq_item::type_id::create("brd_item");
        seq.item.kind      = FABIO_BURST_RD;
        seq.item.addr      = translate_addr(cmd.addr);
        seq.item.burst_len = burst_len[7:0];
        seq.start(fabio_seqr);

        _wait_rsp(FABIO_RD_RESP, rsp);
        // Copy burst read data back to tb_ctrl burst buffer for firmware to read
        for (int i = 0; i <= int'(rsp.burst_len); i++)
            tb_slave.set_burst_rdata(i, rsp.burst_rdata[i]);
        tb_slave.notify_done(rsp.burst_rdata[0]);
    endtask

    // -------------------------------------------------------------------------
    // C2T VIO: send VIO beat, no T2C response expected
    // -------------------------------------------------------------------------
    task _do_c2t_vio(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq = fabio_single_item_seq::type_id::create("vio_seq");
        seq.item          = fabio_seq_item::type_id::create("vio_item");
        seq.item.kind     = FABIO_TXN_VIO;
        seq.item.vio_data = cmd.data_out;
        seq.start(fabio_seqr);
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // HW T2C VIO injection (0x0F): force t2c_vio[15:0] in the DUT to data_out.
    // Mirrors native TB virtio_rx_trigger(): forces the signal that digital_top
    // ties to 16'h0000, triggering the DUT's T2C VIO detection logic.
    // msic_tb_top_hdl.sv continuously forces u_fabio_tgt.t2c_vio from t2c_vio_drv.
    // -------------------------------------------------------------------------
    task _do_hw_t2c_vio(tb_ctrl_cmd cmd);
        `uvm_info("FABIO_HDL", $sformatf("HW T2C VIO inject: t2c_vio <= 0x%04X",
                  cmd.data_out[15:0]), UVM_MEDIUM)
        fabio_vif.t2c_vio_drv = cmd.data_out[15:0];
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // Burst write + C2T VIO mid-burst (0x15): send burst, wait for WRESP, then
    // inject C2T VIO so DUT has received it before firmware reads status.
    // -------------------------------------------------------------------------
    task _do_burst_wr_c2t_vio(tb_ctrl_cmd cmd);
        fabio_single_item_seq bwr_seq = fabio_single_item_seq::type_id::create("bwr_c2t_seq");
        fabio_single_item_seq vio_seq = fabio_single_item_seq::type_id::create("c2t_vio_seq");
        fabio_seq_item rsp;
        int burst_len = int'(cmd.debug0[7:0]);

        bwr_seq.item           = fabio_seq_item::type_id::create("bwr_item");
        bwr_seq.item.kind      = FABIO_BURST_WR;
        bwr_seq.item.addr      = translate_addr(cmd.addr);
        bwr_seq.item.burst_len = burst_len[7:0];
        for (int i = 0; i <= burst_len; i++)
            bwr_seq.item.burst_wdata[i] = cmd.burst_buf[i];
        bwr_seq.start(fabio_seqr);

        _wait_rsp(FABIO_WR_RESP, rsp);

        vio_seq.item          = fabio_seq_item::type_id::create("vio_item");
        vio_seq.item.kind     = FABIO_TXN_VIO;
        vio_seq.item.vio_data = cmd.data_out;
        vio_seq.start(fabio_seqr);

        `uvm_info("FABIO_HDL",
            $sformatf("BurstWr+C2TVIO: len=%0d addr=0x%08X vio=0x%08X",
                      burst_len, cmd.addr, cmd.data_out), UVM_MEDIUM)
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // Burst read + C2T VIO mid-read (0x35): send burst read, wait for RDRESP,
    // store burst data, then inject C2T VIO before clearing STATUS.
    // -------------------------------------------------------------------------
    task _do_burst_rd_c2t_vio(tb_ctrl_cmd cmd);
        fabio_single_item_seq brd_seq = fabio_single_item_seq::type_id::create("brd_c2t_seq");
        fabio_single_item_seq vio_seq = fabio_single_item_seq::type_id::create("c2t_vio_seq");
        fabio_seq_item rsp;
        int burst_len = int'(cmd.debug0[7:0]);

        brd_seq.item           = fabio_seq_item::type_id::create("brd_item");
        brd_seq.item.kind      = FABIO_BURST_RD;
        brd_seq.item.addr      = translate_addr(cmd.addr);
        brd_seq.item.burst_len = burst_len[7:0];
        brd_seq.start(fabio_seqr);

        _wait_rsp(FABIO_RD_RESP, rsp);
        for (int i = 0; i <= int'(rsp.burst_len); i++)
            tb_slave.set_burst_rdata(i, rsp.burst_rdata[i]);

        vio_seq.item          = fabio_seq_item::type_id::create("vio_item");
        vio_seq.item.kind     = FABIO_TXN_VIO;
        vio_seq.item.vio_data = cmd.data_out;
        vio_seq.start(fabio_seqr);

        `uvm_info("FABIO_HDL",
            $sformatf("BurstRd+C2TVIO: len=%0d addr=0x%08X vio=0x%08X",
                      burst_len, cmd.addr, cmd.data_out), UVM_MEDIUM)
        tb_slave.notify_done(rsp.burst_rdata[0]);
    endtask

    // -------------------------------------------------------------------------
    // Burst read + T2C VIO mid-read (0x45): firmware already wrote T2C_VIRTIO_EN
    // to DUT hardware; cmd.data_out carries the expected VIO payload (16-bit).
    // The UVM stubs the VIO delivery by directly depositing cmd.data_out into
    // the tb_ctrl VIO registers so firmware reads the expected value.
    // -------------------------------------------------------------------------
    task _do_burst_rd_t2c_vio(tb_ctrl_cmd cmd);
        fabio_single_item_seq brd_seq = fabio_single_item_seq::type_id::create("brd_t2c_seq");
        fabio_seq_item rsp;
        int burst_len = int'(cmd.debug0[7:0]);

        brd_seq.item           = fabio_seq_item::type_id::create("brd_item");
        brd_seq.item.kind      = FABIO_BURST_RD;
        brd_seq.item.addr      = translate_addr(cmd.addr);
        brd_seq.item.burst_len = burst_len[7:0];
        brd_seq.start(fabio_seqr);

        _wait_rsp(FABIO_RD_RESP, rsp);
        for (int i = 0; i <= int'(rsp.burst_len); i++)
            tb_slave.set_burst_rdata(i, rsp.burst_rdata[i]);

        // Deposit VIO payload directly so firmware reads the expected value.
        tb_slave.set_t2c_vio(cmd.data_out);
        `uvm_info("FABIO_HDL",
            $sformatf("BurstRd+T2CVIO(stub): len=%0d addr=0x%08X vio=0x%08X",
                      burst_len, cmd.addr, cmd.data_out), UVM_MEDIUM)
        tb_slave.notify_done(rsp.burst_rdata[0]);
    endtask

    // -------------------------------------------------------------------------
    // Sequencer API (0x80): parse (id, data) beat sequence accumulated by SEQ_SAVE
    // writes and execute the corresponding FabIO transactions.  Calls
    // tb_slave.notify_seq_done() at the end to release the APB pready hold.
    //
    // Beat IDs match fabio_cmd_id_t in msic_fabio_sequences.h:
    //   0=ADDR, 2=RD_CMD, 3=WR_CMD, 4=WR_DATA, 6=WR_PARAM, 7=VIO_CMD
    // -------------------------------------------------------------------------
    task _do_seq_go(tb_ctrl_cmd cmd);
        int          i = 0;
        logic [31:0] cur_addr;
        int          burst_len;
        logic [31:0] wd[16];

        while (i < int'(cmd.seq_len)) begin
            case (int'(cmd.seq_ids[i]))
                0: begin  // ADDR — save; transaction type follows
                    cur_addr = cmd.seq_datas[i]; i++;
                end
                2: begin  // RD_CMD — burst read
                    burst_len = int'(cmd.seq_datas[i][7:0]); i++;
                    _exec_seq_burst_rd(cur_addr, burst_len);
                end
                3: begin  // WR_CMD — burst write; collect WR_DATA/WR_PARAM pairs
                    burst_len = int'(cmd.seq_datas[i][7:0]); i++;
                    for (int k = 0; k <= burst_len; k++) begin
                        wd[k] = cmd.seq_datas[i]; i++;  // WR_DATA (id=4)
                        i++;                            // skip WR_PARAM (id=6)
                    end
                    _exec_seq_burst_wr(cur_addr, burst_len, wd);
                end
                7: begin  // VIO_CMD — C2T VIO
                    _exec_seq_c2t_vio(cmd.seq_datas[i]); i++;
                end
                default: i++;
            endcase
        end

        `uvm_info("FABIO_HDL",
            $sformatf("SeqGo complete: %0d beats processed", cmd.seq_len), UVM_MEDIUM)
        tb_slave.notify_seq_done();
    endtask

    task _exec_seq_burst_rd(logic [31:0] cpu_addr, int burst_len);
        fabio_single_item_seq brd_seq = fabio_single_item_seq::type_id::create("seq_brd");
        fabio_seq_item rsp;
        brd_seq.item           = fabio_seq_item::type_id::create("brd_item");
        brd_seq.item.kind      = FABIO_BURST_RD;
        brd_seq.item.addr      = translate_addr(cpu_addr);
        brd_seq.item.burst_len = burst_len[7:0];
        brd_seq.start(fabio_seqr);
        _wait_rsp(FABIO_RD_RESP, rsp);
        for (int i = 0; i <= int'(rsp.burst_len); i++)
            tb_slave.set_burst_rdata(i, rsp.burst_rdata[i]);
        `uvm_info("FABIO_HDL",
            $sformatf("SeqBurstRd: addr=0x%08X len=%0d rdata[0]=0x%08X",
                      cpu_addr, burst_len+1, rsp.burst_rdata[0]), UVM_MEDIUM)
    endtask

    task _exec_seq_burst_wr(logic [31:0] cpu_addr, int burst_len, logic [31:0] wd[16]);
        fabio_single_item_seq bwr_seq = fabio_single_item_seq::type_id::create("seq_bwr");
        fabio_seq_item rsp;
        bwr_seq.item           = fabio_seq_item::type_id::create("bwr_item");
        bwr_seq.item.kind      = FABIO_BURST_WR;
        bwr_seq.item.addr      = translate_addr(cpu_addr);
        bwr_seq.item.burst_len = burst_len[7:0];
        for (int i = 0; i <= burst_len; i++)
            bwr_seq.item.burst_wdata[i] = wd[i];
        bwr_seq.start(fabio_seqr);
        _wait_rsp(FABIO_WR_RESP, rsp);
        `uvm_info("FABIO_HDL",
            $sformatf("SeqBurstWr: addr=0x%08X len=%0d", cpu_addr, burst_len+1), UVM_MEDIUM)
    endtask

    task _exec_seq_c2t_vio(logic [31:0] vio_data);
        fabio_single_item_seq vio_seq = fabio_single_item_seq::type_id::create("seq_vio");
        vio_seq.item          = fabio_seq_item::type_id::create("vio_item");
        vio_seq.item.kind     = FABIO_TXN_VIO;
        vio_seq.item.vio_data = vio_data;
        vio_seq.start(fabio_seqr);
        `uvm_info("FABIO_HDL",
            $sformatf("SeqC2TVIO: vio_data=0x%08X", vio_data), UVM_MEDIUM)
    endtask

    // -------------------------------------------------------------------------
    // Concurrent write stress (B4 — opcode 0xA5): drives 1000 FABIO_SINGLE_WR
    // transactions to cmd.addr while firmware's CPU concurrently writes to an
    // adjacent SRAM word.  Each write sends wdata=i (0..999) so the last write
    // leaves the target word at 999.  notify_done() releases STATUS=1 so firmware
    // exits its polling loop and verifies fabio_location==999.
    // -------------------------------------------------------------------------
    task _do_concurrent_wr(tb_ctrl_cmd cmd);
        fabio_single_item_seq seq;
        fabio_seq_item rsp;
        logic [31:0] fab_addr;
        fab_addr = translate_addr(cmd.addr);
        `uvm_info("FABIO_HDL",
            $sformatf("ConcurrentWr(B4): 1000 SINGLE_WR to FabIO addr=0x%08X", fab_addr),
            UVM_LOW)
        for (int i = 0; i < 1000; i++) begin
            seq            = fabio_single_item_seq::type_id::create($sformatf("cwr_%0d", i));
            seq.item       = fabio_seq_item::type_id::create("cwr_item");
            seq.item.kind  = FABIO_SINGLE_WR;
            seq.item.addr  = fab_addr;
            seq.item.wdata = 32'(i);
            seq.start(fabio_seqr);
            _wait_rsp(FABIO_WR_RESP, rsp);
        end
        `uvm_info("FABIO_HDL", "ConcurrentWr(B4): 1000 writes done, fabio_location→999", UVM_LOW)
        tb_slave.notify_done(0);
    endtask

    // -------------------------------------------------------------------------
    // T2C VIO capture: drains t2c_vio_fifo and deposits VIO data in tb_ctrl so
    // firmware reads at TB_CTRL+0x6C (data) and +0x70 (valid) get the right value.
    // Runs concurrently with the command dispatcher throughout the simulation.
    // -------------------------------------------------------------------------
    task _handle_t2c_vio();
        fabio_seq_item vio;
        forever begin
            t2c_vio_fifo.get(vio);
            if (vio.kind == FABIO_TXN_VIO) begin
                tb_slave.set_t2c_vio(vio.vio_data);
                `uvm_info("FABIO_HDL",
                    $sformatf("T2C VIO captured: data=0x%08X → deposited in tb_ctrl", vio.vio_data),
                    UVM_MEDIUM)
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Wait for a T2C response of the expected kind (with timeout).
    // Skips VIO items; warns on unexpected types and keeps waiting.
    // -------------------------------------------------------------------------
    task _wait_rsp(fabio_txn_kind_e expected_kind, output fabio_seq_item rsp);
        fork
            begin : wait_rsp_body
                forever begin
                    t2c_rsp_fifo.get(rsp);
                    if (rsp.kind == expected_kind) break;
                    if (rsp.kind != FABIO_TXN_VIO)
                        `uvm_warning("FABIO_HDL",
                            $sformatf("Unexpected T2C kind=%0s while waiting for %0s — skipping",
                                      rsp.kind.name(), expected_kind.name()))
                end
                disable rsp_timeout_proc;
            end
            begin : rsp_timeout_proc
                repeat (rsp_timeout) @(posedge clk_rst_vif.clk);
                `uvm_error("FABIO_HDL",
                    $sformatf("Timeout (%0d cycles) waiting for T2C %0s",
                              rsp_timeout, expected_kind.name()))
                // disable FIRST: killing the blocked fifo.get() performs an
                // abnormal copy-out that overwrites rsp with null if assigned before disabling.
                disable wait_rsp_body;
                rsp = fabio_seq_item::type_id::create("timeout_rsp");
            end
        join
    endtask

    // -------------------------------------------------------------------------
    // Address translation: CPU/AHB address → FabIO C2T ADDR beat value.
    //
    // fabio_tgt RTL sets n_ahb_haddr = cmd_addr directly (no expansion).
    // The FIO bus matrix (cmsdk_cpuss_ahb_decodeS_FIO.v, regenerated at
    // commit d9b6eccc) decodes full CPU AHB addresses: SRAM=0x2xxxxxxx,
    // APB=0x4xxxxxxx, ROM=0x0000xxxx.  Identity mapping is correct.
    //
    // The old compressed-space offsets (0x00040000 for SRAM, etc.) matched
    // the original bus matrix but became wrong after d9b6eccc regenerated it.
    // -------------------------------------------------------------------------
    function logic [31:0] translate_addr(logic [31:0] cpu_addr);
        return cpu_addr;
    endfunction

endclass

`endif // FABIO_CMD_HANDLER_SV
