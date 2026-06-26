#!/usr/bin/env bash
# run-work.sh - outer autonomy loop. Re-invokes /work in a FRESH process each pass
# so every respawn starts at ~0% context. Exits when: backlog empty, BLOCKED, or capped.
# Usage: run-work.sh [-r repo] [-m maxpasses] [-s sleepsecs]
set -euo pipefail

REPO="$(pwd)"; MAX_PASSES=30; SLEEP_SECONDS=3
while getopts "r:m:s:" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;; m) MAX_PASSES="$OPTARG" ;; s) SLEEP_SECONDS="$OPTARG" ;;
    *) echo "usage: run-work.sh [-r repo] [-m maxpasses] [-s sleepsecs]" >&2; exit 2 ;;
  esac
done
cd "$REPO"
TASKS="$REPO/TASKS.md"; PROGRESS="$REPO/PROGRESS.md"; LOGDIR="$REPO/.claude-runs"
mkdir -p "$LOGDIR"
if [[ ! -f "$TASKS" ]]; then echo "No TASKS.md in $REPO. Create one with '- [ ]' items first." >&2; exit 1; fi
backlog_empty() { [[ -f "$TASKS" ]] || return 0; ! grep -Eq '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]' "$TASKS"; }
pass=0
while true; do
  pass=$((pass + 1))
  if (( pass > MAX_PASSES )); then echo "Hit MaxPasses=$MAX_PASSES. Stopping."; break; fi
  if backlog_empty; then echo "Backlog empty. Done."; break; fi
  stamp="$(date +%Y%m%d-%H%M%S)"; log="$LOGDIR/pass-$pass-$stamp.log"
  echo "=== Pass $pass - $(date +%T) - fresh /work ==="
  set +e; claude -p "/work" 2>&1 | tee "$log"; code="${PIPESTATUS[0]}"; set -e
  if [[ "$code" -ne 0 ]]; then echo "claude exited $code on pass $pass. Stopping. Check $log." >&2; break; fi
  if [[ -f "$PROGRESS" ]] && tail -n 20 "$PROGRESS" | grep -q 'BLOCKED'; then
    echo "Blocker in PROGRESS.md. Stopping for human. See $PROGRESS."; break
  fi
  sleep "$SLEEP_SECONDS"
done
echo "Loop ended. Passes run: $pass. Logs in $LOGDIR."
