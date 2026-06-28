#!/usr/bin/env bash
# Phalanx supervisor process-manager. Runs run-work.sh DETACHED (setsid+nohup) so
# it survives the launching shell/session, then drives the repo's backlog across
# fresh `claude -p` passes until empty / BLOCKED / capped. One supervisor per repo
# (run-work.sh holds the pidfile+lock; this just starts/stops/queries it).
#   supervisord.sh start  [-r repo] [-m maxpasses] [-b tokenbudget]
#   supervisord.sh stop   [-r repo]
#   supervisord.sh status [-r repo]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNWORK="$HERE/run-work.sh"

cmd="${1:-}"; shift 2>/dev/null || true
REPO="$(pwd)"; MAX=""; BUDGET=""
while getopts "r:m:b:" o; do
  case "$o" in r) REPO="$OPTARG" ;; m) MAX="$OPTARG" ;; b) BUDGET="$OPTARG" ;; *) ;; esac
done
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "bad repo path" >&2; exit 1; }
LOGDIR="$REPO/.claude-runs"; PIDF="$LOGDIR/supervisor.pid"; SUPLOG="$LOGDIR/supervisor.log"

pid_of() { cat "$PIDF" 2>/dev/null; }
# Verify the pid is ACTUALLY a run-work.sh process (item 3): a bare `kill -0`
# trusts PID reuse, so an unrelated process inheriting the same pid after a
# crash/reboot would make the loop look permanently "running" -- blocking
# auto-start forever. Where /proc is available, require run-work.sh in cmdline.
alive() {
  local p; p="$(pid_of)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  if [ -r "/proc/$p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'run-work.sh' || return 1
  fi
  return 0
}

case "$cmd" in
  start)
    mkdir -p "$LOGDIR"
    if alive; then echo "supervisor already running (pid $(pid_of)) for $REPO"; exit 0; fi
    args=(-r "$REPO"); [ -n "$MAX" ] && args+=(-m "$MAX"); [ -n "$BUDGET" ] && args+=(-b "$BUDGET")
    if command -v setsid >/dev/null 2>&1; then
      setsid nohup bash "$RUNWORK" "${args[@]}" >>"$SUPLOG" 2>&1 </dev/null &
    else
      nohup bash "$RUNWORK" "${args[@]}" >>"$SUPLOG" 2>&1 </dev/null &
    fi
    sleep 1
    if alive; then echo "supervisor started for $REPO (pid $(pid_of); log: $SUPLOG)";
    else echo "supervisor launch attempted for $REPO (log: $SUPLOG)"; fi
    ;;
  stop)
    p="$(pid_of)"
    # Gate on alive() (not a bare kill -0) so a reused pid isn't signalled (item 3).
    if alive; then
      # setsid makes run-work a process-group leader (pgid==pid): signal the group
      # so the in-flight `claude -p` child dies too. Fall back to the bare pid.
      kill -TERM "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || true
      echo "stopped supervisor (pid $p) for $REPO"
    else
      echo "no running supervisor for $REPO"
    fi
    rm -f "$PIDF" 2>/dev/null; rm -rf "$LOGDIR/supervisor.lock" 2>/dev/null
    ;;
  status)
    if alive; then echo "RUNNING pid=$(pid_of) repo=$REPO"; else echo "STOPPED repo=$REPO"; fi
    [ -f "$SUPLOG" ] && { echo "--- last supervisor.log ---"; tail -n 6 "$SUPLOG"; } || true
    ;;
  *)
    echo "usage: supervisord.sh start|stop|status [-r repo] [-m maxpasses] [-b tokenbudget]" >&2; exit 2 ;;
esac
