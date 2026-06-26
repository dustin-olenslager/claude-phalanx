<#
  Phalanx installer (Windows / PowerShell) — idempotent.
  Mirrors install.sh: detect CLAUDE_DIR, MERGE settings.json + CLAUDE.md (never
  clobber), copy skills/hooks/templates, node --check the gates, run verify sims.

  Usage:
    git clone https://github.com/<you>/claude-phalanx $env:USERPROFILE\.claude\phalanx
    & $env:USERPROFILE\.claude\phalanx\install.ps1
  Env:
    $env:CLAUDE_DIR  install target (default $env:USERPROFILE\.claude)
    $env:MEMORY_DIR  memory dir     (default <CLAUDE_DIR>\memory)
  Daily auto-update on Windows: use Task Scheduler to run, daily,
    cd <CLAUDE_DIR>\phalanx; git pull --tags; ./install.ps1
#>
$ErrorActionPreference = 'Stop'
$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
$CLAUDE_DIR = if ($env:CLAUDE_DIR) { $env:CLAUDE_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$SETTINGS = Join-Path $CLAUDE_DIR 'settings.json'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'node is required (gates + merge scripts are node).' }

Write-Host "==> CLAUDE_DIR=$CLAUDE_DIR"
New-Item -ItemType Directory -Force -Path (Join-Path $CLAUDE_DIR 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $CLAUDE_DIR 'phalanx-templates\state') | Out-Null

Write-Host '==> skills'
Copy-Item -Recurse -Force (Join-Path $HERE 'skills\*') (Join-Path $CLAUDE_DIR 'skills')

Write-Host '==> hooks (anchors + gates -> CLAUDE_DIR root)'
Copy-Item -Force (Join-Path $HERE 'hooks\anchors\*.sh') $CLAUDE_DIR
Copy-Item -Force (Join-Path $HERE 'hooks\gates\*.js') $CLAUDE_DIR

Write-Host '==> agents + commands + work-loop wrappers'
New-Item -ItemType Directory -Force -Path (Join-Path $CLAUDE_DIR 'agents') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $CLAUDE_DIR 'commands') | Out-Null
Copy-Item -Force (Join-Path $HERE 'agents\*.md') (Join-Path $CLAUDE_DIR 'agents')
Copy-Item -Force (Join-Path $HERE 'commands\*.md') (Join-Path $CLAUDE_DIR 'commands')
Copy-Item -Force (Join-Path $HERE 'scripts\run-work.sh') $CLAUDE_DIR
Copy-Item -Force (Join-Path $HERE 'scripts\run-work.ps1') $CLAUDE_DIR
Copy-Item -Force (Join-Path $HERE 'TASKS.template.md') $CLAUDE_DIR

Write-Host '==> templates'
Copy-Item -Force (Join-Path $HERE 'state\*.json') (Join-Path $CLAUDE_DIR 'phalanx-templates\state')
Copy-Item -Force (Join-Path $HERE 'configs\.dependency-cruiser.js') (Join-Path $CLAUDE_DIR 'phalanx-templates')

Write-Host '==> memory dir'
$MEMORY_DIR = if ($env:MEMORY_DIR) { $env:MEMORY_DIR } else { Join-Path $CLAUDE_DIR 'memory' }
New-Item -ItemType Directory -Force -Path $MEMORY_DIR | Out-Null
$mem = Join-Path $MEMORY_DIR 'MEMORY.md'
if (-not (Test-Path $mem)) { '<!-- memory index (§10): one line per memory: - [Title](file.md) — hook. -->' | Set-Content -Encoding utf8 $mem }

Write-Host '==> CLAUDE.md (managed block)'
node (Join-Path $HERE 'scripts\merge-claude-md.mjs') (Join-Path $CLAUDE_DIR 'CLAUDE.md') (Join-Path $HERE 'claude-md\sections.md')

Write-Host '==> settings.json (merge marketplaces + plugins + hooks)'
if (Test-Path $SETTINGS) { Copy-Item -Force $SETTINGS "$SETTINGS.phalanx.bak" }
node (Join-Path $HERE 'scripts\merge-settings.mjs') $SETTINGS (Join-Path $HERE 'settings\fragment.json') $CLAUDE_DIR

Write-Host '==> validate'
foreach ($g in 'pipeline-gate','effect-ca-gate','secret-gate','context-budget','work-autostart','work-respawn') {
  node --check (Join-Path $CLAUDE_DIR "$g.js"); Write-Host "    node --check $g.js ok"
}
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' $SETTINGS
Write-Host '    ok'

Write-Host '==> verify simulations'
$script:FAIL = 0
function Fire($gate, $json) { $json | node (Join-Path $CLAUDE_DIR $gate) }
function ExpectDeny($name, $out) { if ($out -match '"permissionDecision":"deny"') { Write-Host "    PASS $name" } else { Write-Host "    FAIL $name"; $script:FAIL = 1 } }
function ExpectAllow($name, $out) { if ([string]::IsNullOrEmpty($out)) { Write-Host "    PASS $name" } else { Write-Host "    FAIL $name"; $script:FAIL = 1 } }

foreach ($a in 'caveman-anchor','app-pipeline-anchor','ts-arch-anchor') {
  $o = & (Join-Path $CLAUDE_DIR "$a.sh") 2>$null
  # .sh anchors require bash on Windows (git-bash/WSL); skip gracefully if absent
}
$sid = 'phalanx-ps'
ExpectDeny  'tsarch:ts-no-flags'   (Fire 'effect-ca-gate.js' "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"/p/x.ts`"},`"session_id`":`"$sid`"}")
Fire 'effect-ca-gate.js' "{`"tool_name`":`"Skill`",`"tool_input`":{`"skill`":`"clean-architecture`"},`"session_id`":`"$sid`"}" | Out-Null
Fire 'effect-ca-gate.js' "{`"tool_name`":`"Skill`",`"tool_input`":{`"skill`":`"effect-ts`"},`"session_id`":`"$sid`"}" | Out-Null
ExpectAllow 'tsarch:ts-after-skills' (Fire 'effect-ca-gate.js' "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"/p/x.ts`"},`"session_id`":`"$sid`"}")
ExpectDeny  'pipeline:code-no-plan' (Fire 'pipeline-gate.js' "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"/p/y.go`"},`"session_id`":`"$sid`"}")
$leak = 'AKIA' + 'Z3QJ5K7N2WX4Y6PB'   # assembled so no key-shaped literal ships
ExpectDeny  'secret:write-aws-key'  (Fire 'secret-gate.js' "{`"tool_name`":`"Write`",`"tool_input`":{`"file_path`":`"/p/c.ts`",`"content`":`"const k='$leak'`"},`"session_id`":`"$sid`"}")

if ($script:FAIL -ne 0) { throw 'SELF-TEST FAILED' }
Write-Host '==> done. Gates + plugins activate on the NEXT Claude Code session; skills usable now.'
Write-Host "    .sh anchors need bash (Git Bash or WSL) to run on Windows."
