[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1")
foreach ($forbidden in @("/v1/tasks/", "claimTask", "claim-task", "task.claimed", "skybridge-edge-worker.ps1", "invoke-codex-task.ps1", "gh pr create")) {
  if ($script -match [regex]::Escape($forbidden)) { throw "Worker service script references forbidden execution path: $forbidden" }
}
$status = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command status -Json | ConvertFrom-Json
if ([bool]$status.worker_service.can_claim_tasks -or [bool]$status.worker_service.can_execute_tasks) { throw "Service status allows claim or execution." }

[pscustomobject]@{
  ok = $true
  smoke = "worker-service-no-task-claim"
  task_claimed = $false
  task_executed = $false
  codex_worker_execution_started = $false
  pr_created = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
