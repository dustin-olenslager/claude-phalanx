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

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

if [ -n "${PHALANX_NOTIFY_CMD:-}" ]; then
  "$PHALANX_NOTIFY_CMD" "$event" "$msg" "$repo" "$thread" >/dev/null 2>&1 || true
elif [ -n "${PHALANX_NOTIFY_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  json=$(printf '{"event":"%s","message":"%s","repo":"%s","host":"%s","thread":"%s"}' \
    "$(esc "$event")" "$(esc "$msg")" "$(esc "$repo")" "$(esc "$host")" "$(esc "$thread")")
  curl -s -m 10 -X POST -H 'Content-Type: application/json' -d "$json" "$PHALANX_NOTIFY_URL" >/dev/null 2>&1 || true
else
  printf '[phalanx:%s/%s] %s\n' "$event" "$thread" "$msg"
fi
exit 0
