# =============================================================================
# Copyright (C) Neurophos, Inc - All Rights Reserved
# Proprietary and confidential
# -----------------------------------------------------------------------------
# FILE  : jg.tcl
# TITLE : Jasper Gold formal verification flow for pf_ed
#
# USAGE (via Makefile targets):
#   make gui    -- interactive GUI session
#   make prove  -- batch proof, results written to logs/
#   make check  -- elaborate only, no proof
#
# DESIGN: pf_ed (Pixel Frame Embedded Digital block)
# TOP  : pf_ed_wrapper (pin-renaming wrapper; pf_ed is the actual DUT)
#
# PROPERTIES: sva/pf_ed_props.sv (bound to pf_ed)
#   Section 1 – Passthrough integrity (dout/cmd/rst/rdata chain)
#   Section 2 – FSM correctness (valid states, legal transitions, reset)
#   Section 3 – Row-enable (En) one-hot protocol
#   Section 4 – rdata_out active during programming / update
#   Section 5 – UPDATE data-transfer correctness (preload → DAC outputs)
#   Section 6 – Counter bounds (row < NUM_ROWS, col < NUM_COLS)
#   Section 7 – Cover points (PGM_ST, UPDATE reached, full-frame, broadcast)
# =============================================================================

clear -all

# ---------------------------------------------------------------------------
# Locate project root via git so paths are workspace-relative
# ---------------------------------------------------------------------------
set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set ROOT_DIR    [string trimright \
                    [exec git -C $SCRIPT_DIR rev-parse --show-toplevel] "\n"]

set NIPARTS_CW  $ROOT_DIR/design/ni_parts/rtl/cell_wrapper
set NIPARTS_RTL $ROOT_DIR/design/ni_parts/rtl
set DESIGN_RTL  $ROOT_DIR/design/pf_ed/rtl
set FORMAL_SVA  $ROOT_DIR/design/pf_ed/formal/sva

# ---------------------------------------------------------------------------
# Analyze: compile all sources with the behavioral-model define.
# NI_BEHAVIORAL activates the generic RTL models in each cell wrapper.
# SIMULATION is required by ni_cell_wrapper_checks.svh for non-synthesis use.
# ---------------------------------------------------------------------------
analyze -sv12 \
    +define+NI_BEHAVIORAL \
    +define+SIMULATION \
    +incdir+$NIPARTS_CW/include \
    $NIPARTS_CW/ni_gate_primitives.sv \
    $NIPARTS_CW/ni_arstn_scan_sync_pdff.sv \
    $NIPARTS_CW/ni_scan_sync_pdff.sv \
    $NIPARTS_CW/ni_ckinv.sv \
    $NIPARTS_CW/ni_ckbuf.sv \
    $NIPARTS_CW/ni_ckor2.sv \
    $NIPARTS_RTL/ni_rst_sync.sv \
    $DESIGN_RTL/pf_ed.sv \
    $DESIGN_RTL/pf_ed_wrapper.sv \
    $FORMAL_SVA/pf_ed_props.sv

# ---------------------------------------------------------------------------
# Elaborate: top is the wrapper; properties bind to pf_ed inside it.
# ---------------------------------------------------------------------------
elaborate -top pf_ed_wrapper

# Early exit for elaboration-only check (invoked via: make check)
if {[info exists env(JG_ELAB_ONLY)]} {
    puts "INFO: JG_ELAB_ONLY set — exiting after elaboration."
    exit
}

# ---------------------------------------------------------------------------
# Clock
#   clk_in is the primary input. The internal clk_int is derived from it
#   via two ni_ckinv (double-inversion = transparent in NI_BEHAVIORAL mode);
#   Jasper auto-detects it as the same clock domain.
# ---------------------------------------------------------------------------
clock clk_in

# ---------------------------------------------------------------------------
# Reset
#   rst_in: active-high primary reset input.
#   The internal ni_rst_sync synchronises deassertion with a 4-stage chain;
#   arst_n (active-low) is the internal reset that gates the DUT flip-flops.
#   Jasper applies rst_in=1 for the initial reset window and then releases.
# ---------------------------------------------------------------------------
reset -expression {rst_in == 1'b1}

# ---------------------------------------------------------------------------
# Assumptions
#   addr_sel: hardwired pixel-frame ID tie-off in silicon. Constrain it to a
#   legal ID in [0x0, 0xB]. Values 0xC–0xE are reserved; 0xF (SELPGM_ALL) is
#   the broadcast selector and must not be used as a frame's own addr_sel.
#   addr_sel is a top-level input of pf_ed_wrapper (passed through to pf_ed).
# ---------------------------------------------------------------------------
assume -name asm_addr_sel_stable { $stable(addr_sel) }
assume -name asm_addr_sel_range  { addr_sel inside {[4'h0:4'hB]} }

# ---------------------------------------------------------------------------
# Proof configuration
#   Ht  (Heuristic Transformation) – preprocesses the design
#   Tri (IC3/PDR)                  – unbounded safety proof engine
#   I   (k-induction)              – inductive strengthening
# ---------------------------------------------------------------------------
set_engine_mode {Ht Tri I}

# Maximum trace depth for BMC phase.  A full PGM+UPDATE cycle takes:
#   1 (PGM_START cmd) + 64 (data beats) + 1 (UPDATE cmd) + 8*3 (rows) = 90
# cycles minimum after reset de-asserts (~10 cycles); use 200 for margin.
set_max_trace_length 200

# ---------------------------------------------------------------------------
# Prove all properties and cover points
# ---------------------------------------------------------------------------
prove -all

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
set RESULT_DIR [file join $SCRIPT_DIR jgproject]
file mkdir $RESULT_DIR

report -summary
report -all      -file [file join $RESULT_DIR pf_ed_formal_results.txt] -force
report -summary  -file [file join $RESULT_DIR pf_ed_formal_summary.txt] -force
