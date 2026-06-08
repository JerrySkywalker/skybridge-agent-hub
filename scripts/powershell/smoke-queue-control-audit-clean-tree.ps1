$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$before = (git -C $repoRoot status --short | Out-String).Trim()
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command safe-pause -Fixture -Apply -Reason "clean tree smoke" -Json | ConvertFrom-Json
if (-not $result.ok -or [string]::IsNullOrWhiteSpace([string]$result.audit_path)) { throw "Audit fixture did not write audit path." }
$auditPath = [string]$result.audit_path
if ($auditPath -notmatch '\.agent[\\/]+tmp[\\/]+queue-control-audit') { throw "Audit path is not under .agent/tmp/queue-control-audit: $auditPath" }
$ignored = git -C $repoRoot check-ignore $auditPath
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ignored)) { throw "Audit path is not ignored." }
$after = (git -C $repoRoot status --short | Out-String).Trim()
if ($before -ne $after) { throw "Queue-control audit smoke dirtied git status. Before=[$before] After=[$after]" }

[pscustomobject]@{
  ok = $true
  scenario = "queue-control-audit-clean-tree"
  audit_path = $auditPath
  token_printed = $false
} | ConvertTo-Json -Compress
