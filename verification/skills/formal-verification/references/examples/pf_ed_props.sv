// ============================================================================
// Copyright (C) Neurophos, Inc - All Rights Reserved
// Proprietary and confidential
// ----------------------------------------------------------------------------
// FILE  : pf_ed_props.sv
// TITLE : Formal SVA property module for pf_ed
//
// Bound to pf_ed via the bind statement at the bottom of this file.
// All properties reference internal signals directly through the bind scope.
//
// Verification intent derived from the UVM scoreboard (pf_scoreboard.sv):
//   1. Passthrough integrity  - dout/cmd_ndata_out/rst_out track din/inputs.
//   2. FSM correctness        - valid state encoding, legal transitions.
//   3. Row-enable protocol    - En is always zero or one-hot; non-zero only in UPDATE2_ST.
//   4. rdata_out protocol     - high during programming and update operations.
//   5. UPDATE data transfer   - DAC outputs match the preloaded values.
//   6. Counter bounds         - row and col stay within array dimensions.
// ============================================================================

`ifndef PF_ED_PROPS_SV
`define PF_ED_PROPS_SV

module pf_ed_props #(
    parameter int NUM_ROWS = 8,
    parameter int NUM_COLS = 8
) (
    // Internal clock and reset (derived from clk_in / rst_in via cell wrappers)
    input logic        clk_int,
    input logic        arst_n,

    // FSM state
    input logic [2:0]  fsm_st,

    // Passthrough datapath (DUT ports)
    input logic [15:0] din,
    input logic [15:0] dout,
    input logic        cmd_ndata_in,
    input logic        cmd_ndata_out,
    input logic        rst_in,
    input logic        rst_out,

    // Protocol control signals
    input logic        cmd_ndata_q,       // flopped cmd_ndata_int
    input logic [15:0] din_q,             // flopped din_int
    input logic [3:0]  pf_sel_q,          // latched pixel-frame selector
    input logic [3:0]  addr_sel,          // this frame's ID (tied-off in silicon)

    // Row / column address counters
    input logic [3:0]  row,
    input logic [3:0]  col,

    // Read-data status
    input logic        rdata_out_int,     // local rdata status flag
    input logic        rdata_out,         // combined rdata output to chain
    input logic        rdata_in,          // rdata from right neighbor

    // Row-enable and DAC column data outputs
    input logic [7:0]  En,
    input logic [7:0]  DinA0, DinB0,
    input logic [7:0]  DinA1, DinB1,
    input logic [7:0]  DinA2, DinB2,
    input logic [7:0]  DinA3, DinB3,
    input logic [7:0]  DinA4, DinB4,
    input logic [7:0]  DinA5, DinB5,
    input logic [7:0]  DinA6, DinB6,
    input logic [7:0]  DinA7, DinB7,

    // Preload staging memories
    input logic [7:0]  daca_preload [NUM_ROWS][NUM_COLS],
    input logic [7:0]  dacb_preload [NUM_ROWS][NUM_COLS]
);

    // -------------------------------------------------------------------------
    // State encoding (matches localparam in pf_ed)
    // -------------------------------------------------------------------------
    localparam logic [2:0] IDLE_ST     = 3'h0;
    localparam logic [2:0] PGM_ST      = 3'h1;
    localparam logic [2:0] UPDATE0_ST  = 3'h2;
    localparam logic [2:0] UPDATE1_ST  = 3'h3;
    localparam logic [2:0] UPDATE2_ST  = 3'h4;

    // =========================================================================
    // --- SECTION 1: Passthrough integrity ------------------------------------
    // =========================================================================

    // Data bus: dout is din buffered through two ni_ckinv (double-inversion).
    // With NI_BEHAVIORAL the chain is combinational; check at every clock edge.
    property prop_data_passthrough;
        @(posedge clk_int) dout == din;
    endproperty
    ast_data_passthrough: assert property (prop_data_passthrough)
        else $error("pf_ed: data passthrough violation dout=%h din=%h", dout, din);

    // Command/data flag passthrough (same inverter-pair structure)
    property prop_cmd_passthrough;
        @(posedge clk_int) cmd_ndata_out == cmd_ndata_in;
    endproperty
    ast_cmd_passthrough: assert property (prop_cmd_passthrough)
        else $error("pf_ed: cmd_ndata passthrough violation");

    // Reset passthrough
    property prop_rst_passthrough;
        @(posedge clk_int) rst_out == rst_in;
    endproperty
    ast_rst_passthrough: assert property (prop_rst_passthrough)
        else $error("pf_ed: rst passthrough violation");

    // rdata_out = rdata_in | rdata_out_int  (OR cell through a buffer)
    property prop_rdata_or;
        @(posedge clk_int) rdata_out == (rdata_in | rdata_out_int);
    endproperty
    ast_rdata_or: assert property (prop_rdata_or)
        else $error("pf_ed: rdata_out OR combination violated");

    // =========================================================================
    // --- SECTION 2: FSM correctness ------------------------------------------
    // =========================================================================

    // FSM state is always one of the five defined states.
    property prop_fsm_valid;
        @(posedge clk_int) fsm_st inside {IDLE_ST, PGM_ST, UPDATE0_ST, UPDATE1_ST, UPDATE2_ST};
    endproperty
    ast_fsm_valid: assert property (prop_fsm_valid)
        else $error("pf_ed: illegal FSM state %0h", fsm_st);

    // While reset is active (arst_n=0), FSM is held in IDLE.
    property prop_reset_holds_idle;
        @(posedge clk_int) (!arst_n) |-> (fsm_st == IDLE_ST);
    endproperty
    ast_reset_holds_idle: assert property (prop_reset_holds_idle)
        else $error("pf_ed: FSM not in IDLE during reset");

    // UPDATE sequence must progress in order: UPDATE0 → UPDATE1 → UPDATE2.
    property prop_update_seq_0_to_1;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE0_ST) |=> (fsm_st == UPDATE1_ST);
    endproperty
    ast_update_seq_0_to_1: assert property (prop_update_seq_0_to_1)
        else $error("pf_ed: UPDATE0_ST did not advance to UPDATE1_ST");

    property prop_update_seq_1_to_2;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE1_ST) |=> (fsm_st == UPDATE2_ST);
    endproperty
    ast_update_seq_1_to_2: assert property (prop_update_seq_1_to_2)
        else $error("pf_ed: UPDATE1_ST did not advance to UPDATE2_ST");

    // UPDATE2 exits either back to UPDATE0 (more rows) or to IDLE (last row).
    property prop_update_seq_2_exit;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE2_ST) |=> (fsm_st inside {IDLE_ST, UPDATE0_ST});
    endproperty
    ast_update_seq_2_exit: assert property (prop_update_seq_2_exit)
        else $error("pf_ed: UPDATE2_ST exited to unexpected state");

    // On the last update row, UPDATE2 must return to IDLE.
    property prop_update_last_row_to_idle;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE2_ST && row == NUM_ROWS-1) |=> (fsm_st == IDLE_ST);
    endproperty
    ast_update_last_row_to_idle: assert property (prop_update_last_row_to_idle)
        else $error("pf_ed: last UPDATE2_ST row did not return to IDLE");

    // After the last programming pixel (col==NUM_COLS-1, row==NUM_ROWS-1 in
    // PGM_ST with a data beat), the FSM returns to IDLE on the next clock.
    property prop_pgm_last_pixel_to_idle;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == PGM_ST && cmd_ndata_q == 1'b0 &&
         row == NUM_ROWS-1 && col == NUM_COLS-1) |=> (fsm_st == IDLE_ST);
    endproperty
    ast_pgm_last_pixel_to_idle: assert property (prop_pgm_last_pixel_to_idle)
        else $error("pf_ed: PGM_ST did not return to IDLE after last pixel");

    // =========================================================================
    // --- SECTION 3: Row-enable (En) protocol ---------------------------------
    // =========================================================================

    // En is always zero or one-hot — never two or more rows asserted at once.
    property prop_en_onehot_zero;
        @(posedge clk_int) $onehot0(En);
    endproperty
    ast_en_onehot_zero: assert property (prop_en_onehot_zero)
        else $error("pf_ed: En is not zero or one-hot: %b", En);

    // En is only non-zero when the FSM is in UPDATE2_ST.
    // En is the registered form of n_row_sel; n_row_sel is driven to one-hot
    // in UPDATE1_ST and defaults to '0 in all other states.  The register
    // therefore holds the one-hot value for exactly the UPDATE2_ST cycle.
    property prop_en_only_update2;
        @(posedge clk_int) disable iff (!arst_n)
        (En != '0) |-> (fsm_st == UPDATE2_ST);
    endproperty
    ast_en_only_update2: assert property (prop_en_only_update2)
        else $error("pf_ed: En asserted outside UPDATE2_ST (state=%0h)", fsm_st);

    // In UPDATE2_ST the correct row bit is asserted: En[row] == 1.
    // row does not increment until the posedge leaving UPDATE2_ST, so the
    // row value visible in UPDATE2_ST matches the bit that was set in UPDATE1_ST.
    property prop_en_correct_row;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE2_ST) |-> (En[row] == 1'b1);
    endproperty
    ast_en_correct_row: assert property (prop_en_correct_row)
        else $error("pf_ed: En[%0d] not asserted in UPDATE2_ST (En=%b)", row, En);

    // =========================================================================
    // --- SECTION 4: rdata_out protocol ---------------------------------------
    // =========================================================================

    // rdata_out_int is high while in PGM_ST (signals busy to the chain).
    // rdata_out_int is a registered signal; n_rdata_out_int is set to 1 by the
    // PGM_ST combinational logic, so the register holds 1 from the SECOND cycle
    // onward.  Check only when the previous cycle was also PGM_ST to avoid a
    // spurious failure on the single entry cycle where rdata_out_int is still 0.
    property prop_rdata_high_in_pgm;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == PGM_ST && $past(fsm_st) == PGM_ST) |-> (rdata_out_int == 1'b1);
    endproperty
    ast_rdata_high_in_pgm: assert property (prop_rdata_high_in_pgm)
        else $error("pf_ed: rdata_out_int not high in PGM_ST (second cycle+)");

    // rdata_out_int is high during the UPDATE sequence (after the first UPDATE0 cycle).
    // Same registered-output lag as PGM_ST: n_rdata_out_int is set in UPDATE0_ST,
    // so rdata_out_int becomes 1 in UPDATE1_ST.  Check only when the previous cycle
    // was also inside the UPDATE sequence.
    property prop_rdata_high_in_update;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st inside {UPDATE0_ST, UPDATE1_ST, UPDATE2_ST} &&
         $past(fsm_st) inside {UPDATE0_ST, UPDATE1_ST, UPDATE2_ST})
        |-> (rdata_out_int == 1'b1);
    endproperty
    ast_rdata_high_in_update: assert property (prop_rdata_high_in_update)
        else $error("pf_ed: rdata_out_int not high in UPDATE sequence (second cycle+)");

    // rdata_out_int is low in IDLE (no spurious busy signalling at rest).
    property prop_rdata_low_in_idle;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == IDLE_ST) |-> (rdata_out_int == 1'b0);
    endproperty
    ast_rdata_low_in_idle: assert property (prop_rdata_low_in_idle)
        else $error("pf_ed: rdata_out_int spuriously high in IDLE_ST");

    // =========================================================================
    // --- SECTION 5: UPDATE data transfer correctness -------------------------
    //
    // When UPDATE0_ST fires, the combinational mux loads
    // n_col_dacX_a/b_data from daca/b_preload[row][X]. On the following
    // posedge (UPDATE1_ST) DinAX must hold those captured preload values.
    // Uses SVA local variables to capture preload at UPDATE0 time.
    // =========================================================================

    property prop_update_data_correct;
        logic [7:0] a0, b0, a1, b1, a2, b2, a3, b3,
                    a4, b4, a5, b5, a6, b6, a7, b7;
        @(posedge clk_int) disable iff (!arst_n)
        (fsm_st == UPDATE0_ST,
         a0 = daca_preload[row][0], b0 = dacb_preload[row][0],
         a1 = daca_preload[row][1], b1 = dacb_preload[row][1],
         a2 = daca_preload[row][2], b2 = dacb_preload[row][2],
         a3 = daca_preload[row][3], b3 = dacb_preload[row][3],
         a4 = daca_preload[row][4], b4 = dacb_preload[row][4],
         a5 = daca_preload[row][5], b5 = dacb_preload[row][5],
         a6 = daca_preload[row][6], b6 = dacb_preload[row][6],
         a7 = daca_preload[row][7], b7 = dacb_preload[row][7]) |=>
        (DinA0 == a0 && DinB0 == b0 &&
         DinA1 == a1 && DinB1 == b1 &&
         DinA2 == a2 && DinB2 == b2 &&
         DinA3 == a3 && DinB3 == b3 &&
         DinA4 == a4 && DinB4 == b4 &&
         DinA5 == a5 && DinB5 == b5 &&
         DinA6 == a6 && DinB6 == b6 &&
         DinA7 == a7 && DinB7 == b7);
    endproperty
    ast_update_data_correct: assert property (prop_update_data_correct)
        else $error("pf_ed: DAC output does not match preload in UPDATE1_ST (row=%0d)", row);

    // =========================================================================
    // --- SECTION 6: Counter bounds -------------------------------------------
    // =========================================================================

    property prop_row_in_range;
        @(posedge clk_int) row < NUM_ROWS;
    endproperty
    ast_row_in_range: assert property (prop_row_in_range)
        else $error("pf_ed: row counter out of range: %0d", row);

    property prop_col_in_range;
        @(posedge clk_int) col < NUM_COLS;
    endproperty
    ast_col_in_range: assert property (prop_col_in_range)
        else $error("pf_ed: col counter out of range: %0d", col);

    // =========================================================================
    // --- SECTION 7: Cover points (reachability) ------------------------------
    // =========================================================================

    // Verify these states / conditions are reachable (not vacuously unreachable)
    cov_pgm_entered:
        cover property (@(posedge clk_int) disable iff (!arst_n) fsm_st == PGM_ST);

    cov_update_entered:
        cover property (@(posedge clk_int) disable iff (!arst_n) fsm_st == UPDATE0_ST);

    cov_update_all_rows:
        cover property (@(posedge clk_int) disable iff (!arst_n)
                        (fsm_st == UPDATE1_ST && row == NUM_ROWS-1));

    cov_pgm_full_frame:
        cover property (@(posedge clk_int) disable iff (!arst_n)
                        (fsm_st == PGM_ST && cmd_ndata_q == 1'b0 &&
                         row == NUM_ROWS-1 && col == NUM_COLS-1));

    cov_rdata_driven:
        cover property (@(posedge clk_int) disable iff (!arst_n) rdata_out == 1'b1);

    cov_broadcast_cmd:
        cover property (@(posedge clk_int) disable iff (!arst_n)
                        (cmd_ndata_q == 1'b1 && din_q[7:4] == 4'hF));

endmodule : pf_ed_props

// =============================================================================
// Bind pf_ed_props into the pf_ed scope so properties access internal signals.
// =============================================================================
bind pf_ed pf_ed_props #(
    .NUM_ROWS (NUM_ROWS),
    .NUM_COLS (NUM_COLS)
) u_pf_ed_props (
    .clk_int        (clk_int),
    .arst_n         (arst_n),
    .fsm_st         (fsm_st),
    .din            (din),
    .dout           (dout),
    .cmd_ndata_in   (cmd_ndata_in),
    .cmd_ndata_out  (cmd_ndata_out),
    .rst_in         (rst_in),
    .rst_out        (rst_out),
    .cmd_ndata_q    (cmd_ndata_q),
    .din_q          (din_q),
    .pf_sel_q       (pf_sel_q),
    .addr_sel       (addr_sel),
    .row            (row),
    .col            (col),
    .rdata_out_int  (rdata_out_int),
    .rdata_out      (rdata_out),
    .rdata_in       (rdata_in),
    .En             (En),
    .DinA0(DinA0), .DinB0(DinB0),
    .DinA1(DinA1), .DinB1(DinB1),
    .DinA2(DinA2), .DinB2(DinB2),
    .DinA3(DinA3), .DinB3(DinB3),
    .DinA4(DinA4), .DinB4(DinB4),
    .DinA5(DinA5), .DinB5(DinB5),
    .DinA6(DinA6), .DinB6(DinB6),
    .DinA7(DinA7), .DinB7(DinB7),
    .daca_preload   (daca_preload),
    .dacb_preload   (dacb_preload)
);

`endif // PF_ED_PROPS_SV
