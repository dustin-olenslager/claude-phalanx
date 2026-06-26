#!/usr/bin/env bash
# Phalanx standalone leak audit. Scans the whole working tree (tracked files) for
# secrets, and -- when --personal is passed -- for the local denylist terms in
# $PHALANX_LEAKWORDS / $HOME/.claude/.phalanx-leakwords. Exit 1 on any hit.
# Use before going public, or in CI. Read-only; never edits.
#   scripts/leak-scan.sh [--personal]
set -uo pipefail
PERSONAL=0; [ "${1:-}" = "--personal" ] && PERSONAL=1
LEAKWORDS="${PHALANX_LEAKWORDS:-$HOME/.claude/.phalanx-leakwords}"

SECRET_RE='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9a-zA-Z]{16,}|AIza[0-9A-Za-z_-]{35}|sk_mt_[0-9A-Za-z]{20,}|(api[_-]?key|secret|token|password|passwd|client[_-]?secret|access[_-]?token)["'"'"' ]*[:=]["'"'"' ]*["'"'"'][^"'"'"']{16,}["'"'"']'
SECRET_ALLOW='process\.env|import\.meta\.env|os\.environ|getenv|Deno\.env|YOUR_|REPLACE|EXAMPLE|placeholder|xxxx|\$\{|noreply'

fail=0
files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
sh=$(printf '%s\n' "$files" | xargs -r grep -EnHI "$SECRET_RE" 2>/dev/null | grep -EviI "$SECRET_ALLOW" || true)
if [ -n "$sh" ]; then echo "SECRET hits:"; printf '  %s\n' "$sh" | head -20; fail=1; fi

if [ "$PERSONAL" = 1 ] && [ -f "$LEAKWORDS" ]; then
  pat=$(grep -vE '^[[:space:]]*(#|$)' "$LEAKWORDS" | paste -sd'|' - 2>/dev/null)
  if [ -n "$pat" ]; then
    ph=$(printf '%s\n' "$files" | xargs -r grep -EniHI "$pat" 2>/dev/null || true)
    if [ -n "$ph" ]; then echo "PERSONAL/PRIVATE hits:"; printf '  %s\n' "$ph" | head -20; fail=1; fi
  fi
fi

[ "$fail" = 0 ] && echo "leak-scan: clean" || { echo "leak-scan: FAIL"; exit 1; }
