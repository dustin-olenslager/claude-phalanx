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

REPO="$(pwd)"; MAX_PASSES="${PHALANX_MAX_PASSES:-30}"; SLEEP_SECONDS=3
# Default per-run token ceiling (anti-churn): a pathological run is bounded even
# without -b. Override with -b / PHALANX_TOKEN_BUDGET; set 0 to disable.
TOKEN_BUDGET="${PHALANX_TOKEN_BUDGET:-1500000}"
# Consecutive exit-0 passes that advance NOTHING (no TASKS/PROGRESS change) before
# failing closed. `claude -p` returns 0 even on a 401, so the failure counter alone
# can't see a doomed-but-quiet pass -- the no-progress detector is what catches it.
NOPROG_MAX="${PHALANX_NOPROG_MAX:-3}"
while getopts "r:m:s:b:" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;; m) MAX_PASSES="$OPTARG" ;; s) SLEEP_SECONDS="$OPTARG" ;; b) TOKEN_BUDGET="$OPTARG" ;;
    *) echo "usage: run-work.sh [-r repo] [-m maxpasses] [-s sleepsecs] [-b tokenbudget]" >&2; exit 2 ;;
  esac
done
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "bad repo path" >&2; exit 1; }
cd "$REPO"

# Keep per-pass worktree checkouts out of the primary tree's git status (local exclude,
# never committed). Worktrees live under .claude/worktrees/ (the claude --worktree default).
grep -qxF '.claude/worktrees/' "$REPO/.git/info/exclude" 2>/dev/null || echo '.claude/worktrees/' >> "$REPO/.git/info/exclude" 2>/dev/null || true

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# A detached/cron launch can hand run-work a PATH that has the standard bins but
# MISSES the npm global bin where `claude` lives -> `claude` exits 127 ("No such
# file or directory") EVERY pass -> the loop gives up after 3. Append the npm
# global bin + standard bins (appended, so an explicit PATH such as the install
# self-test's stub still takes precedence).
export PATH="${PATH:+$PATH:}$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"

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
# Loop git push creds: a DEDICATED, scoped PAT so a supervised pass can push branches,
# open PRs, and (in opted-in repos) merge to main + deploy. Same safety model as the
# OAuth token: read ONLY the token from an operator-provisioned 0600 file and pass it
# SOLELY on the `claude` invocation env below -- never `. source` it, or every child
# (curl/ssh/docker) would inherit a push-capable token (exfil risk). Provision: write
# `GH_TOKEN=<scoped PAT>` (or `export GH_TOKEN=...`) to $CLAUDE_DIR/.loop-git-env, 0600.
# Inside the pass the orchestrator runs `gh auth setup-git` so git push uses GH_TOKEN;
# gh uses it directly for PRs. Absent -> the loop falls back to PR-less branch work and
# reports a creds gap (it never merges without push creds).
GH_TOKEN_VAL=""
LOOP_GIT_ENV="$CLAUDE_DIR/.loop-git-env"
if [ -f "$LOOP_GIT_ENV" ]; then
  gperms="$(stat -c '%a' "$LOOP_GIT_ENV" 2>/dev/null || stat -f '%Lp' "$LOOP_GIT_ENV" 2>/dev/null || echo '')"
  ggo="${gperms: -2}"
  if [ -n "$gperms" ] && [ "$ggo" != "00" ]; then
    echo "WARN: $LOOP_GIT_ENV is group/other-readable (mode $gperms); skipping. chmod 600 it." >&2
  else
    GH_TOKEN_VAL="$(grep -E '^[[:space:]]*(export[[:space:]]+)?GH_TOKEN=' "$LOOP_GIT_ENV" 2>/dev/null \
      | tail -n1 | sed -E 's/^[[:space:]]*(export[[:space:]]+)?GH_TOKEN=//; s/^["'\'']//; s/["'\'']$//')"
  fi
