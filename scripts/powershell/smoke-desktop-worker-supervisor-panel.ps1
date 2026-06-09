$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @(
  "Worker Supervisor",
  "local-worker-supervisor-card",
  "Can claim tasks",
  "Can execute tasks",
  "Pause requested",
  "Stop requested",
  "Start One disabled",
  "Start Queue disabled",
  "Resume execution disabled"
)) {
  if ($desktop -notmatch [regex]::Escape($required)) { throw "Worker supervisor panel missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-worker-supervisor-panel"; token_printed = $false } | ConvertTo-Json -Compress
