#!/usr/bin/env bash
#
# Bootcheck orchestrator (template).
# Selects a checklist by hostname, runs every sub-check in parallel, prints each
# result as it completes, and exits 0 (all pass) or 1 (any failure/warning).
#
# Version history (append a line every time you roll the version):
# 0.0.1 <date> init template

Version="0.0.1"
HW_dependency="none"
SW_dependency="bash, tput"
TestCaseID="none"
RequirementID=("none")
PIDFILE="/tmp/bootcheck.pid"

# -----------------------------------------------------------------------------
# Resolve absolute path of this script (handle symlinks)
# -----------------------------------------------------------------------------
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# -----------------------------------------------------------------------------
# Global suite version (from VERSION file, maintained by the post-commit hook)
# -----------------------------------------------------------------------------
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    GLOBAL_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
else
    GLOBAL_VERSION="unknown"
fi

# -----------------------------------------------------------------------------
# Colors (only when a capable terminal is attached)
# -----------------------------------------------------------------------------
if [[ -n "${TERM:-}" ]] && tput setaf 1 >/dev/null 2>&1; then
    title=$(tput setaf 7; tput bold)
    red=$(tput setaf 1)
    yellow=$(tput setaf 3)
    green=$(tput setaf 2)
    text_style_reset=$(tput sgr0)
else
    title="" red="" yellow="" green="" text_style_reset=""
fi

# -----------------------------------------------------------------------------
# Pre-scan for --verbose/-v and -no_log; strip them so the case below still works
# -----------------------------------------------------------------------------
VERBOSE=false
NO_LOG=false
REMAINING_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        -no_log)      NO_LOG=true ;;
        *) REMAINING_ARGS+=("$arg") ;;
    esac
done
set -- "${REMAINING_ARGS[@]}"

# -----------------------------------------------------------------------------
# Options, test modes, cancel, metadata reporting
# -----------------------------------------------------------------------------
case "$1" in
  --test-success)
    echo "[PASS] Test Message Success                         Expected: Success                      Actual: Success"
    echo -e "$title \n\n=================================="
    echo -e "$green  All checks run successfully!$text_style_reset"
    exit 0
    ;;
  --test-fail)
    echo "[FAIL] Test Message Fail                        Expected: Success                      Actual: Fail"
    echo -e "$red Total failures: 1 $text_style_reset"
    exit 1
    ;;
  --test-timeout) sleep 60; exit 1 ;;
  --test-crash)   sleep 5;  exit 1 ;;
  --cancel)
    if [[ ! -f "$PIDFILE" ]]; then
        echo "canceled: no running bootcheck found"; exit 1
    fi
    pid=$(cat "$PIDFILE")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "canceled: stale pid file (process not running)"; rm -f "$PIDFILE"; exit 1
    fi
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    kill -- -"$pgid"
    echo "canceled"; exit 0
    ;;
  -h|--help)
    cat <<EOF
Bootcheck Orchestrator - Help

Usage:
  ./run_bootcheck.sh [OPTIONS]

Options:
  -h, --help           Show help
  -v, --verbose        Show per-check result details from each sub-script
  -no_log              Disable log file creation

Test Modes:
  --test-success       Force a successful run (exit 0)
  --test-fail          Force a failed run (exit 1)
  --test-timeout       Simulate hang (sleep 60s, exit 1)
  --test-crash         Simulate crash (sleep 5s, exit 1)
  --cancel             Kill a currently running bootcheck and its sub-scripts

Info Reporting:
  --version            Show suite version (from VERSION file)
  --hw_dependency      Show hardware dependencies
  --sw_dependency      Show software dependencies
  --test_case_id       Show test case ID
  --requirement_id     Show requirement ID
EOF
    exit 0
    ;;
  --version)
    echo "Bootcheck Version: $GLOBAL_VERSION"; exit 0 ;;
  --hw_dependency|--sw_dependency|--test_case_id|--requirement_id)
    report_script="$SCRIPT_DIR/VersionDependencyReportClass.sh"
    if [[ -f "$report_script" ]]; then
        export Version HW_dependency SW_dependency TestCaseID RequirementID
        "$report_script" "$1"
    fi
    exit 0
    ;;
  -*)
    echo "Unknown option: $1"; echo "Use -h or --help for usage."; exit 1 ;;
