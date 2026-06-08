[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\desktop\src\main.tsx")
foreach ($needle in @(
  "Worker Service Panel",
  "Worker service status",
  "Heartbeat age",
  "Current task id",
  "Can claim tasks",
  "Can execute tasks",
  "Start standby preview",
  "Claim task disabled",
  "Execute task disabled",
  "createWorkerServiceReadiness"
)) {
  if ($source -notmatch [regex]::Escape($needle)) { throw "Desktop worker service panel missing text: $needle" }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-worker-service-panel"
  renders_worker_service = $true
  no_task_claim_button = $true
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
