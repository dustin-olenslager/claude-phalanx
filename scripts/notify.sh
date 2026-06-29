#!/usr/bin/env bash
# Phalanx notify dispatcher. Routes a supervisor lifecycle event (start / progress
# / done / blocked) to whatever sink the environment configures. No-op fallback
# prints to stdout, so callers never need to branch on whether a sink exists.
#   notify.sh <event> <message...>
# Sinks (first that is set wins):
#   PHALANX_NOTIFY_CMD  - exec: "<cmd>" <event> <message> <repo> <thread>   (e.g. cc-bot poster)
#   PHALANX_NOTIFY_URL  - HTTP POST {event,message,repo,host,thread} as JSON via curl
# Never fails the caller: every path swallows its own errors.
#
# <thread> is the PER-JOB routing key so an adapter can keep each job in its own
# Telegram topic / chat instead of one blurred feed. Defaults to the repo basename
# (one repo == one thread); override per job with PHALANX_NOTIFY_THREAD.
set -uo pipefail
event="${1:-info}"; shift || true
msg="${*:-}"
repo="${PHALANX_REPO:-$(pwd)}"
host="$(hostname 2>/dev/null || echo unknown)"
thread="${PHALANX_NOTIFY_THREAD:-$(basename "$repo" 2>/dev/null || echo repo)}"

# Robust JSON object: escapes newlines/tabs/control chars, not just quotes. Prefer
# python3 (present on the targets), then jq, then a more complete sed fallback.
build_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
k=["event","message","repo","host","thread"]
print(json.dumps(dict(zip(k,sys.argv[1:]))))' "$event" "$msg" "$repo" "$host" "$thread"
  elif command -v jq >/dev/null 2>&1; then
    jq -n --arg event "$event" --arg message "$msg" --arg repo "$repo" \
      --arg host "$host" --arg thread "$thread" \
      '{event:$event,message:$message,repo:$repo,host:$host,thread:$thread}'
  else
    esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'; }
    printf '{"event":"%s","message":"%s","repo":"%s","host":"%s","thread":"%s"}' \
      "$(esc "$event")" "$(esc "$msg")" "$(esc "$repo")" "$(esc "$host")" "$(esc "$thread")"
  fi
}

# ALWAYS append the event to the local log, regardless of remote sink (item 2).
LOGDIR="${PHALANX_LOGDIR:-$repo/.claude-runs}"
mkdir -p "$LOGDIR" 2>/dev/null || true
ev_ts="$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || echo 0)"
flat_msg="$(printf '%s' "$msg" | tr '\n\t' '  ')"
printf '%s\t%s\t%s\t%s\n' "$ev_ts" "$event" "$thread" "$flat_msg" >> "$LOGDIR/events.log" 2>/dev/null || true

# ponytail: a repo under /tmp is a throwaway test fixture (real jobs + worktrees never live there).
# Log locally above, but NEVER hit a real sink — stops supervisor self-tests flooding Telegram.
# Resolve symlinks first (macOS /tmp -> /private/tmp; a symlinked /tmp on Linux) so the guard
# matches the REAL path, not a literal a fixture could pass to bypass it. Strip any trailing
# slash from TMPDIR so its arm isn't silently dead (TMPDIR=/tmp/ -> pattern /tmp//*).
guard_repo="$(cd "$repo" 2>/dev/null && pwd -P || printf '%s' "$repo")"
guard_tmpdir="${TMPDIR:-/nonexistent}"; guard_tmpdir="${guard_tmpdir%/}"
case "$guard_repo" in
  /tmp|/tmp/*|/private/tmp|/private/tmp/*|"$guard_tmpdir"|"$guard_tmpdir"/*) exit 0 ;;
esac

if [ -n "${PHALANX_NOTIFY_CMD:-}" ]; then
  "$PHALANX_NOTIFY_CMD" "$event" "$msg" "$repo" "$thread" >/dev/null 2>&1 \
    || printf '%s\tWARN\t%s\tnotify-cmd failed\n' "$ev_ts" "$thread" >> "$LOGDIR/events.log" 2>/dev/null || true
elif [ -n "${PHALANX_NOTIFY_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  json="$(build_json)"
  # Authenticate to Herald's secured /event endpoint when a shared secret is set.
  # No-op header when unset (open endpoints keep working).
  auth=(); [ -n "${PHALANX_NOTIFY_SECRET:-}" ] && auth=(-H "x-herald-secret: $PHALANX_NOTIFY_SECRET")
  curl -s -m 10 -X POST -H 'Content-Type: application/json' "${auth[@]}" -d "$json" "$PHALANX_NOTIFY_URL" >/dev/null 2>&1 \
    || printf '%s\tWARN\t%s\tcurl POST failed\n' "$ev_ts" "$thread" >> "$LOGDIR/events.log" 2>/dev/null || true
else
  printf '[phalanx:%s/%s] %s\n' "$event" "$thread" "$msg"
fi
exit 0
