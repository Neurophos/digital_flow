#!/usr/bin/env bash
# Parallel UVM regression runner for the MSIC UVM testbench.
#
# Runs the same test set as run_regression.sh, but distributes tests across N
# worker shards that execute concurrently.  Each worker uses its own isolated
# scratch directory (scratch_parN/) so the shared Xcelium worklib is never
# raced on; within a shard, xrun reuses its elaboration snapshot across the
# shard's tests (re-elaborating only when a compile-time -define changes, e.g.
# the FABIO_CLK clock variants).
#
# Usage:
#   ./run_regression_parallel.sh                 # 5 workers, no coverage
#   ./run_regression_parallel.sh JOBS=8          # 8 workers
#   ./run_regression_parallel.sh COV=1           # + coverage (collected + merged)
#   ./run_regression_parallel.sh JOBS=6 COV=1 SUBSET="msic_smoke_test fabio_cr_test"
#
# Env/args:
#   JOBS=<n>     number of parallel workers (default 5).  Keep <= available
#                Xcelium_Single_Core licenses (check: lmstat -a -c $CDS_LIC_FILE).
#   COV=1        forwarded to every 'make sim'; per-shard coverage is collected
#                into scratch/cov_work/scope and merged + reported at the end.
#   SUBSET="..." run only these labels (space-separated) — for quick validation.
#   Any other X=Y token is forwarded verbatim to every 'make sim'.
#
# Modules (xrun/imc) must be loaded in the environment before invoking, same as
# run_regression.sh.  Exit 0 iff every test passes.

set -u
UVM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$UVM_DIR"

# --------------------------------------------------------------------------
# Parse KEY=VALUE args; everything not recognised is forwarded to 'make sim'.
# --------------------------------------------------------------------------
JOBS=5                          # requested workers
MAX_LIC=5                       # hard cap on concurrent Xcelium sim licenses used
LIC_FEATURE=Xcelium_Single_Core # license feature each running sim consumes
LIC_SERVER="${CDS_LIC_FILE:-27000@fs1}"
COV=0
SUBSET=""
declare -a EXTRA_MAKE_ARGS=()
for tok in "$@"; do
    case "$tok" in
        JOBS=*)        JOBS="${tok#JOBS=}" ;;
        MAX_LIC=*)     MAX_LIC="${tok#MAX_LIC=}" ;;
        LIC_FEATURE=*) LIC_FEATURE="${tok#LIC_FEATURE=}" ;;
        LIC_SERVER=*)  LIC_SERVER="${tok#LIC_SERVER=}" ;;
        COV=1)         COV=1; EXTRA_MAKE_ARGS+=("COV=1") ;;
        SUBSET=*)      SUBSET="${tok#SUBSET=}" ;;
        *=*)           EXTRA_MAKE_ARGS+=("$tok") ;;
        *)             echo "WARN: ignoring unrecognised arg '$tok'" ;;
    esac
done

# --------------------------------------------------------------------------
# License-aware worker cap.  Each concurrently-running simulation checks out
# one $LIC_FEATURE license.  Effective workers = min(JOBS, MAX_LIC, currently
# available).  MAX_LIC (default 5) leaves headroom for other users even when
# more licenses are free.  Tune with MAX_LIC=/LIC_FEATURE=/LIC_SERVER=.
# --------------------------------------------------------------------------
cap_by_licenses() {
    if ! command -v lmstat >/dev/null 2>&1; then
        echo "WARN: lmstat not found; skipping license check (JOBS=$JOBS, MAX_LIC=$MAX_LIC)"
        (( JOBS > MAX_LIC )) && JOBS=$MAX_LIC
        return
    fi
    local line issued inuse avail eff
    line="$(lmstat -a -c "$LIC_SERVER" 2>/dev/null | grep "Users of ${LIC_FEATURE}:")"
    if [[ -z "$line" ]]; then
        echo "WARN: could not query '${LIC_FEATURE}' on ${LIC_SERVER}; capping at MAX_LIC=${MAX_LIC}"
        (( JOBS > MAX_LIC )) && JOBS=$MAX_LIC
        return
    fi
    issued="$(sed -E 's/.*Total of ([0-9]+) license.* issued.*/\1/' <<<"$line")"
    inuse="$(sed -E 's/.*Total of ([0-9]+) license.* in use.*/\1/'   <<<"$line")"
    avail=$(( issued - inuse ))
    eff=$JOBS
    (( eff > MAX_LIC )) && eff=$MAX_LIC
    (( eff > avail ))   && eff=$avail
    echo "License ${LIC_FEATURE}@${LIC_SERVER}: ${issued} issued, ${inuse} in use, ${avail} free; MAX_LIC=${MAX_LIC}"
    if (( eff < 1 )); then
        echo "ERROR: no '${LIC_FEATURE}' licenses available — aborting."; exit 1
    fi
    if (( eff != JOBS )); then
        echo "Capping workers: requested ${JOBS} -> using ${eff}."
        JOBS=$eff
    fi
}
cap_by_licenses

