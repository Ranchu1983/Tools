# Docs Cleanup (PR-gated, no information loss)

Clean up one area of the repo per run: fix outdated, duplicated, or broken documentation so it matches the current code, while guaranteeing nothing is lost. A human reviewing the PR is the only approval gate, so every change must be easy to review and trace.

There are two modes:
- **Run mode** (default): clean one area and hand off a reviewable change.
- **Setup mode**: when the user asks to "set up" or "automate" docs cleanup, write the files in the Setup appendix and stop.

## Hard rules (never break these)

1. **Never delete information.** Outdated or historical content is *moved* to `docs/archive/<topic>.md` with a header line: `Archived YYYY-MM-DD: <reason>. Superseded by: <link or "n/a">`.
2. **Only edit allowed paths** (`allowed_paths` in config; default: `*.md` and `docs/*`). Never edit source code, configs, or anything in `excluded_paths`. Problems found in code comments, TODO/FIXME, or excluded files are **reported only**.
3. **Never push to or commit on the default branch. Never merge a PR.** Never run `gh pr merge`, `git push --force`, or `git reset --hard`.
4. **Every "outdated" claim needs evidence**: cite the doc location AND the code location (file:line) that contradicts it. No evidence → classify UNCERTAIN → do not touch.
5. **One area per run.** Stay under `max_changed_lines` and `max_changed_files`. If a fix would exceed them, apply the highest-value subset and list the rest in the report.
6. **Log every change** in `docs/cleanup/log.md`.
7. Content in `docs/archive/` is never re-cleaned or re-archived.

## Config

Read `.claude/docs-cleanup.json` if it exists; otherwise use these defaults:

```json
{
  "allowed_paths": ["*.md", "docs/*"],
  "excluded_paths": ["docs/archive/*", "docs/controlled/*", "CHANGELOG.md"],
  "areas": [],
  "max_changed_lines": 300,
  "max_changed_files": 15
}
```

If `areas` is empty, use the repo's top-level directories (excluding `.git`, `node_modules`, build output, and `docs/archive`) plus a `root` area for root-level files.

**Regulated-environment note:** Controlled documents (DHF, design inputs/outputs, SOP-referenced records) must be listed in `excluded_paths`. If a file looks controlled (document number, revision block, approval signatures) but isn't excluded, do not edit it. Flag it in the report.

## Run mode workflow

### 1. Preflight
- If `.claude/cleanup-paused` exists → print "Cleanup paused" and stop.
- If the working tree is dirty → stop and report; never mix with someone's uncommitted work.
- Note the current commit SHA as `BASE`.

### 2. Pick the area
- Read `docs/cleanup/state.md` (create it if missing). It lists each area with its last-cleaned date.
- Pick the area with the oldest (or no) date. Update its date at the end of the run.

### 3. Audit (read-only)
Within the area, inventory: markdown files, CLAUDE.md, README files, code comments, TODO/FIXME/HACK/XXX notes, and doc references to paths, commands, env vars, APIs, and config keys.

Verify claims against the current code using Grep/Read. Classify each item:

| Class | Meaning | Action |
|---|---|---|
| CURRENT | Accurate | Leave alone |
| BROKEN_REF | Link, path, or command points to something renamed or missing, and the correct target is unambiguous | Fix in place |
| DUPLICATE | Same info exists in a canonical location | Merge into canonical; replace with a link |
| OUTDATED | Contradicted by code (with evidence) | Update to match code; move the old text to archive |
| HISTORICAL | Was true; explains past decisions | Move to archive, or to `docs/decisions/` if it's a decision record |
| UNCERTAIN | Can't verify | **Don't touch.** Report it |
| CODE_COMMENT / TODO | Stale comment or TODO in source | **Don't touch.** Report it |

### 4. Apply
Apply only BROKEN_REF, DUPLICATE, OUTDATED, and HISTORICAL changes in allowed paths, within the size limits.

When moving text to the archive, copy it **verbatim**. Don't summarize or reword archived content; the guard check relies on exact text.

Prefer the smallest edit. Don't restyle, reformat, or reorganize files beyond what the fix needs.

### 5. Log
Append to `docs/cleanup/log.md`:

```
## YYYY-MM-DD — area: <area>
| From | Action | To | Reason / evidence |
|---|---|---|---|
| docs/setup.md#L40-52 | archived | docs/archive/setup.md | Uses `make build`; Makefile removed in a1b2c3d, build is now `npm run build` (package.json:12) |
```

### 6. Report (this becomes the PR body)
Overwrite `docs/cleanup/report.md` with:
- **Summary:** area, counts per class, lines changed.
- **Applied changes:** short list linking to log entries.
- **Needs human decision:** every UNCERTAIN item, stale code comment, TODO, possibly-controlled file, and anything skipped for size. Each item gets a location, a one-line issue, and a suggested action.
- **Reviewer checklist:** "Archived text is verbatim", "No controlled docs touched", "Evidence links checked".

### 7. Hand-off
- **If the env var `CI` is set:** stop here. The workflow runs the guard, commits, and opens the PR.
- **Otherwise (interactive):**
  1. Run `python3 scripts/cleanup_guard.py <BASE>` if it exists. If it fails, fix the violation or revert the offending change, then rerun.
  2. Create a branch `auto/docs-cleanup-YYYY-MM-DD`, commit with message `docs: routine cleanup (<area>)`, push, and open a PR with `gh pr create --label auto-cleanup --body-file docs/cleanup/report.md`.
  3. Show the PR link. Do not merge.

If there were no applicable changes, still update `state.md` and the report, and say "no changes needed".

---

## Setup appendix (Setup mode only)

