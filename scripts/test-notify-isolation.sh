#!/usr/bin/env bash
# Isolated test: notify.sh must NEVER hit a real sink when the job's repo lives
# under /tmp (supervisor self-tests use throwaway /tmp repos). It must still write
# the local events.log line either way. Picked up by verify.sh's test-*.sh glob.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"   # repo root: a guaranteed non-/tmp base
NOTIFY="$HERE/notify.sh"
FAIL=0
# Keep all scratch OFF /tmp so the guard can't suppress the non-/tmp case by accident.
WORK="$(mktemp -d -p "$ROOT" .notify-test.XXXXXX)"; trap 'rm -rf "$WORK"' EXIT

# Stub sink: touches a sentinel iff it ever runs.
SENTINEL="$WORK/sink-fired"
STUB="$WORK/sink.sh"
cat > "$STUB" <<STUBEOF
#!/usr/bin/env bash
touch "$SENTINEL"
STUBEOF
chmod +x "$STUB"

# Case 1: /tmp repo -> sink MUST NOT fire, events.log MUST still be written.
TMPREPO="$(mktemp -d -p /tmp .notify-test.XXXXXX)"
rm -f "$SENTINEL"
PHALANX_NOTIFY_CMD="$STUB" PHALANX_REPO="$TMPREPO" bash "$NOTIFY" start "hello" >/dev/null 2>&1
if [ -e "$SENTINEL" ]; then echo "  FAIL case1: sink fired for /tmp repo"; FAIL=1; else echo "  ok case1 sink suppressed"; fi
if [ -s "$TMPREPO/.claude-runs/events.log" ]; then echo "  ok case1 events.log written"; else echo "  FAIL case1: events.log missing"; FAIL=1; fi
rm -rf "$TMPREPO"

# Case 2: non-/tmp repo -> sink MUST fire.
REALREPO="$WORK/realrepo"; mkdir -p "$REALREPO"
rm -f "$SENTINEL"
PHALANX_NOTIFY_CMD="$STUB" PHALANX_REPO="$REALREPO" bash "$NOTIFY" start "hello" >/dev/null 2>&1
if [ -e "$SENTINEL" ]; then echo "  ok case2 sink fired"; else echo "  FAIL case2: sink did not fire for non-/tmp repo"; FAIL=1; fi

[ "$FAIL" = 0 ] && echo "test-notify-isolation: PASS" || { echo "test-notify-isolation: FAIL"; exit 1; }
