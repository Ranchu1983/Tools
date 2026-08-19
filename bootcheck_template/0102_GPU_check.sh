#!/bin/bash
#
# Example check: GPU (NVIDIA). Skips gracefully (PASS N/A) when nvidia-smi is absent,
# so the template runs on machines without a GPU. Replace expected values for your product.
#
# Version history (append a line every time you roll the version):
# V1.0.0 <date> - init example
#
# Purpose: validate GPU presence, driver, live utilization, and CUDA discoverability.

#---- version report -----------
Version="1.0.0"
HW_dependency="NVIDIA GPU"
SW_dependency="nvidia-smi (optional)"
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
  - GPU present (nvidia-smi reachable) — skips as N/A when absent
  - GPU model matches expected
  - GPU utilization (5s window) banding
  - CUDA runtime discoverable via ldconfig (libcuda.so.1)
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
# Source: <e.g. hardware BOM / spec doc>. Leave empty to skip the model match.
# ================================================================
EXPECTED_GPU_MODEL=""     # e.g. "NVIDIA RTX A4500"

# ================================================================
# CHECK FUNCTIONS
# ================================================================

# Returns 0 if nvidia-smi is usable, else reports N/A and returns 1.
gpu_present() {
    cmd "command -v nvidia-smi"
    [[ -n "$cmd_result" ]]
}

check_gpu_model() {
    cmd "nvidia-smi --query-gpu=name --format=csv,noheader | head -1"
    local actual="$cmd_result"
    if [[ -z "$EXPECTED_GPU_MODEL" ]]; then
        report_check "PASS" "GPU model" "reported" "$actual"
    elif [[ "$actual" == *"$EXPECTED_GPU_MODEL"* ]]; then
        report_check "PASS" "GPU model" "$EXPECTED_GPU_MODEL" "$actual"
    else
        report_check "FAIL" "GPU model" "$EXPECTED_GPU_MODEL" "$actual"
    fi
}

check_gpu_utilization() {
    # Average utilization over a ~5s window (10 samples).
    cmd "for i in \$(seq 1 10); do nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null; sleep 0.5; done | awk '{s+=\$1} END{if(NR>0) printf \"%.0f\", s/NR; else print \"err\"}'"
    local usage="$cmd_result"
    if [[ "$usage" =~ ^[0-9]+$ ]]; then
        if   [[ "$usage" -le 15 ]]; then report_check "PASS" "GPU utilization (5s)" "<= 15%" "${usage}%"
        elif [[ "$usage" -le 30 ]]; then report_check "WARN" "GPU utilization (5s)" "15% - 30%" "${usage}%"
        else                             report_check "FAIL" "GPU utilization (5s)" "< 30%" "${usage}%"
        fi
    else
        report_check "FAIL" "GPU utilization (5s)" "<= 15%" "unreadable"
    fi
}

check_cuda_ld_path() {
    cmd "ldconfig -p 2>/dev/null | grep -c 'libcuda\.so\.1'"
    if [[ "$cmd_result" =~ ^[1-9][0-9]*$ ]]; then
        report_check "PASS" "CUDA runtime (libcuda.so.1)" "discoverable" "discoverable"
    else
        report_check "WARN" "CUDA runtime (libcuda.so.1)" "discoverable" "not found"
    fi
}

# ================================================================
# MAIN
# ================================================================
init_checks
print_check_header

if gpu_present; then
    check_gpu_model
    check_gpu_utilization
    check_cuda_ld_path
else
    report_check "PASS" "GPU" "present or N/A" "N/A (nvidia-smi not found)"
fi

finish_checks
