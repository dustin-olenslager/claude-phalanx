#!/usr/bin/env bash
# Regression: pipeline-gate.js must WRITE the cross-pass verify flag even when
# .pipeline-off is set — .pipeline-off disables only the BLOCKING. pipeline-gate is
# the SINGLE writer of .claude-runs/verified.<branch>; loop-integrity rule 5c reads it,
# so short-circuiting on .pipeline-off deadlocked automerge fleet-wide (2026-07-02).
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

# A) .pipeline-off SET + verify cmd -> flag MUST still be written (the deadlock bug)
touch "$G/.pipeline-off"; rm -f "$FLAG"
run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm run typecheck\"},\"cwd\":\"$R\",\"session_id\":\"s1\"}" >/dev/null
[ -f "$FLAG" ] || fail "A: verify flag not written while .pipeline-off set (the deadlock)"

# B) .pipeline-off SET + git commit w/o verify -> must NOT be blocked
out="$(run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$R\",\"session_id\":\"s2\"}")"
echo "$out" | grep -q '"permissionDecision":"deny"' && fail "B: commit blocked while .pipeline-off set"

# C) .pipeline-off UNSET + git commit w/o verify -> must be blocked (blocking still works)
rm -f "$G/.pipeline-off"
out="$(run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$R\",\"session_id\":\"s3\"}")"
echo "$out" | grep -q '"permissionDecision":"deny"' || fail "C: commit NOT blocked with pipeline ON (no verify)"

echo "PASS: pipeline-gate writes verify flag under .pipeline-off; blocking intact when ON (3 cases)"
