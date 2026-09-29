#!/usr/bin/env bash
# phalanx-project.test.sh — canary for scripts/phalanx-project.sh.
#
# Proves the per-project gate detects every state it claims (absent / partial / drifted / current)
# and that a compliant adopter passes — the compliant case is what distinguishes "detects nothing"
# from "detects correctly". Same doctrine as the kit's other gate self-tests.
#
#   bash scripts/test-phalanx-project.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HERE/scripts/phalanx-project.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
_ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
_bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

_repo() { p="$WORK/$1"; mkdir -p "$p"; ( cd "$p" && git init -q . && printf 'x\n' >README.md \
  && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1; printf '%s' "$p"; }
_expect() { # name want dir
  ( cd "$3" && bash "$GATE" check "$3" ) >/dev/null 2>&1; got=$?
  if [ "$got" = "$2" ]; then _ok "$1 (exit $got)"; else _bad "$1" "want $2 got $got"; fi
}

echo "phalanx-project.test.sh"

R="$(_repo absent)";  _expect "absent project"     10 "$R"
R="$(_repo partial)"; mkdir -p "$R/.phalanx"; printf 'x\n' > "$R/.phalanx/workflow.md"
                      _expect "partial project"    11 "$R"
R="$(_repo current)"; bash "$GATE" apply "$R" >/dev/null 2>&1
                      _expect "compliant project"   0 "$R"
R="$(_repo drifted)"; bash "$GATE" apply "$R" >/dev/null 2>&1
printf '# hand edit that diverges from the shipped rule\n' >> "$R/.phalanx/workflow.md"
                      _expect "drifted rule"       12 "$R"
R="$(_repo oldstamp)"; bash "$GATE" apply "$R" >/dev/null 2>&1
sed -i 's/^phalanx_version: .*/phalanx_version: v0.0.1/' "$R/.phalanx-project"
                      _expect "stale stamp"        12 "$R"
# never clobber the operator's own contract file
R="$(_repo noclobber)"; bash "$GATE" apply "$R" >/dev/null 2>&1
printf 'MY OWN RULES\n' > "$R/AGENTS.phalanx.md"; bash "$GATE" apply "$R" >/dev/null 2>&1
if grep -q 'MY OWN RULES' "$R/AGENTS.phalanx.md"; then _ok "apply never clobbers the local contract"
else _bad "noclobber" "the local contract was overwritten"; fi
# escape hatch + non-git
R="$(_repo esc)"
if ( cd "$R" && PHALANX_PROJECT_OFF=1 bash "$GATE" check "$R" ) >/dev/null 2>&1; then
  _ok "PHALANX_PROJECT_OFF escape hatch"
else
  _bad "escape hatch" "nonzero"
fi
NG="$WORK/nogit"; mkdir -p "$NG"; _expect "non-git dir not blocked" 0 "$NG"

echo
if [ "$fail" = 0 ]; then printf 'PHALANX-PROJECT.TEST: all green (%d checks)\n' "$pass"; exit 0; fi
printf 'PHALANX-PROJECT.TEST: FAILED (%d ok, %d failed)\n' "$pass" "$fail"; exit 1
