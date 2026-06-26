#!/usr/bin/env bash
# Phalanx installer — idempotent. Detects CLAUDE_DIR, MERGES settings.json +
# CLAUDE.md (never clobbers), copies skills/hooks/templates, chmods, node --checks
# the gates, runs the verify simulations. Re-run any time; safe.
#
# Run it from the cloned repo (the repo IS the update checkout):
#   git clone https://github.com/<you>/claude-phalanx ~/.claude/phalanx
#   ~/.claude/phalanx/install.sh
#
# Env:
#   CLAUDE_DIR=/path   install target (default ~/.claude)
#   MEMORY_DIR=/path   memory dir   (default $CLAUDE_DIR/memory)
#   PHALANX_CRON=1     also install a daily auto-update cron (git pull --tags + reinstall)
#   PHALANX_NO_CRON=1  never touch crontab (overrides PHALANX_CRON)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

command -v node >/dev/null 2>&1 || { echo "FATAL: node is required (gates + merge scripts are node)."; exit 1; }

echo "==> CLAUDE_DIR=$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/phalanx-templates/state"

echo "==> skills"
cp -R "$HERE/skills/." "$CLAUDE_DIR/skills/"

echo "==> hooks (anchors + gates -> CLAUDE_DIR root)"
cp "$HERE"/hooks/anchors/*.sh "$CLAUDE_DIR/"
cp "$HERE"/hooks/gates/*.js "$CLAUDE_DIR/"
chmod +x "$CLAUDE_DIR"/*.sh "$CLAUDE_DIR"/pipeline-gate.js "$CLAUDE_DIR"/effect-ca-gate.js "$CLAUDE_DIR"/secret-gate.js 2>/dev/null || true

echo "==> templates (state + dependency-cruiser)"
cp "$HERE"/state/*.json "$CLAUDE_DIR/phalanx-templates/state/"
cp "$HERE"/configs/.dependency-cruiser.js "$CLAUDE_DIR/phalanx-templates/"

echo "==> memory dir"
MEMORY_DIR="${MEMORY_DIR:-$CLAUDE_DIR/memory}"
mkdir -p "$MEMORY_DIR"
if [ ! -f "$MEMORY_DIR/MEMORY.md" ]; then
  printf '%s\n' '<!-- memory index (§10): one line per memory: - [Title](file.md) — hook. One fact per kebab-case .md file with frontmatter name/description/metadata.type. -->' > "$MEMORY_DIR/MEMORY.md"
  echo "    created $MEMORY_DIR/MEMORY.md"
else
  echo "    kept existing $MEMORY_DIR/MEMORY.md"
fi

echo "==> CLAUDE.md (managed block)"
node "$HERE/scripts/merge-claude-md.mjs" "$CLAUDE_DIR/CLAUDE.md" "$HERE/claude-md/sections.md"

echo "==> settings.json (merge marketplaces + plugins + hooks)"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.phalanx.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
# Hook-command base path. If CLAUDE_DIR is the home default, write "$HOME/.claude"
# so the hooks resolve in any container/user that mounts the same dir at a
# different path (e.g. a shared mount). Override with PHALANX_HOOK_BASE.
if [ -n "${PHALANX_HOOK_BASE:-}" ]; then HOOK_BASE="$PHALANX_HOOK_BASE"
elif [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then HOOK_BASE='$HOME/.claude'
else HOOK_BASE="$CLAUDE_DIR"; fi
node "$HERE/scripts/merge-settings.mjs" "$SETTINGS" "$HERE/settings/fragment.json" "$HOOK_BASE"

echo "==> validate (node --check + JSON parse)"
node --check "$CLAUDE_DIR/pipeline-gate.js"
node --check "$CLAUDE_DIR/effect-ca-gate.js"
node --check "$CLAUDE_DIR/secret-gate.js"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SETTINGS"
echo "    ok"

# ---- verify simulations -----------------------------------------------------
echo "==> verify simulations"
FAIL=0
SID="phalanx-selftest"
rm -rf "/tmp/phalanx-pipeline/$SID" "/tmp/phalanx-tsarch/$SID" 2>/dev/null || true
# assembled at runtime so no AWS-key-shaped literal ships in source (clean for downstream secret scanners)
LEAK="AKIA""Z3QJ5K7N2WX4Y6PB"

fire() { echo "$2" | node "$CLAUDE_DIR/$1"; }
expect_deny() { case "$3" in *'"permissionDecision":"deny"'*) echo "    PASS $1";; *) echo "    FAIL $1 (expected deny) got: $3"; FAIL=1;; esac; }
expect_allow() { if [ -z "$3" ]; then echo "    PASS $1"; else echo "    FAIL $1 (expected allow/empty) got: $3"; FAIL=1; fi; }

# anchors emit valid JSON
for a in caveman-anchor app-pipeline-anchor ts-arch-anchor phase-anchor; do
  if "$CLAUDE_DIR/$a.sh" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' >/dev/null 2>&1; then
    echo "    PASS anchor:$a"; else echo "    FAIL anchor:$a (invalid JSON)"; FAIL=1; fi
done

# phase-anchor MODE/PHASE for: no-state, build, maintain, optimize
for st in none build maintain optimize; do
  d="/tmp/phalanx-ps-$st"; rm -rf "$d"; mkdir -p "$d"
  [ "$st" != "none" ] && cp "$HERE/state/$st.json" "$d/.claude-state.json"
  o=$(cd "$d" && "$CLAUDE_DIR/phase-anchor.sh")
  if echo "$o" | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const c=j.hookSpecificOutput.additionalContext||"";const m=process.argv[1];if(!c)process.exit(1);if(m!=="none"&&!c.includes("mode="+m))process.exit(1);if(m==="none"&&!/NO .claude-state/.test(c))process.exit(1);' "$st" 2>/dev/null; then
    echo "    PASS phase:$st"; else echo "    FAIL phase:$st got: $o"; FAIL=1; fi
  rm -rf "$d"
done

# effect-ca-gate
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/x.ts\"},\"session_id\":\"$SID\"}"); expect_deny "tsarch:ts-no-flags" x "$o"
fire effect-ca-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"clean-architecture\"},\"session_id\":\"$SID\"}" >/dev/null
fire effect-ca-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"effect-ts\"},\"session_id\":\"$SID\"}" >/dev/null
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/x.ts\"},\"session_id\":\"$SID\"}"); expect_allow "tsarch:ts-after-skills" x "$o"
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/x.py\"},\"session_id\":\"phalanx-selftest2\"}"); expect_deny "tsarch:py-ca-only" x "$o"
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$CLAUDE_DIR/skills/x/SKILL.md\"},\"session_id\":\"sx\"}"); expect_allow "tsarch:claudedir-exempt" x "$o"

# pipeline-gate
o=$(fire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/y.go\"},\"session_id\":\"$SID\"}"); expect_deny "pipeline:code-no-plan" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"phased-plan\"},\"session_id\":\"$SID\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/y.go\"},\"session_id\":\"$SID\"}"); expect_allow "pipeline:code-after-plan" x "$o"
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-selftest3\"}"); expect_deny "pipeline:commit-no-verify" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"pnpm test\"},\"session_id\":\"phalanx-selftest3\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-selftest3\"}"); expect_allow "pipeline:commit-after-verify" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tsc --noEmit\"},\"session_id\":\"phalanx-tsc\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-tsc\"}"); expect_allow "pipeline:commit-after-tsc" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ruff check .\"},\"session_id\":\"phalanx-lint\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-lint\"}"); expect_allow "pipeline:commit-after-lint" x "$o"

# secret-gate WRITE-TIME
o=$(fire secret-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/proj/c.ts\",\"content\":\"const k='$LEAK'\"},\"session_id\":\"s\"}"); expect_deny "secret:write-aws-key" x "$o"
o=$(fire secret-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/proj/c.ts\",\"content\":\"const k=process.env.API_KEY\"},\"session_id\":\"s\"}"); expect_allow "secret:write-env-ref" x "$o"

# secret-gate COMMIT-TIME (needs git)
if command -v git >/dev/null 2>&1; then
  g="/tmp/phalanx-secret-dirty"; rm -rf "$g"; mkdir -p "$g"
  ( cd "$g" && git init -q && git config user.email a@b.c && git config user.name a )
  printf "const k='%s'\n" "$LEAK" > "$g/leak.ts"; ( cd "$g" && git add -A )
  o=$(fire secret-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$g\",\"session_id\":\"sc\"}"); expect_deny "secret:commit-staged-leak" x "$o"
  g2="/tmp/phalanx-secret-clean"; rm -rf "$g2"; mkdir -p "$g2"
  ( cd "$g2" && git init -q && git config user.email a@b.c && git config user.name a )
  printf "export const x = 1\n" > "$g2/ok.ts"; ( cd "$g2" && git add -A )
  o=$(fire secret-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$g2\",\"session_id\":\"sc\"}"); expect_allow "secret:commit-clean" x "$o"
  rm -rf "$g" "$g2"
else
  echo "    SKIP secret:commit-* (git not installed)"
fi

rm -rf "/tmp/phalanx-pipeline" "/tmp/phalanx-tsarch" 2>/dev/null || true
if [ "$FAIL" -ne 0 ]; then echo "==> SELF-TEST FAILED"; exit 1; fi

# ---- optional daily auto-update cron ----------------------------------------
if [ "${PHALANX_NO_CRON:-0}" != "1" ] && [ "${PHALANX_CRON:-0}" = "1" ]; then
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l 2>/dev/null | grep -q 'phalanx-auto-update'; then
      echo "==> cron already present"
    else
      line="0 5 * * * cd \"$HERE\" && git pull --tags --quiet && ./install.sh >/dev/null 2>&1 # phalanx-auto-update"
      ( crontab -l 2>/dev/null; echo "$line" ) | crontab -
      echo "==> installed daily auto-update cron (05:00): git pull --tags + reinstall"
    fi
  else
    echo "==> PHALANX_CRON=1 but no crontab; add manually: 0 5 * * * cd $HERE && git pull --tags && ./install.sh"
  fi
fi

echo "==> done. Gates + plugins activate on the NEXT Claude Code session; skills are usable now."
echo "    per-project: cp $CLAUDE_DIR/phalanx-templates/state/<mode>.json <project>/.claude-state.json"
echo "    per-TS-repo: cp $CLAUDE_DIR/phalanx-templates/.dependency-cruiser.js <repo>/.dependency-cruiser.js"
