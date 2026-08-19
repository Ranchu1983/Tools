#!/usr/bin/env bash
#
# Self-describing metadata reporter shared by every sub-check.
# A sub-script exports Version/HW_dependency/SW_dependency/TestCaseID/RequirementID
# and delegates any --<flag> here so all scripts report their metadata uniformly.
#
# 0.0.1  init

Version="${Version:-0.0.0}"
HW_dependency="${HW_dependency:-none}"
SW_dependency="${SW_dependency:-none}"
TestCaseID="${TestCaseID:-none}"
RequirementID=(${RequirementID[@]:-none})

report_version()        { echo "Version: $Version"; }
report_hw_dependency()  { echo "Hardware Dependency: $HW_dependency"; }
report_sw_dependency()  { echo "Software Dependency: $SW_dependency"; }
report_test_case_id()   { echo "Test Case ID: $TestCaseID"; }
report_requirement_id() {
    echo -n "Requirement ID: "
    printf "%s" "${RequirementID[0]}"
    for ((i = 1; i < ${#RequirementID[@]}; i++)); do
        printf ", %s" "${RequirementID[$i]}"
    done
    echo
}

if [[ $# -lt 1 ]]; then
    echo "No arguments provided."
    echo "Expected: --version, --hw_dependency, --sw_dependency, --test_case_id, --requirement_id"
    exit 1
fi

case "$1" in
    --version)         report_version ;;
    --hw_dependency)   report_hw_dependency ;;
    --sw_dependency)   report_sw_dependency ;;
    --test_case_id)    report_test_case_id ;;
    --requirement_id)  report_requirement_id ;;
    *)
        echo "Unexpected argument: $1"
        echo "Expected: --version, --hw_dependency, --sw_dependency, --test_case_id, --requirement_id"
        exit 1
        ;;
esac

: <<'END_COMMENT'
Paste this block into each sub-check header to wire up metadata reporting:

#---- version report -----------
Version="0.0.1"
HW_dependency="none"
SW_dependency="none"
TestCaseID="none"
RequirementID=("none")
# (flag handling is done in the sub-check arg-parse loop; see 0101_template_check.sh)
#==============================
END_COMMENT
