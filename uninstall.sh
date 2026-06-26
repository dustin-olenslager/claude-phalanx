#!/usr/bin/env bash
# Remove Phalanx artifacts. Leaves your own settings.json keys/plugins in place
# by default; pass --settings to strip our hook commands too. Never touches
# operator content outside the PHALANX markers.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

echo "==> removing skills"
for s in caveman caveman-commit caveman-review caveman-stats effect-ts \
         clean-architecture edge-hunter adversary-review optimize-loop \
         maintain-mode arch-enforce; do
  rm -rf "$CLAUDE_DIR/skills/$s"
done

echo "==> removing hooks + templates"
rm -f "$CLAUDE_DIR"/caveman-anchor.sh "$CLAUDE_DIR"/app-pipeline-anchor.sh \
      "$CLAUDE_DIR"/ts-arch-anchor.sh "$CLAUDE_DIR"/phase-anchor.sh \
      "$CLAUDE_DIR"/pipeline-gate.js "$CLAUDE_DIR"/effect-ca-gate.js "$CLAUDE_DIR"/secret-gate.js
echo "==> removing autonomous-loop artifacts"
rm -f "$CLAUDE_DIR"/context-budget.js "$CLAUDE_DIR"/work-autostart.js "$CLAUDE_DIR"/work-respawn.js \
      "$CLAUDE_DIR"/run-work.sh "$CLAUDE_DIR"/run-work.ps1 "$CLAUDE_DIR"/TASKS.template.md
rm -rf "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands"
rm -rf "$CLAUDE_DIR/phalanx-templates"

echo "==> removing daily auto-update cron (if present)"
if command -v crontab >/dev/null 2>&1; then
  crontab -l 2>/dev/null | grep -v 'phalanx-auto-update' | crontab - 2>/dev/null || true
fi

echo "==> stripping PHALANX block from CLAUDE.md"
node -e '
const fs=require("fs");const p=process.argv[1];let c="";try{c=fs.readFileSync(p,"utf8")}catch{process.exit(0)}
const B="<!-- PHALANX:BEGIN";const E="PHALANX:END -->";
const b=c.indexOf(B),e=c.indexOf(E);
if(b!==-1&&e!==-1&&e>b){fs.writeFileSync(p,(c.slice(0,b)+c.slice(e+E.length)).replace(/\n{3,}/g,"\n\n").trimStart());console.log("stripped")}
' "$CLAUDE_DIR/CLAUDE.md"

if [ "${1:-}" = "--settings" ]; then
  echo "==> stripping Phalanx hook commands from settings.json (plugins/marketplaces kept)"
  node -e '
  const fs=require("fs");const p=process.argv[1];let s={};try{s=JSON.parse(fs.readFileSync(p,"utf8"))}catch{process.exit(0)}
  const kill=/(caveman-anchor|app-pipeline-anchor|ts-arch-anchor|phase-anchor|pipeline-gate|effect-ca-gate|secret-gate|context-budget|work-autostart|work-respawn)/;
  for(const ev of Object.keys(s.hooks||{})){
    s.hooks[ev]=(s.hooks[ev]||[]).map(g=>({...g,hooks:(g.hooks||[]).filter(h=>!(h.command&&kill.test(h.command)))})).filter(g=>(g.hooks||[]).length);
  }
  fs.writeFileSync(p,JSON.stringify(s,null,2)+"\n");console.log("settings stripped")
  ' "$CLAUDE_DIR/settings.json"
fi
echo "==> uninstalled. Takes effect next session. (The git checkout at $HERE is left in place — rm -rf it to remove fully.)"
