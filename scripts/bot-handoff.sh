#!/usr/bin/env bash
# Phalanx Telegram-bot hand-off. For a coding request that will plausibly exceed
# one context window, the cc-bot should NOT try to finish it inline in a single
# `claude -p`. Instead it calls this: seed the request as a request-scoped loop
# task, launch the DETACHED supervisor to drive it across fresh processes, and
# print an immediate ack the bot relays to Telegram. The supervisor then posts
# progress / done / BLOCKED back via notify.sh (PHALANX_NOTIFY_CMD/_URL).
#   bot-handoff.sh <repo> "<request text>" [reqid]
# Prints the ack line on stdout. Honors PHALANX_REQ_ID for request-scoped cleanup.
#
# SECURITY: this is a network-reachable entry point (a Telegram message drives it).
#  (a) The Telegram sender id MUST be on PHALANX_ALLOWED_SENDER (space/comma list)
#      or the request is rejected -- so a stranger messaging the bot cannot seed
#      arbitrary work. The bot must pass the sender id via PHALANX_SENDER_ID.
#  (b) <repo> MUST be a line in $CLAUDE_DIR/.phalanx-repos -- never cd to an
#      arbitrary caller-supplied path.
#  (c) the request text is length-capped (it is already newline-flattened by
#      seed-task.sh) so a huge payload can't bloat TASKS.md.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SEED="$HERE/seed-task.sh";        [ -x "$SEED" ] || SEED="$CLAUDE_DIR/seed-task.sh"
SUPERVISORD="$HERE/supervisord.sh"; [ -x "$SUPERVISORD" ] || SUPERVISORD="$CLAUDE_DIR/supervisord.sh"
REGISTRY="$CLAUDE_DIR/.phalanx-repos"
MAX_TEXT_LEN="${PHALANX_MAX_REQ_LEN:-2000}"

repo="${1:?repo required}"; text="${2:?request text required}"; reqid="${3:-}"

# (a) sender allowlist -- reject before doing anything.
sender="${PHALANX_SENDER_ID:-}"
allow="${PHALANX_ALLOWED_SENDER:-}"
if [ -z "$allow" ]; then
  echo "refused: PHALANX_ALLOWED_SENDER is unset; no sender is authorized" >&2; exit 4
fi
ok=0
for a in ${allow//,/ }; do [ "$a" = "$sender" ] && ok=1 && break; done
if [ "$ok" != 1 ]; then
  echo "refused: sender '$sender' not in PHALANX_ALLOWED_SENDER" >&2; exit 4
fi

# (b) repo must be registered -- resolve both sides and require an exact match.
repo="$(cd "$repo" 2>/dev/null && pwd)" || { echo "bad repo path" >&2; exit 1; }
[ -f "$REGISTRY" ] || { echo "refused: no repo registry at $REGISTRY" >&2; exit 5; }
reg_ok=0
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  rp="$(cd "$line" 2>/dev/null && pwd)" || continue
  [ "$rp" = "$repo" ] && reg_ok=1 && break
done < "$REGISTRY"
if [ "$reg_ok" != 1 ]; then
  echo "refused: repo '$repo' is not registered in $REGISTRY" >&2; exit 5
fi

# (c) length cap (text already arrives single-line from the bot; seed-task.sh
# flattens any stray newlines too).
if [ "${#text}" -gt "$MAX_TEXT_LEN" ]; then
  text="${text:0:$MAX_TEXT_LEN}"
fi

id="$(bash "$SEED" "$repo" "$text" $reqid | tail -n1)"
# Always record this req id in pending-unseed BEFORE launching (item 2). If a
# supervisor is already running, `supervisord.sh start` is a no-op and never sees
# PHALANX_REQ_ID -- so that supervisor's own EXIT trap would never unseed THIS
# request and the stale line would re-arm the loop later. run-work.sh's cleanup
# drains pending-unseed for exactly this case. Harmless when we do start fresh
# (the same id is just dropped twice, and unseed is idempotent).
LOGDIR="$repo/.claude-runs"; mkdir -p "$LOGDIR" 2>/dev/null || true
printf '%s\n' "$id" >> "$LOGDIR/pending-unseed" 2>/dev/null || true
# Pass the req id to the supervisor so (when it DOES start fresh) its EXIT trap
# unseeds exactly this request (item 6: no left-open TASKS.md to re-arm the loop).
PHALANX_REQ_ID="$id" bash "$SUPERVISORD" start -r "$repo" >/dev/null 2>&1 || true
echo "autonomous run started (req:$id) on $repo; I'll report when it finishes or hits a blocker."
