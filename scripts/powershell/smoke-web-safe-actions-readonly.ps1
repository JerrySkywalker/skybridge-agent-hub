$ErrorActionPreference = "Stop"
$web = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "apps\web\src\main.tsx")
foreach ($required in @(
  "Safe Actions / Queue Controls",
  "Reason required for mutations",
  "Safe Pause",
  "Stop Queue",
  "Emergency Stop",
  "start_one_preview",
  "start_queue_preview",
  "Start One Apply disabled",
  "Start Queue Apply disabled",
  "Start All disabled",
  "Worker Loop disabled",
  "worker_offline blocker",
  "Audit result appears after safe action apply",
  "token_printed=false"
)) {
  if ($web -notmatch [regex]::Escape($required)) { throw "Web safe action surface missing: $required" }
}
if ($web -match 'arbitrary_shell[^:]+onClick|start_one_apply[^:]+onClick|start_queue_apply[^:]+onClick') {
  throw "Web must not wire forbidden apply actions to active handlers."
}
[pscustomobject]@{
  ok = $true
  scenario = "web-safe-actions-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
