#!/usr/bin/env bash
# Phalanx cleanup / GC loop (Item 4). OPT-IN + SOFT, NEVER a gate and NEVER a merge
# blocker: it scans a repo for drift (TODO/FIXME/HACK/XXX) and stale docs (broken
# relative markdown links), writes a cheap quality grade, and -- only with a SECOND
# explicit opt-in -- opens a fix-up PR carrying the refreshed grade for human review.
#
# Enable the scan:  touch <CLAUDE_DIR>/.gc-on  AND set gc.enabled:true in risk-policy.json.
# Also open a PR:    pass --open-pr (or PHALANX_GC_OPEN_PR=1) with `gh` authed.
# Default (neither): a NO-OP -- prints why and exits 0, writes nothing, changes nothing.
#
# Usage: gc-scan.sh [-r repo] [--open-pr]
set -uo pipefail
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
REPO="$PWD"; OPEN_PR="${PHALANX_GC_OPEN_PR:-0}"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    -r) REPO="${2:-$PWD}"; shift 2 ;;
    --open-pr) OPEN_PR=1; shift ;;
    *) shift ;;
  esac
done

# --- opt-in guard: BOTH the machine-local switch AND policy gc.enabled:true ---
[ -f "$CLAUDE_DIR/.gc-on" ] || { echo "gc: off (.gc-on absent) -- no-op"; exit 0; }
POL="$CLAUDE_DIR/risk-policy.json"
enabled=$(node -e 'try{const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(p.gc&&p.gc.enabled===true?"1":"0")}catch{process.stdout.write("0")}' "$POL" 2>/dev/null || echo 0)
[ "$enabled" = "1" ] || { echo "gc: off (policy gc.enabled != true) -- no-op"; exit 0; }

cd "$REPO" 2>/dev/null || { echo "gc: repo not found: $REPO"; exit 0; }
gradesFile=$(node -e 'try{const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write((p.gc&&p.gc.gradesFile)||"quality-grades.json")}catch{process.stdout.write("quality-grades.json")}' "$POL" 2>/dev/null || echo quality-grades.json)

# --- scan: drift markers + stale (broken) relative doc links ---
markers=$(grep -RIn --exclude-dir=.git -E 'TODO|FIXME|HACK|XXX' . 2>/dev/null | wc -l | tr -d ' ')
broken=0
while IFS= read -r line; do
  f="${line%%:*}"; m="${line#*:}"
  tgt=$(printf '%s' "$m" | sed -E 's/^\]\(//; s/\)$//; s/#.*$//')
  case "$tgt" in http*|mailto:*|"") continue ;; esac
  [ -e "$(dirname "$f")/$tgt" ] || [ -e "$tgt" ] || broken=$((broken+1))
done < <(grep -RIoH --include='*.md' --exclude-dir=.git -E '\]\([^)]+\)' . 2>/dev/null)

# --- grade (cheap heuristic; tune in policy later) ---
grade=A
[ "${markers:-0}" -gt 50 ] && grade=B
[ "${markers:-0}" -gt 200 ] && grade=C
[ "${broken:-0}" -gt 0 ] && grade=C
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
node -e 'const fs=require("fs");const[,g,m,b,t,out]=process.argv;fs.writeFileSync(out,JSON.stringify({grade:g,driftMarkers:+m,brokenDocLinks:+b,scannedAt:t,note:"advisory only; never a merge gate"},null,2)+"\n")' "$grade" "${markers:-0}" "${broken:-0}" "$ts" "$gradesFile"
echo "gc: grade=$grade drift=${markers:-0} brokenDocLinks=${broken:-0} -> $gradesFile"

# --- optional fix-up PR (second opt-in; never without `gh` + --open-pr) ---
if [ "$OPEN_PR" = "1" ] && command -v gh >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  br="chore/gc-$(date -u +%Y%m%d-%H%M%S 2>/dev/null || echo run)"
  if git checkout -q -b "$br" 2>/dev/null; then
    git add "$gradesFile" 2>/dev/null || true
    git commit -q -m "chore(gc): refresh quality grade ($grade; drift=${markers:-0}, brokenDocLinks=${broken:-0})" 2>/dev/null || true
    if git push -q -u origin "$br" 2>/dev/null; then
      gh pr create --fill --title "chore(gc): quality grade $grade" \
        --body "Automated GC scan: drift=${markers:-0}, brokenDocLinks=${broken:-0}. Soft/advisory; NEVER a merge gate." 2>/dev/null \
        || echo "gc: PR open skipped (gh not authed)"
    else
      echo "gc: push skipped (no remote/auth) -- grade left on branch $br"
    fi
  else
    echo "gc: branch $br exists -- skipping PR"
  fi
fi
exit 0
