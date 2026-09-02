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

# On a shared mount a root-run pass writes git objects a non-root repo owner otherwise
# cannot rewrite/gc; a group-shared repo keeps new objects group-writable so any uid in
# the repo group coexists. Idempotent -- re-applying is a no-op.
ensure_shared_git() {
  git -C "$1" config core.sharedRepository group 2>/dev/null || true
  chmod -R g+w "$1/.git" 2>/dev/null || true
  find "$1/.git" -type d -exec chmod g+s {} + 2>/dev/null || true
}
ensure_shared_git "$REPO"

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
# Gate on -f (exists), not -x: a checkout/clone over CIFS/SMB or core.fileMode=false
# silently drops the exec bit, which would skip the in-repo copy (and its /tmp guard).
# We invoke via `bash "$NOTIFY"` below, so the exec bit is irrelevant.
NOTIFY="$HERE/notify.sh"; [ -f "$NOTIFY" ] || NOTIFY="$CLAUDE_DIR/notify.sh"
UNSEED="$HERE/unseed-task.sh"; [ -x "$UNSEED" ] || UNSEED="$CLAUDE_DIR/unseed-task.sh"
WIP_PRESERVE="$HERE/wip-preserve.sh"; [ -f "$WIP_PRESERVE" ] || WIP_PRESERVE="$CLAUDE_DIR/wip-preserve.sh"
GC="$HERE/phalanx-gc.sh"; [ -x "$GC" ] || GC="$CLAUDE_DIR/phalanx-gc.sh"

# The repo's main branch (origin/HEAD > main > master). Passes branch from it and the
# primary tree is returned to it after every pass; a primary tree left parked on a
# stale task/<slug> was the #1 source of "why is my checkout on the wrong branch".
MAIN="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"
[ -z "$MAIN" ] && { git -C "$REPO" show-ref -q refs/heads/main && MAIN=main || { git -C "$REPO" show-ref -q refs/heads/master && MAIN=master; }; }

