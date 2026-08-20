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
# install.sh records the ACTUAL checkout path here; without it a custom CLAUDE_DIR
# (or a checkout living outside CLAUDE_DIR) silently disables auto-update.
if [ -f "$CLAUDE_DIR/.phalanx-checkout" ]; then
  CO="$(cat "$CLAUDE_DIR/.phalanx-checkout" 2>/dev/null)"
fi
CO="${CO:-$CLAUDE_DIR/phalanx}"
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
git fetch --tags --force --quiet origin 2>/dev/null || exit 0
latest=$(git tag -l "v*" --sort=-v:refname 2>/dev/null | head -1)
[ -n "$latest" ] || exit 0
latest_sha=$(git rev-parse -q --verify "refs/tags/$latest^{commit}" 2>/dev/null)
head_sha=$(git rev-parse -q --verify HEAD 2>/dev/null)
if [ -n "$latest_sha" ] && [ "$latest_sha" != "$head_sha" ]; then
  # SECURITY NOTE (audit 2026-08-17): the tag about to be checked out + executed (install.sh)
  # is REMOTE CODE. Anyone able to push a v* tag to origin would get code run under the
  # operator's shell at the next session -- origin-push == RCE. To require a VALID signature on
  # the release tag before trusting it, set PHALANX_REQUIRE_SIGNED_TAGS=1 and sign releases with
  # `git tag -s`. Default (below) trusts unsigned tags -- UNCHANGED behavior, since not every
  # install signs releases -- so the security is available opt-in without breaking auto-update.
  if [ "${PHALANX_REQUIRE_SIGNED_TAGS:-0}" = "1" ] && ! git tag -v "$latest" >/dev/null 2>&1; then
    exit 0  # signed tags required but this one isn't validly signed -> refuse (fail closed, silent)
  fi
  git -c advice.detachedHead=false checkout -f --quiet "$latest" 2>/dev/null \
    || git -c advice.detachedHead=false reset --hard --quiet "refs/tags/$latest" 2>/dev/null \
    || exit 0
  CLAUDE_DIR="$CLAUDE_DIR" ./install.sh >/dev/null 2>&1 || true
fi
exit 0
