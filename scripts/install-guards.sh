#!/usr/bin/env bash
# Install the Phalanx leak guard so it applies to EVERY push from this machine.
# - copies the git hooks into $CLAUDE_DIR/githooks and points git at them globally
#   (core.hooksPath), so any clone you push from is guarded (not just this one);
# - seeds a LOCAL, never-committed denylist stub at $CLAUDE_DIR/.phalanx-leakwords
#   if absent (fill it with your private terms: infra hostnames, internal paths,
#   client/project names, private emails -- NOT things already public like your
#   repo URL or LICENSE name).
# Re-run safe. Honors CLAUDE_DIR (default ~/.claude).
set -euo pipefail

# Defensive: honor the same opt-out install.sh gates the call with, so a direct
# invocation is skippable too.
if [ "${PHALANX_NO_GUARDS:-0}" = "1" ]; then
  echo "==> PHALANX_NO_GUARDS=1 -> skipping leak guard install"
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOKS="$CLAUDE_DIR/githooks"

mkdir -p "$HOOKS"
cp "$HERE"/githooks/pre-push "$HERE"/githooks/pre-commit "$HOOKS/"
chmod +x "$HOOKS"/pre-push "$HOOKS"/pre-commit

# Point git at the shared hooks dir globally (idempotent) -- but NEVER clobber a
# pre-existing FOREIGN hooksPath (Husky/lefthook/etc): that would silently disable
# the user's git hooks. Refuse by default and preserve theirs. PHALANX_FORCE_GUARDS=1
# stashes the old value to $CLAUDE_DIR/.prev-hookspath (uninstall.sh restores it)
# and takes over.
cur="$(git config --global --get core.hooksPath || true)"
if [ -z "$cur" ] || [ "$cur" = "$HOOKS" ]; then
  if [ "$cur" = "$HOOKS" ]; then
    echo "==> core.hooksPath already $HOOKS"
  else
    git config --global core.hooksPath "$HOOKS"
    echo "==> set git core.hooksPath -> $HOOKS"
  fi
elif [ "${PHALANX_FORCE_GUARDS:-0}" = "1" ]; then
  printf '%s\n' "$cur" > "$CLAUDE_DIR/.prev-hookspath"
  git config --global core.hooksPath "$HOOKS"
  echo "==> core.hooksPath was '$cur'; stashed to $CLAUDE_DIR/.prev-hookspath and set -> $HOOKS (PHALANX_FORCE_GUARDS)"
else
  echo "==> WARNING: global core.hooksPath is already '$cur' (not Phalanx's)." >&2
  echo "    Refusing to overwrite your existing git hooks -- the leak guard's pre-push/" >&2
  echo "    pre-commit will NOT be globally active. Re-run with PHALANX_FORCE_GUARDS=1 to" >&2
  echo "    take over (restored on uninstall), or PHALANX_NO_GUARDS=1 to skip guards." >&2
fi

LW="$CLAUDE_DIR/.phalanx-leakwords"
if [ ! -f "$LW" ]; then
  cat > "$LW" <<'EOF'
# Phalanx leak denylist -- LOCAL ONLY, never committed. One term or ERE regex per
# line; # starts a comment. The pre-push hook blocks any push to the PUBLIC
# claude-phalanx repo whose added lines match any of these. Add your private
# infrastructure hostnames, internal absolute paths, client/project names, and
# private emails. Do NOT add things that are already public by design (your repo
# URL, your LICENSE name) or you will block every push.
EOF
  echo "==> created denylist stub $LW (fill it with your private terms)"
else
  echo "==> denylist present: $LW"
fi
echo "==> leak guard installed. Test: scripts/leak-scan.sh --personal"
