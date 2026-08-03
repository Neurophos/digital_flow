##############################################################################
# pf_ed UVM Unit Testbench — Xcelium (xrun)
# Usage:
#   make sim                                  # build + run default test
#   make sim TESTNAME=pf_program_test WAVE=1
#   make help
##############################################################################

.DEFAULT_GOAL := help

# Must be set before including Makefile.common so DESIGN_CONFIG_FILE resolves
DESIGN_NAME := pf_ed

ROOT_DIR    := $(shell git rev-parse --show-toplevel)/

# Pulls in: ALCHEMY, DESIGN_CONFIG_FILE, DESIGN_DIR, CURR_DIR, tool paths
include $(ROOT_DIR)utils/chip_utils/config/Makefile.common

UVM_DIR     := $(CURR_DIR)

# Command-line options (TESTNAME must precede RUN_DIR expansion)
TESTNAME    ?= pf_program_test
GUI         ?= 0
PROBE       ?= 0
WAVE        ?= 0
SEED        ?= 1
TIMEOUT_NS  ?=
COV         ?= 0
COV_DUT     ?= pf_ed

# -------------------------------------------------------------------------
# Scratch tree — all build/sim artifacts live under scratch/
# -------------------------------------------------------------------------
SCRATCH_DIR := $(UVM_DIR)scratch/
HDL_DIR     := $(SCRATCH_DIR)hdl/
HVL_DIR     := $(SCRATCH_DIR)hvl/
SIMLAND_DIR := $(SCRATCH_DIR)simland/
RUN_DIR     := $(SIMLAND_DIR)$(TESTNAME)/
XCELIUM_D   := $(SCRATCH_DIR)xcelium.d
COV_WORKDIR := $(SCRATCH_DIR)cov_work
COV_SCOPE   := $(COV_WORKDIR)/scope
COV_MERGED  := $(COV_SCOPE)/merged

# imc (coverage GUI / merge / report) ships with the vmanager package, and its
# coverage engine comes from Xcelium (MDV_XLM_HOME) — set both up first.
IMC_MODULE  := cadence/vmanager/25.09.003
IMC_LOAD    := source /usr/share/Modules/init/bash && module load $(IMC_MODULE) && \
               export MDV_XLM_HOME=$(XCELIUM_BASE_PATH) &&
COV_REPORT_DIR := $(SCRATCH_DIR)cov_report

# Generated design filelist (Alchemy, from the pf_ed YAML: pf_ed.sv + ni_parts)
MODULE_FILELIST := $(SCRATCH_DIR)$(DESIGN_NAME).f

# The DUT is pf_ed_wrapper (pin-name conversion wrapper around pf_ed). It is not
# in the design YAML, so add it explicitly to the HDL compile.
WRAPPER := $(DESIGN_DIR)pf_ed/rtl/pf_ed_wrapper.sv

XRUN := xrun

# -------------------------------------------------------------------------
# xrun base options (aligned with the project's XRUN_BASE_OPTS)
# -------------------------------------------------------------------------
XRUN_BASE_OPTS := \
    -64bit \
    -sv \
    -uvm \
    -uvmhome CDNS-1.2 \
    -timescale 1ns/1ps \
    -disable_sem2009 \
    -access +rc \
    +libext+.v+.sv+.vp+.vlib \
    -enable_work_yvlib \
    -define NI_BEHAVIORAL \
    -define SIMULATION

XRUN_FLAGS := \
    $(XRUN_BASE_OPTS) \
    +UVM_TESTNAME=$(TESTNAME) \
    +UVM_VERBOSITY=UVM_MEDIUM \
    -svseed $(SEED) \
    -xmlibdirname $(XCELIUM_D) \
    -history_file $(SIMLAND_DIR)xrun.history \
    -l $(RUN_DIR)sim.log

ifneq ($(strip $(TIMEOUT_NS)),)
XRUN_FLAGS += +TIMEOUT_NS=$(TIMEOUT_NS)
endif

# Post-simulation IMC Tcl exclusion script (signal-level toggle exclusions
# for dead logic and structurally-unreachable counter bits).
EXCL_TCL   := $(UVM_DIR)pf_ed_excl.tcl

ifeq ($(COV),1)
XRUN_FLAGS += -coverage all -covoverwrite -covworkdir $(COV_WORKDIR) \
              -covtest $(TESTNAME) -covdut $(COV_DUT) +func_cov
