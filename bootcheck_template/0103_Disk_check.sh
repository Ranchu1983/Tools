#!/bin/bash
#
# Example check: disk usage on physical mount points, plus an optional required dir.
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: fail when any physical partition is dangerously full.

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
  - Disk usage % on all physical mount points (PASS <50%, WARN 50-75%, FAIL >75%)
  - A required data directory exists and is writable (optional; set REQUIRED_DIR)
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
REQUIRED_DIR=""   # e.g. "/var/data"; leave empty to skip the directory check.

# ================================================================
# CHECK FUNCTIONS
# ================================================================

check_physical_disks() {
    # Skip pseudo/virtual filesystems; report usage per real mount point.
    cmd "df -Pl 2>/dev/null | awk 'NR>1 && !/tmpfs|udev|overlay|efivarfs|squashfs/'"
    while read -r line; do
        [[ -z "$line" ]] && continue
        local mount_point usage
        mount_point=$(echo "$line" | awk '{print $6}')
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        [[ "$usage" =~ ^[0-9]+$ ]] || continue

        if   [[ "$usage" -lt 50 ]]; then report_check "PASS" "Disk used on $mount_point" "< 50%" "${usage}%"
        elif [[ "$usage" -le 75 ]]; then report_check "WARN" "Disk used on $mount_point" "50% - 75%" "${usage}%"
        else                             report_check "FAIL" "Disk used on $mount_point" "< 75%" "${usage}%"
        fi
    done <<< "$cmd_result"
}

check_required_dir() {
    [[ -z "$REQUIRED_DIR" ]] && return 0
    # Source: <where this directory requirement comes from>
    if [[ ! -d "$REQUIRED_DIR" ]]; then
        report_check "FAIL" "$REQUIRED_DIR directory" "exists" "not found"
        return
    fi
    report_check "PASS" "$REQUIRED_DIR directory" "exists" "$REQUIRED_DIR"
    if [[ -w "$REQUIRED_DIR" ]]; then
        report_check "PASS" "$REQUIRED_DIR writable" "writable" "writable"
    else
        report_check "FAIL" "$REQUIRED_DIR writable" "writable" "not writable"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

check_physical_disks
check_required_dir

finish_checks
