#!/usr/bin/env bash
# Single bash source of truth for TASKS.md / PROGRESS.md loop state -- mirrors
# hooks/gates/lib/phalanx-hook.js (tasksState). SOURCE this, then call the helpers
# with a repo dir. Pure DETECTION only; stateful concerns (the BLOCKED sentinel
# file, the RESPAWN-DONE strike) stay in the caller (run-work.sh / the gates).
#
# Each returns shell-truthy (exit 0) / falsy (exit 1) so callers read as `if`.

# >=1 open `- [ ]` item in $1/TASKS.md.
ts_has_open() { [ -f "$1/TASKS.md" ] && grep -Eq '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]' "$1/TASKS.md"; }

# An ACTIVE `BLOCKED:` halt directive exists anywhere in $1/PROGRESS.md (WHOLE
# file: a verbose pass must not push it out of a tail window). Matches only an
# optionally-indented, optional single leading "- ", then `BLOCKED:` -- NOT prose/
# tables/headers that merely mention the word.
ts_blocked() { [ -f "$1/PROGRESS.md" ] && grep -Eq '^[[:space:]]*-?[[:space:]]*BLOCKED:' "$1/PROGRESS.md"; }

# First active BLOCKED: directive line of $1/PROGRESS.md (to seed the sentinel),
# else the word BLOCKED.
ts_blocked_line() { grep -Em1 '^[[:space:]]*-?[[:space:]]*BLOCKED:' "$1/PROGRESS.md" 2>/dev/null || echo BLOCKED; }
