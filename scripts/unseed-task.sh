#!/usr/bin/env bash
# Remove a request's seeded line(s) from a repo's TASKS.md. If no task-shaped
# lines ('- [ ]' / '- [x]') remain afterwards, delete TASKS.md entirely so a
# stale file can't re-arm the loop on the next unrelated message (CLAUDE.md item 6).
# Idempotent: safe to call even if the file or the id is already gone.
#   unseed-task.sh <repo> <reqid>
set -euo pipefail
repo="${1:?repo required}"; id="${2:?reqid required}"
tasks="$repo/TASKS.md"
[ -f "$tasks" ] || exit 0
tmp="$(mktemp 2>/dev/null || echo "$tasks.unseed.tmp")"
grep -vF "(req:$id)" "$tasks" > "$tmp" 2>/dev/null || true
mv "$tmp" "$tasks"
if ! grep -Eq '^[[:space:]]*-[[:space:]]*\[[ xX]\]' "$tasks" 2>/dev/null; then
  rm -f "$tasks"
fi
exit 0
