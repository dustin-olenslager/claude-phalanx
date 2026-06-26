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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOKS="$CLAUDE_DIR/githooks"

mkdir -p "$HOOKS"
cp "$HERE"/githooks/pre-push "$HERE"/githooks/pre-commit "$HOOKS/"
chmod +x "$HOOKS"/pre-push "$HOOKS"/pre-commit

# Point git at the shared hooks dir globally (idempotent).
cur="$(git config --global --get core.hooksPath || true)"
if [ "$cur" != "$HOOKS" ]; then
  git config --global core.hooksPath "$HOOKS"
  echo "==> set git core.hooksPath -> $HOOKS$([ -n "$cur" ] && echo " (was: $cur)")"
else
  echo "==> core.hooksPath already $HOOKS"
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
