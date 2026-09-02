#!/usr/bin/env bash
# phalanx-docs-reconcile.sh -- keep the Panoply queue honest against git/GitHub.
#
#   phalanx-docs-reconcile.sh [--apply] [REPO]        (default: cwd, dry run)
#
# The queue is docs/claude/in-progress.d/<slug>.md, one fragment per task (ADR-0004 /
# Panoply). A fragment leaves the queue when its work ships -- but nothing enforced that,
# so fragments saying "IN REVIEW (task/foo)" outlived their merged PRs by weeks and the
# queue stopped meaning anything. This script, per fragment:
#   * finds the branch it names (task/<slug>, wt/<slug>, feat/<slug>, or `branch:` key)
#   * asks GitHub for that branch's PR (needs gh + GH_TOKEN / gh auth; falls back to
#     `git branch --merged` when offline)
#   * PR MERGED (or branch merged into main)  -> SHIPPED: append an entry to
#     docs/claude/completed-features.md, delete the fragment
#   * PR CLOSED unmerged                       -> report (operator decides: reopen or drop)
#   * branch gone + no PR                       -> report as ORPHAN (work never landed)
#   * PR open / branch alive                    -> leave alone
# Then regenerates the rendered queue if the repo has a `queue` npm script.
# Dry run prints the plan; --apply writes. Never touches fragments it cannot classify.
set -u
APPLY=0; REPO=""
for a in "$@"; do case "$a" in --apply) APPLY=1;; -h|--help) sed -n 2,20p "$0"; exit 0;; *) REPO="$a";; esac; done
REPO="${REPO:-$PWD}"; REPO="$(cd "$REPO" && git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo"; exit 1; }
Q="$REPO/docs/claude/in-progress.d"; DONE="$REPO/docs/claude/completed-features.md"
[ -d "$Q" ] || { echo "no queue at $Q"; exit 0; }
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
if [ -z "${GH_TOKEN:-}" ] && [ -f "$CLAUDE_DIR/.loop-git-env" ]; then
  GH_TOKEN="$(grep -E '^(export )?GH_TOKEN=' "$CLAUDE_DIR/.loop-git-env" | head -1 | sed -E 's/^(export )?GH_TOKEN=//; s/^"//; s/"$//')"; export GH_TOKEN
