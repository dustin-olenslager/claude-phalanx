#!/usr/bin/env bash
# wip-preserve.sh - salvage a pass worktree's UNCOMMITTED work before the
# supervisor removes the worktree. A pass that hits the context ceiling (or is
# killed) mid-implementation leaves real files uncommitted -- the verify gate
# forbids committing them on task/<slug> without a green verify, and
# `git worktree remove --force` then destroys them (observed 2026-07-03 on
# fonto/JEX-P2: new lib tree + migrations lost; pass 2 rebuilt from prose).
# Worktrees share refs/stash with the primary repo, so a stash made here
# survives worktree removal. The stash ref is recorded as a WIP-STASH line in
# the shared PROGRESS.md so the NEXT pass restores it before resuming.
# Usage: wip-preserve.sh <primary-repo> <worktree-path> <pass-label>
# Prints the stash SHA when something was salvaged; silent no-op otherwise.
set -uo pipefail
REPO="$1"; WT="$2"; LABEL="$3"
[ -d "$WT" ] || exit 0
[ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ] || exit 0
MSG="phalanx-wip: $LABEL"
git -C "$WT" stash push --include-untracked -m "$MSG" >/dev/null 2>&1 || exit 0
SHA="$(git -C "$REPO" rev-parse refs/stash 2>/dev/null || echo unknown)"
BR="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
printf '\nWIP-STASH: %s ("%s", branch %s) -- uncommitted pass work salvaged before worktree removal. Next pass: in your worktree run `git stash list`, pop the "%s" entry BEFORE resuming, then delete this line.\n' \
  "$SHA" "$MSG" "$BR" "$MSG" >> "$REPO/PROGRESS.md" 2>/dev/null || true
echo "$SHA"
