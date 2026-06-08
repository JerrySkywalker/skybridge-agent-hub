$ErrorActionPreference = "Stop"
$ui = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @("WorkerRoutingPanel", "Multi-worker Readiness", "Selected worker preview", "max_parallel_per_repo", "Claim task disabled", "Worker execution disabled")) {
  if ($ui -notmatch [regex]::Escape($required)) { throw "Desktop multi-worker readiness surface missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-multi-worker-readiness"; token_printed = $false } | ConvertTo-Json -Compress
