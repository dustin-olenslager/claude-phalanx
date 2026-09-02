#!/usr/bin/env bash
# SessionStart nudge: one line when the cwd repo has hygiene findings (stale worktrees,
# merged branches, primary tree off main, BLOCKED sentinel). Read-only, ~0.5s, silent
# when clean or outside a git repo. Never blocks. Full sweep: phalanx-gc.sh --apply --gh
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
GC="$CLAUDE_DIR/phalanx-gc.sh"; [ -x "$GC" ] || GC="$(dirname "$0")/phalanx-gc.sh"
[ -x "$GC" ] || exit 0
top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
out="$(PHALANX_GC_QUIET=1 timeout 20s "$GC" "$top" 2>/dev/null | grep -E '^\s+\[(PLAN|OP)\]')" || true
[ -n "$out" ] || exit 0
n_plan="$(echo "$out" | grep -c '\[PLAN\]')"; n_op="$(echo "$out" | grep -c '\[OP\]')"
echo "[phalanx-gc] $top: $n_plan sweepable + $n_op operator items (worktrees/branches/primary-tree). Run: ~/.claude/phalanx-gc.sh --apply --gh $top"
echo "$out" | head -6