# Pass permissions: `claude -p` is non-interactive, so any tool call outside the
# allow-list is REFUSED (not prompted) and the pass silently makes no progress. Default
# to acceptEdits (file writes inside the tree auto-approved; Bash still needs the
# repo's .claude/settings.json allow-list). Override per repo with .phalanx-pass-args
# (one CLI arg per line) or .phalanx-yolo (--dangerously-skip-permissions).
PASS_ARGS=()
if [ -f "$REPO/.phalanx-pass-args" ]; then mapfile -t PASS_ARGS < <(grep -vE '^[[:space:]]*(#|$)' "$REPO/.phalanx-pass-args"); fi
if [ -f "$REPO/.phalanx-yolo" ]; then PASS_ARGS=(--dangerously-skip-permissions)
elif [ ${#PASS_ARGS[@]} -eq 0 ]; then PASS_ARGS=(--permission-mode acceptEdits); fi

# Worktree lifecycle is OWNED HERE, not by `claude --worktree`: the CLI variant locks
# the tree (a single `remove --force` then fails -> leaked .claude/worktrees/wt-*),
# parks it on a throwaway `worktree-wt-*` branch, and gives it no node_modules, so
# every verify in a JS repo was refused. We add a DETACHED worktree at $MAIN, install
# deps from the lockfile (or run the repo's .phalanx-worktree-setup), run the pass
# with cwd inside it, and tear it down from the EXIT trap so a kill/crash cannot leak.
CUR_WT=""
wt_setup() { # $1=worktree $2=log
  local wt="$1" lg="$2" hook="$REPO/.phalanx-worktree-setup" cmd=""
  if [ -x "$hook" ]; then
    (cd "$wt" && PHALANX_PRIMARY="$REPO" timeout 900s "$hook") >>"$lg" 2>&1 && return 0
    echo "WARN: .phalanx-worktree-setup failed (see $lg); pass runs without deps"; return 1
  fi
  [ -f "$wt/package.json" ] || return 0
  if [ -f "$wt/pnpm-lock.yaml" ]; then cmd="pnpm install --frozen-lockfile --prefer-offline"
  elif [ -f "$wt/yarn.lock" ]; then cmd="yarn install --frozen-lockfile"
  elif [ -f "$wt/package-lock.json" ]; then cmd="npm ci --prefer-offline --no-audit --no-fund"
  elif [ -f "$wt/bun.lock" ] || [ -f "$wt/bun.lockb" ]; then cmd="bun install --frozen-lockfile"; fi
  [ -n "$cmd" ] || return 0
  command -v "${cmd%% *}" >/dev/null 2>&1 || { echo "WARN: ${cmd%% *} not on PATH; worktree has no deps (add .phalanx-worktree-setup)"; return 1; }
  (cd "$wt" && timeout 900s $cmd) >>"$lg" 2>&1 || { echo "WARN: '$cmd' failed in worktree (see $lg); pass runs without deps"; return 1; }
}
wt_teardown() { # salvage uncommitted work, then remove + prune; never leaks on any exit path
  [ -n "$CUR_WT" ] || return 0
  local wt="$CUR_WT"; CUR_WT=""
  [ -f "$WIP_PRESERVE" ] && bash "$WIP_PRESERVE" "$REPO" "$wt" "${1:-teardown}" >/dev/null 2>&1 || true
  git -C "$REPO" worktree unlock "$wt" >/dev/null 2>&1 || true
  git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 \
    || git -C "$REPO" worktree remove --force --force "$wt" >/dev/null 2>&1 \
    || rm -rf "$wt" 2>/dev/null || true
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
}
primary_home() { # return a CLEAN primary tree to $MAIN; a dirty tree is never touched
  [ -n "$MAIN" ] || return 0
  local cur; cur="$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo "")"
  [ "$cur" = "$MAIN" ] && return 0
  [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || { echo "NOTE: primary tree left on '$cur' (dirty) -- loop expects $MAIN"; return 0; }
  git -C "$REPO" checkout -q "$MAIN" >/dev/null 2>&1 && echo "primary tree returned to $MAIN (was $cur)"
}
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

# Quiet early-exit BEFORE lock + auth preflight: a blocked/off repo must not burn
# a full preflight call on every watcher/Herald relaunch attempt. Also materializes
# the BLOCKED sentinel from PROGRESS.md so future checks need only stat the file.
if [ -f "$REPO/.work-off" ] || [ -f "$CLAUDE_DIR/.work-off" ] || [ -f "$BLOCKED_FILE" ]; then
  exit 0
fi
if ts_blocked "$REPO"; then
  mkdir -p "$LOGDIR" 2>/dev/null || true
  ts_blocked_line "$REPO" > "$BLOCKED_FILE" 2>/dev/null || true
  exit 0
fi

# Per-run log subdir so the -b token budget counts ONLY this run's passes, not
# every historical pass-*.log ever written for this repo (item 1). Old logs stay.
RUN_STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 0)-$$"
RUNDIR="$LOGDIR/run-$RUN_STAMP"
mkdir -p "$RUNDIR"

note() { [ -f "$NOTIFY" ] && PHALANX_REPO="$REPO" bash "$NOTIFY" "$1" "$2" >/dev/null 2>&1 || true; }

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
  wt_teardown "exit"; primary_home
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
  # SAME backlog. The worktree is created HERE (detached at $MAIN, deps installed) and
  # torn down by wt_teardown on every exit path. Opt out with PHALANX_NO_WORKTREE=1.
  WT_NAME=""; PASS_CWD="$REPO"
  git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  if [ -z "${PHALANX_NO_WORKTREE:-}" ]; then
    WT_NAME="wt-$pass-$stamp"; wt_dir="$REPO/.claude/worktrees/$WT_NAME"; mkdir -p "$REPO/.claude/worktrees"
    # Base the pass on ORIGIN's main, not the local one: a local main that lags origin
    # (the other machine pushed) would make the pass rebuild old code.
    BASE="${MAIN:-HEAD}"
    if [ -n "$MAIN" ] && (command -v timeout >/dev/null 2>&1 && timeout 20s git -C "$REPO" fetch -q origin "$MAIN" 2>/dev/null || git -C "$REPO" fetch -q origin "$MAIN" 2>/dev/null); then
      git -C "$REPO" show-ref -q "refs/remotes/origin/$MAIN" && BASE="origin/$MAIN"
    fi
    if git -C "$REPO" worktree add --detach "$wt_dir" "$BASE" >/dev/null 2>&1; then
      CUR_WT="$wt_dir"; PASS_CWD="$wt_dir"
      wt_setup "$wt_dir" "$RUNDIR/setup-$pass-$stamp.log" || true
    else
      echo "WARN: git worktree add failed; pass $pass runs in the primary tree"; WT_NAME=""
    fi
  fi
  # Wall-clock cap per pass (item 4): a hung `claude -p` must not block the
  # detached loop forever. `timeout` returns 124 on expiry -- treated as a
  # RECOVERABLE failure below (count it, notify, relaunch fresh), not a hard stop.
  # resolve driver model: .phalanx-model file > PHALANX_MODEL env > (.phalanx-automodel→opus) > unset
  # Map the tier LABEL to a stable `--model` ALIAS (opus|sonnet|haiku), NOT a pinned dated id:
  # the alias auto-tracks the latest model of that tier, so the loop never rots a generation
  # behind (the old map pinned claude-opus-4-8 / claude-sonnet-4-6 and silently aged). `fable`
  # has no CLI alias, so it keeps its explicit current-gen id.
  PHALANX_MODEL_ID=""
  if [ -f "$REPO/.phalanx-model" ]; then
    _label=$(cat "$REPO/.phalanx-model" | tr -d '[:space:]')
    case "$_label" in
      opus)   PHALANX_MODEL_ID="opus" ;;
      sonnet) PHALANX_MODEL_ID="sonnet" ;;
      haiku)  PHALANX_MODEL_ID="haiku" ;;
      fable)  PHALANX_MODEL_ID="claude-fable-5" ;;
    esac
  elif [ -n "${PHALANX_MODEL:-}" ]; then
    case "$PHALANX_MODEL" in
      opus)   PHALANX_MODEL_ID="opus" ;;
      sonnet) PHALANX_MODEL_ID="sonnet" ;;
      haiku)  PHALANX_MODEL_ID="haiku" ;;
      fable)  PHALANX_MODEL_ID="claude-fable-5" ;;
    esac
  elif [ -f "$REPO/.phalanx-automodel" ]; then
    PHALANX_MODEL_ID="opus"
  fi
  MODEL_FLAG=""
  [ -n "$PHALANX_MODEL_ID" ] && MODEL_FLAG="--model $PHALANX_MODEL_ID"

  set +e
  PASS_TO=""; command -v timeout >/dev/null 2>&1 && PASS_TO="timeout ${PHALANX_PASS_TIMEOUT:-1800}s"
  (
    cd "$PASS_CWD" || exit 97
    PHALANX_ONESHOT=1 PHALANX_SUPERVISOR=1 PHALANX_REPO="$REPO" \
      CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN" GH_TOKEN="$GH_TOKEN_VAL" \
      env ${ACCESS_KV[@]+"${ACCESS_KV[@]}"} \
      $PASS_TO claude $MODEL_FLAG "${PASS_ARGS[@]}" -p "/work" 2>&1 | tee "$log"; exit "${PIPESTATUS[0]}"
  ); code=$?
  set -e

  # Remove the pass's worktree (non-interactive --worktree is not auto-cleaned). A HAPPY
  # pass committed + landed its work, but a pass that hit the context ceiling (or died)
  # can leave real UNCOMMITTED files -- the verify gate forbids committing them on
  # task/<slug>, and --force would destroy them (2026-07-03 fonto/JEX-P2 loss). Salvage
  # first: wip-preserve stashes dirty state into the shared repo and records a WIP-STASH
  # line in PROGRESS.md so the next pass restores it before resuming.
  wt_teardown "pass $pass $stamp"
  primary_home

  # Belt-and-suspenders: if this pass ran as root on a shared mount, hand any
  # freshly-created git objects back to the repo owner so the non-root owner can
  # gc/rewrite them. Owner auto-detected; no-op (and harmless) when not root.
  owner="$(stat -c %U "$REPO/.git" 2>/dev/null || true)"
  [ -n "$owner" ] && chown -R "$owner" "$REPO/.git" 2>/dev/null || true

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

# Hygiene on the way out (safe tier only: prune, clean+merged worktrees, merged
# branches, throwaway worktree-* branches, run logs > 14d). PHALANX_NO_GC=1 skips.
if [ -z "${PHALANX_NO_GC:-}" ] && [ -x "$GC" ]; then
  PHALANX_GC_QUIET=1 "$GC" --apply "$REPO" 2>&1 | tail -25 | tee -a "$LOGDIR/gc.log"
fi
echo "Loop ended ($STOP_REASON). Passes run: $pass. Logs in $LOGDIR."
note "done" "supervisor stopped ($STOP_REASON) after $pass pass(es): $REPO"
