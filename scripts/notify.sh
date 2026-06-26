#!/usr/bin/env bash
# Phalanx notify dispatcher. Routes a supervisor lifecycle event (start / progress
# / done / blocked) to whatever sink the environment configures. No-op fallback
# prints to stdout, so callers never need to branch on whether a sink exists.
#   notify.sh <event> <message...>
# Sinks (first that is set wins):
#   PHALANX_NOTIFY_CMD  - exec: "<cmd>" <event> <message> <repo>   (e.g. cc-bot poster)
#   PHALANX_NOTIFY_URL  - HTTP POST {event,message,repo,host} as JSON via curl
# Never fails the caller: every path swallows its own errors.
set -uo pipefail
event="${1:-info}"; shift || true
msg="${*:-}"
repo="${PHALANX_REPO:-$(pwd)}"
host="$(hostname 2>/dev/null || echo unknown)"

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

if [ -n "${PHALANX_NOTIFY_CMD:-}" ]; then
  "$PHALANX_NOTIFY_CMD" "$event" "$msg" "$repo" >/dev/null 2>&1 || true
elif [ -n "${PHALANX_NOTIFY_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  json=$(printf '{"event":"%s","message":"%s","repo":"%s","host":"%s"}' \
    "$(esc "$event")" "$(esc "$msg")" "$(esc "$repo")" "$(esc "$host")")
  curl -s -m 10 -X POST -H 'Content-Type: application/json' -d "$json" "$PHALANX_NOTIFY_URL" >/dev/null 2>&1 || true
else
  printf '[phalanx:%s] %s\n' "$event" "$msg"
fi
exit 0
