#!/usr/bin/env bash
# Regression test for ensure_shared_git() in run-work.sh: on a shared mount it keeps
# .git group-writable + setgid so any uid in the repo's group can write objects.
# Extracts the embedded function from run-work.sh and asserts its OBSERVABLE effect on
# permissions/config. Fully unprivileged — no real-root cross-uid writes required.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# 0) extract ensure_shared_git() out of run-work.sh (not separately sourceable)
awk '/^ensure_shared_git *\(\)/{f=1} f{print} f&&/^}/{exit}' "$REPO/scripts/run-work.sh" > "$T/fn.sh"
[ -s "$T/fn.sh" ] || fail "0: could not extract ensure_shared_git from run-work.sh"
source "$T/fn.sh"

# 1) setup a real repo
git init -q "$T/repo"
[ -d "$T/repo/.git" ] || fail "1: git init did not create .git"

# 2) run the guard
ensure_shared_git "$T/repo"

# 3) guard set core.sharedRepository=group
[ "$(git -C "$T/repo" config --get core.sharedRepository)" = "group" ] || fail "3: core.sharedRepository != group"

# 4) .git dirs are group-writable + setgid
perm=$(stat -c %a "$T/repo/.git/objects")
(( (0$perm & 020) != 0 )) || fail "4a: objects dir lacks group-write ($perm)"
(( (0$perm & 02000) != 0 )) || fail "4b: objects dir lacks setgid ($perm)"

# 5) idempotent — second run leaves config intact, no error
ensure_shared_git "$T/repo"
[ "$(git -C "$T/repo" config --get core.sharedRepository)" = "group" ] || fail "5: not idempotent"

# 6) a new object written after the guard lands in a still-writable dir
touch "$T/repo/.git/objects/testobj"
[ -w "$T/repo/.git/objects" ] || fail "6: objects dir not group/owner writable"

echo "test-shared-git-guard: ok"
