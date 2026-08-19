# Bootcheck Template

A drop-in starting point for a boot-time hardware/software validation suite for a
new product. Copy this folder, rename it, and start adding checks. It encodes the
proven Bootcheck 3.0 architecture: one instance per machine, hostname-dispatched
checklists, parallel sub-checks, and a single machine-readable pass/fail/warn line
per check so a system manager can parse results programmatically.

## What's in here

| File | Purpose |
|---|---|
| `run_bootcheck.sh` | Orchestrator. Picks a checklist by hostname, runs sub-checks in parallel, prints each as it finishes, exits 0/1. |
| `utils_function.sh` | Shared helpers every sub-check sources (`cmd`, `report_check`, `init_checks`, `finish_checks`, …). |
| `0101_template_check.sh` | Copy-me example sub-check with the standard lifecycle. |
| `VersionDependencyReportClass.sh` | Uniform `--version/--*_dependency/--*_id` metadata reporter. |
| `ShowInfo.sh` | Prints metadata for every check in the folder. |
| `VERSION` / `CHANGELOG.md` | Suite version + auto-maintained changelog. |
| `.githooks/post-commit` | Auto-bumps `VERSION` and appends `CHANGELOG.md` when a commit touches any `.sh`. |
| `.claude/commands/autotest.md` | Example Claude Code slash command that runs the suite across machines over SSH. |
| `CLAUDE.md` | Guidance for Claude Code when working in this repo (the "skills"). |

## Quick start

```bash
# 1. Copy the template into your new project and enter it
cp -r bootcheck_template ../my_product_bootcheck && cd ../my_product_bootcheck

# 2. Enable the version-bump hook (one time per clone)
git init            # if not already a repo
git config core.hooksPath .githooks

# 3. Make everything executable
chmod +x run_bootcheck.sh ShowInfo.sh *_check.sh .githooks/post-commit

# 4. Run it
./run_bootcheck.sh          # normal (one line per check)
./run_bootcheck.sh -v       # verbose (per-check detail)
./run_bootcheck.sh -h       # help
```

## Adding a check

1. `cp 0101_template_check.sh 0102_<Name>_check.sh`
2. Set `Version` + dependency vars in the header. `SCRIPT_NAME` auto-derives from the filename.
3. Write `check_*` functions: gather the actual value with `cmd`/`run_cmd`, compare to the
   expected value, call `report_check "PASS|WARN|FAIL" name expected actual`.
4. Call them in `MAIN` between `init_checks` and `finish_checks`.
5. Add the filename to the right `*_functionlist` array in `run_bootcheck.sh`.
6. `chmod +x 0102_<Name>_check.sh`

## Design contract (keep these invariants)

1. **One instance per machine.** Checks are dispatched by matching `$(hostname)` against a
   per-profile checklist in `run_bootcheck.sh`. No central controller drives others at boot.
2. **Machine-readable output.** Normal mode emits exactly one line per sub-check:
   `SCRIPT_NAME [PASS]` or `SCRIPT_NAME [FAIL] detail1, detail2, …`. Verbose (`-v`) adds
   `name [STATUS] Expected: X Actual: Y` rows for humans.
3. **Parallel execution, ordered reporting.** Sub-checks run concurrently; the orchestrator
   prints each result as it completes (0.1s poll loop).
4. **Deterministic exit codes.** `0` = all passed; `1` = any failure or warning — for both
   sub-checks and the orchestrator.
5. **Uniform lifecycle.** Every sub-check parses `-v`/`-d`/`--<report-flag>`/`-h`, sources
   `utils_function.sh`, then runs `init_checks` → check functions → `finish_checks`.
6. **Self-describing.** Every sub-check declares `Version`, `HW_dependency`, `SW_dependency`,
   `TestCaseID`, `RequirementID`; any `--<flag>` routes to the metadata reporter.
7. **Sourced expected values.** Any hardcoded expected value (path, version, package, config,
   IP, service) carries a `# Source: <origin>` comment pointing at where the requirement came
   from. If there's no source, record a `TestCaseID`/`RequirementID` instead of inventing one.
8. **Non-destructive.** Checks are read-only. They must never modify the system under test.
   Privileged reads use key-based SSH with a `sudo -n` (non-interactive) fallback; no secrets
   in the repo (`utils_function.sh` reads `SSH_PASS` from the environment only).

## Status vocabulary

| Status | Meaning | Effect on exit code |
|---|---|---|
| `PASS` | Actual matches expected | none |
| `WARN` | Degraded but not fatal (banding, optional item missing) | non-zero (1) |
| `FAIL` | Actual does not match expected | non-zero (1) |

`report_check` also accepts an integer status: `0` = PASS, non-zero = FAIL.

## Versioning

`VERSION` tracks the suite version independently of individual script versions. The
`post-commit` hook auto-bumps the patch and appends a `CHANGELOG.md` entry whenever a commit
touches any `.sh`. Edit `VERSION` by hand to bump major/minor. When you roll an individual
script's `Version`, append a `# X.Y.Z <date> <description>` line to that file's header block.
