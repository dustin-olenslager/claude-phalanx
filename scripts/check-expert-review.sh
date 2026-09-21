#!/usr/bin/env sh
# check-expert-review.sh — CI gate verifying expert review evidence for non-trivial PRs.
# Exits 0 if review evidence found or PR is trivial; exits 1 with reason if missing.
# Usage: sh scripts/check-expert-review.sh [--since <base-sha>]
#   --since: check all commits in range (CI mode). Default: check current PR via env.

set -eu

# Trivial escape hatches
# 1. PR has label "trivial"
# 2. Latest commit message starts with "trivial:"
# 3. Only 1 file changed, ≤15 lines added, no schema/API/interface files

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

SINCE_MODE=0
REF=""
if [ "${1:-}" = "--since" ]; then
  SINCE_MODE=1
  REF="${2:?usage: check-expert-review.sh --since <ref>}"
fi

# verify_review_evidence <label>
# Checks for:
# 1. plan.md exists in feature area
# 2. checklist.md has items
# 3. new ADR under docs/adr/ since base (CI mode only)
# 4. PR description has ≥2 persona sign-offs
verify_review_evidence() {
  label="$1"

  # 1. plan.md exists (any area)
  if ! find docs/claude -name "plan.md" -type f 2>/dev/null | grep -q .; then
    echo "check-expert-review: $label — no plan.md found in docs/claude/**" >&2
    return 1
  fi

  # 2. checklist.md has unchecked items
  if ! find docs/claude -name "checklist.md" -type f -exec grep -l '^\- \[ \]' {} \; 2>/dev/null | grep -q .; then
    echo "check-expert-review: $label — no checklist.md with pending items found" >&2
    return 1
  fi

  # 3. new ADR under docs/adr/ since base (CI mode only)
  if [ "$SINCE_MODE" -eq 1 ]; then
    if ! git diff --name-only "$REF"..HEAD -- docs/adr/ 2>/dev/null | grep -q '\.md$'; then
      echo "check-expert-review: $label — no new ADR file in docs/adr/ since $REF" >&2
      return 1
    fi
  fi

  # 4. PR description has ≥2 persona sign-offs (only in CI with gh)
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    PR_NUMBER="${GITHUB_PR_NUMBER:-${CI_PR_NUMBER:-}}"
    if [ -n "$PR_NUMBER" ]; then
      body="$(gh pr view "$PR_NUMBER" --json body --jq .body 2>/dev/null || echo "")"
      # Count distinct persona sign-offs: Security, Performance, Maintainability, UX, <domain>
      signoffs=$(echo "$body" | grep -oE '^>?\s*(Security|Performance|Maintainability|UX|[A-Z][a-z]+):\s*(✓|approved|LGTM|sign.?off)' | sort -u | wc -l | tr -d ' ')
      if [ "${signoffs:-0}" -lt 2 ]; then
        echo "check-expert-review: $label — PR #$PR_NUMBER needs ≥2 persona sign-offs in description (found $signoffs)" >&2
        return 1
      fi
    fi
  fi

  return 0
}

# Check for trivial label via gh (if available in CI)
is_trivial=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  PR_NUMBER="${GITHUB_PR_NUMBER:-${CI_PR_NUMBER:-}}"
  if [ -n "$PR_NUMBER" ]; then
    if gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' 2>/dev/null | grep -q '^trivial$'; then
      is_trivial=1
      echo "check-expert-review: PR #$PR_NUMBER has 'trivial' label — skipping"
    fi
  fi
fi

# Check for trivial commit prefix
if [ "$is_trivial" -eq 0 ]; then
  LATEST_MSG="$(git log -1 --pretty=%s 2>/dev/null || echo "")"
  case "$LATEST_MSG" in
    trivial:*) is_trivial=1; echo "check-expert-review: commit message has 'trivial:' prefix — skipping" ;;
  esac
fi

# Check for trivial change (single file, ≤15 lines, no schema/API/interface)
if [ "$is_trivial" -eq 0 ]; then
  if [ "$SINCE_MODE" -eq 1 ]; then
    # CI mode: check each commit in range
    for sha in $(git rev-list "$REF"..HEAD); do
      [ "$(git rev-list --no-walk --count --merges "$sha")" -eq 0 ] || continue
      files="$(git show --name-only --format= "$sha" 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')"
      lines="$(git show --stat --format= "$sha" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/[+,]//g')"
      # Check for schema/API/interface files
      schema_files="$(git show --name-only --format= "$sha" 2>/dev/null | grep -E '\.(sql|prisma|graphql|proto|openapi|yaml|yml)$' | wc -l | tr -d ' ')"
      if [ "$files" -eq 1 ] && [ "${lines:-0}" -le 15 ] && [ "$schema_files" -eq 0 ]; then
        echo "check-expert-review: commit $sha is trivial (1 file, ${lines} lines, no schema) — skipping"
        continue
      fi
      # Non-trivial commit: verify review evidence
      if ! verify_review_evidence "$sha"; then
        fail=1
      fi
    done
  else
    # Pre-commit/local mode: check staged changes
    files="$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
    lines="$(git diff --cached --stat 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/[+,]//g')"
    schema_files="$(git diff --cached --name-only 2>/dev/null | grep -E '\.(sql|prisma|graphql|proto|openapi|yaml|yml)$' | wc -l | tr -d ' ')"
    if [ "$files" -eq 1 ] && [ "${lines:-0}" -le 15 ] && [ "$schema_files" -eq 0 ]; then
      echo "check-expert-review: staged change is trivial (1 file, ${lines} lines, no schema) — skipping"
    else
      if ! verify_review_evidence "staged"; then
        fail=1
      fi
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "check-expert-review: OK"
else
  echo "check-expert-review: FAILED — missing expert review evidence (reasons above)" >&2
fi
exit "$fail"
