#!/bin/bash
#
# Scan every executable check in this directory and print its self-describing
# metadata (--version / --sw_dependency / --hw_dependency / --test_case_id /
# --requirement_id). Handy for a quick inventory of the suite.
#
# 0.0.1 init template

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

Version=0.0.1
self_path=$(realpath "$0")
self_name=$(basename "$0")
printf "${GREEN}%-20s${NC} %s\n" "$self_name" " Version: $Version"

scan_dir="$(cd "$(dirname "$0")" && pwd)"

find -P "$scan_dir" \
    -path "$scan_dir/.git" -prune -o \
    -path "$scan_dir/VersionDependencyReportClass.sh" -prune -o \
    -name '*_check.sh' -type f -executable -print | sort | while read -r script; do
    script_path=$(realpath -P "$script")
    [[ "$script_path" == "$self_path" ]] && continue
    filename="$(basename "$script_path")"
    printf "${YELLOW}%-40s${NC}\n" "$filename"

    for flag in --version --sw_dependency --hw_dependency --test_case_id --requirement_id; do
        output=$("$script_path" "$flag" 2>&1)
        if [[ $? -ne 0 || -z "$output" ]]; then
            echo -e "${RED}  ${flag}: not supported${NC}"
        else
            printf "  %s\n" "$output"
        fi
    done
done