esac

echo "
Bootcheck Version: $GLOBAL_VERSION
$(date)
"

# -----------------------------------------------------------------------------
# Log file setup   (edit LOG_DIR for your product)
# -----------------------------------------------------------------------------
if ! $NO_LOG; then
    LOG_DIR="/var/log/bootcheck"
    [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/bootcheck-log"
    [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/bootcheck.$(hostname).$(whoami).log.INFO.$(date +%Y%m%d-%H%M%S).$$"
    exec > >(tee "$LOG_FILE") 2>&1
    echo "Logging to: $LOG_FILE"
fi

# -----------------------------------------------------------------------------
# Per-profile checklists.
# Define one array per machine type; add your 01NN_*_check.sh filenames.
# -----------------------------------------------------------------------------
dev_functionlist=(
  0101_template_check.sh
  0102_GPU_check.sh
  0103_Disk_check.sh
  0104_Mem_check.sh
  0105_Temp_check.sh
  0106_interface_bandwidth_check.sh
  0107_CPU_check.sh
  0108_NTP_check.sh
)

# Example product profiles — rename/extend for your machines:
typeA_functionlist=(
  0102_GPU_check.sh
  0103_Disk_check.sh
  0104_Mem_check.sh
  0105_Temp_check.sh
  0106_interface_bandwidth_check.sh
  0107_CPU_check.sh
  0108_NTP_check.sh
)

typeB_functionlist=(
  0103_Disk_check.sh
  0104_Mem_check.sh
  0105_Temp_check.sh
)

# -----------------------------------------------------------------------------
# Select checklist by hostname.  Edit the patterns for your fleet.
# -----------------------------------------------------------------------------
case "$(hostname)" in
    *LAPTOP*|*linuxPC*|*dev*)  functionlist=("${dev_functionlist[@]}") ;;
    *typeA*)                   functionlist=("${typeA_functionlist[@]}") ;;
    *typeB*)                   functionlist=("${typeB_functionlist[@]}") ;;
    *)
        # Default to dev list rather than hard-failing so the template runs anywhere.
        echo -e "$yellow  Unrecognized hostname: $(hostname) — using dev checklist.$text_style_reset"
        functionlist=("${dev_functionlist[@]}") ;;
esac

# -----------------------------------------------------------------------------
# Run all checks in parallel; print each as it finishes.
# -----------------------------------------------------------------------------
issue_found=0
SECONDS=0
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"; rm -rf "$tmp_dir"' EXIT

tmp_dir=$(mktemp -d)
pids=()
declare -A pid_to_script

for each_func in "${functionlist[@]}"; do
    if [[ -x "$SCRIPT_DIR/$each_func" ]]; then
        (
            if $VERBOSE; then "$SCRIPT_DIR/$each_func" -v; else "$SCRIPT_DIR/$each_func"; fi
            exit $?
        ) > "$tmp_dir/$each_func.log" 2>&1 &
        pids+=($!)
        pid_to_script[$!]="$each_func"
    else
        echo -e "$yellow  Skipping missing or non-executable script: $each_func $text_style_reset" > "$tmp_dir/$each_func.log"
        ((issue_found++))
    fi
done

while [ ${#pids[@]} -gt 0 ]; do
    for i in "${!pids[@]}"; do
        pid=${pids[$i]}
        if ! kill -0 "$pid" 2>/dev/null; then
            script_name=${pid_to_script[$pid]}
            [[ -f "$tmp_dir/$script_name.log" ]] && cat "$tmp_dir/$script_name.log"
            wait "$pid" || ((issue_found++))
            unset "pids[$i]"
        fi
    done
    sleep 0.1
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
total_time=$SECONDS
mins=$((total_time / 60))
secs=$((total_time % 60))

echo -e "$title \n\n=================================="
echo -e "$green Total runtime: ${mins} minute(s) and ${secs} second(s).$text_style_reset"

if [[ $issue_found -eq 0 ]]; then
  echo -e "$title $green  All local checks run successfully!$text_style_reset"
  exit 0
else
  echo -e "$red Total failures: $issue_found$text_style_reset"
  exit 1
fi
