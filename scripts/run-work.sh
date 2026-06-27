#!/usr/bin/env bash
# run-work.sh - the canonical UNATTENDED supervisor loop. Re-invokes /work in a
# FRESH `claude -p` process each pass so every respawn starts at ~0% context;
# each pass resumes from PROGRESS.md, drives the top task to green-or-checkpoint,
# and exits. The supervisor relaunches until: backlog empty (done), a BLOCKED line
# in PROGRESS.md (halt for human), MaxPasses, or an optional token budget.
#
# Single-instance per repo (pidfile + lockfile). Stoppable via .work-off (repo or
# global) or by killing the pidfile pid (see supervisord.sh stop). Each pass runs
# PHALANX_ONESHOT=1 + PHALANX_SUPERVISOR=1 so the per-pass loop drives ONE task to
# green and the SUPERVISOR (not the Stop hook) provides multi-pass continuation.
#
# Usage: run-work.sh [-r repo] [-m maxpasses] [-s sleepsecs] [-b tokenbudget]
set -uo pipefail

# Resolve script dir BEFORE any cd (BASH_SOURCE may be relative).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="$(pwd)"; MAX_PASSES=30; SLEEP_SECONDS=3; TOKEN_BUDGET=0
while getopts "r:m:s:b:" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;; m) MAX_PASSES="$OPTARG" ;; s) SLEEP_SECONDS="$OPTARG" ;; b) TOKEN_BUDGET="$OPTARG" ;;
    *) echo "usage: run-work.sh [-r repo] [-m maxpasses] [-s sleepsecs] [-b tokenbudget]" >&2; exit 2 ;;
  esac
done
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "bad repo path" >&2; exit 1; }
cd "$REPO"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
# Headless auth: each `claude -p` pass needs CLAUDE_CODE_OAUTH_TOKEN -- the
# interactive OAuth in .credentials.json is rejected for `claude -p` (401). Read
# ONLY the token from the operator-provisioned file and pass it solely on the
# `claude` invocation env (below), never `. source` it into the whole pass env --
# otherwise every child (curl/docker/ssh) inherits the token (exfil risk).
# Mint via `claude setup-token`; write `export CLAUDE_CODE_OAUTH_TOKEN=...` (or a
# bare `CLAUDE_CODE_OAUTH_TOKEN=...`) to $CLAUDE_DIR/.headless-env, mode 0600.
OAUTH_TOKEN=""
HEADLESS_ENV="$CLAUDE_DIR/.headless-env"
if [ -f "$HEADLESS_ENV" ]; then
  # Refuse a group- or other-readable token file (perms must be 0600/0400):
  # reject if either the group digit or the other digit is non-zero.
  perms="$(stat -c '%a' "$HEADLESS_ENV" 2>/dev/null || stat -f '%Lp' "$HEADLESS_ENV" 2>/dev/null || echo '')"
  go="${perms: -2}"
  if [ -n "$perms" ] && [ "$go" != "00" ]; then
    echo "WARN: $HEADLESS_ENV is group/other-readable (mode $perms); skipping. chmod 600 it." >&2
  else
    OAUTH_TOKEN="$(grep -E '^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_OAUTH_TOKEN=' "$HEADLESS_ENV" 2>/dev/null \
      | tail -n1 | sed -E 's/^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'']//; s/["'\'']$//')"
  fi
fi
NOTIFY="$HERE/notify.sh"; [ -x "$NOTIFY" ] || NOTIFY="$CLAUDE_DIR/notify.sh"
UNSEED="$HERE/unseed-task.sh"; [ -x "$UNSEED" ] || UNSEED="$CLAUDE_DIR/unseed-task.sh"
TASKS="$REPO/TASKS.md"; PROGRESS="$REPO/PROGRESS.md"; LOGDIR="$REPO/.claude-runs"
PIDF="$LOGDIR/supervisor.pid"; LOCK="$LOGDIR/supervisor.lock"
# Per-run log subdir so the -b token budget counts ONLY this run's passes, not
# every historical pass-*.log ever written for this repo (item 1). Old logs stay.
RUN_STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 0)-$$"
RUNDIR="$LOGDIR/run-$RUN_STAMP"
mkdir -p "$RUNDIR"

