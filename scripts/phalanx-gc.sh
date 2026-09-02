#!/usr/bin/env bash
# phalanx-gc.sh -- fleet-wide git hygiene for loop repos: stale worktrees, merged
# branches, throwaway `worktree-*` branches, old run logs, drifted primary trees.
#
#   phalanx-gc.sh [--apply] [--gh] [--registry FILE] [--keep-days N] [REPO ...]
#
# Default = DRY RUN (prints what it would do). --apply performs the SAFE tier only:
#   * git worktree prune
#   * remove non-primary worktrees that are CLEAN (no modified/untracked) AND whose
#     branch is merged into main OR fully pushed (origin/<branch> contains HEAD) OR a
#     CLI throwaway `worktree-*` branch with 0 unique commits OR (--gh) the head of a
#     MERGED pull request. Locked worktrees are unlocked first (`claude --worktree`
#     locks them; a single --force cannot remove them). Removal runs against the
#     primary path recorded in the worktree's own .git file, so bind-mount aliases
#     (/workspace vs /mnt/user/...) do not break it; a worktree whose registration
#     is already gone is rm -rf'd (it was verified clean first).
#   * delete local branches merged into main/origin-main (not checked out anywhere)
#   * (--gh) delete local branches whose PR is MERGED -- catches squash/rebase merges
#     that `--merged` cannot see. Needs `gh` + auth (GH_TOKEN or gh auth login).
#   * delete `worktree-*` branches with 0 unique commits (not checked out anywhere)
#   * delete .claude-runs/run-* dirs + pass-*.log older than --keep-days (default 14)
#   * checkout main in the primary tree when it is CLEAN and its branch is merged
# Everything else (dirty worktrees, unpushed branches, stashes, BLOCKED sentinels,
# primary tree dirty/unmerged, open-PR branches, remote branches) is REPORTED for the
# operator, never touched. Exit 0 always; the report is the product.
# PHALANX_GC_QUIET=1 prints only repos with findings.
set -u
APPLY=0; GH=0; KEEP_DAYS=14; REG=""; REPOS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1;;
    --gh) GH=1;;
    --registry) REG="$2"; shift;;
    --keep-days) KEEP_DAYS="$2"; shift;;
    -h|--help) sed -n 2,26p "$0"; exit 0;;
    *) REPOS+=("$1");;
  esac; shift
