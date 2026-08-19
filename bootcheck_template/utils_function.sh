#!/bin/bash
#
# Shared utilities for bootcheck sub-scripts.
# Source this from every sub-check:  source "$SCRIPT_DIR/utils_function.sh"
#
# Public API:
#   cmd "..."                            run a command locally or over SSH; sets cmd_result, cmd_exit_code
#   run_cmd "..."                        local-only wrapper, echoes output
#   debug_msg "..."                      print a debug banner when DEBUG=true
#   init_checks                          reset counters + start timer
#   print_check_header                   print a section banner in verbose mode
#   report_check STATUS NAME EXP ACT     record one check result
#   finish_checks                        print summary + exit 0 (all pass) / 1 (any fail/warn)

# ================================================================
# Shared credentials (optional)
# ================================================================
# Sourced from the environment; never hardcode a secret in the repo.
# Only used to feed `sudo -S` for privileged remote reads. SSH auth itself
# should be key-based (BatchMode). When empty, sudo falls back to `sudo -n`.
PASSWORD="${SSH_PASS:-}"

# ================================================================
# Colors (only when a capable terminal is attached)
# ================================================================
if [[ -n "${TERM:-}" ]] && tput setaf 1 >/dev/null 2>&1; then
    green=$(tput setaf 2)
    red=$(tput setaf 1)
    yellow=$(tput setaf 3)
    reset=$(tput sgr0)
else
    green="" red="" yellow="" reset=""
fi

# ================================================================
# Execute a command locally or via SSH.
# Requires globals: DEBUG, REMOTE_PC, PASSWORD
# Sets globals:     cmd_result, cmd_exit_code
# ================================================================
cmd() {
  local command="$*"

  if $DEBUG; then
    local caller="${FUNCNAME[1]:-main}"
    echo -e "\n--- DEBUG $caller ---" >&2
    if [[ -z "$REMOTE_PC" || "$REMOTE_PC" == "localhost" ]]; then
      echo "$command" >&2
    else
      echo "$REMOTE_PC:\"$command\"" >&2
    fi
  fi

  if [[ -z "$REMOTE_PC" || "$REMOTE_PC" == "localhost" ]]; then
    cmd_result=$(bash -c "$command" 2>&1)
    cmd_exit_code=$?
  else
    if ! ping -c 1 "$REMOTE_PC" &>/dev/null; then
      echo -e "${yellow}[ping] $REMOTE_PC unreachable${reset}"
      cmd_result="ping failed"
      cmd_exit_code=1
      return
    fi

    if [[ "$command" == sudo* ]]; then
      if [[ -n "$PASSWORD" ]]; then
        cmd_result=$(ssh -o ConnectTimeout=1 -o BatchMode=yes -o StrictHostKeyChecking=no "${REMOTE_USER:-horizon}"@"$REMOTE_PC" \
          "echo \"$PASSWORD\" | sudo -S ${command#sudo }" 2>&1)
      else
        cmd_result=$(ssh -o ConnectTimeout=1 -o BatchMode=yes -o StrictHostKeyChecking=no "${REMOTE_USER:-horizon}"@"$REMOTE_PC" \
          "sudo -n ${command#sudo }" 2>&1)
      fi
    else
      cmd_result=$(ssh -o ConnectTimeout=1 -o BatchMode=yes -o StrictHostKeyChecking=no "${REMOTE_USER:-horizon}"@"$REMOTE_PC" \
        "$command" 2>&1)
    fi
    cmd_exit_code=$?
  fi

  if $DEBUG; then
    echo -e "--- DEBUG OUTPUT ---" >&2
    echo "$cmd_result" >&2
    echo "---------------------" >&2
  fi
}

# ================================================================
# Run a local-only command; echo its output.
# Requires global: DEBUG
# ================================================================
run_cmd() {
    local CMD="$1"
    $DEBUG && echo -e "\n--- DEBUG: Running: $CMD ---" >&2
    local OUTPUT
    OUTPUT=$(bash -c "$CMD" 2>&1)
    $DEBUG && echo -e "--- DEBUG Output ---\n$OUTPUT\n" >&2
    echo "$OUTPUT"
}

# ================================================================
# Print a labelled debug section header.
# ================================================================
debug_msg() {
    $DEBUG && echo -e "\n--- DEBUG: $1 ---" >&2
}

# ================================================================
# Initialize check counters and start timer.
# Sets globals: START_TIME, PASS_COUNT, WARN_COUNT, FAIL_COUNT, failures
# ================================================================
init_checks() {
    START_TIME=$(date +%s)
    PASS_COUNT=0
    WARN_COUNT=0
    FAIL_COUNT=0
    failures=()
}

# ================================================================
# Print verbose section header banner.
# Requires globals: VERBOSE, SCRIPT_NAME
# ================================================================
print_check_header() {
    if $VERBOSE; then
        echo "==============================================================="
        echo " $SCRIPT_NAME Check "
        echo "==============================================================="
    fi
}

# ================================================================
# Record a single check result.
# Status: "PASS"/"WARN"/"FAIL", or integer 0=PASS / non-zero=FAIL
# Requires globals: VERBOSE, PASS_COUNT, WARN_COUNT, FAIL_COUNT, failures
# ================================================================
report_check() {
    local status="$1"
    local name="$2"
    local expected="$3"
    local actual="$4"

    if [[ "$status" == "0" ]]; then
        status="PASS"
    elif [[ "$status" =~ ^[1-9][0-9]*$ ]]; then
        status="FAIL"
    fi

    if [[ "$status" == "PASS" ]]; then
        ((PASS_COUNT++))
        $VERBOSE && printf "%-45s ${green}[PASS]${reset} Expected: %-25s Actual: %s\n" "$name" "$expected" "$actual" || true
    elif [[ "$status" == "WARN" ]]; then
        ((WARN_COUNT++))
        failures+=("Expected ${name}: ${expected} Actual: ${actual}")
        $VERBOSE && printf "%-45s ${yellow}[WARN]${reset} Expected: %-25s Actual: %s\n" "$name" "$expected" "$actual" || true
    else
        ((FAIL_COUNT++))
        failures+=("Expected ${name}: ${expected} Actual: ${actual}")
        $VERBOSE && printf "%-45s ${red}[FAIL]${reset} Expected: %-25s Actual: %s\n" "$name" "$expected" "$actual" || true
    fi
}

# ================================================================
# Print verbose summary footer, condensed result line, then exit.
# Requires globals: VERBOSE, START_TIME, PASS_COUNT, WARN_COUNT,
#                   FAIL_COUNT, failures, SCRIPT_NAME
# ================================================================
finish_checks() {
    local RUNTIME=$(( $(date +%s) - START_TIME ))

    if $VERBOSE; then
        echo "==============================================================="
        echo " Checks completed: $PASS_COUNT passed, $WARN_COUNT warned, $FAIL_COUNT failed."
        echo " Total runtime: ${RUNTIME}s"
        echo "==============================================================="
    fi

    if [[ $FAIL_COUNT -eq 0 && $WARN_COUNT -eq 0 ]]; then
        echo "${green}$SCRIPT_NAME [PASS]${reset}"
        $VERBOSE && printf "\n" || true
        exit 0
    else
        local detail="${failures[0]}"
        local i
        for ((i=1; i<${#failures[@]}; i++)); do
            detail+=", ${failures[$i]}"
        done
        [[ $FAIL_COUNT -gt 0 ]] && echo "${red}$SCRIPT_NAME [FAIL] $detail${reset}" || echo "${yellow}$SCRIPT_NAME [WARN] $detail${reset}"
        $VERBOSE && printf "\n" || true
        exit 1
    fi
}