ALWAYS_MAKE_ARGS=(FABIO_ASSERT=1)

RESULTS_DIR="regr_results"
STATUS_DIR="${RESULTS_DIR}/parallel_status"
rm -rf "$STATUS_DIR"
mkdir -p "$RESULTS_DIR" "$STATUS_DIR"

STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
START_EPOCH="$(date +%s)"

# --------------------------------------------------------------------------
# Test lists (kept in sync with run_regression.sh).
# --------------------------------------------------------------------------
NOFW_TESTS=(
    msic_smoke_test fabio_reset_test fabio_cr_test fabio_vio_after_burst_test
    fabio_cr_vio_midburst_test fabio_invalid_cmd_test fabio_credit_stress_test
    uart_rx_toggle_test fabio_16b_mode_test jtag_probe_test jtag_coresight_test
    jtag_soc_rom_table_test jtag_mem_access_test gpio_reg_coverage_test
    dac_ctrl_reg_test fabio_tgt_reg_test spi_host_reg_test dac_fsm_test
    clock_ctrl_reg_test chip_ctrl_reg_test dac_datapath_test busmatrix_error_test fabio_intr_event_test
)
FW_TESTS=(
    coresight_fw_discovery_test fabio_write_test fabio_read_rom_test
    fabio_write_sram_test fabio_write_spi_test fabio_write_timer0_test
    fabio_write_timer1_test fabio_write_dualtimer_test fabio_write_uart0_test
    fabio_write_uart1_test fabio_write_uart2_test fabio_write_watchdog_test
    fabio_write_gpio_test fabio_write_dac_sram_test fabio_write_chip_ctrl_test
    fabio_write_clock_ctrl_test fabio_burst_write_test fabio_burst_write_sram_test
    fabio_burst_write_sram_coverage_test fabio_burst_write_dac_sram_test
    fabio_burst_read_test fabio_burst_read_rom_test fabio_write_rom_test
    fabio_burst_write_rom_test fabio_en_toggle_test fabio_virtio_c2t_test
    fabio_virtio_t2c_test fabio_virtio_c2t_irq_test fabio_virtio_t2c_irq_test
    fabio_virtio_t2c_hw_test fabio_virtio_t2c_repeated_same_data_test
    fabio_burst_read_virtio_t2c_tx_test fabio_burst_write_virtio_c2t_test
    fabio_burst_write_virtio_t2c_test fabio_burst_write_c2t_vio_midburst_test
    fabio_burst_write_t2c_vio_midburst_test fabio_burst_write_c2t_vio_midread_test
    fabio_burst_write_t2c_vio_midread_test fabio_sequencer_burst_read_test
    fabio_sequencer_dual_burst_read_b2b_test fabio_sequencer_random_traffic_test
    spi_error_interrupt_test spi_error_conditions_test fabio_bus_contention_test busmatrix_apb_contention_test
    timer0_irq_test timer1_irq_test dualtimer_test1 uart0_tx_irq_test1 uart2_tx_irq_test1 clock_ctrl_test1
    uart0_rx_test1 uart1_rx_test1 uart2_rx_test1
    spi_jedec_read_test spi_read_status_registers_test spi_word_write_test spi_page_write_test spi_clocking_test spi_fifo_depth_test spi_event_interrupt_test spi_watermark_test spi_host_test1 quad_spi_word_write_test quad_spi_page_write_test dual_spi_word_read_test dual_spi_page_read_test
)

