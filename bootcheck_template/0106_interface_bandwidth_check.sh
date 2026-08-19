#!/bin/bash
#
# Example check: network interface link status and bandwidth.
# Interfaces are declared per profile; the name is discovered at runtime by matching
# the expected IP pattern (so it works regardless of eth0/enpXsY naming).
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: confirm each required NIC is up, at the expected IP, speed, and duplex.

#---- version report -----------
Version="1.0.0"
HW_dependency="none"
SW_dependency="iproute2"
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
  - Each declared interface has an IP matching its expected pattern
  - Link detected (carrier), duplex, and link speed via /sys/class/net/
  - net.core.rmem_max meets a minimum (optional; set MIN_RMEM_MAX)

Interface name is discovered at runtime by matching EXPECTED_IPS — not hardcoded.
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
# Interface definitions per profile
#   IFACE_LABELS    : human-readable label in output
#   EXPECTED_IPS    : ERE regex of the expected IPv4 ("auto" = use default-route iface)
#   EXPECTED_SPEEDS : expected link speed in Mb/s ("TBD" = skip)
#   EXPECTED_DUPLEX : expected duplex ("TBD" = skip)
# Customize these arrays for your fleet.
# ================================================================
MIN_RMEM_MAX=0    # e.g. 8388608; set 0 to skip the sysctl check.

setup_typeA_interfaces() {
    IFACE_LABELS=(   "intranet"              )
    EXPECTED_IPS=(   "172\.16\.[0-9]+\.101"  )
    EXPECTED_SPEEDS=("TBD"                   )
    EXPECTED_DUPLEX=("full"                  )
}

# Default profile: just validate the primary (default-route) interface is up.
setup_default_interfaces() {
    IFACE_LABELS=(   "primary" )
    EXPECTED_IPS=(   "auto"    )
    EXPECTED_SPEEDS=("TBD"     )
    EXPECTED_DUPLEX=("TBD"     )
}

# ================================================================
# CHECK FUNCTIONS
# ================================================================

read_sysfs() {
    local path="$1" value
    value=$(cat "$path" 2>/dev/null)
    if $DEBUG; then
        echo -e "\n--- DEBUG read_sysfs ---\ncat $path\n--- OUTPUT ---\n$value\n----------" >&2
    fi
    echo "$value"
}

# Interface carrying the default route.
default_route_iface() {
    cmd "ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if(\$i==\"dev\"){print \$(i+1); exit}}'"
    echo "$cmd_result"
}

# Print "<iface> <ip>" for the first interface whose IPv4 matches the pattern.
find_iface_by_ip() {
    local pattern="$1"
    cmd "ip -4 addr"
    echo "$cmd_result" | awk -v pat="$pattern" '
        /^[0-9]+:/ { iface=$2; sub(/:$/,"",iface) }
        /inet /    { split($2,a,"/"); if (a[1] ~ pat) { print iface " " a[1]; exit } }'
}

check_link() {
    local iface="$1" label="$2" exp_speed="$3" exp_duplex="$4"
    local sysfs="/sys/class/net/$iface"

    local carrier
    carrier=$(read_sysfs "$sysfs/carrier")
    if [[ "$carrier" == "1" ]]; then
        report_check "PASS" "$label link detected" "yes" "yes"
    else
        report_check "FAIL" "$label link detected" "yes" "no"
    fi

    if [[ "$exp_duplex" != "TBD" ]]; then
        local d; d=$(read_sysfs "$sysfs/duplex")
        [[ "$d" == "$exp_duplex" ]] \
            && report_check "PASS" "$label duplex" "$exp_duplex" "$d" \
            || report_check "FAIL" "$label duplex" "$exp_duplex" "${d:-not found}"
    fi

    if [[ "$exp_speed" != "TBD" ]]; then
        local s; s=$(read_sysfs "$sysfs/speed")
        [[ "$s" == "$exp_speed" ]] \
            && report_check "PASS" "$label speed" "${exp_speed}Mb/s" "${s}Mb/s" \
            || report_check "FAIL" "$label speed" "${exp_speed}Mb/s" "${s:-not found}Mb/s"
    fi
}

run_interface_checks() {
    for i in "${!IFACE_LABELS[@]}"; do
        local label="${IFACE_LABELS[$i]}"
        local exp_ip="${EXPECTED_IPS[$i]}"
        local exp_speed="${EXPECTED_SPEEDS[$i]}"
        local exp_duplex="${EXPECTED_DUPLEX[$i]}"
        local iface actual_ip

        if [[ "$exp_ip" == "auto" ]]; then
            iface=$(default_route_iface)
            if [[ -z "$iface" ]]; then
                report_check "FAIL" "$label IP" "default route" "no default route found"
                continue
            fi
            actual_ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
            report_check "PASS" "$label IP" "default-route iface" "${actual_ip:-none} ($iface)"
        else
            local discovery
            discovery=$(find_iface_by_ip "$exp_ip")
            iface=$(echo "$discovery" | awk '{print $1}')
            actual_ip=$(echo "$discovery" | awk '{print $2}')
            if [[ -z "$iface" ]]; then
                report_check "FAIL" "$label IP" "$exp_ip" "no interface with matching IP"
                continue
            fi
            report_check "PASS" "$label IP" "matches pattern" "$actual_ip ($iface)"
        fi

        check_link "$iface" "$label" "$exp_speed" "$exp_duplex"
    done
}

check_rmem_max() {
    [[ "$MIN_RMEM_MAX" -le 0 ]] && return 0
    # Source: <sysctl tuning role / spec>
    cmd "sysctl -n net.core.rmem_max 2>/dev/null"
    local actual; actual=$(echo "$cmd_result" | xargs)
    if [[ "$actual" =~ ^[0-9]+$ ]] && [[ "$actual" -ge "$MIN_RMEM_MAX" ]]; then
        report_check "PASS" "net.core.rmem_max" ">= $MIN_RMEM_MAX" "$actual"
    else
        report_check "FAIL" "net.core.rmem_max" ">= $MIN_RMEM_MAX" "${actual:-unknown}"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

cmd "hostname"
host_name="$cmd_result"

case "${host_name,,}" in
    *typea*) setup_typeA_interfaces ;;
    *)       setup_default_interfaces ;;   # runs anywhere: validates the primary NIC
esac

run_interface_checks
check_rmem_max

finish_checks
