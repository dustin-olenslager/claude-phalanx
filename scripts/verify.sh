#!/usr/bin/env bash
# Repo verify entrypoint: syntax-check the supervisor + run every test-*.sh suite.
# Exits non-zero on the first failure. This is the gate-recognized verification.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || exit 1
fail=0
echo "== syntax =="
for s in run-work.sh supervisord.sh phalanx-watch.sh seed-task.sh unseed-task.sh; do
  [ -f "$s" ] && { bash -n "$s" && echo "  ok $s" || { echo "  FAIL $s"; fail=1; }; }
done
echo "== test suites =="
for t in test-*.sh; do
  [ -f "$t" ] || continue
  if bash "$t" >/tmp/vt.$$ 2>&1; then echo "  ok $t"; else echo "  FAIL $t"; tail -15 /tmp/vt.$$; fail=1; fi
done
rm -f /tmp/vt.$$
[ "$fail" = 0 ] && echo "VERIFY: all green" || { echo "VERIFY: FAILED"; exit 1; }
