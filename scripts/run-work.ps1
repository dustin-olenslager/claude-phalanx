# run-work.ps1 - outer autonomy loop. Re-invokes /work in a FRESH process each pass.
param([string]$Repo = (Get-Location).Path, [int]$MaxPasses = 30, [int]$SleepSeconds = 3)
$ErrorActionPreference = "Stop"
Set-Location $Repo
$tasks = Join-Path $Repo "TASKS.md"; $progress = Join-Path $Repo "PROGRESS.md"; $logDir = Join-Path $Repo ".claude-runs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (-not (Test-Path $tasks)) { Write-Host "No TASKS.md in $Repo. Create one with '- [ ]' items first." -ForegroundColor Yellow; exit 1 }
function Backlog-Empty {
  if (-not (Test-Path $tasks)) { return $true }
  $open = Select-String -Path $tasks -Pattern '^\s*-\s*\[\s*\]' -ErrorAction SilentlyContinue
  return ($null -eq $open)
}
$pass = 0
while ($true) {
  $pass++
  if ($pass -gt $MaxPasses) { Write-Host "Hit MaxPasses=$MaxPasses. Stopping. Re-run to continue." -ForegroundColor Yellow; break }
  if (Backlog-Empty) { Write-Host "Backlog empty. Done." -ForegroundColor Green; break }
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"; $log = Join-Path $logDir "pass-$pass-$stamp.log"; $now = Get-Date -Format T
  Write-Host "=== Pass $pass - $now - fresh /work ===" -ForegroundColor Cyan
  & claude -p "/work" 2>&1 | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  if ($code -ne 0) { Write-Host "claude exited $code on pass $pass. Stopping. Check $log." -ForegroundColor Red; break }
  if (Test-Path $progress) {
    $tail = Get-Content $progress -Tail 20 -ErrorAction SilentlyContinue
    if ($tail -match 'BLOCKED') { Write-Host "Blocker in PROGRESS.md. Stopping for human. See $progress." -ForegroundColor Yellow; break }
  }
  Start-Sleep -Seconds $SleepSeconds
}
Write-Host "Loop ended. Passes run: $pass. Logs in $logDir." -ForegroundColor Gray