fi
# Generalized loop access: a user wires WHATEVER extra creds their loop needs
# (CLOUDFLARE_API_TOKEN, FLY_API_TOKEN, registry logins, ssh host vars, ...) into
# $CLAUDE_DIR/.loop-access.env, 0600, as raw `KEY=value` lines (no quotes, `export`
# optional, `#` comments ok). Same safety model as the two tokens above: each var is
# passed SOLELY on the `claude` invocation env below, never `. source`d into the
# supervisor's own long-lived env. The pass's agent + its worker bash see them (so it
# can deploy/auth); the supervisor process does not. MCP servers, browser/e2e, skills,
# and ssh are already inherited from the same ~/.claude -- this file is only for SECRETS.
ACCESS_KV=()
LOOP_ACCESS_ENV="$CLAUDE_DIR/.loop-access.env"
if [ -f "$LOOP_ACCESS_ENV" ]; then
  aperms="$(stat -c '%a' "$LOOP_ACCESS_ENV" 2>/dev/null || stat -f '%Lp' "$LOOP_ACCESS_ENV" 2>/dev/null || echo '')"
  if [ -n "$aperms" ] && [ "${aperms: -2}" != "00" ]; then
    echo "WARN: $LOOP_ACCESS_ENV is group/other-readable (mode $aperms); skipping. chmod 600 it." >&2
  else
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"   # ltrim
      case "$line" in ''|'#'*) continue;; esac
      line="${line#export }"
      case "$line" in *=*) ACCESS_KV+=("$line");; esac
    done < "$LOOP_ACCESS_ENV"
  fi
fi
NOTIFY="$HERE/notify.sh"; [ -x "$NOTIFY" ] || NOTIFY="$CLAUDE_DIR/notify.sh"
UNSEED="$HERE/unseed-task.sh"; [ -x "$UNSEED" ] || UNSEED="$CLAUDE_DIR/unseed-task.sh"
# Single source of truth for TASKS/PROGRESS parsing (mirrors the JS lib tasksState).
TS_LIB="$HERE/tasks-state.sh"; [ -f "$TS_LIB" ] || TS_LIB="$CLAUDE_DIR/tasks-state.sh"
# shellcheck source=/dev/null
. "$TS_LIB" || { echo "FATAL: cannot source $TS_LIB" >&2; exit 1; }
TASKS="$REPO/TASKS.md"; PROGRESS="$REPO/PROGRESS.md"; LOGDIR="$REPO/.claude-runs"
PIDF="$LOGDIR/supervisor.pid"; LOCK="$LOGDIR/supervisor.lock"
# Structured sentinels (control flow MUST NOT depend on tail-window position):
#  - BLOCKED file = authoritative human-halt (item 1); written the moment a
#    BLOCKED line first appears in PROGRESS.md, honored even if later passes push
#    that line out of any tail window.
#  - pending-unseed = req ids that some run must unseed even if it isn't the one
#    that seeded them (item 2: bot-handoff re-arm leak when a supervisor is up).
BLOCKED_FILE="$LOGDIR/BLOCKED"; PENDING_UNSEED="$LOGDIR/pending-unseed"
# Per-run log subdir so the -b token budget counts ONLY this run's passes, not
# every historical pass-*.log ever written for this repo (item 1). Old logs stay.
RUN_STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 0)-$$"
RUNDIR="$LOGDIR/run-$RUN_STAMP"
mkdir -p "$RUNDIR"

note() { [ -x "$NOTIFY" ] && PHALANX_REPO="$REPO" "$NOTIFY" "$1" "$2" >/dev/null 2>&1 || true; }

