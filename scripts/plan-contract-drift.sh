#!/usr/bin/env sh
# plan-contract-drift.sh — read-only fleet audit of the shared plan-doc contract.
#
# The contract (/workspace/PANOPLY-OPTIMIZATION.md) says every project's plan lives in exactly one
# doc inside that project's repo: docs/claude/roadmap.md (strategic), docs/claude/in-progress.md
# (tactical, generated), a worklog target (CHANGELOG/HISTORY or docs/claude/worklog.md), and the
# per-task fragments docs/claude/in-progress.d/<slug>.md. This script reports, per repo in the
# contract's project→repo map, whether those files EXIST and are GIT-TRACKED — because an on-disk
# plan that is not committed is invisible to CI, to the Phalanx loop, and to the other harness.
#
# READ-ONLY: it never writes to a repo. It prints one line per repo and exits nonzero if any
# required artifact is missing or untracked. It is advisory — the operator acts on the report;
# it does not gate a merge.
#
#   sh scripts/plan-contract-drift.sh            # audit the default fleet
#   sh scripts/plan-contract-drift.sh /workspace/foo   # audit one repo
#   REPOS="/a /b" sh scripts/plan-contract-drift.sh     # audit an explicit list
set -eu

# The project→repo map is the source of truth in PANOPLY-OPTIMIZATION.md §2. This list mirrors it;
# a repo moved/added there must be reflected here (and vice-versa — reconcile against the doc).
DEFAULT_REPOS="claude-code-factory claude-phalanx depona flutter fonto frame-forge fylo \
hive-edge-fallback levio nexalog ordica platform plexo pushd"

if [ "$#" -gt 0 ]; then
  REPOS="$*"
else
  REPOS="${REPOS:-$DEFAULT_REPOS}"
fi

ROOT="/workspace"
fail=0

printf "%-22s %-8s %-8s %-9s %-9s %-9s %s\n" \
  REPO ROADMAP QUEUE WORKLOG AGENTS MIRROR NOTES

for name in $REPOS; do
  # Accept a bare repo name (resolved under ROOT) or an absolute/relative path.
  case "$name" in
    /*|./*) repo="$name" ;;
    *)      repo="$ROOT/$name" ;;
  esac
  label="$(basename "$repo")"
  [ -d "$repo/.git" ] || { printf "%-22s %-8s %-8s %-9s %-9s %-9s %s\n" \
      "$label" "-" "-" "-" "-" "-" "NOT A GIT REPO"; fail=1; continue; }

  # --- plan artifacts ---
  roadmap="ok";  [ -f "$repo/docs/claude/roadmap.md" ] || roadmap="MISSING"
  queue="ok";    [ -f "$repo/docs/claude/in-progress.md" ] || queue="MISSING"
  worklog="ok"
  if   [ -f "$repo/CHANGELOG.md" ]; then worklog="ok"
  elif [ -f "$repo/HISTORY.md" ];   then worklog="ok"
  elif [ -f "$repo/docs/claude/worklog.md" ]; then worklog="ok"
  else worklog="MISSING"; fi

  # --- git-tracked? (the real failure: on disk but never committed) ---
  if [ "$roadmap" = "ok" ] && [ -z "$(git -C "$repo" ls-files -- docs/claude/roadmap.md)" ]; then
    roadmap="UNTRACKED"
  fi
  if [ "$worklog" = "ok" ]; then
    wl=""
    if [ -f "$repo/CHANGELOG.md" ]; then wl="CHANGELOG.md"
    elif [ -f "$repo/HISTORY.md" ]; then wl="HISTORY.md"
    else wl="docs/claude/worklog.md"; fi
    [ -z "$(git -C "$repo" ls-files -- "$wl")" ] && worklog="UNTRACKED"
  fi

  # --- agent contract ---
  agents="ok"; [ -f "$repo/AGENTS.md" ] || agents="MISSING"
  mirror="ok"; grep -q 'MIRROR:start' "$repo/AGENTS.md" 2>/dev/null || mirror="no-mirror"

  notes=""
  [ "$roadmap" = "ok" ]      || { notes="$notes roadmap=$roadmap"; }
  [ "$queue" = "ok" ]        || { notes="$notes queue=$queue"; }
  [ "$worklog" = "ok" ]      || { notes="$notes worklog=$worklog"; }
  [ "$agents" = "ok" ]       || { notes="$notes agents=$agents"; }
  [ "$mirror" = "ok" ]       || { notes="$notes $mirror"; }

  status="ok"
  [ "$roadmap" = "ok" ] && [ "$worklog" = "ok" ] && [ "$agents" = "ok" ] && [ "$mirror" = "ok" ] \
    || status="DRIFT"

  if [ "$status" = "ok" ]; then
    printf "%-22s %-8s %-8s %-9s %-9s %-9s %s\n" "$label" ok ok ok ok ok ""
  else
    fail=1
    printf "%-22s %-8s %-8s %-9s %-9s %-9s %s\n" \
      "$label" "$roadmap" "$queue" "$worklog" "$agents" "$mirror" "$(echo "$notes" | sed 's/^ //')"
  fi
done

echo
if [ "$fail" -eq 1 ]; then
  echo "drift detected — see rows above; this script is advisory and changed nothing." >&2
  exit 1
fi
echo "all repos conform to the plan-doc contract." >&2
