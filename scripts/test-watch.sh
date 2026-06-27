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

# mk_repo opts the repo into unattended auto-run (.phalanx-autorun) so the BLOCKED-skip
# cases below reach the blocked check; the autorun gate itself is covered by case D.
mk_repo() { local d="$T/$1"; mkdir -p "$d/.claude-runs"; printf -- '- [ ] (req:X) do a thing\n' > "$d/TASKS.md"; touch "$d/.phalanx-autorun"; echo "$d"; }
run() { local reg="$T/registry"; printf '%s\n' "$1" > "$reg"; CLAUDE_DIR="$CLAUDE_DIR" bash "$WATCH" -f "$reg" 2>&1; }

# A) open tasks + BLOCKED sentinel -> skip
a="$(mk_repo blocked-sentinel)"; echo "### BLOCKED / skipped" > "$a/.claude-runs/BLOCKED"
out="$(run "$a")"
echo "$out" | grep -q "skip (BLOCKED" || fail "A: sentinel repo not skipped: $out"
echo "$out" | grep -q "starting supervisor" && fail "A: launched a blocked repo"

# B) open tasks + PROGRESS.md active BLOCKED: directive (no sentinel) -> skip (same
# detection as run-work; v1.6.5 made it an ACTIVE directive, NOT prose like "### BLOCKED").
b="$(mk_repo blocked-progress)"; printf '## notes\nBLOCKED: needs operator sign-off\n' > "$b/PROGRESS.md"
out="$(run "$b")"
echo "$out" | grep -q "skip (BLOCKED" || fail "B: progress-blocked repo not skipped: $out"
echo "$out" | grep -q "starting supervisor" && fail "B: launched a blocked repo"

# C) control: no open tasks, no BLOCKED -> not skipped-as-blocked, not launched
c="$T/clean"; mkdir -p "$c"; : > "$c/TASKS.md"
out="$(run "$c")"
echo "$out" | grep -q "skip (BLOCKED" && fail "C: clean repo wrongly flagged BLOCKED"
echo "$out" | grep -q "starting supervisor" && fail "C: launched a repo with no open tasks"

# D) open tasks but NO .phalanx-autorun opt-in -> skip (the fleet-runaway fix)
d="$T/no-autorun"; mkdir -p "$d/.claude-runs"; printf -- '- [ ] (req:X) do a thing\n' > "$d/TASKS.md"
out="$(run "$d")"
echo "$out" | grep -q "skip (no .phalanx-autorun" || fail "D: non-opted repo not skipped: $out"
echo "$out" | grep -q "starting supervisor" && fail "D: launched a non-opted repo"

echo "ok: phalanx-watch requires .phalanx-autorun, skips BLOCKED repos (no churn), leaves clean repos alone"
