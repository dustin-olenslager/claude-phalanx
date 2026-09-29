#!/usr/bin/env bash
# phalanx-project.sh — apply and verify the Phalanx standard in ONE project, for ANY agent.
#
# Why this exists: Phalanx's gates live in Claude Code's `settings.json`, its anchors in `CLAUDE.md`,
# and its git hooks scope themselves to `*claude-phalanx*` checkouts. So a Hermes, Codex, Cursor or
# CI agent working in your project gets none of it, and neither does a Claude session that has not
# installed Phalanx globally. This script is the per-repo half: it writes the project-local surfaces
# a coding agent actually reads, installs a repo-local guard, and runs the verification.
#
#   scripts/phalanx-project.sh check  [dir]   exit 0 = applied & current
#                                             10 = not applied · 11 = partial · 12 = drifted
#   scripts/phalanx-project.sh apply  [dir]   idempotent; never clobbers your files
#   scripts/phalanx-project.sh verify [dir]   run the repo's gates (the STANDARD gate, unfiltered)
#   scripts/phalanx-project.sh stamp  [dir]   write/refresh .phalanx-project
#
# Env: PHALANX_PROJECT_OFF=1 disables check (adopting repo mid-migration).
#      PHALANX_NO_GUARDS=1    skips the repo-local leak guard.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${2:-$PWD}"
[ -d "$DIR" ] || { echo "phalanx-project: no such directory: $DIR" >&2; exit 2; }
DIR="$(cd "$DIR" && pwd)"

STAMP=".phalanx-project"
CONTRACT="AGENTS.phalanx.md"
RULES_DIR=".phalanx"
GUARD_DIR=".githooks"

_kit_version() {
  v="$(git -C "$HERE" describe --tags --abbrev=0 2>/dev/null || true)"
  [ -n "$v" ] || v="$(git -C "$HERE" tag --sort=-v:refname 2>/dev/null | head -1 || true)"
  [ -n "$v" ] || v="unreleased"
  printf '%s' "$v"
}
_kit_sha() { git -C "$HERE" rev-parse --short HEAD 2>/dev/null || printf 'unknown'; }

# ---------------------------------------------------------------- check ----
# Emits "STATUS<tab>reason"; the caller maps that to an exit code.
_inspect() {
  _st="current"; _why=""

  if [ ! -f "$STAMP" ]; then
    if [ -f "$CONTRACT" ] || [ -d "$RULES_DIR" ]; then
      _st="partial"; _why="surfaces present but no $STAMP stamp"
    else
      _st="absent"; _why="no Phalanx project surfaces found"
    fi
  else
    _want="$(_kit_version)"
    _got="$(sed -n 's/^phalanx_version:[[:space:]]*//p' "$STAMP" | head -1)"
    if [ -n "$_got" ] && [ "$_got" != "$_want" ]; then
      _st="drifted"; _why="stamp says $_got, phalanx is $_want"
    fi
  fi

  # A stale contract (rule bodies changed upstream) is drift too.
  if [ "$_st" = "current" ] && [ -d "$RULES_DIR" ]; then
    for _f in workflow.md quality-bar.md git-workflow.md clean-architecture.md; do
      [ -f "$HERE/.claude/rules/$_f" ] || continue
      if [ -f "$RULES_DIR/$_f" ] && ! cmp -s "$HERE/.claude/rules/$_f" "$RULES_DIR/$_f"; then
        _st="drifted"; _why="$RULES_DIR/$_f differs from the shipped rule"
        break
      fi
    done
  fi

  printf '%s\t%s\n' "$_st" "$_why"
}

cmd_check() {
  if [ "${PHALANX_PROJECT_OFF:-0}" = "1" ]; then
    echo "phalanx-project: OFF (PHALANX_PROJECT_OFF=1)"; exit 0
  fi
  [ -d "$DIR/.git" ] || { echo "phalanx-project: $DIR is not a git working tree"; exit 0; }
  out="$(cd "$DIR" && _inspect)"
  st="$(printf '%s' "$out" | cut -f1)"; why="$(printf '%s' "$out" | cut -f2)"
  case "$st" in
    current) echo "phalanx-project: OK — Phalanx $(_kit_version) applied in $DIR"; exit 0 ;;
    absent)  echo "phalanx-project: NOT APPLIED — $why" >&2
             echo "  apply it:  $HERE/scripts/phalanx-project.sh apply $DIR" >&2; exit 10 ;;
    partial) echo "phalanx-project: PARTIAL — $why" >&2
             echo "  finish it:  $HERE/scripts/phalanx-project.sh apply $DIR" >&2; exit 11 ;;
    drifted) echo "phalanx-project: DRIFTED — $why" >&2
             echo "  refresh it:  $HERE/scripts/phalanx-project.sh apply $DIR" >&2; exit 12 ;;
    *)       echo "phalanx-project: unknown state $st" >&2; exit 1 ;;
  esac
}

