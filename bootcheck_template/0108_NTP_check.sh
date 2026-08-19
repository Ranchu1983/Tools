#!/bin/bash
#
# Example check: NTP / system time synchronization (systemd-timesyncd via timedatectl).
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: confirm the system clock is being disciplined by NTP and is in sync.
# Note: on machines that get time from PTP instead, set EXPECTED_NTP="no".

#---- version report -----------
Version="1.0.0"
HW_dependency="none"
SW_dependency="systemd-timesyncd"
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
  - NTP client enabled state matches expected (timedatectl NTP; set EXPECTED_NTP yes|no)
  - System clock synchronized (timedatectl NTPSynchronized) — only when EXPECTED_NTP=yes
  - Configured NTP server drop-in present (optional; set NTP_CONF + EXPECTED_NTP_SERVER)
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
# Source: <time-sync role / spec>
# ================================================================
EXPECTED_NTP="yes"          # "yes" = NTP disciplines the clock; "no" = time comes from elsewhere (e.g. PTP)
NTP_CONF=""                 # e.g. "/etc/systemd/timesyncd.conf.d/99-product.conf"; empty = skip
EXPECTED_NTP_SERVER=""      # e.g. "pool.ntp.org"; checked inside NTP_CONF

# ================================================================
# CHECK FUNCTIONS
# ================================================================

check_ntp_enabled() {
    cmd "timedatectl show --property=NTP --value 2>/dev/null"
    local actual="$cmd_result"
    if [[ -z "$actual" ]]; then
        report_check "FAIL" "NTP client state" "$EXPECTED_NTP" "timedatectl unavailable"
        return 1
    fi
    if [[ "$actual" == "$EXPECTED_NTP" ]]; then
        report_check "PASS" "NTP client state" "$EXPECTED_NTP" "$actual"
    else
        report_check "FAIL" "NTP client state" "$EXPECTED_NTP" "$actual"
    fi
}

check_clock_synchronized() {
    # Only meaningful when this machine is supposed to use NTP.
    [[ "$EXPECTED_NTP" != "yes" ]] && return 0
    cmd "timedatectl show --property=NTPSynchronized --value 2>/dev/null"
    local synced="$cmd_result"
    if [[ "$synced" == "yes" ]]; then
        report_check "PASS" "System clock synchronized" "yes" "yes"
    else
        report_check "WARN" "System clock synchronized" "yes" "${synced:-unknown}"
    fi
}

check_ntp_server_conf() {
    [[ -z "$NTP_CONF" ]] && return 0
    if [[ ! -f "$NTP_CONF" ]]; then
        report_check "FAIL" "$(basename "$NTP_CONF")" "exists" "not found"
        return 1
    fi
    report_check "PASS" "$(basename "$NTP_CONF")" "exists" "present"

    [[ -z "$EXPECTED_NTP_SERVER" ]] && return 0
    local server
    server=$(grep -oP '^\s*NTP=\K.+' "$NTP_CONF" 2>/dev/null | tail -n1)
    if [[ "$server" == *"$EXPECTED_NTP_SERVER"* ]]; then
        report_check "PASS" "NTP server" "$EXPECTED_NTP_SERVER" "$server"
    else
        report_check "FAIL" "NTP server" "$EXPECTED_NTP_SERVER" "${server:-not set}"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

check_ntp_enabled
check_clock_synchronized
check_ntp_server_conf

finish_checks
