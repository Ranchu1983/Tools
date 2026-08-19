#!/bin/bash
#
# Example check: RAM usage percentage.
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: warn/fail when memory pressure is high at boot.

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
  - RAM usage % (PASS <=20%, WARN 20-40%, FAIL >40%)
  - Total RAM meets a minimum (optional; set MIN_TOTAL_GB)
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
# Config (customize per product)
# ================================================================
MIN_TOTAL_GB=0    # e.g. 32; set 0 to skip the minimum-RAM check.

# ================================================================
# CHECK FUNCTIONS
# ================================================================

check_memory_usage() {
    # Integer percent of used RAM (no bc dependency).
    cmd "free -m | awk 'NR==2 {printf \"%.0f\", (\$3/\$2)*100}'"
    local mem="$cmd_result"
    if [[ "$mem" =~ ^[0-9]+$ ]]; then
        if   [[ "$mem" -le 20 ]]; then report_check "PASS" "RAM usage" "<= 20%" "${mem}%"
        elif [[ "$mem" -le 40 ]]; then report_check "WARN" "RAM usage" "20% - 40%" "${mem}%"
        else                           report_check "FAIL" "RAM usage" "< 40%" "${mem}%"
        fi
    else
        report_check "FAIL" "RAM usage" "<= 20%" "unreadable"
    fi
}

check_total_ram() {
    [[ "$MIN_TOTAL_GB" -le 0 ]] && return 0
    # Source: <hardware BOM / spec doc>
    cmd "free -g | awk 'NR==2 {print \$2}'"
    local total="$cmd_result"
    if [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -ge "$MIN_TOTAL_GB" ]]; then
        report_check "PASS" "Total RAM" ">= ${MIN_TOTAL_GB}GB" "${total}GB"
    else
        report_check "FAIL" "Total RAM" ">= ${MIN_TOTAL_GB}GB" "${total:-unknown}GB"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

check_memory_usage
check_total_ram

finish_checks
