Run the full bootcheck suite on every target machine over SSH, then per-script.

CUSTOMIZE for your fleet before first use:
  - Remote path where the suite is deployed:  /home/<user>/bootcheck/
  - SSH targets: replace <hostA>/<hostB> and their IPs with your machines.
  - If your targets need a login shell for environment (PATH, product env vars),
    invoke remote scripts via `bash -l -c "..."` so /etc/profile.d/ is sourced.

---

## Phase 0 — Sync local files to all targets

Sync the local working directory to every remote in parallel before running.
Local source: this git repo root (the directory containing run_bootcheck.sh).
Remote destination: /home/<user>/bootcheck/

```bash
for ip in <hostA-ip> <hostB-ip>; do
  rsync -av --delete --exclude='.git' \
    -e "ssh -o StrictHostKeyChecking=no -o TCPKeepAlive=yes" \
    ./ <user>@"$ip":/home/<user>/bootcheck/ &
done
wait
```
Report files transferred per target, or any rsync errors. Always run Phase 0 first.

---

## Phase 1 — Full suite result (run_bootcheck.sh)

Run in parallel on all targets:
```bash
ssh <user>@<hostA-ip> 'bash -l -c /home/<user>/bootcheck/run_bootcheck.sh'
ssh <user>@<hostB-ip> 'bash -l -c /home/<user>/bootcheck/run_bootcheck.sh'
```
Report per machine: exit code, the PASS/FAIL summary, and any [FAIL]/[WARN] lines.

---

## Phase 2 — Individual scripts, exit code only

For each machine, run every applicable 01NN_*_check.sh with no flags; capture exit
code + summary line. Present as a table: Machine | Script | Exit | Summary line.

## Phase 3 — Individual scripts with -v (verbose)

Repeat Phase 2 with `-v`; show per-check detail rows. Flag any [FAIL]/[WARN].

## Phase 4 — Individual scripts with -d (debug)

Repeat Phase 2 with `-d`; show DEBUG command/output blocks. Highlight anomalies.

---

## Notes
- `[PASS] N/A not applicable` is correct behaviour, not a failure.
- If SSH fails, mark the machine unreachable and continue.
- Phase 1 runs all machines in parallel; Phases 2–4 run sequentially per script.