endif

ifeq ($(GUI),1)
XRUN_FLAGS += -gui
endif

ifeq ($(PROBE),1)
XRUN_FLAGS += -input "@database -open waves -into waves.shm -default; \
    probe -create pf_tb_top_hdl -shm -depth all -all -memories -dynamic"
endif

WAVE_DB    := $(RUN_DIR)waves.shm
WAVE_PROBE := @database -open waves -into $(WAVE_DB) -default; \
    probe -create pf_tb_top_hdl -shm -depth all -all -memories -dynamic
ifeq ($(WAVE),1)
ifeq ($(GUI),1)
XRUN_FLAGS += -input "$(WAVE_PROBE)"
else
XRUN_FLAGS += -input "$(WAVE_PROBE); run; exit"
endif
endif

# -------------------------------------------------------------------------
# Include paths (for `include resolution inside packages)
# -------------------------------------------------------------------------
INCDIR := \
    +incdir+$(UVM_DIR)common \
    +incdir+$(UVM_DIR)interfaces \
    +incdir+$(UVM_DIR)env \
    +incdir+$(UVM_DIR)sequences \
    +incdir+$(UVM_DIR)tests \
    +incdir+$(UVM_DIR)scoreboards \
    +incdir+$(UVM_DIR)agents/stream \
    +incdir+$(UVM_DIR)agents/dac \
    +incdir+$(UVM_DIR)tb

# -------------------------------------------------------------------------
# Source partitions
#   HDL : pf_pkg + design(.f) + wrapper + interfaces + HDL top
#   HVL : agent pkgs + tb pkg + HVL top
# -------------------------------------------------------------------------
PF_PKG     := $(UVM_DIR)common/pf_pkg.sv

INTERFACES := \
    $(UVM_DIR)interfaces/pf_clk_rst_if.sv \
    $(UVM_DIR)interfaces/pf_stream_if.sv \
    $(UVM_DIR)interfaces/pf_dac_if.sv

HDL_TOP := $(UVM_DIR)tb/pf_tb_top_hdl.sv

AGENT_PKGS := \
    $(UVM_DIR)agents/stream/pf_stream_pkg.sv \
    $(UVM_DIR)agents/dac/pf_dac_pkg.sv

TB_PKG  := $(UVM_DIR)tb/pf_tb_pkg.sv
HVL_TOP := $(UVM_DIR)tb/pf_tb_top_hvl.sv

# -------------------------------------------------------------------------
# Targets
# -------------------------------------------------------------------------
COV_SERVE_PORT ?= 8080

.PHONY: sim filelist clean help helpcov cov_gui cov_merge cov_report cov_excl_report cov_serve

sim: $(MODULE_FILELIST) | $(HDL_DIR) $(HVL_DIR) $(RUN_DIR) $(XCELIUM_D)
	$(XRUN) $(XRUN_FLAGS) $(INCDIR) \
	    -makelib $(HDL_DIR) \
	        $(PF_PKG) \
	        -f $(MODULE_FILELIST) \
	        $(WRAPPER) \
	        $(INTERFACES) \
	        $(HDL_TOP) \
	    -endlib \
	    -makelib $(HVL_DIR) \
	        $(AGENT_PKGS) \
	        $(TB_PKG) \
	        $(HVL_TOP) \
	    -endlib \
	    -top pf_tb_top_hdl \
	    -top pf_tb_top_hvl

# Preprocess the pf_ed RTL (pf_ed.pysv -> pf_ed.sv) before Alchemy lists it.
.PHONY: prepro
prepro:
	@$(MAKE) -C $(DESIGN_DIR)$(DESIGN_NAME)/rtl prepro

# Generate the design filelist from the pf_ed YAML via Alchemy (pf_ed.sv + ni_parts)
$(MODULE_FILELIST): $(DESIGN_CONFIG_FILE) | $(SCRATCH_DIR)
	@echo "Preprocessing pf_ed RTL (pysv -> sv)..."
	@$(MAKE) -C $(DESIGN_DIR)$(DESIGN_NAME)/rtl prepro
	@echo "Generating design filelist via Alchemy..."
	@$(ALCHEMY) -ws $(ROOT_DIR) -yaml $(DESIGN_CONFIG_FILE) -top $(DESIGN_NAME) -sim $(MODULE_FILELIST) -abs

