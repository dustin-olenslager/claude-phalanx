#!/usr/bin/env bash
# Phalanx standalone leak audit. Scans the whole working tree (tracked files) for
# secrets, and -- when --personal is passed -- for the local denylist terms in
# $PHALANX_LEAKWORDS / $HOME/.claude/.phalanx-leakwords. Exit 1 on any hit.
# Use before going public, or in CI. Read-only; never edits.
#   scripts/leak-scan.sh [--personal] [--public]
# --public: PUBLIC-repo push path -- gitleaks is MANDATORY and FAIL-CLOSED. If
# gitleaks is missing or errors out, the scan FAILS (exit 1) rather than silently
# falling back to the weaker regex set. Without --public, regex-only as before.
set -uo pipefail
PERSONAL=0; PUBLIC=0
for arg in "$@"; do
  case "$arg" in
    --personal) PERSONAL=1 ;;
    --public)   PUBLIC=1 ;;
  esac
done
LEAKWORDS="${PHALANX_LEAKWORDS:-$HOME/.claude/.phalanx-leakwords}"

SECRET_RE='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9a-zA-Z]{16,}|AIza[0-9A-Za-z_-]{35}|sk_mt_[0-9A-Za-z]{20,}|(api[_-]?key|secret|token|password|passwd|client[_-]?secret|access[_-]?token)["'"'"' ]*[:=]["'"'"' ]*["'"'"'][^"'"'"']{16,}["'"'"']'
SECRET_ALLOW='process\.env|import\.meta\.env|os\.environ|getenv|Deno\.env|YOUR_|REPLACE|EXAMPLE|placeholder|xxxx|\$\{|noreply'

fail=0

# PUBLIC push path: gitleaks is mandatory + fail-closed.
if [ "$PUBLIC" = 1 ]; then
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "leak-scan: FAIL — --public requires gitleaks, which is not installed (fail-closed)." >&2
    exit 1
  fi
  if gitleaks detect --no-banner --redact -s . >/dev/null 2>&1; then
    echo "leak-scan: gitleaks clean"
  else
    echo "leak-scan: FAIL — gitleaks flagged secrets (or errored). Resolve before pushing public." >&2
    exit 1
  fi
fi

files=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
# Scope the allowlist to the MATCHED substring (-o), not the whole line: a benign
# `process.env.X` on the same line as a real secret must not suppress the hit.
raw=$(printf '%s\n' "$files" | xargs -r grep -EnHIo "$SECRET_RE" 2>/dev/null || true)
sh=$(printf '%s\n' "$raw" | grep -EviI "$SECRET_ALLOW" || true)
if [ -n "$sh" ]; then echo "SECRET hits:"; printf '  %s\n' "$sh" | head -20; fail=1; fi

if [ "$PERSONAL" = 1 ] && [ -f "$LEAKWORDS" ]; then
  pat=$(grep -vE '^[[:space:]]*(#|$)' "$LEAKWORDS" | paste -sd'|' - 2>/dev/null)
  if [ -n "$pat" ]; then
    ph=$(printf '%s\n' "$files" | xargs -r grep -EniHI "$pat" 2>/dev/null || true)
    if [ -n "$ph" ]; then echo "PERSONAL/PRIVATE hits:"; printf '  %s\n' "$ph" | head -20; fail=1; fi
  fi
fi

[ "$fail" = 0 ] && echo "leak-scan: clean" || { echo "leak-scan: FAIL"; exit 1; }
