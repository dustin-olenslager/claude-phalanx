#!/usr/bin/env bash
# Seed a request into a repo's TASKS.md as a loop task; print its req id on stdout.
# Request-scoped: the line carries a unique (req:<id>) tag so unseed-task.sh can
# remove EXACTLY this request's lines later. This is what stops a left-open
# TASKS.md (e.g. from a one-shot bot run) from silently re-arming the loop on the
# next unrelated message (CLAUDE.md item 6).
#   seed-task.sh <repo> "<request text>" [reqid]
set -euo pipefail
repo="${1:?repo required}"; text="${2:?request text required}"
# Default id: pid + epoch. Unique enough for one machine; caller may pass a bot id.
id="${3:-r$$-$(date +%s 2>/dev/null || echo 0)}"
tasks="$repo/TASKS.md"
# Flatten newlines/CR to spaces so a multi-line request stays ONE task line and
# can't spill orphan continuation lines into TASKS.md (item 3).
text="$(printf '%s' "$text" | tr '\r\n' '  ')"

# Serialize all TASKS.md mutations on one repo-local lock (item 2) so a concurrent
# seed/unseed/checkoff can't interleave a read-modify-write. flock is best-effort:
# if it isn't installed the append still runs (append is atomic enough on its own).
lockdir="$repo/.claude-runs"; mkdir -p "$lockdir" 2>/dev/null || true
# A brand-new request clears a stale human-halt sentinel so it can't smother fresh
# work (mirrors work-autostart's stale-BLOCKED rule). The detector re-materializes
# it if PROGRESS.md still carries a live BLOCKED line.
rm -f "$lockdir/BLOCKED" 2>/dev/null || true
_seed() {
  [ -f "$tasks" ] || printf '# TASKS\n\n' > "$tasks"
  printf -- '- [ ] (req:%s) %s\n' "$id" "$text" >> "$tasks"
}
if command -v flock >/dev/null 2>&1; then
  exec 9>"$lockdir/tasks.lock"; flock 9; _seed; flock -u 9
else
  _seed
fi
printf '%s\n' "$id"