# ---------------------------------------------------------------- apply ----
cmd_apply() {
  echo "==> phalanx-project apply — Phalanx $(_kit_version) -> $DIR"
  mkdir -p "$DIR/$RULES_DIR" "$DIR/$GUARD_DIR"

  # Rule modules: the four that bind every coding project. Never clobber an edited local copy.
  for f in workflow.md quality-bar.md git-workflow.md clean-architecture.md testing.md; do
    src="$HERE/.claude/rules/$f"
    [ -f "$src" ] || continue
    if [ ! -f "$DIR/$RULES_DIR/$f" ]; then
      cp "$src" "$DIR/$RULES_DIR/$f"; echo "    added $RULES_DIR/$f"
    elif ! cmp -s "$src" "$DIR/$RULES_DIR/$f"; then
      echo "    NOTE $RULES_DIR/$f differs from the shipped rule — yours wins; review the CHANGELOG"
    fi
  done

  # The provider-neutral contract an agent reads. Created only if absent; never overwrites.
  if [ ! -f "$DIR/$CONTRACT" ]; then
    cat > "$DIR/$CONTRACT" <<CONTRACT_EOF
# Phalanx project contract — $(basename "$DIR")

The Phalanx standard applies in this repository, for every agent and every harness — not only for
Claude Code. Read this before you write anything.

## The gates (run them; do not describe them)

    $(printf '%s' "$HERE")/scripts/phalanx-project.sh verify $DIR

Runs the project's own test/lint/typecheck entrypoints and Phalanx's checks, unfiltered, in this
session. A subagent's "done" is a claim; this is the evidence. Never merge on a report of green.

## The rules

- \`$RULES_DIR/workflow.md\` — plan first, present the plan, one branch per batch.
- \`$RULES_DIR/git-workflow.md\` — pre-flight, one open PR per repo, squash-merge, delete the branch.
- \`$RULES_DIR/quality-bar.md\` — the STANDARD gate before any merge.
- \`$RULES_DIR/clean-architecture.md\` — dependencies point inward, always.
- \`$RULES_DIR/testing.md\` — what "tested" means here.

## Status

    sh $(printf '%s' "$HERE")/scripts/phalanx-project.sh check $DIR

Exit 0 = current. 10 = not applied. 11 = partial. 12 = drifted. Disable with PHALANX_PROJECT_OFF=1.
CONTRACT_EOF
    echo "    added $CONTRACT"
  else
    echo "    NOTE $CONTRACT already exists — left untouched"
  fi

  # Repo-local leak guard, scoped to THIS repo (the global install path only guards phalanx itself).
  if [ "${PHALANX_NO_GUARDS:-0}" != "1" ]; then
    for h in pre-commit pre-push; do
      [ -f "$HERE/githooks/$h" ] && cp "$HERE/githooks/$h" "$DIR/$GUARD_DIR/$h" && chmod +x "$DIR/$GUARD_DIR/$h"
    done
    # A repo-local hooksPath, set only when git has none of its own — never take over a repo that
    # already points somewhere (husky/lefthook) without saying so.
    cur="$(git -C "$DIR" config --local --get core.hooksPath || true)"
    if [ -z "$cur" ]; then
      git -C "$DIR" config --local core.hooksPath "$GUARD_DIR"
      echo "    set repo-local core.hooksPath -> $GUARD_DIR"
    elif [ "$cur" != "$GUARD_DIR" ]; then
      echo "    NOTE core.hooksPath is '$cur' — left alone; add $GUARD_DIR to it if you want the guard"
    fi
  fi

  {
    printf '# phalanx project stamp — written by scripts/phalanx-project.sh (do not hand-edit)\n'
    printf 'phalanx_version: %s\n' "$(_kit_version)"
    printf 'phalanx_sha: %s\n' "$(_kit_sha)"
    printf 'applied_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'applied_by: %s\n' "${PHALANX_APPLIED_BY:-unknown-agent}"
  } > "$DIR/$STAMP"
  echo "    stamped $STAMP at $(_kit_version)"
}

# ---------------------------------------------------------------- verify ----
# The STANDARD gate. Prefers the project's OWN entrypoints (its package scripts, Makefile, or a
# verify.sh) over any tool we would guess, then falls back to Phalanx's own suite for THIS repo.
cmd_verify() {
  echo "==> phalanx-project verify — $DIR"
  cd "$DIR" || exit 1
  ran=0; fail=0

  # 1. The project's own gate, if it declares one.
  if [ -f package.json ] && command -v node >/dev/null 2>&1; then
    for s in verify check test; do
      if node -e "process.exit(require('./package.json').scripts&&require('./package.json').scripts['$s']?0:1)" 2>/dev/null; then
        echo "  -- npm run $s"; npm run --silent "$s" || fail=1; ran=1; break
      fi
    done
  fi
  if [ "$ran" = 0 ] && [ -f Makefile ] && grep -qE '^verify:' Makefile 2>/dev/null; then
    echo "  -- make verify"; make verify || fail=1; ran=1
  fi
  if [ "$ran" = 0 ] && [ -f scripts/verify.sh ]; then
    echo "  -- scripts/verify.sh"; bash scripts/verify.sh || fail=1; ran=1
  fi
  if [ "$ran" = 0 ]; then
    echo "  -- no project gate found (package.json verify/check/test, Makefile verify, scripts/verify.sh)"
    echo "     the STANDARD gate is a CLAIM until this repo declares one" >&2
  fi

  # 2. Phalanx's own checks that apply anywhere.
  [ -f "$HERE/scripts/check-docs.sh" ] && { echo "  -- check-docs"; sh "$HERE/scripts/check-docs.sh" >/dev/null 2>&1 || echo "     (check-docs reported findings)"; }
  if [ -f "$HERE/scripts/leak-scan.sh" ]; then
    echo "  -- leak-scan"; sh "$HERE/scripts/leak-scan.sh" . >/dev/null 2>&1 || { echo "     leak-scan FAILED"; fail=1; }
  fi

  [ "$fail" = 0 ] && { echo "PHALANX-PROJECT VERIFY: green"; exit 0; }
  echo "PHALANX-PROJECT VERIFY: FAILED" >&2; exit 1
}

cmd_stamp() { cmd_apply >/dev/null 2>&1; echo "stamped $DIR/$STAMP"; }

case "${1:-check}" in
  check|status) cmd_check ;;
  apply)        cmd_apply ;;
  verify)       cmd_verify ;;
  stamp)        cmd_stamp ;;
  *) echo "phalanx-project: unknown command ${1:-} (check | apply | verify | stamp)" >&2; exit 2 ;;
esac
