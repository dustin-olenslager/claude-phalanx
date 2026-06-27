#!/usr/bin/env bash
# Isolated test: phalanx-watch must SKIP a human-halted (BLOCKED) repo instead of
# relaunching it (the churn/notify-spam bug). No real supervisor is launched -- the
# cases under test all skip before the launch line. `node tasks-state.sh` mirror.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO/scripts/phalanx-watch.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CLAUDE_DIR="$T/cd"; mkdir -p "$CLAUDE_DIR"

mk_repo() { local d="$T/$1"; mkdir -p "$d/.claude-runs"; printf -- '- [ ] (req:X) do a thing\n' > "$d/TASKS.md"; echo "$d"; }
run() { local reg="$T/registry"; printf '%s\n' "$1" > "$reg"; CLAUDE_DIR="$CLAUDE_DIR" bash "$WATCH" -f "$reg" 2>&1; }

# A) open tasks + BLOCKED sentinel -> skip
a="$(mk_repo blocked-sentinel)"; echo "### BLOCKED / skipped" > "$a/.claude-runs/BLOCKED"
out="$(run "$a")"
echo "$out" | grep -q "skip (BLOCKED" || fail "A: sentinel repo not skipped: $out"
echo "$out" | grep -q "starting supervisor" && fail "A: launched a blocked repo"

# B) open tasks + PROGRESS.md BLOCKED line (no sentinel) -> skip (same detection as run-work)
b="$(mk_repo blocked-progress)"; printf '## notes\n### BLOCKED / skipped remaining open items\n' > "$b/PROGRESS.md"
out="$(run "$b")"
echo "$out" | grep -q "skip (BLOCKED" || fail "B: progress-blocked repo not skipped: $out"
echo "$out" | grep -q "starting supervisor" && fail "B: launched a blocked repo"

# C) control: no open tasks, no BLOCKED -> not skipped-as-blocked, not launched
c="$T/clean"; mkdir -p "$c"; : > "$c/TASKS.md"
out="$(run "$c")"
echo "$out" | grep -q "skip (BLOCKED" && fail "C: clean repo wrongly flagged BLOCKED"
echo "$out" | grep -q "starting supervisor" && fail "C: launched a repo with no open tasks"

echo "ok: phalanx-watch skips BLOCKED repos (no churn), leaves clean repos alone"
