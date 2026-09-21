#!/usr/bin/env bash
# Regression test for scripts/plan-contract-drift.sh — the fleet audit must fail on a repo whose
# agent kit exists ON DISK but is NOT COMMITTED. That is the exact gap that let claude-phalanx
# report "conforming" for weeks while all 43 of its own kit files sat untracked on main: the audit
# checked existence, not tracked-ness, so a fresh clone / CI runner / other harness saw nothing.
# Builds throwaway git repos under a temp dir and asserts on the report. Touches nothing real.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT="$HERE/plan-contract-drift.sh"
FAIL=0
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1" >&2; FAIL=1; }

[ -f "$DRIFT" ] || { fail "0: plan-contract-drift.sh not found next to this test"; exit 1; }

# mk_kit <dir> — lay the whole contract down on disk (uncommitted).
mk_kit() {
  local r="$1"
  mkdir -p "$r/docs/claude" "$r/.claude/rules" "$r/scripts" "$r/.cursor/rules" "$r/.github"
  printf '# roadmap\n'   > "$r/docs/claude/roadmap.md"
  printf '# queue\n'     > "$r/docs/claude/in-progress.md"
  printf '# worklog\n'   > "$r/docs/claude/worklog.md"
  printf '# AGENTS\n<!-- MIRROR:start -->\nrules\n<!-- MIRROR:end -->\n' > "$r/AGENTS.md"
  printf 'rule body\n'   > "$r/.claude/rules/code-style.md"
  printf '#!/bin/sh\necho sync\n' > "$r/scripts/sync-agents.sh"
  printf 'mirror\n'      > "$r/.cursor/rules/00-preamble.mdc"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t )
}

# run <dir> — audit one repo; sets $OUT (stdout) and $RC (exit code).
run() { OUT="$(sh "$DRIFT" "$1" 2>/dev/null)"; RC=$?; }

has() { printf '%s\n' "$OUT" | grep -q "$1"; }

# 1) everything committed -> conforms, exit 0, all hard columns ok
mk_kit "$WORK/good"
( cd "$WORK/good" && git add -A >/dev/null && git commit -qm "kit committed" )
run "$WORK/good"
[ "$RC" -eq 0 ] || fail "1a: committed kit should conform, exit=$RC"
has '^good *ok *ok *ok *ok *ok *ok' || fail "1b: expected an all-ok row"

# 2) THE REGRESSION: plan docs committed, kit left untracked -> drift, exit 1, named in notes
mk_kit "$WORK/bad"
( cd "$WORK/bad" && git add docs/claude/roadmap.md docs/claude/worklog.md >/dev/null \
    && git commit -qm "plan docs only" )
run "$WORK/bad"
[ "$RC" -eq 1 ] || fail "2a: untracked kit must be drift, exit=$RC"
has 'kit=UNTRACKED'     || fail "2b: notes must name kit=UNTRACKED"
has 'agents=UNTRACKED'  || fail "2c: notes must name agents=UNTRACKED"
has 'mirror=UNTRACKED'  || fail "2d: notes must name mirror=UNTRACKED"

# 3) kit absent altogether -> MISSING, not a silent ok
mk_kit "$WORK/none"
( cd "$WORK/none" && rm -rf .claude .cursor scripts/sync-agents.sh \
    && git add -A >/dev/null && git commit -qm "plan docs only, no kit" )
run "$WORK/none"
[ "$RC" -eq 1 ] || fail "3a: absent kit must be drift, exit=$RC"
has 'kit=MISSING'    || fail "3b: notes must name kit=MISSING"
has 'mirror=MISSING' || fail "3c: notes must name mirror=MISSING"

# 4) an untracked roadmap is still caught (behaviour that predates the kit columns)
mk_kit "$WORK/noroadmap"
( cd "$WORK/noroadmap" && git add AGENTS.md .claude .cursor scripts docs/claude/worklog.md >/dev/null \
    && git commit -qm "everything but the roadmap" )
run "$WORK/noroadmap"
[ "$RC" -eq 1 ] || fail "4a: untracked roadmap must be drift, exit=$RC"
has 'roadmap=UNTRACKED' || fail "4b: notes must name roadmap=UNTRACKED"

# 5) soft findings are reported but never fail the run (queue view untracked, no CI workflow)
mk_kit "$WORK/soft"
( cd "$WORK/soft" && git add AGENTS.md .claude .cursor scripts docs/claude/roadmap.md \
    docs/claude/worklog.md >/dev/null && git commit -qm "kit committed, queue view left out" )
run "$WORK/soft"
[ "$RC" -eq 0 ] || fail "5a: soft findings must not fail the audit, exit=$RC"
has 'soft: queue-untracked' || fail "5b: untracked queue view must be reported as a soft note"
has 'no-ci-workflow'        || fail "5c: a repo with no workflow must be reported as a soft note"

# 6) CHANGELOG.md counts as the worklog target (no docs/claude/worklog.md needed)
mk_kit "$WORK/chlog"
( cd "$WORK/chlog" && rm -f docs/claude/worklog.md && printf '# Changelog\n' > CHANGELOG.md \
    && git add -A >/dev/null && git commit -qm "kit committed, CHANGELOG as worklog" )
run "$WORK/chlog"
[ "$RC" -eq 0 ] || fail "6a: CHANGELOG.md must satisfy the worklog column, exit=$RC"
has '^chlog *ok *ok *ok *ok *ok *ok' || fail "6b: expected an all-ok row for the CHANGELOG repo"

# 7) a path that is not a git repo is drift, not a crash
mkdir -p "$WORK/notrepo"
run "$WORK/notrepo"
[ "$RC" -eq 1 ] || fail "7a: non-repo path must be drift, exit=$RC"
has 'NOT A GIT REPO' || fail "7b: non-repo path must be labelled"

if [ "$FAIL" -eq 0 ]; then echo "  plan-contract-drift: all assertions passed"; else exit 1; fi
