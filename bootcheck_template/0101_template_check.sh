#!/bin/bash
#
# COPY THIS FILE to create a new check:  cp 0101_template_check.sh 01NN_<Name>_check.sh
#
# Naming:  <4-digit ID>_<Name>_check.sh   e.g. 0102_Disk_check.sh
# Then:    1) set SCRIPT_NAME auto-derives from filename, set Version + dependency vars
#          2) write check_* functions using cmd/run_cmd + report_check
#          3) call them in MAIN between init_checks and finish_checks
#          4) add the filename to the right *_functionlist in run_bootcheck.sh
#          5) chmod +x 01NN_<Name>_check.sh
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init template
#
# Purpose: <one line describing what this check validates>

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

# ================================================================
# Argument parsing (uniform across all sub-checks)
# ================================================================
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
  --<flag>        Metadata report (--version, --hw_dependency, --sw_dependency,
                  --test_case_id, --requirement_id)

Functions tested:
  - <list what this script checks>
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

# ================================================================
# Load shared utilities
# ================================================================
source "$SCRIPT_DIR/utils_function.sh"

REMOTE_PC=""          # empty = run locally; set to a host to run over SSH
cmd_result=""
cmd_exit_code=""

# ================================================================
# CHECK FUNCTIONS
# Each function: gather actual value with cmd/run_cmd, compare to an
# expected value, then report_check "PASS|WARN|FAIL" name expected actual.
# For any hardcoded expected value, add a  # Source: <origin>  comment.
# ================================================================

check_example_pass() {
    # Example: confirm bash is available (always true) — replace with a real check.
    cmd "command -v bash"
    local actual="$cmd_result"
    # Source: <where the expected value comes from, e.g. ansible role / spec doc>
    if [[ -n "$actual" ]]; then
        report_check "PASS" "bash available" "present" "$actual"
    else
        report_check "FAIL" "bash available" "present" "not found"
    fi
}

check_example_threshold() {
    # Example: PASS / WARN / FAIL banding on a numeric value.
    cmd "nproc"
    local cores="$cmd_result"
    if [[ "$cores" =~ ^[0-9]+$ ]]; then
        if   [[ "$cores" -ge 8 ]]; then report_check "PASS" "CPU cores" ">= 8" "$cores"
        elif [[ "$cores" -ge 4 ]]; then report_check "WARN" "CPU cores" "4 - 7" "$cores"
        else                            report_check "FAIL" "CPU cores" ">= 4" "$cores"
        fi
    else
        report_check "FAIL" "CPU cores" ">= 4" "unreadable"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

cmd "hostname"
host_name="$cmd_result"

check_example_pass
check_example_threshold

# Hostname-aware branching example (uncomment and adapt):
# case "${host_name,,}" in
#     *"typeA"*) check_typeA_specific ;;
#     *"typeB"*) check_typeB_specific ;;
# esac

finish_checks