done
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
[ -z "$REG" ] && REG="$CLAUDE_DIR/.phalanx-repos"
if [ ${#REPOS[@]} -eq 0 ] && [ -f "$REG" ]; then
  while IFS= read -r l; do l="${l%%#*}"; l="$(echo "$l" | xargs)"; [ -n "$l" ] && REPOS+=("$l"); done < "$REG"
fi
[ ${#REPOS[@]} -eq 0 ] && { echo "no repos (pass paths or fill $REG)"; exit 0; }
if [ $GH = 1 ]; then
  if [ -z "${GH_TOKEN:-}" ] && [ -f "$CLAUDE_DIR/.loop-git-env" ]; then
    GH_TOKEN="$(grep -E '^(export )?GH_TOKEN=' "$CLAUDE_DIR/.loop-git-env" | head -1 | sed -E 's/^(export )?GH_TOKEN=//; s/^"//; s/"$//')"; export GH_TOKEN
  fi
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 || { echo "--gh: gh not authenticated (set GH_TOKEN or gh auth login); continuing without PR data"; GH=0; }
fi

tag() { if [ $APPLY = 1 ]; then echo "  [DO]   $*"; else echo "  [PLAN] $*"; fi; }
info() { echo "  [INFO] $*"; }
warn() { echo "  [OP]   $*"; }
run() { [ $APPLY = 1 ] && "$@"; }

main_of() {
  local m; m="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"
  [ -z "$m" ] && { git -C "$1" show-ref -q refs/heads/main && m=main || m=master; }
  echo "$m"
}
merged_into_main() { # repo branch main
  local r="$1" b="$2" m="$3"
  git -C "$r" merge-base --is-ancestor "$b" "$m" 2>/dev/null && return 0
  git -C "$r" show-ref -q "refs/remotes/origin/$m" && git -C "$r" merge-base --is-ancestor "$b" "origin/$m" 2>/dev/null && return 0
  return 1
}
pushed() {
  local r="$1" b="$2"
  git -C "$r" show-ref -q "refs/remotes/origin/$b" || return 1
  git -C "$r" merge-base --is-ancestor "$b" "origin/$b" 2>/dev/null
}
unique_count() { git -C "$1" rev-list --count "$3..$2" 2>/dev/null || echo 999; }
pr_merged() { [ -n "$MERGED_HEADS" ] && echo "$MERGED_HEADS" | grep -qx "$1"; }
pr_open() { [ -n "$OPEN_HEADS" ] && echo "$OPEN_HEADS" | grep -qx "$1"; }

wt_remove() { # $1=worktree path (as registered)  -> 0 on success
  local wt="$1" owner="$2" g
  if [ -f "$wt/.git" ]; then # use the primary path the worktree itself records (bind-mount safe)
    g="$(sed -n 's/^gitdir: //p' "$wt/.git" | head -1)"; g="${g%/.git/worktrees/*}"; [ -d "$g/.git" ] && owner="$g"
  fi
  git -C "$owner" worktree unlock "$wt" >/dev/null 2>&1
  git -C "$owner" worktree remove --force "$wt" >/dev/null 2>&1 && return 0
  git -C "$owner" worktree remove --force --force "$wt" >/dev/null 2>&1 && return 0
  # registration gone or aliased beyond git's tolerance: the tree was verified clean, drop it
  rm -rf "$wt" 2>/dev/null; git -C "$owner" worktree prune >/dev/null 2>&1
  [ -e "$wt" ] && return 1 || return 0
}

gc_repo() {
  local R="$1"
  [ -d "$R" ] || { echo "## $R"; warn "registry path does not exist -- remove it from $REG"; return; }
  git -C "$R" rev-parse --git-dir >/dev/null 2>&1 || { echo "## $R"; warn "not a git repo (stray loop state?): $(ls -a "$R" | grep -E 'TASKS.md|PROGRESS.md|\.claude-runs|\.phalanx' | tr '\n' ' ')"; return; }
  local common; common="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  local top; top="$(dirname "$common")"
  local M; M="$(main_of "$top")"
  MERGED_HEADS=""; OPEN_HEADS=""
  if [ $GH = 1 ]; then
    local slug; slug="$(git -C "$top" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]##; s#\.git$##')"
    if [ -n "$slug" ]; then
      MERGED_HEADS="$(timeout 90 gh pr list -R "$slug" --state merged --limit 1000 --json headRefName -q '.[].headRefName' 2>/dev/null | sort -u)"
      OPEN_HEADS="$(timeout 60 gh pr list -R "$slug" --state open --limit 500 --json headRefName -q '.[].headRefName' 2>/dev/null | sort -u)"
    fi
  fi
  local out; out="$(mktemp)"
  {
  local pr; pr="$(git -C "$top" worktree list --porcelain | grep -c '^prunable' || true)"
  [ "$pr" -gt 0 ] && tag "worktree prune ($pr prunable)"
  run git -C "$top" worktree prune

  # B. worktrees
  local wt br st lk reason
  while IFS= read -r line; do
    wt="${line%% *}"; [ "$wt" = "$top" ] && continue
    [ "$(readlink -f "$wt" 2>/dev/null)" = "$(readlink -f "$top")" ] && continue
    [ -d "$wt" ] || continue
    br="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
    st="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l)"
    lk="$(git -C "$top" worktree list --porcelain | awk -v w="$wt" '$0=="worktree "w{f=1} f&&/^locked/{print "locked";exit} f&&/^$/{exit}')"
    reason=""
    if [ "$st" -gt 0 ]; then warn "worktree KEEP (dirty $st files) $wt [$br]"; continue; fi
    if [ "$br" = DETACHED ]; then reason="detached+clean"
    elif [[ "$br" == worktree-* ]] && [ "$(unique_count "$top" "$br" "$M")" = 0 ]; then reason="throwaway $br, 0 unique commits"
    elif merged_into_main "$top" "$br" "$M"; then reason="$br merged into $M"
    elif pr_merged "$br"; then reason="$br PR merged (squash)"
    elif pushed "$top" "$br"; then reason="$br fully pushed to origin (branch kept)"
    else warn "worktree KEEP (clean but $br unmerged+unpushed, $(unique_count "$top" "$br" "$M") unique commits$(pr_open "$br" && echo ', PR OPEN')) $wt"; continue
    fi
    tag "worktree remove $wt ($reason${lk:+, unlock first})"
    [ $APPLY = 1 ] && { wt_remove "$wt" "$top" || warn "worktree remove FAILED $wt (root-owned files? rm as root, then git worktree prune)"; }
  done < <(git -C "$top" worktree list | awk '{print $1}')
  run git -C "$top" worktree prune

  # C/D. branches
  local checked; checked="$(git -C "$top" worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2);print $2}')"
  local b uc n_merged=0 n_pr=0 n_throw=0 n_open=0
  while IFS= read -r b; do
    [ -z "$b" ] && continue; [ "$b" = "$M" ] && continue
    echo "$checked" | grep -qx "$b" && continue
    if [[ "$b" == worktree-* ]]; then
      uc="$(unique_count "$top" "$b" "$M")"
      if [ "$uc" = 0 ]; then n_throw=$((n_throw+1)); run git -C "$top" branch -D "$b" >/dev/null 2>&1
      else warn "throwaway branch $b has $uc unique commits (work landed on the CLI's scratch branch?) -- inspect: git log $M..$b"; fi
      continue
    fi
    if merged_into_main "$top" "$b" "$M"; then n_merged=$((n_merged+1)); run git -C "$top" branch -D "$b" >/dev/null 2>&1
    elif pr_merged "$b"; then n_pr=$((n_pr+1)); run git -C "$top" branch -D "$b" >/dev/null 2>&1
    elif pr_open "$b"; then n_open=$((n_open+1)); fi
  done < <(git -C "$top" branch --format='%(refname:short)')
  [ $n_merged -gt 0 ] && tag "delete $n_merged local branches merged into $M"
  [ $n_pr -gt 0 ] && tag "delete $n_pr local branches whose PR is MERGED (squash)"
  [ $n_throw -gt 0 ] && tag "delete $n_throw throwaway worktree-* branches (0 unique commits)"
  [ $n_open -gt 0 ] && info "$n_open branches have an OPEN PR (review backlog)"
  local unm; unm="$(git -C "$top" branch --no-merged "$M" --format='%(refname:short)' | grep -vc '^worktree-' || true)"
  [ $APPLY = 0 ] && [ "$unm" -gt 0 ] && info "$unm unmerged branches before this run (triage: git branch --no-merged $M)"
  [ $APPLY = 1 ] && { unm="$(git -C "$top" branch --no-merged "$M" --format='%(refname:short)' | grep -vc '^worktree-' || true)"; [ "$unm" -gt 0 ] && info "$unm unmerged branches remain (operator triage: git branch --no-merged $M)"; }
  if [ $GH = 1 ] && [ -n "$MERGED_HEADS" ]; then
    local rstale; rstale="$(git -C "$top" branch -r --format='%(refname:short)' | sed 's|^origin/||' | grep -vx "$M\|HEAD" | grep -Fxf <(echo "$MERGED_HEADS") | wc -l)"
    [ "$rstale" -gt 0 ] && warn "$rstale REMOTE branches with merged PRs still on origin (enable delete_branch_on_merge, or: git push origin --delete <branch>)"
  fi

  # E. run logs
  if [ -d "$top/.claude-runs" ]; then
    local old; old="$(find "$top/.claude-runs" -maxdepth 1 \( -name 'run-*' -o -name 'pass-*.log' \) -mtime +"$KEEP_DAYS" | wc -l)"
    [ "$old" -gt 0 ] && tag "delete $old .claude-runs entries older than ${KEEP_DAYS}d"
    [ $APPLY = 1 ] && find "$top/.claude-runs" -maxdepth 1 \( -name 'run-*' -o -name 'pass-*.log' \) -mtime +"$KEEP_DAYS" -exec rm -rf {} +
    [ -f "$top/.claude-runs/BLOCKED" ] && warn "BLOCKED sentinel ($(( ( $(date +%s) - $(stat -c %Y "$top/.claude-runs/BLOCKED") ) / 86400 ))d old): $(head -c 160 "$top/.claude-runs/BLOCKED" | tr '\n' ' ')"
  fi

  # F. primary tree
  local pb pst; pb="$(git -C "$top" symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"; pst="$(git -C "$top" status --porcelain | wc -l)"
  if [ "$pb" != "$M" ]; then
    if [ "$pst" = 0 ] && { merged_into_main "$top" "$pb" "$M" || pr_merged "$pb"; }; then tag "primary tree: checkout $M (was $pb, clean, merged)"; run git -C "$top" checkout -q "$M"
    else warn "primary tree on $pb (dirty=$pst, $(merged_into_main "$top" "$pb" "$M" && echo merged || echo unmerged)) -- loop expects $M"; fi
  fi
  local ab; ab="$(git -C "$top" rev-list --left-right --count "$M...origin/$M" 2>/dev/null | tr '\t' '/')"
  [ -n "$ab" ] && [ "$ab" != "0/0" ] && info "$M ahead/behind origin = $ab"

  # G. stashes
  local sc; sc="$(git -C "$top" stash list | wc -l)"
  [ "$sc" -gt 0 ] && info "$sc stashes (oldest: $(git -C "$top" stash list --format='%cr %gs' | tail -1 | head -c 100))"
  # H. two backlogs
  if [ -f "$top/TASKS.md" ] && [ -d "$top/docs/claude/in-progress.d" ]; then
    warn "TWO backlogs: TASKS.md ($(grep -c '^- \[ \]' "$top/TASKS.md") open) AND docs/claude/in-progress.d ($(ls "$top/docs/claude/in-progress.d" | wc -l) files) -- loop reads TASKS.md only"
  fi
  } > "$out" 2>&1
  if [ -s "$out" ] || [ -z "${PHALANX_GC_QUIET:-}" ]; then echo "## $top ($M)"; cat "$out"; fi
  rm -f "$out"
}
for r in "${REPOS[@]}"; do gc_repo "$r"; done
[ $APPLY = 1 ] || echo "(dry run -- rerun with --apply for the safe tier; add --gh to use PR state)"
