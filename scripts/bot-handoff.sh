#!/usr/bin/env bash
# Phalanx Telegram-bot hand-off. For a coding request that will plausibly exceed
# one context window, the cc-bot should NOT try to finish it inline in a single
# `claude -p`. Instead it calls this: seed the request as a request-scoped loop
# task, launch the DETACHED supervisor to drive it across fresh processes, and
# print an immediate ack the bot relays to Telegram. The supervisor then posts
# progress / done / BLOCKED back via notify.sh (PHALANX_NOTIFY_CMD/_URL).
#   bot-handoff.sh <repo> "<request text>" [reqid]
# Prints the ack line on stdout. Honors PHALANX_REQ_ID for request-scoped cleanup.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SEED="$HERE/seed-task.sh";        [ -x "$SEED" ] || SEED="$CLAUDE_DIR/seed-task.sh"
SUPERVISORD="$HERE/supervisord.sh"; [ -x "$SUPERVISORD" ] || SUPERVISORD="$CLAUDE_DIR/supervisord.sh"

repo="${1:?repo required}"; text="${2:?request text required}"; reqid="${3:-}"
repo="$(cd "$repo" 2>/dev/null && pwd)" || { echo "bad repo path" >&2; exit 1; }

id="$(bash "$SEED" "$repo" "$text" $reqid | tail -n1)"
# Pass the req id to the supervisor so its EXIT trap unseeds exactly this request
# (item 6: no left-open TASKS.md to re-arm the loop on the next bot message).
PHALANX_REQ_ID="$id" bash "$SUPERVISORD" start -r "$repo" >/dev/null 2>&1 || true
echo "autonomous run started (req:$id) on $repo; I'll report when it finishes or hits a blocker."
