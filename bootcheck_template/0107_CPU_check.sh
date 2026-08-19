#!/bin/bash
#
# Example check: CPU model, live load, core count, and scaling governor.
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: validate the CPU spec and that it is idle/tuned as expected at boot.

#---- version report -----------
Version="1.0.0"
HW_dependency="none"
SW_dependency="none"
TestCaseID="none"
RequirementID=("none")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}" _check.sh)

VERBOSE=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<EOF
$SCRIPT_NAME Check - Help

Usage:
  ./$(basename "${BASH_SOURCE[0]}") [OPTIONS]

Options:
  -h, --help      Show help
  -v, --verbose   Show per-check result details
  -d, --debug     Show debug command/output messages
  --<flag>        Metadata report

Functions tested:
  - CPU model matches expected (optional; set EXPECTED_CPU_MODEL)
  - Core count meets a minimum (optional; set MIN_CORES)
  - CPU utilization over a 5s window (PASS <=20%, WARN 20-40%, FAIL >40%)
  - Scaling governor matches expected (optional; set EXPECTED_GOVERNOR)
EOF
            exit 0
            ;;
        -v|--verbose) VERBOSE=true ;;
        -d|--debug)   DEBUG=true ;;
        --*)
            report_script="$SCRIPT_DIR/VersionDependencyReportClass.sh"
            if [[ -f "$report_script" ]]; then
                export Version HW_dependency SW_dependency TestCaseID RequirementID
                "$report_script" "$1"
            fi
            exit 0
            ;;
    esac
    shift
done

source "$SCRIPT_DIR/utils_function.sh"

REMOTE_PC=""
cmd_result=""
cmd_exit_code=""

# ================================================================
# Expected values (customize per product)
# Source: <hardware BOM / power-tuning role / spec doc>
# ================================================================
EXPECTED_CPU_MODEL=""     # e.g. "Intel(R) Core(TM) i7-14701E"; empty = report only
MIN_CORES=0               # e.g. 8; 0 = skip
EXPECTED_GOVERNOR=""      # e.g. "performance"; empty = skip

# ================================================================
# CHECK FUNCTIONS
# ================================================================

check_cpu_model() {
    cmd "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//'"
    local actual="$cmd_result"
    if [[ -z "$EXPECTED_CPU_MODEL" ]]; then
        report_check "PASS" "CPU model" "reported" "$actual"
    elif [[ "$actual" == "$EXPECTED_CPU_MODEL" ]]; then
        report_check "PASS" "CPU model" "matches" "matches"
    else
        report_check "FAIL" "CPU model" "$EXPECTED_CPU_MODEL" "$actual"
    fi
}

check_core_count() {
    [[ "$MIN_CORES" -le 0 ]] && return 0
    cmd "nproc"
    local cores="$cmd_result"
    if [[ "$cores" =~ ^[0-9]+$ ]] && [[ "$cores" -ge "$MIN_CORES" ]]; then
        report_check "PASS" "CPU cores" ">= $MIN_CORES" "$cores"
    else
        report_check "FAIL" "CPU cores" ">= $MIN_CORES" "${cores:-unknown}"
    fi
}

check_cpu_load() {
    # Utilization over a 5s window from /proc/stat deltas (integer %).
    local load_cmd="u1=\$(awk '/^cpu /{print \$2+\$3+\$4}' /proc/stat); t1=\$(awk '/^cpu /{print \$2+\$3+\$4+\$5}' /proc/stat); sleep 5; u2=\$(awk '/^cpu /{print \$2+\$3+\$4}' /proc/stat); t2=\$(awk '/^cpu /{print \$2+\$3+\$4+\$5}' /proc/stat); echo \$(( (u2-u1)*100 / (t2-t1) ))"
    cmd "$load_cmd"
    local load="$cmd_result"
    if [[ "$load" =~ ^[0-9]+$ ]]; then
        if   [[ "$load" -le 20 ]]; then report_check "PASS" "CPU utilization (5s)" "<= 20%" "${load}%"
        elif [[ "$load" -le 40 ]]; then report_check "WARN" "CPU utilization (5s)" "20% - 40%" "${load}%"
        else                            report_check "FAIL" "CPU utilization (5s)" "< 40%" "${load}%"
        fi
    else
        report_check "FAIL" "CPU utilization (5s)" "<= 20%" "unreadable"
    fi
}

check_governor() {
    [[ -z "$EXPECTED_GOVERNOR" ]] && return 0
    # Source: <power-tuning role / spec>
    cmd "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u"
    local gov="$cmd_result"
    if [[ -z "$gov" ]]; then
        report_check "WARN" "CPU governor" "$EXPECTED_GOVERNOR" "cpufreq not available"
    elif [[ "$(echo "$gov" | wc -l)" == "1" && "$gov" == "$EXPECTED_GOVERNOR" ]]; then
        report_check "PASS" "CPU governor" "$EXPECTED_GOVERNOR" "$gov"
    else
        report_check "FAIL" "CPU governor" "$EXPECTED_GOVERNOR" "$(echo "$gov" | paste -sd, -)"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

check_cpu_model
check_core_count
check_cpu_load
check_governor

finish_checks
