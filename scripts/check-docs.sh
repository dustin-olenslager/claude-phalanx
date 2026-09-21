#!/usr/bin/env sh
# check-docs.sh — the landing gate: no code change may land without its doc update in the same commit.
#
# Enforces the "same-change update contract" (.claude/rules/documentation.md) mechanically: a commit
# that changes any non-doc file (source, config, schema, scripts, CI) must also change the worklog
# target in the SAME commit. This is the provider-neutral floor — it binds every agent in every tool,
# because it runs in required CI (scripts/templates/ci-verify.yml) and, for convenience, in the
# pre-commit hook.
#
#   sh scripts/check-docs.sh              # check the staged changes (pre-commit context)
#   sh scripts/check-docs.sh --since REF  # check every commit in REF..HEAD (CI context)
#
# Worklog target: CHANGELOG.md / HISTORY.md if present, else docs/claude/worklog.md.
# Override with DOCS_WORKLOG=<path>. "Doc" files are exempt from the mandatory line; the exempt
# extensions default to `md` and are overridable via DOCS_EXEMPT (space-separated, e.g. `md rst adoc`).
# A repo whose product IS markdown (a docs site, a blog) must set DOCS_EXEMPT to empty so shipped .md
# changes are treated as code. POSIX sh, no runtime deps.
#
# The gate enforces PRESENCE, not CORRECTNESS: a garbage worklog line passes. Correctness is a review
# problem, not an automation problem — the honest limit of any git-native kit.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- worklog target ---
WORKLOG="${DOCS_WORKLOG:-}"
if [ -z "$WORKLOG" ]; then
  if [ -f CHANGELOG.md ]; then WORKLOG="CHANGELOG.md"
  elif [ -f HISTORY.md ]; then WORKLOG="HISTORY.md"
  elif [ -f docs/claude/worklog.md ]; then WORKLOG="docs/claude/worklog.md"
  else
    echo "check-docs: no worklog target (CHANGELOG.md / HISTORY.md / docs/claude/worklog.md)" >&2
    exit 1
  fi
fi

# --- exempt (doc) extensions ---
DOCS_EXEMPT="${DOCS_EXEMPT:-md}"

# A file is "code" if its extension is not in DOCS_EXEMPT. Deleted files count too (they are changes).
is_code() {
  ext="${1##*.}"
  case " $DOCS_EXEMPT " in
    *" $ext "*) return 1;;   # doc — exempt
    *) return 0;;            # code
  esac
}

# check_files <label>: read newline-delimited paths on stdin; fail if code changed but the worklog did not.
check_files() {
  label="$1"
  changed_code=0; touched_worklog=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "$WORKLOG" ] && touched_worklog=1
    is_code "$f" && changed_code=1
  done
  if [ "$changed_code" -eq 1 ] && [ "$touched_worklog" -eq 0 ]; then
    echo "check-docs: $label changed code but not $WORKLOG" >&2
    echo "  add a line to $WORKLOG in the same commit (see .claude/rules/documentation.md)" >&2
    return 1
  fi
  return 0
}

fail=0

if [ "${1:-}" = "--since" ]; then
  ref="${2:?usage: check-docs.sh --since <ref>}"
  git rev-parse --verify "$ref^{commit}" >/dev/null 2>&1 || {
    echo "check-docs: ref '$ref' not found — cannot verify doc currency" >&2
    exit 1
  }
  for sha in $(git rev-list "$ref"..HEAD); do
    [ "$(git rev-list --no-walk --count --merges "$sha")" -eq 0 ] || continue
    git show --name-only --format= "$sha" 2>/dev/null | check_files "commit $sha" || fail=1
  done
else
  git diff --cached --name-only 2>/dev/null | check_files "staged change" || fail=1
fi

[ "$fail" -eq 0 ] && echo "check-docs: OK"
exit "$fail"