# --- single-instance lock (atomic mkdir) -------------------------------------
# Verify a recorded pid is ACTUALLY a live run-work.sh (item 3): a bare `kill -0`
# trusts PID reuse, so after a crash/reboot an unrelated process holding the same
# pid would make the loop look permanently "running" and block auto-start forever.
runwork_pid_alive() {
  local p="$1"
  [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  if [ -r "/proc/$p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'run-work.sh' || return 1
  fi
  return 0
}
# Single-instance lock. flock is kernel-atomic AND auto-released the instant this process
# dies (even SIGKILL/crash) -- so there is no orphan lock and, crucially, no stale-pidfile
# RECLAIM RACE. That race is what let N supervisors run the SAME repo at once: a killed
# supervisor left lock+stale-pidfile behind, then several launchers all saw "owner dead ->
# reclaim" and the non-atomic `rm -rf + mkdir` let them ALL proceed. flock -n admits exactly
# one holder; everyone else exits 3. Legacy mkdir guard kept only if flock is unavailable.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK.flock" || { echo "cannot open lock file for $REPO" >&2; exit 3; }
  if ! flock -n 9; then echo "supervisor already running for $REPO" >&2; exit 3; fi
elif ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$PIDF" ] && runwork_pid_alive "$(cat "$PIDF" 2>/dev/null)"; then
    echo "supervisor already running (pid $(cat "$PIDF")) for $REPO" >&2; exit 3
  fi
  # Dead/stale owner (no-flock fallback only): reclaim the lock dir.
  rm -rf "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || { echo "cannot acquire lock" >&2; exit 3; }
fi
# Install the cleanup trap immediately after acquiring the lock and BEFORE writing
# the pidfile (item 3): if anything below fails, the trap still releases the lock.
STOP_REASON="ended"
cleanup() {
  rm -f "$PIDF" 2>/dev/null; rm -rf "$LOCK" 2>/dev/null
  # request-scoped one-shot cleanup: if this run seeded a single tagged request,
  # remove its line so a left-open TASKS.md can't re-arm the loop later (item 6).
  [ -n "${PHALANX_REQ_ID:-}" ] && [ -x "$UNSEED" ] && "$UNSEED" "$REPO" "$PHALANX_REQ_ID" >/dev/null 2>&1 || true
  # Drain pending-unseed (item 2): unseed every req id another caller (e.g.
  # bot-handoff while a supervisor was already up) parked here -- those ids would
  # otherwise never be removed and could re-arm the loop on the next message.
  if [ -f "$PENDING_UNSEED" ] && [ -x "$UNSEED" ]; then
    while IFS= read -r rid; do
      [ -n "$rid" ] && "$UNSEED" "$REPO" "$rid" >/dev/null 2>&1 || true
    done < "$PENDING_UNSEED"
    rm -f "$PENDING_UNSEED" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'STOP_REASON="signalled"; exit 0' INT TERM
echo "$$" > "$PIDF"

if [ ! -f "$TASKS" ]; then echo "No TASKS.md in $REPO. Create one with '- [ ]' items first." >&2; exit 1; fi

backlog_empty() { ! ts_has_open "$REPO"; }
off()           { [ -f "$REPO/.work-off" ] || [ -f "$CLAUDE_DIR/.work-off" ]; }
# Authoritative halt: the sentinel file wins (item 1). The PROGRESS.md scan is a
# DETECTOR only -- it scans the WHOLE file (not a tail window, which a verbose pass
# could push the BLOCKED line out of) and, on first sight, materializes the
# sentinel so control flow never again depends on tail position.
blocked() {
  [ -f "$BLOCKED_FILE" ] && return 0
  if ts_blocked "$REPO"; then
    ts_blocked_line "$REPO" > "$BLOCKED_FILE" 2>/dev/null || true
    return 0
  fi
  return 1
}
spent_tokens()  { local b; b=$(cat "$RUNDIR"/pass-*.log 2>/dev/null | wc -c); echo $(( b / 4 )); }

# Fail CLOSED: every non-progress stop path routes here so the watcher (which skips
# a repo iff .claude-runs/BLOCKED exists) never relaunches a doomed loop. Writes the
# sentinel + a human-visible PROGRESS line + notifies. A human clears it:
# rm .claude-runs/BLOCKED (and the PROGRESS BLOCKED line).
fail_closed() {
  local reason="$1"
  mkdir -p "$LOGDIR" 2>/dev/null || true
  printf 'BLOCKED: %s\n' "$reason" > "$BLOCKED_FILE" 2>/dev/null || true
  printf '\nBLOCKED: %s\n' "$reason" >> "$PROGRESS" 2>/dev/null || true
  note blocked "$reason"
}
# Fingerprint of REAL progress: completion state of TASKS.md + content of PROGRESS.md.
# A pass that checks a box OR writes a new checkpoint changes this; a pass that spins
# (identical output, nothing advanced) does not. Used to catch exit-0 no-progress churn.
progress_fp() {
  # grep -c exits 1 on zero matches; under the loop's set -e + pipefail that would
  # abort the run, so swallow it. Same for a missing PROGRESS.md.
  local d; d="$(grep -cE '^[[:space:]]*-[[:space:]]*\[[xX]\]' "$TASKS" 2>/dev/null || echo 0)"
  { printf '%s' "$d"; cat "$PROGRESS" 2>/dev/null || true; } | cksum | awk '{print $1}'
}

# --- preflight: never spawn a doomed loop ------------------------------------
# Missing token => every `claude -p` 401s. Fail closed at ZERO passes instead of
# burning 3 (x every repo, every watcher tick) before the failure counter gives up.
if [ -z "$OAUTH_TOKEN" ]; then
  echo "No headless OAuth token ($HEADLESS_ENV). Failing closed." >&2
  fail_closed "no headless auth token; provision $CLAUDE_DIR/.headless-env (claude setup-token), then rm $BLOCKED_FILE"
  exit 1
fi
# Cheap live auth check: one tiny `claude -p`. Because `claude -p` exits 0 on a 401,
# detect by the expected marker in OUTPUT, not the exit code. A bad/expired token
# fails here for ~1 trivial call instead of 3 full passes. Disable: PHALANX_AUTH_PREFLIGHT=0.
if [ "${PHALANX_AUTH_PREFLIGHT:-1}" = "1" ] && command -v claude >/dev/null 2>&1; then
  TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 60s"
  pf_out="$(CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN" $TO claude -p 'reply with exactly: PHALANX_AUTH_OK' 2>&1)"
  if ! printf '%s' "$pf_out" | grep -q 'PHALANX_AUTH_OK'; then
    echo "Auth preflight failed (token invalid/expired or claude unreachable). Failing closed." >&2
    fail_closed "headless auth preflight failed (401/expired?); refresh $CLAUDE_DIR/.headless-env, then rm $BLOCKED_FILE"
    exit 1
  fi
fi

note start "supervisor up: $REPO (max=$MAX_PASSES, budget=$TOKEN_BUDGET)"
pass=0; fails=0; noprog=0; fp_prev="$(progress_fp)"
while true; do
  if off;          then echo "Kill switch (.work-off). Stopping."; STOP_REASON="work-off"; break; fi
  if blocked;      then echo "BLOCKED (sentinel). Halting for human."; STOP_REASON="blocked"; note blocked "$(cat "$BLOCKED_FILE" 2>/dev/null | tr '\n' ' ')"; break; fi
  if backlog_empty; then echo "Backlog empty. Done."; STOP_REASON="done"; break; fi
  pass=$((pass + 1))
  if (( pass > MAX_PASSES )); then echo "Hit MaxPasses=$MAX_PASSES. Stopping."; STOP_REASON="maxpasses"; fail_closed "hit MaxPasses=$MAX_PASSES without draining backlog; review then rm $BLOCKED_FILE"; break; fi
  if (( TOKEN_BUDGET > 0 )) && (( $(spent_tokens) > TOKEN_BUDGET )); then
    echo "Token budget $TOKEN_BUDGET exceeded (~$(spent_tokens)). Stopping."; STOP_REASON="budget"; fail_closed "token budget $TOKEN_BUDGET exceeded (~$(spent_tokens) tokens); review then rm $BLOCKED_FILE"; break; fi

  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 0)"; log="$RUNDIR/pass-$pass-$stamp.log"
  echo "=== Pass $pass - $(date +%T 2>/dev/null) - fresh /work ==="
  note progress "pass $pass starting"
  # Worktree isolation: run the pass in its OWN checkout so concurrent passes / other
  # instances never collide on the primary tree's branch or index. Loop STATE
  # (TASKS.md/PROGRESS.md/.claude-runs) stays at the primary (shared) root -- the gates
  # and orchestrator resolve it via --git-common-dir, so the worktree pass drains the
  # SAME backlog. Non-interactive `--worktree` is NOT auto-removed, so we remove it after
  # the pass. Opt out (or an older `claude` without --worktree) with PHALANX_NO_WORKTREE=1.
  WT_NAME=""; WT_FLAGS=""
  if [ -z "${PHALANX_NO_WORKTREE:-}" ]; then WT_NAME="wt-$pass-$stamp"; WT_FLAGS="--worktree $WT_NAME"; fi
  # Wall-clock cap per pass (item 4): a hung `claude -p` must not block the
  # detached loop forever. `timeout` returns 124 on expiry -- treated as a
  # RECOVERABLE failure below (count it, notify, relaunch fresh), not a hard stop.
  set +e
  if command -v timeout >/dev/null 2>&1; then
    PHALANX_ONESHOT=1 PHALANX_SUPERVISOR=1 PHALANX_REPO="$REPO" \
      CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN" GH_TOKEN="$GH_TOKEN_VAL" \
      env ${ACCESS_KV[@]+"${ACCESS_KV[@]}"} \
      timeout "${PHALANX_PASS_TIMEOUT:-1800}s" claude -p "/work" $WT_FLAGS 2>&1 | tee "$log"; code="${PIPESTATUS[0]}"
  else
    PHALANX_ONESHOT=1 PHALANX_SUPERVISOR=1 PHALANX_REPO="$REPO" \
      CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN" GH_TOKEN="$GH_TOKEN_VAL" \
      env ${ACCESS_KV[@]+"${ACCESS_KV[@]}"} \
      claude -p "/work" $WT_FLAGS 2>&1 | tee "$log"; code="${PIPESTATUS[0]}"
  fi
  set -e

  # Remove the pass's worktree (non-interactive --worktree is not auto-cleaned). The work
  # is already committed on its branch + landed to main by the orchestrator; --force drops
  # the throwaway checkout. State files live at the primary root, so nothing is lost.
  if [ -n "$WT_NAME" ]; then
    git -C "$REPO" worktree remove --force "$REPO/.claude/worktrees/$WT_NAME" >/dev/null 2>&1 || true
    git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  fi

  if [ "$code" -eq 124 ]; then
    fails=$((fails + 1))
    echo "pass $pass timed out after ${PHALANX_PASS_TIMEOUT:-1800}s (consecutive fails: $fails). Relaunching fresh."
    note progress "pass $pass timed out (${PHALANX_PASS_TIMEOUT:-1800}s); relaunching"
    if (( fails >= 3 )); then echo "3 consecutive failures. Stopping. See $log." >&2; STOP_REASON="repeated-failure"; fail_closed "supervisor stopped: 3 consecutive pass failures (last=timeout); fix then rm $BLOCKED_FILE"; break; fi
  elif [ "$code" -ne 0 ]; then
    fails=$((fails + 1))
    echo "claude exited $code on pass $pass (consecutive fails: $fails). Will relaunch fresh."
    # A killed/crashed pass is RECOVERABLE: the next fresh /work resumes from
    # PROGRESS.md. Only give up after several consecutive failures.
    if (( fails >= 3 )); then echo "3 consecutive failures. Stopping. See $log." >&2; STOP_REASON="repeated-failure"; fail_closed "supervisor stopped: 3 consecutive pass failures (last exit=$code); fix then rm $BLOCKED_FILE"; break; fi
  else
    fails=0
    # Exit 0 != progress. `claude -p` returns 0 even on a 401 auth failure, so the
    # failure counter can't see a doomed-but-quiet pass. Compare the progress
    # fingerprint: N consecutive exit-0 passes that advance NOTHING => fail closed.
    fp_now="$(progress_fp)"
    if [ "$fp_now" = "$fp_prev" ]; then
      noprog=$((noprog + 1))
      echo "pass $pass made no progress (no TASKS/PROGRESS change; $noprog/$NOPROG_MAX)."
      note progress "pass $pass: no progress ($noprog/$NOPROG_MAX)"
      if (( noprog >= NOPROG_MAX )); then STOP_REASON="no-progress"; fail_closed "no progress in $NOPROG_MAX consecutive passes (stuck task, or auth/verify failing silently); investigate then rm $BLOCKED_FILE"; break; fi
    else
      noprog=0
    fi
    fp_prev="$fp_now"
  fi
  sleep "$SLEEP_SECONDS"
done

echo "Loop ended ($STOP_REASON). Passes run: $pass. Logs in $LOGDIR."
note "done" "supervisor stopped ($STOP_REASON) after $pass pass(es): $REPO"
