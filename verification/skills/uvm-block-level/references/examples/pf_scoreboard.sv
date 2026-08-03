/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
-------------------------------------------------------------------------------
Reference scoreboard for pf_ed. Two independent checks:

 1. Passthrough integrity: dout/cmd_ndata_out must equal din/cmd_ndata every
    cycle (the DUT buffers the stream straight through to the next frame).

 2. Program / update correctness: between a PGM_START and the 64th data beat
    addressed to our pixel-frame ID, the streamed pixel values are recorded in
    row-major order. On UPDATE, the DAC outputs are strobed out a row at a time
    (En[row]); each captured row must match the recorded values in the same
    order. This avoids modeling the DUT's internal addressing — it only checks
    that the values stream in and come back out in the same order.

NOTE: ordering, not exact internal cycle alignment, is checked. If a real run
shows an off-by-one, the data-collection window here is the thing to tune.
*//////////////////////////////////////////////////////////////////////////////

class pf_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(pf_scoreboard)

    uvm_tlm_analysis_fifo #(pf_stream_seq_item) in_fifo;    // passthrough check
    uvm_tlm_analysis_fifo #(pf_stream_seq_item) prog_fifo;  // program model
    uvm_tlm_analysis_fifo #(pf_stream_seq_item) out_fifo;
    uvm_tlm_analysis_fifo #(pf_dac_seq_item)    dac_fifo;

    int pf_id = 1;

    // Program being streamed (row-major: index = row*PF_COLS + col).
    logic [7:0] tmp_a [$];
    logic [7:0] tmp_b [$];
    // Frame committed to the DACs at the last UPDATE — what the strobes show.
    logic [7:0] exp_a [$];
    logic [7:0] exp_b [$];
    bit         frame_valid = 0;

    int unsigned passthrough_errors = 0;
    int unsigned data_errors        = 0;
    int unsigned frames_checked     = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        in_fifo   = new("in_fifo",   this);
        prog_fifo = new("prog_fifo", this);
        out_fifo  = new("out_fifo",  this);
        dac_fifo  = new("dac_fifo",  this);
        void'(uvm_config_db #(int)::get(this, "", "pf_id", pf_id));
    endfunction

    task run_phase(uvm_phase phase);
        fork
            _check_passthrough();
            _model_program();
            _check_dac();
        join
    endtask

    // ---- Check 1: dout/cmd_ndata_out track din/cmd_ndata each cycle ----------
    task _check_passthrough();
        pf_stream_seq_item in_item, out_item;
        forever begin
            in_fifo.get(in_item);
            out_fifo.get(out_item);
            if ((in_item.data !== out_item.data) ||
                (in_item.is_cmd !== out_item.is_cmd)) begin
                `uvm_error("PF_SB",
                    $sformatf("Passthrough mismatch: in{cmd=%0b data=%h} out{cmd=%0b data=%h}",
                              in_item.is_cmd, in_item.data, out_item.is_cmd, out_item.data))
                passthrough_errors++;
            end
        end
    endtask

    // ---- Model: record the program stream and commit it on UPDATE -----------
    // tmp_* collects the beats of the in-flight program; on UPDATE we snapshot
    // it into exp_* (the frame now driven onto the DACs). Committing at UPDATE
    // (not PGM_START) keeps exp_* stable while the previous update's row strobes
    // are still being checked, so back-to-back programs don't race.
    task _model_program();
        pf_stream_seq_item it;
        bit programming = 0;
        forever begin
            prog_fifo.get(it);
            if (it.is_cmd) begin
                logic [3:0] pf_sel = it.data[7:4];
                logic [3:0] cmd    = it.data[3:0];
                if ((pf_sel == pf_id) || (pf_sel == pf_pkg::PF_SEL_ALL)) begin
                    case (cmd)
                        pf_pkg::PF_PGM_START: begin
                            programming = 1;
                            tmp_a.delete();
                            tmp_b.delete();
                        end
                        pf_pkg::PF_UPDATE: begin
                            if (tmp_a.size() == pf_pkg::PF_ROWS * pf_pkg::PF_COLS) begin
                                exp_a = tmp_a;
                                exp_b = tmp_b;
                                frame_valid = 1;
                                `uvm_info("PF_SB", $sformatf("Committed frame (%0d pixels) at UPDATE, id=%0d",
                                          exp_a.size(), pf_id), UVM_MEDIUM)
                            end
                        end
                        default: ;
                    endcase
                end
            end
            else if (programming) begin
                tmp_a.push_back(it.data[7:0]);
                tmp_b.push_back(it.data[15:8]);
                if (tmp_a.size() == pf_pkg::PF_ROWS * pf_pkg::PF_COLS)
                    programming = 0;
            end
        end
    endtask

    // ---- Check 2: each strobed DAC row matches the committed frame -----------
    task _check_dac();
        pf_dac_seq_item d;
        forever begin
            dac_fifo.get(d);
            if (!frame_valid) continue;   // no committed frame to compare against yet
            for (int c = 0; c < pf_pkg::PF_COLS; c++) begin
                int idx = d.row * pf_pkg::PF_COLS + c;
                if (idx >= exp_a.size()) continue;
                if (d.daca[c] !== exp_a[idx]) begin
                    `uvm_error("PF_SB", $sformatf("DAC A mismatch row=%0d col=%0d exp=%h got=%h",
                              d.row, c, exp_a[idx], d.daca[c]))
                    data_errors++;
                end
                if (d.dacb[c] !== exp_b[idx]) begin
                    `uvm_error("PF_SB", $sformatf("DAC B mismatch row=%0d col=%0d exp=%h got=%h",
                              d.row, c, exp_b[idx], d.dacb[c]))
                    data_errors++;
                end
            end
            if (d.row == pf_pkg::PF_ROWS - 1) frames_checked++;
        end
    endtask

    function void report_phase(uvm_phase phase);
        if (passthrough_errors == 0 && data_errors == 0)
            `uvm_info("PF_SB", $sformatf("*** SCOREBOARD PASSED *** (frames checked: %0d)",
                      frames_checked), UVM_NONE)
        else
            `uvm_error("PF_SB",
                $sformatf("*** SCOREBOARD FAILED *** passthrough_errors=%0d data_errors=%0d",
                          passthrough_errors, data_errors))
    endfunction

endclass
