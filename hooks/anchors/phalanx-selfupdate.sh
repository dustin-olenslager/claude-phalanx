#!/usr/bin/env bash
# SessionStart hook: keep this install current without waiting for the cron, so a
# session started right after a release picks it up. Designed to be cheap + safe
# on a shared mount:
#   - THROTTLE: if checked within PHALANX_UPDATE_THROTTLE (default 4h), do nothing
#     and touch no network -- so the common case is a single stamp read;
#   - LOCK: a non-blocking flock means a concurrent session/cron never collide on
#     the install (whoever holds it wins; the other skips);
#   - ONLY-IF-BEHIND: fetch tags, compare to the latest release tag; reinstall
#     ONLY when behind. Synchronous but rare (real work happens just after a tag).
# Silent always. Disable updates: touch $CLAUDE_DIR/.no-autoupdate.
CLAUDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CO="$CLAUDE_DIR/phalanx"
THROTTLE_SECS="${PHALANX_UPDATE_THROTTLE:-14400}"
STAMP="$CLAUDE_DIR/.phalanx-update.stamp"
LOCK="$CLAUDE_DIR/.phalanx-update.lock"

[ -d "$CO/.git" ] || exit 0
[ -f "$CLAUDE_DIR/.no-autoupdate" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

now=$(date +%s 2>/dev/null || echo 0)
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$THROTTLE_SECS" ] && exit 0
fi

exec 9>"$LOCK" 2>/dev/null || exit 0
if command -v flock >/dev/null 2>&1; then flock -n 9 || exit 0; fi
echo "$now" > "$STAMP" 2>/dev/null || true

cd "$CO" || exit 0
git fetch --tags --quiet origin 2>/dev/null || exit 0
latest=$(git tag -l "v*" --sort=-v:refname 2>/dev/null | head -1)
cur=$(git describe --tags --always 2>/dev/null)
if [ -n "$latest" ] && [ "$latest" != "$cur" ]; then
  git -c advice.detachedHead=false checkout --quiet "$latest" 2>/dev/null || exit 0
  CLAUDE_DIR="$CLAUDE_DIR" ./install.sh >/dev/null 2>&1 || true
fi
exit 0
