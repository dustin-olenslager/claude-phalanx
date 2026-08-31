#!/usr/bin/env bash
# Regressions around the cross-pass verify flag (.claude-runs/verified.<branch>).
#
# The SINGLE writer is `phalanx-verify`, which records the child command's EXIT CODE.
# Until 2026-08-31 the writer was pipeline-gate.js itself — a PreToolUse hook, i.e. it
# fired BEFORE the command ran, so it recorded intent, not outcome: `npm test` marked
# the branch green whether the suite passed, failed, or died at startup, and rule 5b/5c
# would then pass a red branch through to commit and automerge. Cases D and E below are
# the guards for that; case A keeps the 2026-07-02 guard (a flag must still be writable
# while .pipeline-off is set, or automerge deadlocks fleet-wide) pointed at the new writer.
# No frameworks. Copies the gate to a throwaway dir so .pipeline-off never touches the repo.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

G="$T/gates"; mkdir -p "$G/lib"
cp "$REPO/hooks/gates/pipeline-gate.js" "$G/"
cp "$REPO/hooks/gates/lib/phalanx-hook.js" "$G/lib/"
GATE="$G/pipeline-gate.js"

R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$R" checkout -q -b task/x
FLAG="$R/.claude-runs/verified.task_x"

run() { printf '%s' "$1" | env -u PHALANX_WARN node "$GATE"; }
REC="$REPO/scripts/phalanx-verify"

# A) .pipeline-off SET + recorder green -> flag MUST still be written (the deadlock bug)
touch "$G/.pipeline-off"; rm -f "$FLAG"
( cd "$R" && "$REC" true ) >/dev/null 2>&1 || true
[ -f "$FLAG" ] || fail "A: verify flag not written while .pipeline-off set (the deadlock)"

# B) .pipeline-off SET + git commit w/o verify -> must NOT be blocked
out="$(run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$R\",\"session_id\":\"s2\"}")"
echo "$out" | grep -q '"permissionDecision":"deny"' && fail "B: commit blocked while .pipeline-off set"

# C) .pipeline-off UNSET + git commit w/o verify -> must be blocked (blocking still works).
#    Clear the flag case A wrote: the gate now reads the REPO flag, which outlives a
#    session id, so "no verify" has to mean no flag on disk.
rm -f "$G/.pipeline-off" "$FLAG"
out="$(run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$R\",\"session_id\":\"s3\"}")"
echo "$out" | grep -q '"permissionDecision":"deny"' || fail "C: commit NOT blocked with pipeline ON (no verify)"

# D) a BARE verify command must NOT write the flag. This is the fail-open: a PreToolUse
#    hook cannot know the outcome, so seeing the command is not evidence it passed.
rm -f "$FLAG"
run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm run typecheck\"},\"cwd\":\"$R\",\"session_id\":\"s4\"}" >/dev/null
[ -f "$FLAG" ] && fail "D: bare verify command wrote the flag (fail-open: intent recorded as outcome)"

# E) a RED recorder run must REVOKE a standing green, not leave it up.
( cd "$R" && "$REC" true ) >/dev/null 2>&1 || true
[ -f "$FLAG" ] || fail "E: recorder green did not write the flag"
( cd "$R" && "$REC" false ) >/dev/null 2>&1 || true
[ -f "$FLAG" ] && fail "E: red recorder run left a green flag standing"

echo "PASS: recorder is the only writer (exit-code keyed); .pipeline-off cannot starve it; blocking intact (5 cases)"
