# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this bootcheck repo.
This is a template derived from Bootcheck 3.0 — adapt the product-specific parts
(hostnames, IPs, deploy paths, source references) for the new product.

## Git

- Do not auto commit and push. Leave changes staged for the user to review.
- The `post-commit` hook auto-bumps `VERSION` and `CHANGELOG.md` on any `.sh` commit
  (enable with `git config core.hooksPath .githooks`). Don't hand-edit those unless
  bumping major/minor.

## Communication

- Always flag mistakes to the user — including errors in their instructions (duplicate
  script numbers, wrong filenames, incorrect assumptions). Do not silently follow bad input.
- Ask clarifying questions when requirements are ambiguous. Gather enough before implementing.
- Present a clear design before coding: show the checklist of what will be checked, the
  expected values, and the structure.
- Suggest improvements — better approaches, edge cases, potential issues.

## Versioning

When rolling a version number in any script, append a version-history comment line
(`# X.Y.Z <date> <description>`) after the last entry in that file's header block.

## Source references (critical for a validation suite)

- Whenever a check hardcodes an expected value (path, version, package, config, IP, service,
  env var, udev rule, directory), add a `# Source: <origin>` comment next to where that value
  is defined, pointing at the authoritative origin (e.g. an ansible role, a spec doc, a config
  repo path, a requirement ticket) it was derived from.
- If a check has no identifiable source, do NOT invent one — instead remind the user to add a
  `TestCaseID` / `RequirementID` for that check.

## Architecture (how the suite fits together)

### Orchestrator — `run_bootcheck.sh`
Selects a `*_functionlist` array by matching `$(hostname)`, launches each sub-check in the
background (output captured to a temp file), and prints results in completion order via a
0.1s poll loop. Exit code: `0` = all pass, `1` = any failure/warning. Handles `-v`, `-no_log`,
`--cancel`, `--test-*` modes, `-h`, and `--<metadata-flag>`.

### Sub-checks — `01NN_<Name>_check.sh`
Uniform lifecycle:
1. Parse `-v`/`--verbose`, `-d`/`--debug`, `--<flag>` (metadata), `-h`/`--help`.
2. `source "$SCRIPT_DIR/utils_function.sh"`.
3. `init_checks` → resets counters + timer.
4. `print_check_header` → banner when verbose.
5. Call check functions, each ending in `report_check`.
6. `finish_checks` → prints the condensed result line and exits 0/1.

Output contract:
- Normal: one line → `SCRIPT_NAME [PASS]` or `SCRIPT_NAME [FAIL] detail1, detail2, …`
- Verbose (`-v`): per-check rows `name [STATUS] Expected: X Actual: Y` before the summary.

### Shared utilities — `utils_function.sh`
| Function | Purpose |
|---|---|
| `init_checks` | Sets `START_TIME`, `PASS_COUNT`, `WARN_COUNT`, `FAIL_COUNT`, `failures[]` |
| `report_check STATUS NAME EXPECTED ACTUAL` | Counts, records failures, prints verbose row |
| `finish_checks` | Prints summary; exits 0 (all pass) or 1 (any fail/warn) |
| `print_check_header` | Section banner in verbose mode |
| `cmd "..."` | Runs locally or over SSH; sets `cmd_result`, `cmd_exit_code` |
| `run_cmd "..."` | Local-only wrapper, echoes output |
| `debug_msg "..."` | Debug banner when `DEBUG=true` |

`report_check` accepts integer status (`0`=PASS, non-zero=FAIL) or string `PASS/WARN/FAIL`.

### Metadata reporting — `VersionDependencyReportClass.sh`
Every sub-check declares `Version`, `HW_dependency`, `SW_dependency`, `TestCaseID`,
`RequirementID`. Passing any `--<flag>` exports those and routes here for uniform reporting.
`ShowInfo.sh` walks the folder and prints all of it.

## Adding a new sub-check
1. Copy `0101_template_check.sh` → `01NN_<Name>_check.sh`.
2. Set `Version` + dependency vars (`SCRIPT_NAME` auto-derives from the filename).
3. Implement checks with `cmd`/`run_cmd` + `report_check`; add `# Source:` for every expected value.
4. `init_checks` → check functions → `finish_checks` in MAIN.
5. Add the filename to the right `*_functionlist` in `run_bootcheck.sh`.
6. `chmod +x 01NN_<Name>_check.sh`.

## Product-specific things to customize (search-and-replace when starting a new product)
- **Hostname patterns + profiles** in `run_bootcheck.sh` (`typeA`/`typeB`/`dev` → your machines).
- **`LOG_DIR`** in `run_bootcheck.sh`.
- **`REMOTE_USER`/deploy paths/IPs** if you add a remote runner (see the reference project's
  `run_bootcheck_remote.sh` for the pattern).
- **`# Source:` origins** — point them at this product's config/spec repo.
- **`.claude/commands/`** — update SSH aliases, IPs, and remote paths for this fleet.

## Non-negotiable invariants
Read-only checks (never modify the system under test); deterministic exit codes; one summary
line per sub-check; parallel run / ordered report; no secrets in the repo (`SSH_PASS` from env
only, `sudo -n` fallback).