fi
SLUG="$(git -C "$REPO" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]##; s#\.git$##')"
GH=0; [ -n "$SLUG" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && GH=1
MAIN="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"; [ -z "$MAIN" ] && MAIN=main
git -C "$REPO" fetch -q origin "$MAIN" 2>/dev/null || true

# One PR table for the repo: headRef<TAB>state<TAB>number<TAB>mergedAt<TAB>url (latest per head wins, MERGED preferred)
PRS=""
if [ $GH = 1 ]; then
  PRS="$(timeout 120 gh pr list -R "$SLUG" --state all --limit 1000 --json headRefName,state,number,mergedAt,url \
    -q '.[] | [.headRefName,.state,(.number|tostring),(.mergedAt//""),.url] | @tsv' 2>/dev/null \
    | awk -F'\t' '{ if(!($1 in s) || $2=="MERGED") { s[$1]=$0 } } END { for(k in s) print s[k] }')"
fi
pr_row() { [ -n "$PRS" ] && printf '%s\n' "$PRS" | awk -F'\t' -v b="$1" '$1==b{print; exit}'; }

fm() { awk -v k="$1" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} $0 ~ "^"k":"{sub("^"k":[ ]*",""); gsub(/^"|"$/,""); print; exit}' "$2"; }
n_ship=0; n_closed=0; n_orphan=0; n_keep=0; n_unk=0; ENTRIES=""
for f in "$Q"/*.md; do
  [ -f "$f" ] || continue; base="$(basename "$f")"; [ "$base" = "README.md" ] && continue
  title="$(fm title "$f")"; status="$(fm status "$f")"; area="$(fm area "$f")"
  # The branch must come from the `branch:` key or the STATUS line itself -- a branch named
  # somewhere in the body is usually one PR of a multi-PR initiative, not the task's own.
  br="$(fm branch "$f")"
  [ -z "$br" ] && br="$(printf '%s' "$status" | grep -oE '(task|wt|feat|fix)/[A-Za-z0-9._-]*[A-Za-z0-9]' | head -1)"
  # A single-task fragment ("In review", "Shipped to PR", "awaiting merge") that names its branch
  # only in the body still classifies; initiative trackers (phases, M1..M5, PR-1/PR-2) do not.
  if [ -z "$br" ] && printf '%s' "$status" | grep -qiE '^(in[ -]review|in review|shipped|ready for review|pr open|shipped-pending-review)' \
     && ! printf '%s' "$status" | grep -qiE 'phase|M[0-9]|PR-[0-9]|part [0-9]|step'; then
    br="$(grep -oE '(task|wt|feat|fix)/[A-Za-z0-9._-]*[A-Za-z0-9]' "$f" | head -1)"
  fi
  if [ -z "$br" ]; then n_unk=$((n_unk+1)); echo "  [?]     $base -- no branch in status/branch key; status: ${status:0:80}"; continue; fi
  # A merged PR whose fragment still tracks an operator step (apply migration, rebuild image,
  # provision) is NOT done -- the fragment is the reminder. Report, do not retire.
  if printf '%s' "$status" | grep -qiE 'not applied|awaiting operator|not rebuilt|provision'; then
    n_keep=$((n_keep+1)); echo "  [OP]    $base -- operator step pending ($br): ${status:0:90}"; continue
  fi
  row="$(pr_row "$br")"; st="$(printf '%s' "$row" | cut -f2)"; num="$(printf '%s' "$row" | cut -f3)"; merged="$(printf '%s' "$row" | cut -f4 | cut -c1-10)"; url="$(printf '%s' "$row" | cut -f5)"
  local_alive=0; git -C "$REPO" show-ref -q "refs/heads/$br" && local_alive=1
  remote_alive=0; git -C "$REPO" show-ref -q "refs/remotes/origin/$br" && remote_alive=1
  merged_local=0; [ $local_alive = 1 ] && git -C "$REPO" merge-base --is-ancestor "$br" "origin/$MAIN" 2>/dev/null && merged_local=1
  if [ "$st" = "MERGED" ] || [ $merged_local = 1 ]; then
    n_ship=$((n_ship+1)); [ -z "$merged" ] && merged="$(date +%F)"
    echo "  [SHIP]  $base -> completed-features ($br${num:+, PR #$num} $merged)"
    ENTRIES="$ENTRIES
### ${title:-$base} — $merged
- **What shipped:** ${title:-$base}${num:+ ([PR #$num]($url))}. Queue fragment \`$base\` retired by phalanx-docs-reconcile.
- **Area:** \`${area:-unknown}\`
- **Branch:** \`$br\`
"
    [ $APPLY = 1 ] && rm -f "$f"
  elif [ "$st" = "CLOSED" ]; then
    n_closed=$((n_closed+1)); echo "  [OP]    $base -- PR #$num CLOSED unmerged ($br): reopen or delete the fragment"
  elif [ -z "$row" ] && [ $local_alive = 0 ] && [ $remote_alive = 0 ]; then
    n_orphan=$((n_orphan+1)); echo "  [OP]    $base -- ORPHAN: branch $br gone, no PR (work never landed?)"
  else
    n_keep=$((n_keep+1))
  fi
done
if [ $APPLY = 1 ] && [ -n "$ENTRIES" ]; then
  if [ -f "$DONE" ]; then
    # newest first: insert before the first REAL entry -- a "### " line outside a fenced block
    # that is not the template placeholder or the EXAMPLE row -- else append at the end.
    tmp="$(mktemp)"; awk -v e="$ENTRIES" 'BEGIN{done=0;fence=0} /^```/{fence=!fence} /^### / && !fence && !done && $0 !~ /<Feature name>|EXAMPLE/ {print e; done=1} {print} END{if(!done) print e}' "$DONE" > "$tmp" && mv "$tmp" "$DONE"
  else
    printf '# Completed Features\n%s\n' "$ENTRIES" > "$DONE"
  fi
  if grep -q '"queue"' "$REPO/package.json" 2>/dev/null; then (cd "$REPO" && (pnpm queue || npm run queue) >/dev/null 2>&1) || true; fi
fi
echo "queue: ship=$n_ship closed=$n_closed orphan=$n_orphan keep=$n_keep unclassified=$n_unk (gh=$GH)$( [ $APPLY = 1 ] || echo '  -- dry run; --apply to retire shipped fragments')"
