#!/usr/bin/env bash
# Isolated test for install-guards.sh hooksPath handling (§5.3). Runs in a throwaway
# HOME so it never touches the real global git config. No frameworks.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T"            # isolates `git config --global` -> $T/.gitconfig
CLAUDE_DIR="$T/.claude"
HOOKS="$CLAUDE_DIR/githooks"
run() { env CLAUDE_DIR="$CLAUDE_DIR" "$@" bash "$REPO/scripts/install-guards.sh" >/dev/null 2>&1 || true; }
get() { git config --global --get core.hooksPath 2>/dev/null || true; }

# 1) no prior hooksPath -> Phalanx sets it
git config --global --unset core.hooksPath 2>/dev/null || true
run
[ "$(get)" = "$HOOKS" ] || fail "1: expected $HOOKS, got '$(get)'"

# 2) already ours -> stays, no stash
run
[ "$(get)" = "$HOOKS" ] || fail "2: not idempotent"
[ ! -f "$CLAUDE_DIR/.prev-hookspath" ] || fail "2: stash should not exist"

# 3) FOREIGN prior -> refuse, preserve theirs, no stash
git config --global core.hooksPath /tmp/husky-hooks
run
[ "$(get)" = "/tmp/husky-hooks" ] || fail "3: clobbered foreign hooksPath -> '$(get)'"
[ ! -f "$CLAUDE_DIR/.prev-hookspath" ] || fail "3: should not stash without FORCE"

# 4) FOREIGN prior + FORCE -> stash + take over
run PHALANX_FORCE_GUARDS=1
[ "$(get)" = "$HOOKS" ] || fail "4: FORCE did not take over"
[ "$(cat "$CLAUDE_DIR/.prev-hookspath")" = "/tmp/husky-hooks" ] || fail "4: bad stash"

# 5) uninstall restore logic (mirror of uninstall.sh) restores the stashed value
if [ "$(get)" = "$HOOKS" ] && [ -f "$CLAUDE_DIR/.prev-hookspath" ]; then
  prev="$(cat "$CLAUDE_DIR/.prev-hookspath")"
  [ -n "$prev" ] && git config --global core.hooksPath "$prev"
fi
[ "$(get)" = "/tmp/husky-hooks" ] || fail "5: restore failed -> '$(get)'"

# 6) PHALANX_NO_GUARDS=1 -> no-op (leaves current value untouched)
git config --global core.hooksPath /tmp/other
run PHALANX_NO_GUARDS=1
[ "$(get)" = "/tmp/other" ] || fail "6: NO_GUARDS still touched hooksPath"

echo "ok: all install-guards hooksPath cases pass"
