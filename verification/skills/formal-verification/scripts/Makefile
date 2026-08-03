# =============================================================================
# Copyright (C) Neurophos, Inc - All Rights Reserved
# Proprietary and confidential
# -----------------------------------------------------------------------------
# TITLE : Jasper Gold formal verification flow — pf_ed
#
# Targets:
#   gui    — open interactive Jasper GUI session
#   prove  — run full batch proof (logs → logs/)
#   check  — elaborate only, validate compile + bind (no proof)
#   clean  — remove project directory and logs
# =============================================================================

ROOT_DIR     := $(shell git -C $(dir $(abspath $(lastword $(MAKEFILE_LIST)))) \
                    rev-parse --show-toplevel)
JASPER       ?= jaspergold
JG_PROJ      := jgproject
LOG_DIR      := logs
PYTHON       := $(ROOT_DIR)/scripts/venv/bin/python3
REPORT_PY    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))jg_html_report.py
TXT_RESULTS  := $(JG_PROJ)/pf_ed_formal_results.txt
HTML_REPORT  := $(JG_PROJ)/pf_ed_formal_report.html

.PHONY: gui prove check report clean help

# ---- Interactive GUI --------------------------------------------------------
gui:
	mkdir -p $(JG_PROJ) $(LOG_DIR)
	$(JASPER) -fpv -proj $(JG_PROJ) -tcl jg.tcl

# ---- Full batch proof -------------------------------------------------------
prove:
	mkdir -p $(JG_PROJ) $(LOG_DIR)
	$(JASPER) -fpv -proj $(JG_PROJ) -batch -tcl jg.tcl \
	    2>&1 | tee $(LOG_DIR)/prove.stdout
	@echo ""
	@echo "Results: $(JG_PROJ)/pf_ed_formal_results.txt"

# ---- Elaboration check only (no proof run) ----------------------------------
check:
	mkdir -p $(JG_PROJ) $(LOG_DIR)
	JG_ELAB_ONLY=1 $(JASPER) -fpv -proj $(JG_PROJ) -batch -tcl jg.tcl \
	    2>&1 | tee $(LOG_DIR)/check.stdout

# ---- HTML report from most-recent prove results -----------------------------
report: $(TXT_RESULTS)
	$(PYTHON) $(REPORT_PY) $(TXT_RESULTS) $(HTML_REPORT)
	@echo "Open: $(HTML_REPORT)"

# ---- Clean ------------------------------------------------------------------
clean:
	rm -rf $(JG_PROJ) $(LOG_DIR)

# ---- Help -------------------------------------------------------------------
help:
	@echo ""
	@echo "pf_ed Jasper Gold Formal Verification"
	@echo "======================================"
	@echo ""
	@echo "Targets:"
	@echo "  gui    — open interactive Jasper GUI session"
	@echo "  prove  — run full batch proof (results → $(JG_PROJ)/)"
	@echo "  check  — elaborate only: validate compile + bind, no proof"
	@echo "  report — convert last prove results to HTML (requires prior prove run)"
	@echo "  clean  — remove $(JG_PROJ)/ and $(LOG_DIR)/"
	@echo "  help   — show this message"
	@echo ""
	@echo "Variables (override on command line):"
	@echo "  JASPER=$(JASPER)"
	@echo ""
	@echo "Logs:    $(LOG_DIR)/prove.stdout"
	@echo "Results: $(TXT_RESULTS)"
	@echo "HTML:    $(HTML_REPORT)"
	@echo ""