# --------------------------------------------------------------------------
# Build the job list.  Each job is: "LABEL<TAB>make-arg make-arg ..."
# (label = sim run directory / archived log name; may differ from TESTNAME
# for the clock variants and jtag_cpu_halt).
# --------------------------------------------------------------------------
declare -a JOBS_LIST=()
add_job() { JOBS_LIST+=("$1"$'\t'"$2"); }

for t in "${NOFW_TESTS[@]}"; do add_job "$t" "TESTNAME=$t"; done
for t in "${FW_TESTS[@]}"; do   add_job "$t" "TESTNAME=$t FIRMWARE_TESTNAME=$t"; done

# DAC SRAM CPU read/write test: reads cross the 10 kHz dac_clk read
# synchroniser (~0.4 ms each); the 4-lane x 56-macro sweep needs the extended
# watchdog.  Fully toggles the ram*_gated_rdata AHB debug-read path.
add_job "dac_sram_read_test" "TESTNAME=dac_sram_read_test FIRMWARE_TESTNAME=dac_sram_read_test TIMEOUT_NS=200000000"

# FabIO clock-variant tests (compile-time -define; own RUN_LABEL).
add_job "fabio_burst_write_sram_test_10mhz"   "TESTNAME=fabio_burst_write_sram_test RUN_LABEL=fabio_burst_write_sram_test_10mhz FIRMWARE_TESTNAME=fabio_burst_write_sram_test FABIO_CLK=10"
add_job "fabio_burst_write_sram_test_1000mhz" "TESTNAME=fabio_burst_write_sram_test RUN_LABEL=fabio_burst_write_sram_test_1000mhz FIRMWARE_TESTNAME=fabio_burst_write_sram_test FABIO_CLK=1000"
add_job "fabio_burst_write_test_10mhz"        "TESTNAME=fabio_burst_write_test RUN_LABEL=fabio_burst_write_test_10mhz FIRMWARE_TESTNAME=fabio_burst_write_test FABIO_CLK=10"
add_job "fabio_burst_write_test_1000mhz"      "TESTNAME=fabio_burst_write_test RUN_LABEL=fabio_burst_write_test_1000mhz FIRMWARE_TESTNAME=fabio_burst_write_test FABIO_CLK=1000"

# GPIO tests: no free-running FabIO clock, long timeout, relaxed pass criterion.
add_job "gpio_output_test" "TESTNAME=gpio_output_test FIRMWARE_TESTNAME=gpio_output_test FABIO_NOCLK=1 TIMEOUT_NS=500000000"
add_job "gpio_test"        "TESTNAME=gpio_test FIRMWARE_TESTNAME=gpio_test FABIO_NOCLK=1 TIMEOUT_NS=500000000"
add_job "gpio_ctrl_reg_walk_test" "TESTNAME=gpio_ctrl_reg_walk_test FIRMWARE_TESTNAME=gpio_ctrl_reg_walk_test FABIO_NOCLK=1 TIMEOUT_NS=500000000"

# JTAG CPU halt (firmware name differs from test name).
add_job "jtag_cpu_halt_test" "TESTNAME=jtag_cpu_halt_test FIRMWARE_TESTNAME=jtag_halt_test FABIO_NOCLK=1"

# Optional subset filter for quick validation.
if [[ -n "$SUBSET" ]]; then
    declare -a FILTERED=()
    for spec in "${JOBS_LIST[@]}"; do
        label="${spec%%$'\t'*}"
        for want in $SUBSET; do
            [[ "$label" == "$want" ]] && FILTERED+=("$spec")
        done
    done
    JOBS_LIST=("${FILTERED[@]}")
