/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
*//////////////////////////////////////////////////////////////////////////////

// APB slave for tb_ctrl at 0x40007000 (PORT7 of cpuss_apb_subsystem).
//
// Maintains a 1024-word register file indexed by paddr[11:2].  When firmware
// writes CTRL (word 1) with a non-zero command code the slave:
//   1. Captures the register snapshot into a tb_ctrl_cmd.
//   2. Publishes it on command_ap (sequences can subscribe for BFM dispatch).
//   3. Auto-clears CTRL so a subsequent STATUS poll returns 0 (not busy).
//
// This is a zero-wait-state slave: PREADY is permanently asserted.  STATUS
// never goes busy in this stub tier; full BFM execution is added in later tiers.

`ifndef TB_CTRL_SLAVE_SV
`define TB_CTRL_SLAVE_SV

class tb_ctrl_slave extends uvm_component;
    `uvm_component_utils(tb_ctrl_slave)

    uvm_analysis_port #(tb_ctrl_cmd) command_ap;

    virtual msic_apb_if vif;

    // Register file — word-addressed (byte_offset >> 2)
    local logic [31:0] regs[1024];

    // Register word indices
    localparam int IDX_MODULE_ID   = 0;   // 0x000  RO
    localparam int IDX_CTRL        = 1;   // 0x004  command trigger
    localparam int IDX_ADDR        = 2;   // 0x008
    localparam int IDX_DATA_OUT    = 3;   // 0x00C  firmware -> BFM
    localparam int IDX_DATA_IN     = 4;   // 0x010  BFM -> firmware
    localparam int IDX_STATUS      = 5;   // 0x014  bit[0] = busy
    localparam int IDX_DEBUG0      = 6;   // 0x018
    localparam int IDX_DEBUG1      = 7;   // 0x01C
    localparam int IDX_DEBUG2      = 8;   // 0x020
    localparam int IDX_DEBUG3      = 9;   // 0x024
    localparam int IDX_BURST_BASE  = 10;  // 0x028..0x064  (16 words)
    localparam int IDX_GPIO_BFM    = 26;  // 0x068
    localparam int IDX_FABIO_VIO_D = 27;  // 0x06C
    localparam int IDX_FABIO_VIO_V = 28;  // 0x070
    localparam int IDX_FABIO_SEQ   = 64;  // 0x100 SEQ_ID, 0x104 SEQ_DATA, 0x108 SEQ_SAVE, 0x10C SEQ_GO
    localparam int IDX_FABIO_GOLD  = 68;  // 0x110..0x14C (16 words)
    localparam int IDX_ERR_CNT     = 960; // 0xF00
    localparam int IDX_RAND_SEED   = 961; // 0xF04

    // Sequencer beat accumulation buffer (filled by SEQ_SAVE writes, consumed on SEQ_GO)
    local int unsigned seq_buf_len;
    local logic [31:0] seq_buf_ids  [128];
    local logic [31:0] seq_buf_datas[128];

    // SEQ_GO pready-hold state
    local bit          hold_pready_low;
    local bit          seq_go_started;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        command_ap = new("command_ap", this);
        if (!uvm_config_db #(virtual msic_apb_if)::get(this, "", "apb_vif", vif))
            `uvm_fatal("TB_CTRL", "apb_vif not found in config_db")
        reset_regs();
        // Self-register so FabIO sequences can call notify_done()
        uvm_config_db #(tb_ctrl_slave)::set(null, "*", "tb_ctrl_slave", this);
    endfunction

    task run_phase(uvm_phase phase);
        hold_pready_low = 0;
        seq_go_started  = 0;
        vif.pready  <= 1'b1;
        vif.prdata  <= '0;
        vif.pslverr <= 1'b0;

        forever begin
            @(posedge vif.pclk);
            if (!vif.presetn) begin
                reset_regs();
                hold_pready_low = 0;
                seq_go_started  = 0;
                vif.prdata  <= '0;
                vif.pready  <= 1'b1;
                vif.pslverr <= 1'b0;
            end else begin
                // Default: follow hold_pready_low flag
                if (hold_pready_low)
                    vif.pready <= 1'b0;
                else
                    vif.pready <= 1'b1;
                vif.pslverr <= 1'b0;

                // SETUP phase: pre-load read data; detect upcoming SEQ_GO to pre-hold pready
                if (vif.psel && !vif.penable) begin
                    vif.prdata <= regs[vif.paddr[11:2]];
                    if (vif.pwrite && int'(vif.paddr[11:2]) == IDX_FABIO_SEQ + 3
                            && !hold_pready_low) begin
                        hold_pready_low = 1;
                        vif.pready <= 1'b0;  // override default above
                    end
                    // Clear the dispatch guard once any non-SEQ_GO transaction begins.
                    // seq_go_started stays 1 through the ACCESS release cycle so the
                    // still-active ACCESS phase cannot trigger a phantom re-dispatch.
                    if (int'(vif.paddr[11:2]) != IDX_FABIO_SEQ + 3)
                        seq_go_started = 0;
                end
                // Clear in APB IDLE (psel=0) as well
                if (!vif.psel)
                    seq_go_started = 0;

                // ACCESS phase: complete the transaction
                if (vif.psel && vif.penable) begin
                    if (vif.pwrite) begin
                        if (int'(vif.paddr[11:2]) == IDX_FABIO_SEQ + 3) begin
                            // SEQ_GO: dispatch once, then stall until notify_seq_done()
                            if (!seq_go_started) begin
                                seq_go_started = 1;
                                dispatch_seq_go();
                            end
                        end else begin
                            apb_write(int'(vif.paddr[11:2]), vif.pwdata, vif.pstrb);
                        end
                    end else begin
                        vif.prdata <= regs[vif.paddr[11:2]];
                    end
                end
            end
        end
    endtask

    // Called by fabio_cmd_handler when an operation completes.
    // Deposits read data and clears STATUS so firmware poll exits.
    function void notify_done(logic [31:0] data_in = '0);
        regs[IDX_DATA_IN] = data_in;
        regs[IDX_STATUS]  = '0;
    endfunction

    // Write one word into the burst read-back buffer (for burst read results).
    function void set_burst_rdata(int idx, logic [31:0] data);
        if (idx >= 0 && idx < 16)
            regs[IDX_BURST_BASE + idx] = data;
    endfunction

    // Deposits val into the GPIO_BFM register (IDX_GPIO_BFM = 26, offset 0x068).
    // Called by gpio_bfm_handler when firmware issues a GPIO_BFM_READ command (CTRL=0x10).
    function void set_gpio_bfm(logic [31:0] val);
        regs[IDX_GPIO_BFM] = val;
    endfunction

    // Called by fabio_cmd_handler when a T2C VIO packet arrives from the DUT.
    // Deposits vio_data at IDX_FABIO_VIO_D (0x6C) and sets valid at IDX_FABIO_VIO_V (0x70).
    function void set_t2c_vio(logic [31:0] vio_data);
        regs[IDX_FABIO_VIO_D] = vio_data;
        regs[IDX_FABIO_VIO_V] = 32'h1;
    endfunction

    // Called by fabio_cmd_handler when a SEQ_GO sequence is fully complete.
    // Releases the pready hold so the CPU's APB write to SEQ_GO completes.
    // seq_go_started is intentionally NOT cleared here — it stays 1 through the
    // ACCESS release cycle to prevent phantom re-dispatch (cleared in SETUP of
    // next non-SEQ_GO transaction or when psel deasserts).
    function void notify_seq_done();
        hold_pready_low = 0;
        seq_buf_len     = 0;
    endfunction

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------
    local function void reset_regs();
        for (int i = 0; i < 1024; i++) regs[i] = '0;
        regs[IDX_MODULE_ID] = 32'h6800_AB00;  // matches legacy tb_ctrl.sv
        regs[IDX_RAND_SEED] = $urandom;        // non-zero seed for random traffic test
        seq_buf_len         = 0;
    endfunction

    local function void apb_write(int widx, logic [31:0] wdata, logic [3:0] strb);
        if (widx == IDX_MODULE_ID) return;  // read-only
        if (strb[0]) regs[widx][ 7: 0] = wdata[ 7: 0];
        if (strb[1]) regs[widx][15: 8] = wdata[15: 8];
        if (strb[2]) regs[widx][23:16] = wdata[23:16];
        if (strb[3]) regs[widx][31:24] = wdata[31:24];
        if (widx == IDX_CTRL && regs[IDX_CTRL] != '0) begin
            // For commands where firmware polls STATUS, pre-set STATUS=1 here
            // so the firmware's next APB read sees "busy" before cmd_handler fires.
            // STATUS is cleared by notify_done() when the transaction completes.
            if (is_blocking_cmd(regs[IDX_CTRL]))
                regs[IDX_STATUS] = 32'h1;
            dispatch_command();
            regs[IDX_CTRL] = '0;
        end
        // SEQ_SAVE (0x108): push current (SEQ_ID, SEQ_DATA) into the sequence buffer.
        if (widx == IDX_FABIO_SEQ + 2 && wdata[0] && seq_buf_len < 128) begin
            seq_buf_ids  [seq_buf_len] = regs[IDX_FABIO_SEQ];
            seq_buf_datas[seq_buf_len] = regs[IDX_FABIO_SEQ + 1];
            seq_buf_len++;
        end
    endfunction

    // Publish a SEQ_GO command carrying the accumulated beat sequence.
    local function void dispatch_seq_go();
        tb_ctrl_cmd cmd;
        cmd         = tb_ctrl_cmd::type_id::create("seq_go_cmd");
        cmd.ctrl    = 32'h00800000;  // ctrl[23:16] = 8'h80
        cmd.seq_len = seq_buf_len;
        for (int i = 0; i < seq_buf_len; i++) begin
            cmd.seq_ids  [i] = seq_buf_ids  [i];
            cmd.seq_datas[i] = seq_buf_datas[i];
        end
        `uvm_info("TB_CTRL", $sformatf("SEQ_GO dispatched: %0d beats", seq_buf_len), UVM_MEDIUM)
        command_ap.write(cmd);
    endfunction

    // Returns 1 for commands where firmware polls STATUS waiting for completion.
    local function logic is_blocking_cmd(logic [31:0] ctrl_val);
        // Concurrent-write stress (B4) encodes its opcode in ctrl[31:24]
        // (magic 0xA5A10000); [23:16] is 0xA1, so it must be matched here and
        // not in the [23:16] case below (else STATUS is never raised and the
        // firmware's completion poll returns immediately -> no CPU/FabIO overlap).
        if (ctrl_val[31:24] == 8'hA5) return 1'b1;   // 0xA5A10000 = concurrent write stress (B4)
        case (ctrl_val[23:16])
            8'h03: return 1'b1;   // 0x00030000 = single read
            8'h0B: return 1'b1;   // 0x000B0000 = burst read
            default: return 1'b0;
        endcase
    endfunction

    local function void dispatch_command();
        tb_ctrl_cmd cmd;
        cmd          = tb_ctrl_cmd::type_id::create("cmd");
        cmd.ctrl     = regs[IDX_CTRL];
        cmd.addr     = regs[IDX_ADDR];
        cmd.data_out = regs[IDX_DATA_OUT];
        cmd.debug0   = regs[IDX_DEBUG0];
        cmd.debug2   = regs[IDX_DEBUG2];
        for (int i = 0; i < 16; i++)
            cmd.burst_buf[i] = regs[IDX_BURST_BASE + i];
        `uvm_info("TB_CTRL", $sformatf("CMD dispatched: %s", cmd.convert2string()), UVM_HIGH)
        command_ap.write(cmd);
    endfunction
endclass

`endif // TB_CTRL_SLAVE_SV