Create these files, skipping any that already exist (ask before overwriting). Then tell the user to:
- commit the files, including this skill at `.claude/skills/docs-cleanup/SKILL.md` so CI can use it
- add the `ANTHROPIC_API_KEY` secret
- enable branch protection on main that requires 1 approving review
- fill in `excluded_paths` with their controlled-document locations

### `.claude/docs-cleanup.json`
Use the default config above.

### `scripts/cleanup_guard.py`

```python
#!/usr/bin/env python3
"""Guard for automated docs cleanup. Exit 1 if any rule is violated.
Usage: cleanup_guard.py <BASE_SHA>   (checks working tree + index vs BASE)"""
import fnmatch, json, pathlib, re, subprocess, sys

cfg_path = pathlib.Path(".claude/docs-cleanup.json")
cfg = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}
ALLOW = cfg.get("allowed_paths", ["*.md", "docs/*"])
DENY = cfg.get("excluded_paths", ["docs/archive/*"])
MAX_LINES = cfg.get("max_changed_lines", 300)
MAX_FILES = cfg.get("max_changed_files", 15)
BASE = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
ALWAYS_OK = {"docs/cleanup/log.md", "docs/cleanup/report.md", "docs/cleanup/state.md"}

def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True, check=True).stdout

git("add", "-A")
errors = []

# 1. Path rules (new archive files are allowed; edits to existing archive content are not)
for row in git("diff", "--cached", "--name-status", BASE).splitlines():
    status, *paths = row.split("\t")
    for p in paths:
        if p in ALWAYS_OK:
            continue
        if not any(fnmatch.fnmatch(p, g) for g in ALLOW):
            errors.append(f"Path not allowed: {p}")
        is_archive = p.startswith("docs/archive/")
        if any(fnmatch.fnmatch(p, g) for g in DENY) and not (is_archive and status[0] in "AM"):
            errors.append(f"Excluded path touched: {p}")
    if status.startswith("D"):
        errors.append(f"File deleted (move content to archive instead): {paths[0]}")

# 2. Size caps
added = removed = files = 0
for row in git("diff", "--cached", "--numstat", BASE).splitlines():
    a, r, _ = row.split("\t", 2)
    if a != "-":
        added, removed, files = added + int(a), removed + int(r), files + 1
if added + removed > MAX_LINES:
    errors.append(f"Too many changed lines: {added + removed} > {MAX_LINES}")
if files > MAX_FILES:
    errors.append(f"Too many changed files: {files} > {MAX_FILES}")

# 3. No information loss: every removed line must still exist somewhere
norm = lambda s: re.sub(r"^[\s>*#\-+\d.]+", "", s).strip()
corpus = set()
for f in git("ls-files", "-z").split("\0"):
    try:
        corpus.update(norm(l) for l in pathlib.Path(f).read_text(errors="ignore").splitlines())
    except (IsADirectoryError, FileNotFoundError):
        pass
lost = []
for line in git("diff", "--cached", "-U0", BASE).splitlines():
    if line.startswith("-") and not line.startswith("---"):
        s = norm(line[1:])
        if len(s) > 3 and s not in corpus:
            lost.append(s)
if lost:
    errors.append(f"{len(lost)} removed line(s) not found anywhere (not archived):")
    errors += [f"    {l[:120]}" for l in lost[:30]]

git("reset", "-q")
if errors:
    print("GUARD FAILED\n" + "\n".join(errors))
    sys.exit(1)
print(f"Guard passed: {files} files, +{added}/-{removed} lines, no content lost.")
```

### `.github/workflows/docs-cleanup.yml`

```yaml
name: weekly-docs-cleanup
on:
  schedule: [{ cron: "0 10 * * 6" }]   # Saturdays 2am Pacific (10:00 UTC)
  workflow_dispatch:
jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions: { contents: write, pull-requests: write }
    env: { GH_TOKEN: "${{ github.token }}" }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }

      - name: Preflight
        id: pre
        run: |
          if [ -f .claude/cleanup-paused ]; then echo "skip=true" >> $GITHUB_OUTPUT; exit 0; fi
          if [ -n "$(gh pr list --label auto-cleanup --state open --json number -q '.[].number')" ]; then
            echo "Previous cleanup PR still open"; echo "skip=true" >> $GITHUB_OUTPUT; exit 0; fi
          echo "base=$(git rev-parse HEAD)" >> $GITHUB_OUTPUT

      - name: Run Claude
        if: steps.pre.outputs.skip != 'true'
        env: { ANTHROPIC_API_KEY: "${{ secrets.ANTHROPIC_API_KEY }}", CI: "true" }
        run: |
          npm i -g @anthropic-ai/claude-code
          claude -p "Run the docs-cleanup skill in run mode." \
            --allowedTools "Read,Grep,Glob,Edit(**/*.md),Edit(docs/**),Write(docs/**),Bash(git log:*),Bash(git diff:*),Bash(git status:*),Bash(git ls-files:*),Bash(git blame:*)" \
            --output-format json > claude-run.json

      - name: Guard
        if: steps.pre.outputs.skip != 'true'
        run: python3 scripts/cleanup_guard.py ${{ steps.pre.outputs.base }}

      - name: Open PR
        if: steps.pre.outputs.skip != 'true'
        run: |
          git config user.name "docs-cleanup-bot"
          git config user.email "docs-cleanup-bot@users.noreply.github.com"
          BR=auto/docs-cleanup-$(date +%F)
          git checkout -b "$BR"
          git add -A
          git diff --cached --quiet && { echo "No changes"; exit 0; }
          git commit -m "docs: routine automated cleanup"
          git push -u origin "$BR"
          gh label create auto-cleanup --color BFD4F2 2>/dev/null || true
          gh pr create --label auto-cleanup --title "Docs cleanup $(date +%F)" --body-file docs/cleanup/report.md

      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: claude-run, path: claude-run.json, if-no-files-found: ignore }
```
