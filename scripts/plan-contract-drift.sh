#!/usr/bin/env sh
# plan-contract-drift.sh — read-only fleet audit of the shared plan-doc contract.
#
# The contract (/workspace/PANOPLY-OPTIMIZATION.md) says every project's plan lives in exactly one
# doc inside that project's repo: docs/claude/roadmap.md (strategic), docs/claude/in-progress.md
# (tactical, generated), a worklog target (CHANGELOG/HISTORY or docs/claude/worklog.md), and the
# per-task fragments docs/claude/in-progress.d/<slug>.md. This script reports, per repo in the
# contract's project→repo map, whether those files EXIST **and are GIT-TRACKED** — because an
# on-disk plan that is not committed is invisible to CI, to the Phalanx loop, and to the other
# harness.
#
# Tracked-ness covers the agent kit as well as the plan docs (added 2026-09-21): AGENTS.md, at least
# one tracked .claude/rules/ module, scripts/sync-agents.sh, and at least one generated mirror.
# Before this, the script only proved the files EXISTED, which is how claude-phalanx reported
# "conforming" with all 43 of its own kit files untracked on main — no fresh clone, no CI runner and
# no other harness could see any of it, and nothing in the fleet audit said so.
#
# Columns:
#   ROADMAP / QUEUE / WORKLOG / KIT / AGENTS   ok | MISSING | UNTRACKED
#   MIRROR                                     ok | no-mirror | MISSING | UNTRACKED
#   NOTES       hard findings first; after `|`, `soft:` findings. Soft notes never fail the run.
#
# Deliberately NOT hard requirements (each has a legitimate exception in the fleet today):
#   * docs/claude/in-progress.md tracked — PANOPLY §1a calls the queue a *generated view* that is
#     never committed; frame-forge follows that literally while 12 repos commit it. → soft
#     `queue-untracked`.
#   * .claude/settings.json tracked — it is the Claude-only permission gate and should be committed,
#     but two repos still lag. → soft `settings-untracked`.
#   * the two kit gates wired into CI — levio/plexo wire them into ci.yml rather than a verify.yml,
#     and fylo has a *recorded operator decision* not to wire them at all. → soft `gates-not-wired`
#     / `no-ci-workflow`.
#
# READ-ONLY: it never writes to a repo. It prints one line per repo and exits nonzero if any
# required artifact is missing or untracked. It is advisory — the operator acts on the report;
# it does not gate a merge. It audits each repo's CURRENT checkout (index + HEAD), so a repo left
# on a feature branch is audited as that branch, not as its default branch.
#
#   sh scripts/plan-contract-drift.sh            # audit the default fleet
#   sh scripts/plan-contract-drift.sh /workspace/foo   # audit one repo
#   REPOS="/a /b" sh scripts/plan-contract-drift.sh     # audit an explicit list
set -eu

# The project→repo map is the source of truth in PANOPLY-OPTIMIZATION.md §2. This list mirrors it;
# a repo moved/added there must be reflected here (and vice-versa — reconcile against the doc).
# flutter was removed from §2 on 2026-09-19: /workspace/flutter is a pristine upstream
# flutter/flutter clone (branch `stable`), not a Joeybuilt project — the kit landed there by mistake.
DEFAULT_REPOS="claude-code-factory claude-phalanx depona fonto frame-forge fylo \
hive-edge-fallback levio nexalog ordica platform plexo pushd"

if [ "$#" -gt 0 ]; then
  REPOS="$*"
else
  REPOS="${REPOS:-$DEFAULT_REPOS}"
fi

ROOT="/workspace"
fail=0

# is_tracked <repo> <path> [<path>…] — true only if EVERY path is in that repo's index.
is_tracked() {
  _r="$1"; shift
  for _p in "$@"; do
    if [ -z "$(git -C "$_r" ls-files -- "$_p" 2>/dev/null)" ]; then
      return 1
    fi
  done
  return 0
}

# count_tracked <repo> <pathspec> — how many indexed files match.
count_tracked() {
  git -C "$1" ls-files -- "$2" 2>/dev/null | wc -l | tr -d ' '
}

# any_exists <repo> <path> [<path>…] — true if at least one path is present on disk.
any_exists() {
  _r="$1"; shift
  for _p in "$@"; do
    if [ -e "$_r/$_p" ]; then return 0; fi
  done
  return 1
}

# row <repo> <roadmap> <queue> <worklog> <kit> <agents> <mirror> <notes>
row() {
  printf "%-22s %-9s %-9s %-9s %-9s %-9s %-11s %s\n" \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}

row REPO ROADMAP QUEUE WORKLOG KIT AGENTS MIRROR NOTES

