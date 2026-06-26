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
[ -f "$tasks" ] || printf '# TASKS\n\n' > "$tasks"
printf -- '- [ ] (req:%s) %s\n' "$id" "$text" >> "$tasks"
printf '%s\n' "$id"