fi

NJOBS="${#JOBS_LIST[@]}"
if [[ "$NJOBS" -eq 0 ]]; then echo "No jobs to run."; exit 1; fi
[[ "$JOBS" -gt "$NJOBS" ]] && JOBS="$NJOBS"

echo "==================================================="
echo " PARALLEL REGRESSION: $NJOBS tests across $JOBS workers"
echo " COV=$COV  extra: ${EXTRA_MAKE_ARGS[*]:-(none)}"
echo "==================================================="

# --------------------------------------------------------------------------
# GPIO tests use a relaxed pass criterion (UVM_FATAL=0 && UVM_ERROR=0); the
# firmware TEST FAILED banner is expected for the un-modelled pad banks.
# All other tests: "TEST PASSED" && "UVM_ERROR : 0" && no UVM_FATAL.
# --------------------------------------------------------------------------
evaluate_log() {
    local log="$1" label="$2"
    if [[ ! -f "$log" ]]; then echo "FAIL (no log)"; return; fi
    if grep -qE "UVM_FATAL[[:space:]]*:[[:space:]]*[1-9]" "$log"; then echo "FAIL (UVM_FATAL)"; return; fi
    case "$label" in
        gpio_output_test|gpio_test)
            if grep -qE "UVM_ERROR[[:space:]]*:[[:space:]]*[1-9]" "$log"; then echo "FAIL (UVM_ERROR)"; else echo "PASS"; fi ;;
        *)
            if grep -qF "TEST PASSED" "$log" && grep -qE "UVM_ERROR[[:space:]]*:[[:space:]]*0" "$log"; then echo "PASS"; else echo "FAIL"; fi ;;
    esac
}

# --------------------------------------------------------------------------
# Worker: processes its round-robin slice sequentially in an isolated scratch
# dir.  Writes one status file per job: "<label>\t<status>".
# --------------------------------------------------------------------------
run_worker() {
    local wid="$1"; shift
    local shard_scratch="${UVM_DIR}/scratch_par${wid}/"
    for spec in "$@"; do
        local label="${spec%%$'\t'*}"
        local margs="${spec#*$'\t'}"
        local run_log="${shard_scratch}simland/${label}/sim.log"
        local dest_log="${RESULTS_DIR}/${label}.log"
        echo "[w${wid}] START ${label}"
        # shellcheck disable=SC2086
        make sim $margs SCRATCH_DIR="$shard_scratch" \
            "${ALWAYS_MAKE_ARGS[@]}" "${EXTRA_MAKE_ARGS[@]+"${EXTRA_MAKE_ARGS[@]}"}" \
            >"${STATUS_DIR}/${label}.build" 2>&1 || true
        [[ -f "$run_log" ]] && cp "$run_log" "$dest_log"
        local status; status="$(evaluate_log "$dest_log" "$label")"
        printf '%s\t%s\n' "$label" "$status" > "${STATUS_DIR}/${label}.status"
        echo "[w${wid}] DONE  ${label} -> ${status}"
    done
}

# Round-robin distribute jobs to workers (spreads adjacent slow tests apart).
declare -a WORKER_SPECS
for ((i=0; i<NJOBS; i++)); do
    w=$(( i % JOBS ))
    WORKER_SPECS[$w]="${WORKER_SPECS[$w]:-}${WORKER_SPECS[$w]:+$'\n'}${JOBS_LIST[$i]}"
done

# Launch workers.
declare -a WPIDS=()
for ((w=0; w<JOBS; w++)); do
    mapfile -t slice <<< "${WORKER_SPECS[$w]}"
    run_worker "$w" "${slice[@]}" &
    WPIDS+=("$!")
done
for pid in "${WPIDS[@]}"; do wait "$pid"; done

