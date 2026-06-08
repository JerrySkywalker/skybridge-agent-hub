[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "apps\web\src\main.tsx")
foreach ($needle in @(
  "WorkerReadinessPanel",
  "Worker Service",
  "Heartbeat age",
  "Can claim",
  "task_claim=",
  "task_execute=",
  "codex_execute=",
  "Web has no direct local process control",
  "Start One remains disabled until Goal 195"
)) {
  if ($source -notmatch [regex]::Escape($needle)) { throw "Web worker readiness panel missing text: $needle" }
}

[pscustomobject]@{
  ok = $true
  smoke = "web-worker-readiness-panel"
  renders_worker_readiness = $true
  direct_local_process_control = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
