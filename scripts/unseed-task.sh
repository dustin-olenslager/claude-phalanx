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

# mktemp IN the repo dir (item 2) so the mv is a same-filesystem atomic rename --
# the default /tmp may be a different fs, where mv falls back to copy+unlink (a
# brief window of a truncated/partial TASKS.md and a non-atomic replace).
_unseed() {
  [ -f "$tasks" ] || return 0
  local tmp
  tmp="$(mktemp "$repo/.TASKS.md.unseed.XXXXXX" 2>/dev/null || echo "$tasks.unseed.tmp")"
  grep -vF "(req:$id)" "$tasks" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$tasks"
  if ! grep -Eq '^[[:space:]]*-[[:space:]]*\[[ xX]\]' "$tasks" 2>/dev/null; then
    rm -f "$tasks"
  fi
}

# Serialize against seed/checkoff on the same repo-local lock (item 2).
lockdir="$repo/.claude-runs"; mkdir -p "$lockdir" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$lockdir/tasks.lock"; flock 9; _unseed; flock -u 9
else
  _unseed
fi
exit 0