filelist: $(MODULE_FILELIST)
	@echo "Design filelist: $(MODULE_FILELIST)"

$(SCRATCH_DIR) $(HDL_DIR) $(HVL_DIR) $(SIMLAND_DIR) $(RUN_DIR) $(XCELIUM_D):
	mkdir -p $@

clean:
	rm -rf $(SCRATCH_DIR) xcelium.d cds.lib hdl.var *.log *.key *.diag

cov_gui:
	@test -d $(COV_SCOPE)/$(TESTNAME) || { \
	    echo "No coverage data at $(COV_SCOPE)/$(TESTNAME)."; \
	    echo "Run 'make sim COV=1 TESTNAME=$(TESTNAME)' first."; exit 1; }
	$(IMC_LOAD) imc -64bit -gui -load $(COV_SCOPE)/$(TESTNAME) &

# Generate a non-interactive (batch) coverage report for TESTNAME:
#   - a detailed HTML report (all metrics, openable in a browser)
#   - an uncovered-only detail report to highlight what's missing
# Set REPORT_TEST=merged to report the merged database.
REPORT_TEST ?= $(TESTNAME)
cov_report:
	@test -d $(COV_SCOPE)/$(REPORT_TEST) || { \
	    echo "No coverage data at $(COV_SCOPE)/$(REPORT_TEST)."; \
	    echo "Run 'make sim COV=1 TESTNAME=$(REPORT_TEST)' first."; exit 1; }
	@mkdir -p $(COV_REPORT_DIR)
	$(IMC_LOAD) imc -64bit -execcmd \
	    "load -run $(COV_SCOPE)/$(REPORT_TEST); \
	     report_metrics -detail -all -metrics all -source off -out $(COV_REPORT_DIR)/full -overwrite; \
	     report_metrics -detail -uncovered -metrics all -source off -out $(COV_REPORT_DIR)/uncovered -overwrite; \
	     exit"
	@echo "Full report     : $(COV_REPORT_DIR)/full/index.html"
	@echo "Uncovered report: $(COV_REPORT_DIR)/uncovered/index.html"
	@echo ""
	@echo "NOTE: Open reports via 'make cov_serve' — Firefox blocks file:// JS loading."

cov_merge:
	@runs=$$(find $(COV_SCOPE) -mindepth 1 -maxdepth 1 -type d ! -name merged 2>/dev/null); \
	if [ -z "$$runs" ]; then \
	    echo "No coverage runs found under $(COV_SCOPE)."; \
	    echo "Run 'make sim COV=1 ...' for one or more tests first."; exit 1; \
	fi; \
	echo "Merging coverage runs:"; for r in $$runs; do echo "  $$r"; done; \
	run_args=$$(echo "$$runs" | tr '\n' ' '); \
	$(IMC_LOAD) imc -64bit -execcmd "merge $$run_args -out $(COV_MERGED) -overwrite; exit"
	@echo "Merged coverage written to $(COV_MERGED)"
	@echo "View with: make cov_gui TESTNAME=merged"

# Like cov_report but sources pf_ed_excl.tcl first so that dead logic and
# unreachable counter bits are excluded before grade calculation.
# Typical flow:
#   make sim COV=1 TESTNAME=pf_coverage_test
#   make cov_excl_report REPORT_TEST=pf_coverage_test
#   (or after merge: make cov_merge && make cov_excl_report REPORT_TEST=merged)
cov_excl_report:
	@test -d $(COV_SCOPE)/$(REPORT_TEST) || { \
	    echo "No coverage data at $(COV_SCOPE)/$(REPORT_TEST)."; \
	    echo "Run 'make sim COV=1 TESTNAME=$(REPORT_TEST)' first."; exit 1; }
	@test -f $(EXCL_TCL) || { echo "Exclusion script not found: $(EXCL_TCL)"; exit 1; }
	@mkdir -p $(COV_REPORT_DIR)
	$(IMC_LOAD) imc -64bit -execcmd \
	    "load -run $(COV_SCOPE)/$(REPORT_TEST); \
	     source $(EXCL_TCL); \
	     report_metrics -detail -all -metrics all -source off -out $(COV_REPORT_DIR)/full_excl -overwrite; \
	     report_metrics -detail -uncovered -metrics all -source off -out $(COV_REPORT_DIR)/uncovered_excl -overwrite; \
	     exit"
	@echo "Full report (with exclusions)     : $(COV_REPORT_DIR)/full_excl/index.html"
	@echo "Uncovered report (with exclusions): $(COV_REPORT_DIR)/uncovered_excl/index.html"
	@echo ""
	@echo "NOTE: Open reports via 'make cov_serve' — Firefox blocks file:// JS loading."