# --------------------------------------------------------------------------
# Collect coverage from all shards into the unified scope, then merge/report.
# Per-test .ucd dirs and per-elaboration .ucm models are copied into
# scratch/cov_work/scope so the existing cov_merge/cov_report work unchanged.
# --------------------------------------------------------------------------
if [[ "$COV" == "1" ]]; then
    echo ""
    echo "=== Collecting coverage from $JOBS shards ==="
    UNIFIED_SCOPE="${UVM_DIR}/scratch/cov_work/scope"
    rm -rf "$UNIFIED_SCOPE"; mkdir -p "$UNIFIED_SCOPE"
    for ((w=0; w<JOBS; w++)); do
        shard_scope="${UVM_DIR}/scratch_par${w}/cov_work/scope"
        [[ -d "$shard_scope" ]] || continue
        cp -n "$shard_scope"/*.ucm "$UNIFIED_SCOPE"/ 2>/dev/null || true
        find "$shard_scope" -mindepth 1 -maxdepth 1 -type d ! -name merged \
            -exec cp -rn {} "$UNIFIED_SCOPE"/ \; 2>/dev/null || true
    done
    echo "Collected $(find "$UNIFIED_SCOPE" -mindepth 1 -maxdepth 1 -type d | wc -l) run dirs, $(ls "$UNIFIED_SCOPE"/*.ucm 2>/dev/null | wc -l) model(s)."
    make cov_merge && make cov_report REPORT_TEST=merged
fi

# --------------------------------------------------------------------------
# Aggregate summary.
# --------------------------------------------------------------------------
ELAPSED_S=$(( $(date +%s) - START_EPOCH ))
ELAPSED_FMT="$(printf '%02d:%02d:%02d' $((ELAPSED_S/3600)) $(((ELAPSED_S%3600)/60)) $((ELAPSED_S%60)))"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
COMMIT="$(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo unknown)"

declare -a NAMES=() STATUSES=(); PASS_COUNT=0; FINAL_STATUS=0
# Preserve job order for the printed table.
for spec in "${JOBS_LIST[@]}"; do
    label="${spec%%$'\t'*}"
    st="$(cut -f2 "${STATUS_DIR}/${label}.status" 2>/dev/null || echo 'FAIL (no status)')"
    NAMES+=("$label"); STATUSES+=("$st")
    if [[ "$st" == "PASS" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FINAL_STATUS=1; fi
done
FAIL_COUNT=$(( ${#STATUSES[@]} - PASS_COUNT ))

print_summary() {
    echo "==================================================="
    echo "              PARALLEL TEST SUMMARY                "
    echo "==================================================="
    printf "%-52s %s\n" "TESTNAME" "STATUS"
    echo "---------------------------------------------------"
    for i in "${!NAMES[@]}"; do printf "%-52s %s\n" "${NAMES[$i]}" "${STATUSES[$i]}"; done
    echo "==================================================="
    printf "Result  : %d PASS  %d FAIL   (%d workers)\n" "$PASS_COUNT" "$FAIL_COUNT" "$JOBS"
    printf "Elapsed : %s  (started %s)\n" "$ELAPSED_FMT" "$STARTED_AT"
}
echo ""; print_summary
printf "REGR_RESULT: %d PASS %d FAIL elapsed=%s workers=%d branch=%s commit=%s\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$ELAPSED_FMT" "$JOBS" "$BRANCH" \
    "$(git log -1 --pretty=format:'%h' 2>/dev/null || echo unknown)"

REGR_LOG="${RESULTS_DIR}/regr_par_$(date '+%y-%m-%d_%H%M%S').log"
{ echo "Started : ${STARTED_AT}"; echo "Elapsed : ${ELAPSED_FMT}"; echo "Workers : ${JOBS}";
  echo "Branch  : ${BRANCH}"; echo "Commit  : ${COMMIT}"; echo ""; print_summary; } > "$REGR_LOG"
echo ""; echo "Regression log: ${UVM_DIR}/${REGR_LOG}"

exit "$FINAL_STATUS"
