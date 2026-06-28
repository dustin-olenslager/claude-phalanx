#!/usr/bin/env bash
# Isolated test: run-work must FAIL CLOSED (write .claude-runs/BLOCKED) on the
# token-wasting paths so phalanx-watch never relaunches a doomed loop. Stubs
# `claude` -- no real auth/model. Covers:
#   A. exit-0 no-progress churn (claude returns 0 on a 401; nothing advances)
#   B. auth preflight failure (token present but invalid)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mk_repo() {  # $1=dir
  local r="$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t && git config user.name t )
  printf '%s\n' '- [ ] (req:T1) do a thing' > "$r/TASKS.md"
}
mk_cdir() { # $1=dir  -- CLAUDE_DIR with a 0600 headless token
  local c="$1"; mkdir -p "$c"; printf 'CLAUDE_CODE_OAUTH_TOKEN=dummy\n' > "$c/.headless-env"; chmod 600 "$c/.headless-env"
}
# Stub claude: preflight prompt -> emit the OK marker (pass preflight); /work pass ->
# behave like a 401 (print error, EXIT 0) and touch NOTHING (no progress).
mk_stub_noprogress() { # $1=bindir
  local b="$1"; mkdir -p "$b"
  cat > "$b/claude" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *PHALANX_AUTH_OK*) echo "PHALANX_AUTH_OK"; exit 0 ;;
  *) echo "API Error: 401 Invalid authentication credentials"; exit 0 ;;
esac
STUB
  chmod +x "$b/claude"
}
# Stub claude that FAILS preflight (never emits the marker).
mk_stub_badauth() { # $1=bindir
  local b="$1"; mkdir -p "$b"
  cat > "$b/claude" <<'STUB'
#!/usr/bin/env bash
echo "API Error: 401 Invalid authentication credentials"; exit 0
STUB
  chmod +x "$b/claude"
}

# ---- Case A: exit-0 no-progress -> BLOCKED after NOPROG_MAX passes ----------
A="$WORK/a"; mk_repo "$A"; CA="$WORK/a-cdir"; mk_cdir "$CA"; BA="$WORK/a-bin"; mk_stub_noprogress "$BA"
out="$(cd "$A" && PATH="$BA:$PATH" CLAUDE_DIR="$CA" PHALANX_NO_WORKTREE=1 \
  PHALANX_NOPROG_MAX=2 PHALANX_AUTH_PREFLIGHT=0 \
  bash "$HERE/run-work.sh" -r "$A" -m 20 -s 0 2>&1)"
passes="$(printf '%s' "$out" | grep -c '=== Pass ')"
if [ -f "$A/.claude-runs/BLOCKED" ] && grep -q 'no progress' "$A/.claude-runs/BLOCKED" && [ "$passes" -le 3 ]; then
  echo "ok A: exit-0 no-progress fails closed after $passes passes (BLOCKED written, watcher will skip)"
else
  echo "FAIL A: passes=$passes blocked=$([ -f "$A/.claude-runs/BLOCKED" ] && echo yes || echo NO)"; echo "$out" | tail -8; FAIL=1
fi

# ---- Case B: auth preflight failure -> BLOCKED at ZERO passes ---------------
B="$WORK/b"; mk_repo "$B"; CB="$WORK/b-cdir"; mk_cdir "$CB"; BB="$WORK/b-bin"; mk_stub_badauth "$BB"
out="$(cd "$B" && PATH="$BB:$PATH" CLAUDE_DIR="$CB" PHALANX_NO_WORKTREE=1 \
  PHALANX_AUTH_PREFLIGHT=1 \
  bash "$HERE/run-work.sh" -r "$B" -m 20 -s 0 2>&1)"
passes="$(printf '%s' "$out" | grep -c '=== Pass ')"
if [ -f "$B/.claude-runs/BLOCKED" ] && grep -qi 'preflight' "$B/.claude-runs/BLOCKED" && [ "$passes" -eq 0 ]; then
  echo "ok B: bad-auth preflight fails closed at 0 passes (no wasted /work passes)"
else
  echo "FAIL B: passes=$passes blocked=$([ -f "$B/.claude-runs/BLOCKED" ] && echo yes || echo NO)"; echo "$out" | tail -8; FAIL=1
fi

# ---- Case C: missing token -> BLOCKED at ZERO passes -----------------------
C="$WORK/c"; mk_repo "$C"; CC="$WORK/c-cdir"; mkdir -p "$CC"  # no .headless-env
out="$(cd "$C" && PATH="$BA:$PATH" CLAUDE_DIR="$CC" PHALANX_NO_WORKTREE=1 \
  bash "$HERE/run-work.sh" -r "$C" -m 20 -s 0 2>&1)"
passes="$(printf '%s' "$out" | grep -c '=== Pass ')"
if [ -f "$C/.claude-runs/BLOCKED" ] && grep -qi 'no headless auth token' "$C/.claude-runs/BLOCKED" && [ "$passes" -eq 0 ]; then
  echo "ok C: missing token fails closed at 0 passes"
else
  echo "FAIL C: passes=$passes blocked=$([ -f "$C/.claude-runs/BLOCKED" ] && echo yes || echo NO)"; echo "$out" | tail -8; FAIL=1
fi

[ "$FAIL" = 0 ] && echo "PASS: anti-churn breakers all fail closed" || { echo "TESTS FAILED"; exit 1; }
