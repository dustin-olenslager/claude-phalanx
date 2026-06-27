#!/usr/bin/env bash
# Phalanx first-class evidence (Item 5). OPT-IN + SOFT: capture per-breakpoint browser
# screenshots tied to the CURRENT head SHA, write a manifest, and stage/commit them as
# evidence. It is NOT a gate and is NEVER required for `verify` to pass -- it degrades to
# a no-op when off, or when playwright / a URL is unavailable (the README graceful-
# degradation promise). The verify phase never depends on evidence existing.
#
# Enable: touch <CLAUDE_DIR>/.evidence-on AND set evidence.enabled:true in risk-policy.json.
# Usage: evidence.sh -u <url> [-r repo] [--commit]
set -uo pipefail
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
REPO="$PWD"; URL="${PHALANX_EVIDENCE_URL:-}"; DO_COMMIT="${PHALANX_EVIDENCE_COMMIT:-0}"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    -u) URL="${2:-}"; shift 2 ;;
    -r) REPO="${2:-$PWD}"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    *) shift ;;
  esac
done

# --- opt-in guard: BOTH the switch AND policy evidence.enabled:true ---
[ -f "$CLAUDE_DIR/.evidence-on" ] || { echo "evidence: off (.evidence-on absent) -- no-op"; exit 0; }
POL="$CLAUDE_DIR/risk-policy.json"
enabled=$(node -e 'try{const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(p.evidence&&p.evidence.enabled===true?"1":"0")}catch{process.stdout.write("0")}' "$POL" 2>/dev/null || echo 0)
[ "$enabled" = "1" ] || { echo "evidence: off (policy evidence.enabled != true) -- no-op"; exit 0; }

# --- soft preconditions: any missing -> graceful no-op, exit 0 (NEVER fail verify) ---
cd "$REPO" 2>/dev/null || { echo "evidence: repo not found: $REPO"; exit 0; }
[ -n "$URL" ] || { echo "evidence: no URL (-u) -- soft skip"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "evidence: node absent -- soft skip"; exit 0; }
node -e 'require.resolve("playwright")' >/dev/null 2>&1 || { echo "evidence: playwright not installed -- soft skip (graceful degradation)"; exit 0; }

dir=$(node -e 'try{const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write((p.evidence&&p.evidence.dir)||"evidence")}catch{process.stdout.write("evidence")}' "$POL" 2>/dev/null || echo evidence)
bps=$(node -e 'try{const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const b=(p.evidence&&p.evidence.breakpoints)||[390,1440];process.stdout.write(b.join(" "))}catch{process.stdout.write("390 1440")}' "$POL" 2>/dev/null || echo "390 1440")
sha=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
outdir="$dir/$sha"; mkdir -p "$outdir"

# --- capture per breakpoint (soft: one bp failing doesn't abort the rest) ---
ok=0
for bp in $bps; do
  if node -e '
const {chromium}=require("playwright");
(async()=>{const b=await chromium.launch();const pg=await b.newPage({viewport:{width:+process.argv[2],height:900}});
await pg.goto(process.argv[1],{waitUntil:"domcontentloaded",timeout:30000});
await pg.screenshot({path:process.argv[3],fullPage:true});await b.close();})().catch(e=>{console.error(""+e);process.exit(1)});
' "$URL" "$bp" "$outdir/bp-$bp.png" 2>/dev/null; then ok=$((ok+1)); fi
done
[ "$ok" -gt 0 ] || { echo "evidence: no screenshots captured -- soft skip"; exit 0; }

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
node -e 'const fs=require("fs");const[,s,u,t,o,...bp]=process.argv;fs.writeFileSync(o+"/manifest.json",JSON.stringify({headSha:s,url:u,capturedAt:t,breakpoints:bp.map(Number)},null,2)+"\n")' "$sha" "$URL" "$ts" "$outdir" $bps
echo "evidence: captured $ok shot(s) for $sha -> $outdir"

# --- stage (or, with the third opt-in, commit) the evidence ---
if command -v git >/dev/null 2>&1; then
  git add "$dir" 2>/dev/null || true
  if [ "$DO_COMMIT" = "1" ]; then
    git commit -q -m "test(evidence): browser evidence for $sha" 2>/dev/null && echo "evidence: committed $outdir" || echo "evidence: commit skipped"
  else
    echo "evidence: staged $outdir (pass --commit to commit)"
  fi
fi
exit 0
