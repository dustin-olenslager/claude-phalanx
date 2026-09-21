#!/usr/bin/env sh
# init-repo-protection.sh — Interactive branch protection setup via gh CLI.
# Run from repo root. Requires gh auth (gh auth status). Prompts for confirmation.
# Exits 0 on success or user decline; exits 1 on gh missing/unauthenticated/repo not found.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Panoply: Branch Protection Setup ==="

# Check gh CLI
if ! command -v gh >/dev/null 2>&1; then
  echo "✗ gh CLI not found. Install: https://cli.github.com"
  echo "  Then run: gh auth login"
  exit 1
fi

# Check auth
if ! gh auth status >/dev/null 2>&1; then
  echo "✗ gh not authenticated. Run: gh auth login"
  exit 1
fi

# Get repo info
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || {
  echo "✗ Not a GitHub repo or no remote. Run from a repo with GitHub remote."
  exit 1
}

DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)" || DEFAULT_BRANCH="main"

echo "Repo: $REPO"
echo "Default branch: $DEFAULT_BRANCH"
echo ""
echo "This will configure branch protection on '$DEFAULT_BRANCH':"
echo "  • Require pull request reviews (1 reviewer)"
echo "  • Require status checks to pass ('verify' job)"
echo "  • Dismiss stale reviews on new commits"
echo "  • Require branches to be up to date before merging"
echo "  • Restrict force pushes"
echo "  • Restrict deletions"
echo ""

printf "Apply these settings? [y/N] "
read -r confirm
case "$confirm" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Skipped."; exit 0 ;;
esac

echo "Configuring branch protection..."

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/branches/$DEFAULT_BRANCH/protection" \
  -f required_status_checks='{"strict":true,"contexts":["verify"]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"dismissal_restrictions":{},"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"required_approving_review_count":1}' \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f block_creations=false \
  -f required_linear_history=true \
  -f allow_auto_merge=false \
  -f required_deployments=[] \
  >/dev/null

echo "✓ Branch protection configured on $DEFAULT_BRANCH"
echo ""
echo "Verify in GitHub: Settings → Branches → Branch protection rules"
echo "Required status check: 'verify' (from ci-verify.yml)"