for name in $REPOS; do
  # Accept a bare repo name (resolved under ROOT) or an absolute/relative path.
  case "$name" in
    /*|./*) repo="$name" ;;
    *)      repo="$ROOT/$name" ;;
  esac
  label="$(basename "$repo")"
  if [ ! -d "$repo/.git" ]; then
    row "$label" "-" "-" "-" "-" "-" "-" "NOT A GIT REPO"
    fail=1
    continue
  fi

  # --- plan artifacts: do they exist? ---
  roadmap="ok"
  [ -f "$repo/docs/claude/roadmap.md" ] || roadmap="MISSING"
  queue="ok"
  [ -f "$repo/docs/claude/in-progress.md" ] || queue="MISSING"
  wl=""
  if   [ -f "$repo/CHANGELOG.md" ];            then wl="CHANGELOG.md"
  elif [ -f "$repo/HISTORY.md" ];              then wl="HISTORY.md"
  elif [ -f "$repo/docs/claude/worklog.md" ];  then wl="docs/claude/worklog.md"
  fi
  worklog="ok"
  [ -n "$wl" ] || worklog="MISSING"

  # --- plan artifacts: are they committed? (the failure mode this script exists for) ---
  if [ "$roadmap" = "ok" ] && ! is_tracked "$repo" docs/claude/roadmap.md; then
    roadmap="UNTRACKED"
  fi
  if [ "$worklog" = "ok" ] && ! is_tracked "$repo" "$wl"; then
    worklog="UNTRACKED"
  fi

  # --- the agent kit: rule modules + the generator that keeps the mirrors honest ---
  kit="ok"
  n_rules="$(count_tracked "$repo" .claude/rules)"
  sync_tracked=0
  if is_tracked "$repo" scripts/sync-agents.sh; then sync_tracked=1; fi
  if [ "$n_rules" -eq 0 ] || [ "$sync_tracked" -eq 0 ]; then
    if [ -d "$repo/.claude/rules" ] || [ -f "$repo/scripts/sync-agents.sh" ]; then
      kit="UNTRACKED"
    else
      kit="MISSING"
    fi
  fi

  # --- agent contract: AGENTS.md itself, its MIRROR marker, and the mirrors it generates ---
  agents="ok"
  [ -f "$repo/AGENTS.md" ] || agents="MISSING"
  if [ "$agents" = "ok" ] && ! is_tracked "$repo" AGENTS.md; then
    agents="UNTRACKED"
  fi
  mirror="ok"
  grep -q 'MIRROR:start' "$repo/AGENTS.md" 2>/dev/null || mirror="no-mirror"
  if [ "$mirror" = "ok" ]; then
    n_mirrors="$(git -C "$repo" ls-files -- .cursor .clinerules .windsurf \
      .github/copilot-instructions.md GEMINI.md CONVENTIONS.md 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n_mirrors" -eq 0 ]; then
      if any_exists "$repo" .cursor .clinerules .windsurf .github/copilot-instructions.md \
                    GEMINI.md CONVENTIONS.md; then
        mirror="UNTRACKED"
      else
        mirror="MISSING"
      fi
    fi
  fi

  # --- soft findings: real gaps, but each has a legitimate exception somewhere in the fleet ---
  soft=""
  if [ "$queue" = "ok" ] && ! is_tracked "$repo" docs/claude/in-progress.md; then
    soft="$soft queue-untracked"
  fi
  if [ -f "$repo/.claude/settings.json" ] && ! is_tracked "$repo" .claude/settings.json; then
    soft="$soft settings-untracked"
  fi
  if [ "$(count_tracked "$repo" .github/workflows)" -eq 0 ]; then
    soft="$soft no-ci-workflow"
  else
    wired_sync=0; wired_docs=0
    for wf in $(git -C "$repo" ls-files -- .github/workflows 2>/dev/null); do
      if git -C "$repo" show "HEAD:$wf" 2>/dev/null | grep -q 'sync-agents\.sh'; then wired_sync=1; fi
      if git -C "$repo" show "HEAD:$wf" 2>/dev/null | grep -q 'check-docs\.sh';  then wired_docs=1; fi
    done
    if [ "$wired_sync" -eq 0 ] || [ "$wired_docs" -eq 0 ]; then
      soft="$soft gates-not-wired"
    fi
  fi

  # --- assemble the row ---
  notes=""
  [ "$roadmap" = "ok" ] || notes="$notes roadmap=$roadmap"
  [ "$queue"   = "ok" ] || notes="$notes queue=$queue"
  [ "$worklog" = "ok" ] || notes="$notes worklog=$worklog"
  [ "$kit"     = "ok" ] || notes="$notes kit=$kit"
  [ "$agents"  = "ok" ] || notes="$notes agents=$agents"
  [ "$mirror"  = "ok" ] || notes="$notes mirror=$mirror"

  shown="$(printf '%s' "$notes" | sed 's/^ //')"
  softs="$(printf '%s' "$soft"  | sed 's/^ //')"
  if [ -n "$softs" ]; then
    if [ -n "$shown" ]; then shown="$shown | soft: $softs"; else shown="soft: $softs"; fi
  fi

  hard_ok=1
  for v in "$roadmap" "$worklog" "$kit" "$agents" "$mirror"; do
    [ "$v" = "ok" ] || hard_ok=0
  done
  [ "$hard_ok" -eq 1 ] || fail=1
  row "$label" "$roadmap" "$queue" "$worklog" "$kit" "$agents" "$mirror" "$shown"
done

echo
if [ "$fail" -eq 1 ]; then
  echo "drift detected — see rows above; this script is advisory and changed nothing." >&2
  exit 1
fi
echo "all repos conform to the plan-doc contract (hard columns; check 'soft:' notes above)." >&2
