$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "apps\desktop\src\main.tsx")
foreach ($required in @(
  "Safe Actions / Queue Controls",
  "Safe Pause",
  "Stop Queue",
  "Emergency Stop",
  "start_one_preview",
  "start_queue_preview",
  "Start One Apply disabled",
  "Start Queue Apply disabled",
  "Start All disabled",
  "Run Forever disabled",
  "Worker Loop disabled",
  "worker_offline blocker",
  "Audit result",
  "token_printed"
)) {
  if ($desktop -notmatch [regex]::Escape($required)) { throw "Desktop safe action surface missing: $required" }
}
if ($desktop -match 'start-dev-queue-189-200\.ps1|skybridge-campaign\.ps1"\s*,\s*"resume"') {
  throw "Desktop must not expose campaign execution commands."
}
[pscustomobject]@{
  ok = $true
  scenario = "desktop-safe-actions-readonly"
  token_printed = $false
} | ConvertTo-Json -Compress