# IMC HTML reports use JavaScript to load report_data/data.report.
# Browsers block that fetch when index.html is opened via file://, so the
# report must be served over HTTP.  A local Python server fixes this.
cov_serve:
	@test -d $(COV_REPORT_DIR) || { \
	    echo "No reports found at $(COV_REPORT_DIR)."; \
	    echo "Run 'make cov_report' or 'make cov_excl_report' first."; exit 1; }
	@echo "Serving coverage reports at http://localhost:$(COV_SERVE_PORT)/"
	@echo "Sub-reports available:"
	@ls -d $(COV_REPORT_DIR)/*/index.html 2>/dev/null | sed "s|$(COV_REPORT_DIR)/|  http://localhost:$(COV_SERVE_PORT)/|"
	@echo "Press Ctrl-C to stop."
	cd $(COV_REPORT_DIR) && env -u LD_LIBRARY_PATH python3 -m http.server $(COV_SERVE_PORT)

help:
	@echo ""
	@echo "============================================================================"
	@echo " pf_ed UVM Unit Testbench  —  Xcelium (xrun)"
	@echo "============================================================================"
	@echo ""
	@echo " Run all commands from this directory (design/pf_ed/uvm)."
	@echo ""
	@echo " Usage:"
	@echo "   make <target> [OPTION=value ...]"
	@echo ""
	@echo " Targets:"
	@echo "   sim        Build (design + UVM TB) and run a test."
	@echo "   filelist   (Re)generate the design .f filelist from the YAML via Alchemy."
	@echo "   clean      Remove the scratch/ tree and any stray build artifacts."
	@echo "   cov_gui         Open TESTNAME's coverage report in the IMC GUI (after COV=1)."
	@echo "   cov_report      Batch HTML coverage report (full + uncovered) for TESTNAME."
	@echo "   cov_merge       Merge all per-test coverage runs into 'merged'."
	@echo "   cov_excl_report Like cov_report but applies pf_ed_excl.tcl exclusions first."
	@echo "   help            Show this message (default target)."
	@echo ""
	@echo " Options (pass as VAR=value):"
	@echo "   TESTNAME=<name>  UVM test to run                  (default: $(TESTNAME))"
	@echo "   SEED=<N>         Randomization seed (-svseed)     (default: $(SEED))"
	@echo "   TIMEOUT_NS=<ns>  Watchdog timeout in ns           (default: 1000000 = 1 ms)"
	@echo "   COV=1            Enable coverage generation       (DUT: COV_DUT=$(COV_DUT))"
	@echo "   WAVE=1           Dump SHM waveforms to scratch/simland/<test>/waves.shm"
	@echo "   GUI=1            Open the Simvision GUI after elaboration"
	@echo "   PROBE=1          Auto-probe all signals (use with GUI=1)"
	@echo ""
	@echo " How to run (examples):"
	@echo "   make sim"
	@echo "   make sim TESTNAME=pf_program_test WAVE=1"
	@echo "   make sim COV=1   &&   make cov_gui"
	@echo ""
	@echo " Available tests:"
	@ls $(UVM_DIR)tests/*.sv 2>/dev/null | xargs -n1 -I{} basename {} .sv | sed 's/^/   /'
	@echo ""
	@echo " See also: make helpcov  (coverage + IMC report workflow)"
	@echo ""

helpcov:
	@echo ""
	@echo "============================================================================"
	@echo " pf_ed Coverage & IMC Report Workflow"
	@echo "============================================================================"
	@echo ""
	@echo " 1. Run simulation with coverage instrumentation:"
	@echo ""
	@echo "   make sim COV=1 TESTNAME=pf_coverage_test"
	@echo "   make sim COV=1 TESTNAME=pf_program_test"
	@echo ""
	@echo " 2a. Open interactive IMC GUI for a single run:"
	@echo ""
	@echo "   make cov_gui TESTNAME=pf_coverage_test"
	@echo ""
	@echo " 2b. Batch HTML report (full + uncovered, NO exclusions):"
	@echo ""
	@echo "   make cov_report REPORT_TEST=pf_coverage_test"
	@echo "   # outputs:"
	@echo "   #   scratch/cov_report/full/index.html"
	@echo "   #   scratch/cov_report/uncovered/index.html"
	@echo ""
	@echo " 2c. Batch HTML report WITH toggle exclusions applied (pf_ed_excl.tcl):"
	@echo ""
	@echo "   make cov_excl_report REPORT_TEST=pf_coverage_test"
	@echo "   # outputs:"
	@echo "   #   scratch/cov_report/full_excl/index.html"
	@echo "   #   scratch/cov_report/uncovered_excl/index.html"
	@echo ""
	@echo " 2d. View reports in Firefox (REQUIRED — do NOT open index.html directly):"
	@echo ""
	@echo "   make cov_serve          # default port $(COV_SERVE_PORT)"
	@echo "   make cov_serve COV_SERVE_PORT=9090"
	@echo "   # then open http://localhost:$(COV_SERVE_PORT)/full_excl/index.html"
	@echo ""
	@echo "   WHY: IMC reports load report_data/data.report via JavaScript."
	@echo "   Firefox (and Chrome) block that fetch when using file:// URLs"
	@echo "   (same-origin policy). A local HTTP server bypasses this."
	@echo ""
	@echo " 3. Merge multiple test runs, then report the combined database:"
	@echo ""
	@echo "   make cov_merge"
	@echo "   make cov_excl_report REPORT_TEST=merged"
	@echo "   make cov_gui         TESTNAME=merged"
	@echo ""
	@echo "============================================================================"
	@echo " Manual IMC batch mode (what the targets wrap)"
	@echo "============================================================================"
	@echo ""
	@echo "  source /usr/share/Modules/init/bash"
	@echo "  module load $(IMC_MODULE)"
	@echo "  export MDV_XLM_HOME=$(XCELIUM_BASE_PATH)"
	@echo ""
	@echo "  # Plain report:"
	@echo "  imc -64bit -execcmd \\"
	@echo "    \"load -run scratch/cov_work/scope/<TESTNAME>; \\"
	@echo "     report_metrics -detail -all      -metrics all -source off -out scratch/cov_report/full      -overwrite; \\"
	@echo "     report_metrics -detail -uncovered -metrics all -source off -out scratch/cov_report/uncovered -overwrite; \\"
	@echo "     exit\""
	@echo ""
	@echo "  # Report with signal-level toggle exclusions:"
	@echo "  imc -64bit -execcmd \\"
	@echo "    \"load -run scratch/cov_work/scope/<TESTNAME>; \\"
	@echo "     source $(EXCL_TCL); \\"
	@echo "     report_metrics -detail -all      -metrics all -source off -out scratch/cov_report/full_excl      -overwrite; \\"
	@echo "     report_metrics -detail -uncovered -metrics all -source off -out scratch/cov_report/uncovered_excl -overwrite; \\"
	@echo "     exit\""
	@echo ""
	@echo "  # Merge two runs, then view:"
	@echo "  imc -64bit -execcmd \\"
	@echo "    \"merge scratch/cov_work/scope/pf_coverage_test scratch/cov_work/scope/pf_program_test \\"
	@echo "           -out scratch/cov_work/scope/merged -overwrite; exit\""
	@echo ""
	@echo "============================================================================"
	@echo " report_metrics flag reference"
	@echo "============================================================================"
	@echo ""
	@echo "   -detail          per-item breakdown (not just totals)"
	@echo "   -all             all items (covered + uncovered)"
	@echo "   -uncovered       only items with 0 hits (highlights gaps)"
	@echo "   -metrics all     all types: block, toggle, FSM, branch, expr, statement, functional"
	@echo "   -metrics toggle  toggle only"
	@echo "   -source off      omit annotated source in HTML (faster, smaller)"
	@echo "   -out <dir>       output directory  →  <dir>/index.html + <dir>/report_data/"
	@echo "   -overwrite       replace existing report directory"
	@echo ""
	@echo " Exclusions file : $(EXCL_TCL)"
	@echo " Coverage scope  : $(COV_SCOPE)/"
	@echo " Report root     : $(COV_REPORT_DIR)/"
	@echo ""
