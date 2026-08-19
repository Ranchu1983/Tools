#!/bin/bash
#
# Example check: CPU / motherboard / GPU temperatures.
# Reads /sys/class/thermal thermal zones; GPU temp via nvidia-smi if present.
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: warn/fail on thermal excursions at boot.

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
  - CPU package temp (thermal zone x86_pkg_temp)
  - Motherboard temp (thermal zone acpitz)
  - GPU temp (nvidia-smi, if present)
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
# CHECK FUNCTIONS
# ================================================================

band() {  # band NAME TEMP WARN_AT FAIL_AT
    local name="$1" temp="$2" warn="$3" fail="$4"
    if   [[ "$temp" -le "$warn" ]]; then report_check "PASS" "$name" "<= ${warn}C" "${temp}C"
    elif [[ "$temp" -le "$fail" ]]; then report_check "WARN" "$name" "${warn}C - ${fail}C" "${temp}C"
    else                                 report_check "FAIL" "$name" "< ${fail}C" "${temp}C"
    fi
}

check_thermal_zones() {
    local found=false
    cmd 'for z in /sys/class/thermal/thermal_zone*; do
            [ -r "$z/type" ] && [ -r "$z/temp" ] && echo "$(cat "$z/type"):$(( $(cat "$z/temp") / 1000 ))"
         done'
    while read -r line; do
        [[ -z "$line" ]] && continue
        local type temp
        type=$(echo "$line" | cut -d: -f1)
        temp=$(echo "$line" | cut -d: -f2)
        [[ "$temp" =~ ^[0-9]+$ ]] || continue
        case "$type" in
            x86_pkg_temp) band "CPU temp"         "$temp" 65 80; found=true ;;
            acpitz)       band "Motherboard temp" "$temp" 55 75; found=true ;;
        esac
    done <<< "$cmd_result"
    $found || report_check "WARN" "Thermal zones" "readable" "no x86_pkg_temp/acpitz zone found"
}

check_gpu_temp() {
    cmd "command -v nvidia-smi"
    [[ -z "$cmd_result" ]] && return 0
    cmd "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -1"
    local t="$cmd_result"
    [[ "$t" =~ ^[0-9]+$ ]] && band "GPU temp" "$t" 60 80
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

check_thermal_zones
check_gpu_temp

finish_checks
