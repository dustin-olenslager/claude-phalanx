#!/usr/bin/env bash
# Regression: removing a pass worktree with UNCOMMITTED work must not lose it
# (2026-07-03 fonto/JEX-P2 loss: ceiling-tripped pass checkpointed, supervisor
# removed the worktree, all uncommitted code destroyed). wip-preserve.sh stashes
# the dirty state into the shared repo + records a WIP-STASH line so the next
# pass restores real files instead of rebuilding from prose.
# Picked up by verify.sh's test-*.sh glob.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIP="$HERE/wip-preserve.sh"
FAIL=0
R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT
(
  cd "$R" && git init -q && git config user.email a@b.c && git config user.name a \
    && echo base > tracked.txt && git add tracked.txt && git commit -qm init && git branch -M main \
    && git worktree add -q .claude/worktrees/wt -b worktree-wt-1 main
) || { echo "test-wip-preserve: FAIL (fixture setup)"; exit 1; }
WT="$R/.claude/worktrees/wt"

# Case 1: dirty worktree (tracked mod + untracked nested file) -> preserved.
echo changed >> "$WT/tracked.txt"
mkdir -p "$WT/lib/intelligence"
echo 'export const x = 1' > "$WT/lib/intelligence/new.ts"
sha="$(bash "$WIP" "$R" "$WT" "pass 1 test")"
git -C "$R" worktree remove --force "$WT" >/dev/null 2>&1
git -C "$R" worktree prune >/dev/null 2>&1
if git -C "$R" stash list | grep -q 'phalanx-wip: pass 1 test'; then echo "  ok case1 stash exists"; else echo "  FAIL case1: no phalanx-wip stash after worktree removal"; FAIL=1; fi
if grep -q '^WIP-STASH:' "$R/PROGRESS.md" 2>/dev/null; then echo "  ok case1 WIP-STASH line"; else echo "  FAIL case1: no WIP-STASH line in PROGRESS.md"; FAIL=1; fi
if [ -n "$sha" ] && grep -q "$sha" "$R/PROGRESS.md" 2>/dev/null; then echo "  ok case1 stash sha recorded"; else echo "  FAIL case1: stash sha not recorded"; FAIL=1; fi

# Case 2: NEXT pass (fresh worktree) restores the salvaged files.
git -C "$R" worktree add -q .claude/worktrees/wt2 -b worktree-wt-2 main
WT2="$R/.claude/worktrees/wt2"
( cd "$WT2" && git stash pop -q ) >/dev/null 2>&1
if grep -q changed "$WT2/tracked.txt" 2>/dev/null; then echo "  ok case2 tracked mod restored"; else echo "  FAIL case2: tracked modification lost"; FAIL=1; fi
if [ -f "$WT2/lib/intelligence/new.ts" ]; then echo "  ok case2 untracked file restored"; else echo "  FAIL case2: untracked file lost"; FAIL=1; fi
git -C "$R" worktree remove --force "$WT2" >/dev/null 2>&1

# Case 3: clean worktree -> no-op (no stash, no WIP-STASH line, exit 0).
rm -f "$R/PROGRESS.md"
git -C "$R" worktree add -q .claude/worktrees/wt3 -b worktree-wt-3 main
out="$(bash "$WIP" "$R" "$R/.claude/worktrees/wt3" "pass 3 test")"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then echo "  ok case3 clean no-op"; else echo "  FAIL case3: expected silent exit 0 (rc=$rc out='$out')"; FAIL=1; fi
if git -C "$R" stash list | grep -q 'pass 3 test'; then echo "  FAIL case3: stash created for clean worktree"; FAIL=1; else echo "  ok case3 no stash"; fi
if [ -f "$R/PROGRESS.md" ]; then echo "  FAIL case3: PROGRESS.md written for clean worktree"; FAIL=1; else echo "  ok case3 no WIP-STASH line"; fi

# Case 4: missing worktree path -> silent exit 0 (pass may have never created one).
if bash "$WIP" "$R" "$R/.claude/worktrees/nope" "pass 4 test" >/dev/null 2>&1; then echo "  ok case4 missing worktree no-op"; else echo "  FAIL case4: nonzero exit for missing worktree"; FAIL=1; fi

[ "$FAIL" = 0 ] && echo "test-wip-preserve: PASS" || { echo "test-wip-preserve: FAIL"; exit 1; }
