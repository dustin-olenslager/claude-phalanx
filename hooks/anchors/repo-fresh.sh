#!/usr/bin/env bash
# SessionStart: never start work from stale code. Two machines (workstation + server) share
# every repo through origin only, so the local checkout is a cache, not the truth.
#   * fetch --prune (8s cap; offline -> silent)
#   * main clean + behind + not ahead  -> fast-forward it, say so
#   * main behind but dirty/ahead/not checked out -> loud one-liner with the exact command
#   * current branch has commits origin cannot see -> say so (the other machine can't either)
# Read-only apart from the fast-forward, which cannot lose anything. Silent when current.
# Opt out per repo: touch .phalanx-no-fresh   Opt out globally: PHALANX_NO_FRESH=1
[ -n "${PHALANX_NO_FRESH:-}" ] && exit 0
top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$top/.phalanx-no-fresh" ] && exit 0
git -C "$top" remote get-url origin >/dev/null 2>&1 || exit 0
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 8s"
$TO git -C "$top" fetch -q --prune origin 2>/dev/null || { echo "[repo-fresh] origin unreachable -- local state may be stale"; exit 0; }
MAIN="$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"
[ -z "$MAIN" ] && { git -C "$top" show-ref -q refs/heads/main && MAIN=main || MAIN=master; }
git -C "$top" show-ref -q "refs/remotes/origin/$MAIN" || exit 0
cur="$(git -C "$top" symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
dirty="$(git -C "$top" status --porcelain 2>/dev/null | wc -l)"
lr="$(git -C "$top" rev-list --left-right --count "$MAIN...origin/$MAIN" 2>/dev/null)"; ahead="${lr%%	*}"; behind="${lr##*	}"; ahead="${ahead:-0}"; behind="${behind:-0}"
msgs=()
if [ "$behind" -gt 0 ]; then
  if [ "$cur" = "$MAIN" ] && [ "$dirty" = 0 ] && [ "$ahead" = 0 ]; then
    if git -C "$top" merge -q --ff-only "origin/$MAIN" >/dev/null 2>&1; then msgs+=("$MAIN fast-forwarded $behind commit(s) to $(git -C "$top" rev-parse --short "origin/$MAIN")")
    else msgs+=("$MAIN is $behind behind origin and could not fast-forward -- run: git pull --ff-only origin $MAIN"); fi
  else
    why=""; [ "$cur" != "$MAIN" ] && why="on $cur"; [ "$dirty" != 0 ] && why="${why:+$why, }$dirty uncommitted"; [ "$ahead" != 0 ] && why="${why:+$why, }$ahead local commits on $MAIN"
    msgs+=("STALE: $MAIN is $behind behind origin ($why) -- do not branch from it; git checkout $MAIN && git pull --ff-only origin $MAIN")
  fi
elif [ "$ahead" -gt 0 ]; then
  msgs+=("$MAIN has $ahead commit(s) origin does not -- the other machine cannot see them; push or move them to a branch")
fi
if [ "$cur" != "$MAIN" ] && [ "$cur" != DETACHED ]; then
  up="$(git -C "$top" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
  if [ -z "$up" ]; then
    n="$(git -C "$top" rev-list --count "origin/$MAIN..$cur" 2>/dev/null || echo 0)"
    [ "$n" -gt 0 ] && msgs+=("$cur: $n commit(s) never pushed -- invisible from the other machine; git push -u origin $cur")
  else
    ub="$(git -C "$top" rev-list --left-right --count "$cur...$up" 2>/dev/null)"; ua="${ub%%	*}"; ubh="${ub##*	}"
    [ "${ua:-0}" -gt 0 ] && msgs+=("$cur: ${ua} unpushed commit(s) -- git push")
    [ "${ubh:-0}" -gt 0 ] && msgs+=("$cur: ${ubh} commit(s) behind $up (edited elsewhere) -- git pull --ff-only before touching it")
  fi
fi
[ ${#msgs[@]} -eq 0 ] && exit 0
printf '[repo-fresh] %s\n' "${msgs[@]}"