note() { [ -x "$NOTIFY" ] && PHALANX_REPO="$REPO" "$NOTIFY" "$1" "$2" >/dev/null 2>&1 || true; }

# --- single-instance lock (atomic mkdir) -------------------------------------
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
    echo "supervisor already running (pid $(cat "$PIDF")) for $REPO" >&2; exit 3
  fi
  rm -rf "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || { echo "cannot acquire lock" >&2; exit 3; }
fi
echo "$$" > "$PIDF"
STOP_REASON="ended"
cleanup() {
  rm -f "$PIDF" 2>/dev/null; rm -rf "$LOCK" 2>/dev/null
  # request-scoped one-shot cleanup: if this run seeded a single tagged request,
  # remove its line so a left-open TASKS.md can't re-arm the loop later (item 6).
  [ -n "${PHALANX_REQ_ID:-}" ] && [ -x "$UNSEED" ] && "$UNSEED" "$REPO" "$PHALANX_REQ_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'STOP_REASON="signalled"; exit 0' INT TERM

if [ ! -f "$TASKS" ]; then echo "No TASKS.md in $REPO. Create one with '- [ ]' items first." >&2; exit 1; fi

backlog_empty() { [ -f "$TASKS" ] || return 0; ! grep -Eq '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]' "$TASKS"; }
off()           { [ -f "$REPO/.work-off" ] || [ -f "$CLAUDE_DIR/.work-off" ]; }
blocked()       { [ -f "$PROGRESS" ] && tail -n 25 "$PROGRESS" | grep -q 'BLOCKED'; }
spent_tokens()  { local b; b=$(cat "$RUNDIR"/pass-*.log 2>/dev/null | wc -c); echo $(( b / 4 )); }

note start "supervisor up: $REPO (max=$MAX_PASSES)"
pass=0; fails=0
while true; do
  if off;          then echo "Kill switch (.work-off). Stopping."; STOP_REASON="work-off"; break; fi
  if blocked;      then echo "BLOCKED in PROGRESS.md. Halting for human."; STOP_REASON="blocked"; note blocked "$(tail -n 3 "$PROGRESS" | tr '\n' ' ')"; break; fi
  if backlog_empty; then echo "Backlog empty. Done."; STOP_REASON="done"; break; fi
  pass=$((pass + 1))
  if (( pass > MAX_PASSES )); then echo "Hit MaxPasses=$MAX_PASSES. Stopping."; STOP_REASON="maxpasses"; break; fi
  if (( TOKEN_BUDGET > 0 )) && (( $(spent_tokens) > TOKEN_BUDGET )); then
    echo "Token budget $TOKEN_BUDGET exceeded (~$(spent_tokens)). Stopping."; STOP_REASON="budget"; break; fi

  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 0)"; log="$RUNDIR/pass-$pass-$stamp.log"
  echo "=== Pass $pass - $(date +%T 2>/dev/null) - fresh /work ==="
  note progress "pass $pass starting"
  set +e
  PHALANX_ONESHOT=1 PHALANX_SUPERVISOR=1 PHALANX_REPO="$REPO" \
    CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN" \
    claude -p "/work" 2>&1 | tee "$log"; code="${PIPESTATUS[0]}"
  set -e

  if [ "$code" -ne 0 ]; then
    fails=$((fails + 1))
    echo "claude exited $code on pass $pass (consecutive fails: $fails). Will relaunch fresh."
    # A killed/crashed pass is RECOVERABLE: the next fresh /work resumes from
    # PROGRESS.md. Only give up after several consecutive failures.
    if (( fails >= 3 )); then echo "3 consecutive failures. Stopping. See $log." >&2; STOP_REASON="repeated-failure"; note blocked "supervisor stopped: 3 consecutive pass failures"; break; fi
  else
    fails=0
  fi
  sleep "$SLEEP_SECONDS"
done

echo "Loop ended ($STOP_REASON). Passes run: $pass. Logs in $LOGDIR."
note done "supervisor stopped ($STOP_REASON) after $pass pass(es): $REPO"
