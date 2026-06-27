#!/usr/bin/env bash
# Phalanx auto-start watcher. Runs the human's "do nothing" path: scan a registry
# of repo roots and, for each repo that has open TASKS.md items but no running
# supervisor and no kill switch, launch a DETACHED supervisor. Idempotent and
# safe to run on a cron (every few minutes) -- repos already supervised are
# skipped, so it never double-starts.
#   phalanx-watch.sh [-f registry]
# Registry (default $CLAUDE_DIR/.phalanx-repos): one absolute repo path per line,
# '#' comments and blanks ignored.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SUPERVISORD="$HERE/supervisord.sh"; [ -x "$SUPERVISORD" ] || SUPERVISORD="$CLAUDE_DIR/supervisord.sh"
REGISTRY="$CLAUDE_DIR/.phalanx-repos"
while getopts "f:" o; do case "$o" in f) REGISTRY="$OPTARG" ;; esac; done

[ -f "$REGISTRY" ] || { echo "no registry at $REGISTRY (one repo path per line). nothing to watch."; exit 0; }

has_open()      { [ -f "$1/TASKS.md" ] && grep -Eq '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]' "$1/TASKS.md"; }
# Verify the pid is ACTUALLY run-work.sh (item 3): without this, PID reuse after a
# crash/reboot makes a repo look permanently supervised, so phalanx-watch never
# restarts a dead loop. Where /proc exists, require run-work.sh in the cmdline.
sup_alive() {
  local p; p="$(cat "$1/.claude-runs/supervisor.pid" 2>/dev/null)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  if [ -r "/proc/$p/cmdline" ]; then
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'run-work.sh' || return 1
  fi
  return 0
}
off()           { [ -f "$1/.work-off" ] || [ -f "$CLAUDE_DIR/.work-off" ]; }

started=0
while IFS= read -r line || [ -n "$line" ]; do
  # Trim leading/trailing whitespace via parameter expansion (echo|xargs mangles
  # quotes/backslashes). Treat a line as a comment ONLY if it STARTS with '#', so a
  # valid absolute path containing '#' is preserved (item 4).
  repo="$line"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  case "$repo" in \#*) continue ;; esac
  [ -z "$repo" ] && continue
  [ -d "$repo" ] || { echo "skip (missing dir): $repo"; continue; }
  if off "$repo";      then echo "skip (.work-off): $repo"; continue; fi
  if ! has_open "$repo"; then continue; fi
  if sup_alive "$repo"; then echo "skip (already supervised): $repo"; continue; fi
  echo "starting supervisor for $repo"
  bash "$SUPERVISORD" start -r "$repo" >/dev/null 2>&1 && started=$((started + 1))
done < "$REGISTRY"
echo "watcher pass complete. supervisors started: $started."
