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
chmod +x "$CLAUDE_DIR"/*.sh "$CLAUDE_DIR"/*.js 2>/dev/null || true

echo "==> agents + commands + work-loop wrappers"
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands"
cp "$HERE"/agents/*.md "$CLAUDE_DIR/agents/"
cp "$HERE"/commands/*.md "$CLAUDE_DIR/commands/"
cp "$HERE"/scripts/run-work.sh "$HERE"/scripts/run-work.ps1 "$CLAUDE_DIR/" 2>/dev/null || true
# v1.4 no-babysit: supervisor process-manager, auto-start watcher, notify sink,
# request-scoped seed/unseed, and the Telegram bot hand-off entrypoint.
cp "$HERE"/scripts/supervisord.sh "$HERE"/scripts/phalanx-watch.sh "$HERE"/scripts/notify.sh \
   "$HERE"/scripts/seed-task.sh "$HERE"/scripts/unseed-task.sh "$HERE"/scripts/bot-handoff.sh \
   "$HERE"/scripts/gc-scan.sh "$HERE"/scripts/evidence.sh "$CLAUDE_DIR/" 2>/dev/null || true
cp "$HERE"/TASKS.template.md "$CLAUDE_DIR/" 2>/dev/null || true
chmod +x "$CLAUDE_DIR"/run-work.sh "$CLAUDE_DIR"/supervisord.sh "$CLAUDE_DIR"/phalanx-watch.sh \
         "$CLAUDE_DIR"/notify.sh "$CLAUDE_DIR"/seed-task.sh "$CLAUDE_DIR"/unseed-task.sh "$CLAUDE_DIR"/bot-handoff.sh \
         "$CLAUDE_DIR"/gc-scan.sh "$CLAUDE_DIR"/evidence.sh 2>/dev/null || true

echo "==> templates (state + dependency-cruiser + policy)"
cp "$HERE"/state/*.json "$CLAUDE_DIR/phalanx-templates/state/"
cp "$HERE"/configs/.dependency-cruiser.js "$CLAUDE_DIR/phalanx-templates/"
cp "$HERE"/policy/risk-policy.json "$CLAUDE_DIR/phalanx-templates/" 2>/dev/null || true

# Policy contract (Items 2-5 unifying primitive). Create-if-absent so a release
# pull never clobbers operator opt-ins; the refreshed template lives alongside.
echo "==> policy contract (create-if-absent)"
if [ ! -f "$CLAUDE_DIR/risk-policy.json" ]; then
  cp "$HERE/policy/risk-policy.json" "$CLAUDE_DIR/risk-policy.json"
  echo "    created $CLAUDE_DIR/risk-policy.json"
else
  echo "    kept existing $CLAUDE_DIR/risk-policy.json"
fi

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
for g in pipeline-gate effect-ca-gate secret-gate loop-integrity-gate context-budget work-autostart work-intent work-respawn; do
  node --check "$CLAUDE_DIR/$g.js" && echo "    node --check $g.js ok"
done
for s in run-work supervisord phalanx-watch notify seed-task unseed-task bot-handoff gc-scan evidence; do
  bash -n "$CLAUDE_DIR/$s.sh" && echo "    bash -n $s.sh ok"
done
for h in caveman-anchor app-pipeline-anchor ts-arch-anchor phase-anchor phalanx-selfupdate; do
  bash -n "$CLAUDE_DIR/$h.sh" && echo "    bash -n $h.sh ok"
done
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SETTINGS"
echo "    ok"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$CLAUDE_DIR/risk-policy.json" && echo "    risk-policy.json parses ok"

# ---- verify simulations -----------------------------------------------------
echo "==> verify simulations"
FAIL=0
SID="phalanx-selftest"
rm -rf "/tmp/phalanx-pipeline/$SID" "/tmp/phalanx-tsarch/$SID" 2>/dev/null || true
# assembled at runtime so no AWS-key-shaped literal ships in source (clean for downstream secret scanners)
LEAK="AKIA""Z3QJ5K7N2WX4Y6PB"

# Run gates from an isolated temp dir so live OFF-switch files (.pipeline-off etc.)
# and the operator's runtime env don't skew the logic self-test.
TG="$(mktemp -d 2>/dev/null || echo /tmp/phalanx-tg)"; mkdir -p "$TG"
for j in pipeline-gate effect-ca-gate secret-gate loop-integrity-gate context-budget work-autostart work-respawn; do
  cp "$CLAUDE_DIR/$j.js" "$TG/" 2>/dev/null || true
done
fire() { echo "$2" | PHALANX_WARN= node "$TG/$1"; }
expect_deny() { case "$3" in *'"permissionDecision":"deny"'*) echo "    PASS $1";; *) echo "    FAIL $1 (expected deny) got: $3"; FAIL=1;; esac; }
expect_allow() { if [ -z "$3" ]; then echo "    PASS $1"; else echo "    FAIL $1 (expected allow/empty) got: $3"; FAIL=1; fi; }
# Item 3 (gates as teachers): a blocked reason must also carry a concrete "Fix →" recipe.
expect_teach() { case "$3" in *"Fix →"*) echo "    PASS $1 (teaches)";; *) echo "    FAIL $1 (no remediation recipe) got: $3"; FAIL=1;; esac; }

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
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/x.ts\"},\"session_id\":\"$SID\"}"); expect_deny "tsarch:ts-no-flags" x "$o"; expect_teach "tsarch:ts-no-flags" x "$o"
fire effect-ca-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"clean-architecture\"},\"session_id\":\"$SID\"}" >/dev/null
fire effect-ca-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"effect-ts\"},\"session_id\":\"$SID\"}" >/dev/null
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/x.ts\"},\"session_id\":\"$SID\"}"); expect_allow "tsarch:ts-after-skills" x "$o"
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/x.py\"},\"session_id\":\"phalanx-selftest2\"}"); expect_deny "tsarch:py-ca-only" x "$o"
o=$(fire effect-ca-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$CLAUDE_DIR/skills/x/SKILL.md\"},\"session_id\":\"sx\"}"); expect_allow "tsarch:claudedir-exempt" x "$o"

# pipeline-gate
o=$(fire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/y.go\"},\"session_id\":\"$SID\"}"); expect_deny "pipeline:code-no-plan" x "$o"; expect_teach "pipeline:code-no-plan" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"phased-plan\"},\"session_id\":\"$SID\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/proj/src/y.go\"},\"session_id\":\"$SID\"}"); expect_allow "pipeline:code-after-plan" x "$o"
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-selftest3\"}"); expect_deny "pipeline:commit-no-verify" x "$o"; expect_teach "pipeline:commit-no-verify" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"pnpm test\"},\"session_id\":\"phalanx-selftest3\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-selftest3\"}"); expect_allow "pipeline:commit-after-verify" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"tsc --noEmit\"},\"session_id\":\"phalanx-tsc\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-tsc\"}"); expect_allow "pipeline:commit-after-tsc" x "$o"
fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ruff check .\"},\"session_id\":\"phalanx-lint\"}" >/dev/null
o=$(fire pipeline-gate.js "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"session_id\":\"phalanx-lint\"}"); expect_allow "pipeline:commit-after-lint" x "$o"

# item 2 risk routing: default OFF == identical to today ($TG has no risk-policy.json
# so ROUTING_ON is false -- the asserts above prove the unchanged path). Here: switch +
# enabled policy + a LOW rule fast-paths a LOW code edit; HIGH still blocks; and neither
# the switch alone nor an enabled-policy alone routes (double-key opt-in, data master wins).
RR="$TG/rr"; mkdir -p "$RR"; cp "$CLAUDE_DIR/pipeline-gate.js" "$RR/"
cat > "$RR/risk-policy.json" <<'JSON'
{ "riskRouting": { "enabled": true }, "riskTierRules": [ { "match": "\\.go$", "tier": "LOW" }, { "match": ".*", "tier": "HIGH" } ] }
JSON
rrfire() { echo "$2" | PHALANX_WARN= node "$RR/$1"; }
o=$(rrfire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/p/a.go\"},\"session_id\":\"rr0\"}"); expect_deny "risk:no-switch-blocks" x "$o"
touch "$RR/.risk-routing-on"
o=$(rrfire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/p/a.go\"},\"session_id\":\"rr1\"}"); expect_allow "risk:low-fastpath-allows" x "$o"
o=$(rrfire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/p/a.rs\"},\"session_id\":\"rr1\"}"); expect_deny "risk:high-still-blocks" x "$o"
cat > "$RR/risk-policy.json" <<'JSON'
{ "riskRouting": { "enabled": false }, "riskTierRules": [ { "match": "\\.go$", "tier": "LOW" } ] }
JSON
o=$(rrfire pipeline-gate.js "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/p/a.go\"},\"session_id\":\"rr2\"}"); expect_deny "risk:policy-disabled-blocks" x "$o"
rm -rf "$RR"

# secret-gate WRITE-TIME
o=$(fire secret-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/proj/c.ts\",\"content\":\"const k='$LEAK'\"},\"session_id\":\"s\"}"); expect_deny "secret:write-aws-key" x "$o"; expect_teach "secret:write-aws-key" x "$o"
o=$(fire secret-gate.js "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/proj/c.ts\",\"content\":\"const k=process.env.API_KEY\"},\"session_id\":\"s\"}"); expect_allow "secret:write-env-ref" x "$o"

# work-intent (UserPromptSubmit): speaks on code-intent, silent on read-only + under .work-off
wi() { echo "$1" | node "$CLAUDE_DIR/work-intent.js"; }
mkdir -p /tmp/phalanx-wi 2>/dev/null; rm -f /tmp/phalanx-wi/.work-off /tmp/phalanx-wi/TASKS.md
o=$(wi "{\"prompt\":\"add a retry to the fetch call\",\"cwd\":\"/tmp/phalanx-wi\"}"); case "$o" in *Phalanx*) echo "    PASS intent:code-speaks";; *) echo "    FAIL intent:code-speaks got: $o"; FAIL=1;; esac
o=$(wi "{\"prompt\":\"why is the test failing?\",\"cwd\":\"/tmp/phalanx-wi\"}"); [ -z "$o" ] && echo "    PASS intent:question-silent" || { echo "    FAIL intent:question-silent got: $o"; FAIL=1; }
touch /tmp/phalanx-wi/.work-off
o=$(wi "{\"prompt\":\"add a retry to the fetch call\",\"cwd\":\"/tmp/phalanx-wi\"}"); [ -z "$o" ] && echo "    PASS intent:work-off-silent" || { echo "    FAIL intent:work-off-silent got: $o"; FAIL=1; }
rm -rf /tmp/phalanx-wi 2>/dev/null

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

# ---- v1.4 no-babysit sims (items 1,4,5,6,7) --------------------------------
echo "==> v1.4 no-babysit sims"

# item 5 loop-integrity-gate. Needs a cwd OUTSIDE /tmp (the gate excludes ^/tmp/
# code paths like every gate). Run the $TG copy so HERE-based .work-off checks
# can't read a live global switch.
LIGG="$TG/loop-integrity-gate.js"
LIGDIR="$HOME/.phalanx-lig-selftest"; rm -rf "$LIGDIR"; mkdir -p "$LIGDIR"
li() { echo "$1" | PHALANX_WARN= node "$LIGG"; }
printf '# T\n- [x] done\n' > "$LIGDIR/TASKS.md"
o=$(li "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$LIGDIR/x.js\"},\"cwd\":\"$LIGDIR\",\"session_id\":\"li1\"}"); expect_deny "loop:seed-before-edit" x "$o"; expect_teach "loop:seed-before-edit" x "$o"
printf '# T\n- [ ] do it\n' > "$LIGDIR/TASKS.md"
o=$(li "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$LIGDIR/x.js\"},\"cwd\":\"$LIGDIR\",\"session_id\":\"li1\"}"); expect_allow "loop:edit-after-seed" x "$o"
if command -v git >/dev/null 2>&1; then
  ( cd "$LIGDIR" && git init -q && git config user.email a@b.c && git config user.name a && git checkout -q -b task/x && git commit -q --allow-empty -m i )
  o=$(li "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$LIGDIR\",\"session_id\":\"li2\"}"); expect_deny "loop:commit-before-verify" x "$o"
  li "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$LIGDIR\",\"session_id\":\"li2\"}" >/dev/null
  o=$(li "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$LIGDIR\",\"session_id\":\"li2\"}"); expect_allow "loop:commit-after-verify" x "$o"
else echo "    SKIP loop:commit-* (git not installed)"; fi
rm -rf "$LIGDIR"

# item 4 context-budget: occupancy from the REAL usage signal (last transcript usage
# line) + env-derived window (PHALANX_CTX_WINDOW, default ~1M) -- NOT raw byte size.
CBJ="$TG/context-budget.js"
CBDIR="$(mktemp -d 2>/dev/null || echo /tmp/phalanx-cb)"; mkdir -p "$CBDIR"
printf '# T\n- [ ] big\n' > "$CBDIR/TASKS.md"
# one assistant transcript line whose usage = $1 input + $2 cache_read tokens.
cbusage() { printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":12}}}\n' "$1" "$2"; }

# FALSE-CEILING GUARD (the bug this fixes): a transcript huge in BYTES (the fixed
# system prompt + CLAUDE.md dump) -- ~57% of a 200k window under the old bytes/3.5 --
# but whose real usage is ~168k/1M = 17% must stay SILENT (below the 38% warn).
NORMTP="$CBDIR/normal.jsonl"
{ head -c 400000 /dev/zero | tr '\0' x; printf '\n'; cbusage 2 168000; } > "$NORMTP"
o=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$NORMTP" "$CBDIR" | node "$CBJ")
[ -z "$o" ] && echo "    PASS cb:normal-no-falsetrip" || { echo "    FAIL cb:normal-no-falsetrip got: $o"; FAIL=1; }

# real high usage (~50% of 1M) trips. supervisor active -> defer msg, never "/clear".
BIGTP="$CBDIR/t.jsonl"; { head -c 40000 /dev/zero | tr '\0' x; printf '\n'; cbusage 2 500000; } > "$BIGTP"
rm -f "$CBDIR/PROGRESS.md"
o=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$BIGTP" "$CBDIR" | PHALANX_SUPERVISOR=1 node "$CBJ")
case "$o" in *"supervisor will relaunch"*) case "$o" in *"/clear"*) echo "    FAIL cb:sup-defers (mentions /clear)"; FAIL=1;; *) echo "    PASS cb:sup-defers";; esac;; *) echo "    FAIL cb:sup-defers got: $o"; FAIL=1;; esac

# one-shot, no supervisor -> NEVER writes a RESPAWN file.
rm -f "$CBDIR/PROGRESS.md"
printf '{"transcript_path":"%s","cwd":"%s"}' "$BIGTP" "$CBDIR" | PHALANX_ONESHOT=1 node "$CBJ" >/dev/null
[ -f "$CBDIR/PROGRESS.md" ] && { echo "    FAIL cb:oneshot-no-respawn (wrote RESPAWN)"; FAIL=1; } || echo "    PASS cb:oneshot-no-respawn"

# env-derived window: the SAME normal transcript trips once the window is tiny (200k).
rm -f "$CBDIR/PROGRESS.md"
o=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$NORMTP" "$CBDIR" | PHALANX_CTX_WINDOW=200000 node "$CBJ")
case "$o" in *"CONTEXT CEILING"*) echo "    PASS cb:env-window-trips";; *) echo "    FAIL cb:env-window-trips got: $o"; FAIL=1;; esac

# byte-size FALLBACK still works when a transcript has no usage line yet (pure bytes).
PURETP="$CBDIR/pure.jsonl"; head -c 200000 /dev/zero | tr '\0' x > "$PURETP"
rm -f "$CBDIR/PROGRESS.md"
o=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$PURETP" "$CBDIR" | PHALANX_CTX_WINDOW=100000 node "$CBJ")
case "$o" in *"CONTEXT CEILING"*) echo "    PASS cb:byte-fallback";; *) echo "    FAIL cb:byte-fallback got: $o"; FAIL=1;; esac
rm -rf "$CBDIR"

# item 4 work-respawn: supervisor active -> stop (empty, no block/continue).
WRJ="$TG/work-respawn.js"
WRDIR="$(mktemp -d 2>/dev/null || echo /tmp/phalanx-wr)"; printf '# T\n- [ ] x\n' > "$WRDIR/TASKS.md"
o=$(printf '{"cwd":"%s"}' "$WRDIR" | PHALANX_SUPERVISOR=1 node "$WRJ"); [ -z "$o" ] && echo "    PASS respawn:sup-stops" || { echo "    FAIL respawn:sup-stops got: $o"; FAIL=1; }
rm -rf "$WRDIR"

# item 7 work-autostart: a risk-flagged open task trips; a safe task stays quiet.
WAJ="$TG/work-autostart.js"
WADIR="$(mktemp -d 2>/dev/null || echo /tmp/phalanx-wa)"
printf '# T\n- [ ] do the migration cutover flip; facts wont be in memory_entries\n' > "$WADIR/TASKS.md"
o=$(printf '{"cwd":"%s"}' "$WADIR" | node "$WAJ"); case "$o" in *data-risk*) echo "    PASS autostart:risk-trips";; *) echo "    FAIL autostart:risk-trips got: $o"; FAIL=1;; esac
printf '# T\n- [ ] add a blue button\n' > "$WADIR/TASKS.md"
o=$(printf '{"cwd":"%s"}' "$WADIR" | node "$WAJ"); case "$o" in *data-risk*) echo "    FAIL autostart:safe-falsetrip"; FAIL=1;; *) echo "    PASS autostart:safe-quiet";; esac
# v1.4.1: a risk flag in PROGRESS.md (with a SAFE TASKS.md) must still trip.
printf '# T\n- [ ] add a blue button\n' > "$WADIR/TASKS.md"
printf '# PROGRESS\n<!-- note: graphiti-only facts since 2026-05-28 will not be in memory_entries post-flip (data-continuity) -->\n' > "$WADIR/PROGRESS.md"
o=$(printf '{"cwd":"%s"}' "$WADIR" | node "$WAJ"); case "$o" in *data-risk*) echo "    PASS autostart:risk-in-progress";; *) echo "    FAIL autostart:risk-in-progress got: $o"; FAIL=1;; esac
rm -rf "$WADIR"

# item 4 GC loop (opt-in, soft, never a gate): OFF -> no-op (writes nothing); ON (switch +
# policy gc.enabled:true) -> writes a quality grade. Never touches a remote without --open-pr.
GCOFF="$(mktemp -d)"; GCON="$(mktemp -d)"; GR1="$(mktemp -d)"; GR2="$(mktemp -d)"
CLAUDE_DIR="$GCOFF" bash "$CLAUDE_DIR/gc-scan.sh" -r "$GR1" >/dev/null 2>&1
[ -f "$GR1/quality-grades.json" ] && { echo "    FAIL gc:off-no-op (wrote grade)"; FAIL=1; } || echo "    PASS gc:off-no-op"
touch "$GCON/.gc-on"; printf '{ "gc": { "enabled": true } }\n' > "$GCON/risk-policy.json"
printf '# d\n[ok](real.md)\n' > "$GR2/real.md"
CLAUDE_DIR="$GCON" bash "$CLAUDE_DIR/gc-scan.sh" -r "$GR2" >/dev/null 2>&1
[ -f "$GR2/quality-grades.json" ] && echo "    PASS gc:on-writes-grade" || { echo "    FAIL gc:on-writes-grade"; FAIL=1; }
rm -rf "$GCOFF" "$GCON" "$GR1" "$GR2"

# item 5 first-class evidence (opt-in, soft, NEVER required for verify): OFF -> no-op;
# ON but missing inputs (no URL / no playwright) -> graceful soft skip, exit 0, no dir.
EVOFF="$(mktemp -d)"; EVON="$(mktemp -d)"; EVR="$(mktemp -d)"
CLAUDE_DIR="$EVOFF" bash "$CLAUDE_DIR/evidence.sh" -u "http://x" -r "$EVR" >/dev/null 2>&1
[ -d "$EVR/evidence" ] && { echo "    FAIL evidence:off-no-op"; FAIL=1; } || echo "    PASS evidence:off-no-op"
touch "$EVON/.evidence-on"; printf '{ "evidence": { "enabled": true } }\n' > "$EVON/risk-policy.json"
CLAUDE_DIR="$EVON" bash "$CLAUDE_DIR/evidence.sh" -r "$EVR" >/dev/null 2>&1; eec=$?
{ [ "$eec" = 0 ] && [ ! -d "$EVR/evidence" ]; } && echo "    PASS evidence:on-no-url-soft" || { echo "    FAIL evidence:on-no-url-soft (ec=$eec)"; FAIL=1; }
rm -rf "$EVOFF" "$EVON" "$EVR"

# notify port: the per-job thread routing key reaches the adapter as a 4th arg and
# defaults to the repo basename (so each job lands in its own Telegram topic/chat).
NDIR="$(mktemp -d)"; NOUT="$NDIR/got"
printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s|%%s\\n" "$1" "$2" "$3" "$4" > "$GOTFILE"\n' > "$NDIR/sink.sh"; chmod +x "$NDIR/sink.sh"
GOTFILE="$NOUT" PHALANX_NOTIFY_CMD="$NDIR/sink.sh" PHALANX_REPO="/x/my-repo" bash "$CLAUDE_DIR/notify.sh" done "all green" >/dev/null 2>&1
got=$(cat "$NOUT" 2>/dev/null || echo)
case "$got" in *"|my-repo") echo "    PASS notify:thread-to-adapter";; *) echo "    FAIL notify:thread-to-adapter got: $got"; FAIL=1;; esac
out=$(PHALANX_REPO="/x/my-repo" bash "$CLAUDE_DIR/notify.sh" info hi 2>/dev/null)
case "$out" in *my-repo*) echo "    PASS notify:default-thread-is-repo";; *) echo "    FAIL notify:default-thread-is-repo got: $out"; FAIL=1;; esac
rm -rf "$NDIR"

# items 1+6 supervisor loop drains a backlog across fresh passes (stub claude),
# and request-scoped unseed removes a left-open TASKS.md.
if command -v sed >/dev/null 2>&1; then
  SDIR="$(mktemp -d)"; mkdir -p "$SDIR/repo" "$SDIR/bin" "$SDIR/cd"
  cat > "$SDIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
t="./TASKS.md"; [ -f "$t" ] && sed -i '0,/- \[ \]/s//- [x]/' "$t" 2>/dev/null || true
exit 0
STUB
  chmod +x "$SDIR/bin/claude"
  printf '# T\n- [ ] a -- ok\n- [ ] b -- ok\n' > "$SDIR/repo/TASKS.md"
  PATH="$SDIR/bin:$PATH" CLAUDE_DIR="$SDIR/cd" bash "$CLAUDE_DIR/run-work.sh" -r "$SDIR/repo" -m 6 -s 0 >/dev/null 2>&1 || true
  if grep -Eq '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]' "$SDIR/repo/TASKS.md" 2>/dev/null; then echo "    FAIL supervisor:drains-backlog"; FAIL=1; else echo "    PASS supervisor:drains-backlog"; fi
  # request-scoped: a fresh repo whose only task is the seed -> unseed removes the
  # whole file, so a later unrelated message can't re-arm the loop (item 6).
  RS="$SDIR/reqscoped"; mkdir -p "$RS"
  id=$(bash "$CLAUDE_DIR/seed-task.sh" "$RS" "one off" | tail -n1); bash "$CLAUDE_DIR/unseed-task.sh" "$RS" "$id"
  [ -f "$RS/TASKS.md" ] && { echo "    FAIL reqscoped:unseed-removes-empty"; FAIL=1; } || echo "    PASS reqscoped:unseed-removes-empty"
  rm -rf "$SDIR"
else echo "    SKIP supervisor:* (sed not installed)"; fi

rm -rf "/tmp/phalanx-pipeline" "/tmp/phalanx-tsarch" "$TG" 2>/dev/null || true
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

# ---- auto-start watcher registry + optional cron ----------------------------
REG="$CLAUDE_DIR/.phalanx-repos"
if [ ! -f "$REG" ]; then
  cat > "$REG" <<'EOF'
# Phalanx auto-start registry -- one absolute repo path per line; # comments ok.
# phalanx-watch.sh launches a DETACHED supervisor for any listed repo that has
# open TASKS.md items, no running supervisor, and no .work-off. Add repo roots:
#   /workspace/my-project
EOF
  echo "==> created watcher registry stub $REG (add repo roots to enable auto-start)"
else
  echo "==> watcher registry present: $REG"
fi
if [ "${PHALANX_NO_CRON:-0}" != "1" ] && [ "${PHALANX_WATCH:-0}" = "1" ]; then
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l 2>/dev/null | grep -q 'phalanx-watch'; then
      echo "==> watcher cron already present"
    else
      wline="*/5 * * * * CLAUDE_DIR=\"$CLAUDE_DIR\" \"$CLAUDE_DIR/phalanx-watch.sh\" >/dev/null 2>&1 # phalanx-watch"
      ( crontab -l 2>/dev/null; echo "$wline" ) | crontab -
      echo "==> installed auto-start watcher cron (*/5): scan $REG, launch supervisors"
    fi
  else
    echo "==> PHALANX_WATCH=1 but no crontab; add manually: */5 * * * * $CLAUDE_DIR/phalanx-watch.sh"
  fi
fi

# ---- leak guard (default on; PHALANX_NO_GUARDS=1 to skip) --------------------
if [ "${PHALANX_NO_GUARDS:-0}" != "1" ]; then
  echo "==> leak guard"
  CLAUDE_DIR="$CLAUDE_DIR" bash "$HERE/scripts/install-guards.sh" | sed 's/^/    /'
fi

echo "==> done. Gates + plugins activate on the NEXT Claude Code session; skills are usable now."
echo "    per-project: cp $CLAUDE_DIR/phalanx-templates/state/<mode>.json <project>/.claude-state.json"
echo "    per-TS-repo: cp $CLAUDE_DIR/phalanx-templates/.dependency-cruiser.js <repo>/.dependency-cruiser.js"
